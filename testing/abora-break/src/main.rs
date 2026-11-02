//! abora-break: break an Abora test VM on purpose, so `anix doctor` and its repairs can be tested.
//!
//! Test harness only. It runs on the developer's machine and reaches the VM over SSH; it is never
//! built into the ISO, the installer, the Nix modules or anything copied to a user's machine
//! (`make check` fails if anything that ships mentions it). The script it sends refuses to run
//! on bare metal.

use std::io::Write;
use std::process::{Command, ExitCode, Stdio};

const HELP: &str = "\
abora-break: break an Abora test VM on purpose (test harness only)

Usage:
  abora-break [options] <fault>...           break the VM
  abora-break [options] restore <fault>...   undo those faults
  abora-break list                           the faults and what anix doctor should report

Options:
  --ssh <user@host>    the test VM (root, or a user with passwordless sudo)
  --port <n>           SSH port (default 22; QEMU user networking usually forwards 2222)
  --print              print the script instead of running it
  -h, --help           this help

The VM needs SSH: set `anix.services.openssh = true;` in its /etc/nixos/anix.nix and run
`anix apply`. The script refuses to run unless systemd-detect-virt reports a VM.";

/// One way to break a system. `doctor` is the finding `anix doctor` should report afterwards.
struct Fault {
    name: &'static str,
    doctor: &'static str,
    note: &'static str,
    breaks: &'static str,
    restores: &'static str,
}

// State lives in /var/lib/abora-break on the VM, so `restore` works after a reboot too.
const FAULTS: &[Fault] = &[
    Fault {
        name: "full-esp",
        doctor: "boot-space (warn), repair gc-generations",
        note: "UEFI installs only; fills /boot until under 64 MB is free",
        breaks: r#"[ -d /sys/firmware/efi ] || { echo "full-esp: this VM boots with BIOS, so there is no EFI partition" >&2; exit 1; }
free=$(df --output=avail -B1 /boot | tail -n 1)
fill=$((free - 32 * 1024 * 1024))
[ "$fill" -gt 0 ] || { echo "full-esp: /boot already has under 32 MB free"; exit 0; }
fallocate -l "$fill" /boot/abora-break-fill"#,
        restores: "rm -f /boot/abora-break-fill",
    },
    Fault {
        name: "stopped-dns",
        doctor: "network-dns (fail), repair restart-networkmanager",
        note: "points resolv.conf at an unreachable server; the route stays up",
        breaks: r#"[ -e "$state/resolv.conf" ] || [ -L "$state/resolv.conf" ] || cp -P /etc/resolv.conf "$state/resolv.conf"
rm -f /etc/resolv.conf
printf 'nameserver 192.0.2.1\n' > /etc/resolv.conf"#,
        restores: r#"if [ -e "$state/resolv.conf" ] || [ -L "$state/resolv.conf" ]; then
  rm -f /etc/resolv.conf && cp -P "$state/resolv.conf" /etc/resolv.conf && rm -f "$state/resolv.conf"
fi
systemctl restart NetworkManager.service 2>/dev/null || true"#,
    },
    Fault {
        name: "failed-unit",
        doctor: "services (fail), repair reset-failed",
        note: "a transient unit named abora-break-test that exits 1",
        breaks: "systemd-run --quiet --unit=abora-break-test --property=Type=oneshot /bin/sh -c 'exit 1' || true",
        restores: "systemctl reset-failed abora-break-test.service 2>/dev/null || true",
    },
    Fault {
        name: "wrong-gpu",
        doctor: "gpu-driver (fail)",
        note: "sets abora.gpu to a driver the VM doesn't load; needs a reboot or a GPU the doctor can see",
        breaks: r#"local_nix=/etc/nixos/abora-local.nix
[ -e "$state/abora-local.nix" ] || cp -p "$local_nix" "$state/abora-local.nix"
current=$(sed -n 's/^ *abora\.gpu *= *"\([^"]*\)".*/\1/p' "$local_nix")
wrong=nvidia-open; [ "$current" = nvidia-open ] && wrong=amdgpu
if grep -q '^ *abora\.gpu *=' "$local_nix"; then
  sed -i "s/^\( *abora\.gpu *= *\)\"[^\"]*\"/\1\"$wrong\"/" "$local_nix"
else
  echo "wrong-gpu: $local_nix has no abora.gpu line" >&2; exit 1
fi"#,
        restores: r#"[ -e "$state/abora-local.nix" ] && cp -p "$state/abora-local.nix" /etc/nixos/abora-local.nix && rm -f "$state/abora-local.nix" || true"#,
    },
    Fault {
        name: "missing-abora-file",
        doctor: "abora-file-theme-sync.sh (fail), repair rebuild",
        note: "removes /etc/abora/theme-sync.sh",
        breaks: r#"[ -e "$state/theme-sync.sh" ] || [ -L "$state/theme-sync.sh" ] || cp -P /etc/abora/theme-sync.sh "$state/theme-sync.sh"
rm -f /etc/abora/theme-sync.sh"#,
        restores: r#"if [ -e "$state/theme-sync.sh" ] || [ -L "$state/theme-sync.sh" ]; then
  cp -P "$state/theme-sync.sh" /etc/abora/theme-sync.sh && rm -f "$state/theme-sync.sh"
fi"#,
    },
    Fault {
        name: "read-only-root",
        doctor: "disk-readonly (fail)",
        note: "emergency read-only remount (SysRq u), as the kernel does after disk errors; restore reboots",
        // `mount -o remount,ro /` fails on a running system ("mount point is busy"): the journal and other
        // services hold files open for writing. SysRq u forces it, like a real filesystem error does.
        breaks: r#"sync
cat /proc/sys/kernel/sysrq > "$state/sysrq"
echo 1 > /proc/sys/kernel/sysrq
echo u > /proc/sysrq-trigger
sleep 2
cat "$state/sysrq" > /proc/sys/kernel/sysrq"#,
        // ext4 usually refuses to go back to read-write ("unprocessed orphan inode list"), just as after a
        // real error, so a reboot is the restore. The filesystem is already read-only, so nothing is lost.
        restores: r#"if mount -o remount,rw / 2>/dev/null; then
  rm -f "$state/sysrq"
else
  echo 'abora-break: / cannot go back to read-write while running; rebooting the VM'
  echo 1 > /proc/sys/kernel/sysrq
  echo b > /proc/sysrq-trigger
fi"#,
    },
];

fn fault(name: &str) -> Option<&'static Fault> {
    FAULTS.iter().find(|f| f.name == name)
}

/// The script sent to the VM. It stops on the first error and never runs on bare metal.
fn script(faults: &[&Fault], restore: bool) -> String {
    let mut out = String::from(
        "set -eu\n\
         virt=$(systemd-detect-virt --vm 2>/dev/null || true)\n\
         if [ -z \"$virt\" ] || [ \"$virt\" = none ]; then\n\
         \x20 echo 'abora-break: this is not a virtual machine; refusing to break it.' >&2; exit 3\n\
         fi\n\
         state=/var/lib/abora-break\n",
    );
    // A read-only root can't take the state directory, so it is created before anything breaks.
    if !restore {
        out.push_str("mkdir -p \"$state\"\n");
    }
    for f in faults {
        let (verb, body) = if restore {
            ("restoring", f.restores)
        } else {
            ("breaking", f.breaks)
        };
        out.push_str(&format!(
            "echo 'abora-break: {verb} {}'\n({body})\n",
            f.name
        ));
    }
    out
}

struct Args {
    ssh: Option<String>,
    port: u16,
    print: bool,
    restore: bool,
    faults: Vec<&'static Fault>,
}

fn parse(argv: &[String]) -> Result<Option<Args>, String> {
    let mut args = Args {
        ssh: None,
        port: 22,
        print: false,
        restore: false,
        faults: Vec::new(),
    };
    let mut it = argv.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                println!("{HELP}");
                return Ok(None);
            }
            "list" => {
                for f in FAULTS {
                    println!("{:<20} doctor: {}\n{:<20} {}", f.name, f.doctor, "", f.note);
                }
                return Ok(None);
            }
            "--ssh" => args.ssh = Some(it.next().ok_or("--ssh needs user@host")?.clone()),
            "--port" => {
                let value = it.next().ok_or("--port needs a number")?;
                args.port = value
                    .parse()
                    .map_err(|_| format!("--port: not a port number: {value}"))?;
            }
            "--print" => args.print = true,
            "restore" if args.faults.is_empty() => args.restore = true,
            name => {
                let f = fault(name)
                    .ok_or_else(|| format!("unknown fault '{name}' (see: abora-break list)"))?;
                if !args.faults.iter().any(|g| g.name == f.name) {
                    args.faults.push(f);
                }
            }
        }
    }
    if args.faults.is_empty() {
        return Err("name at least one fault (see: abora-break list)".into());
    }
    if args.ssh.is_none() && !args.print {
        return Err("--ssh <user@host> is required (or --print to see the script)".into());
    }
    Ok(Some(args))
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse(&argv) {
        Ok(Some(args)) => args,
        Ok(None) => return ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("abora-break: {message}");
            return ExitCode::from(2);
        }
    };
    let body = script(&args.faults, args.restore);
    if args.print {
        print!("{body}");
        return ExitCode::SUCCESS;
    }
    let target = args.ssh.expect("checked in parse");
    let mut child = match Command::new("ssh")
        .args([
            "-p",
            &args.port.to_string(),
            "-o",
            "BatchMode=yes",
            &target,
            "sudo -n sh -s",
        ])
        .stdin(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(err) => {
            eprintln!("abora-break: can't run ssh: {err}");
            return ExitCode::FAILURE;
        }
    };
    if let Some(mut stdin) = child.stdin.take() {
        if let Err(err) = stdin.write_all(body.as_bytes()) {
            eprintln!("abora-break: can't send the script: {err}");
        }
    }
    match child.wait() {
        Ok(status) if status.success() => ExitCode::SUCCESS,
        Ok(status) => {
            eprintln!("abora-break: the VM reported a failure ({status})");
            ExitCode::FAILURE
        }
        Err(err) => {
            eprintln!("abora-break: {err}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn argv(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn every_fault_restores_and_names_its_doctor_finding() {
        for f in FAULTS {
            assert!(
                !f.breaks.trim().is_empty() && !f.restores.trim().is_empty(),
                "{}",
                f.name
            );
            assert!(!f.doctor.is_empty(), "{}", f.name);
        }
    }

    #[test]
    fn the_script_refuses_bare_metal_before_doing_anything() {
        let body = script(&[fault("failed-unit").unwrap()], false);
        let guard = body.find("refusing to break it").unwrap();
        let work = body.find("systemd-run").unwrap();
        assert!(guard < work);
        assert!(body.starts_with("set -eu\n"));
    }

    #[test]
    fn state_dir_is_made_before_root_goes_read_only() {
        let body = script(
            &[
                fault("read-only-root").unwrap(),
                fault("stopped-dns").unwrap(),
            ],
            false,
        );
        assert!(body.find("mkdir -p \"$state\"").unwrap() < body.find("sysrq-trigger").unwrap());
    }

    #[test]
    fn restore_runs_the_restore_steps() {
        let args = parse(&argv(&["--print", "restore", "full-esp"]))
            .unwrap()
            .unwrap();
        assert!(args.restore);
        let body = script(&args.faults, args.restore);
        assert!(body.contains("rm -f /boot/abora-break-fill"));
        assert!(!body.contains("fallocate"));
    }

    #[test]
    fn needs_a_target_and_a_known_fault() {
        assert!(parse(&argv(&["full-esp"])).is_err());
        assert!(parse(&argv(&["--print"])).is_err());
        assert!(parse(&argv(&["--print", "melt-cpu"])).is_err());
        let args = parse(&argv(&[
            "--ssh",
            "root@vm",
            "--port",
            "2222",
            "failed-unit",
            "failed-unit",
        ]))
        .unwrap()
        .unwrap();
        assert_eq!(args.port, 2222);
        assert_eq!(args.faults.len(), 1);
    }
}
