use std::path::Path;

pub const ROOT_LABEL: &str = "ABORA_ROOT";
pub const EFI_LABEL: &str = "ABORA_EFI";
pub const MIN_ESP_BYTES: u64 = 536_870_912;

/// Everything the disk engine does to the machine goes through this, so the
/// exact command sequence can be checked without a real disk.
pub trait Host {
    fn is_block(&self, path: &str) -> bool;
    /// Runs a command that changes the machine, bounded by `timeout_secs`.
    fn run(&mut self, timeout_secs: u32, argv: &[&str]) -> Result<(), String>;
    /// Runs a read-only query and returns its stdout.
    fn query(&mut self, argv: &[&str]) -> Option<String>;
    fn sleep(&mut self, secs: u64);
    fn log(&mut self, message: &str);
    /// Dry runs cannot read back a label they never wrote.
    fn verifies_writes(&self) -> bool {
        true
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout {
    pub efi: String,
    pub root: String,
}

impl Layout {
    pub fn render(&self) -> String {
        format!("efi={}\nroot={}\n", self.efi, self.root)
    }
}

/// nvme/mmcblk/loop devices number partitions as <disk>p<N>; sd/vd/hd as <disk><N>.
pub fn part_suffix(disk: &str) -> &'static str {
    if ["nvme", "mmcblk", "loop"]
        .iter()
        .any(|kind| disk.contains(kind))
    {
        "p"
    } else {
        ""
    }
}

pub fn partition_path(disk: &str, number: u32) -> String {
    format!("{disk}{}{number}", part_suffix(disk))
}

fn settle(host: &mut dyn Host) {
    if host
        .run(20, &["udevadm", "settle", "--timeout=15"])
        .is_err()
    {
        host.log("udevadm settle timed out after 15s");
    }
}

fn reread_table(host: &mut dyn Host, disk: &str) {
    if host.run(15, &["partprobe", disk]).is_err() {
        host.log(&format!("partprobe timed out for {disk}"));
    }
    settle(host);
}

fn release_target(host: &mut dyn Host, target: &str) {
    let _ = host.run(30, &["umount", "-R", target]);
}

fn require_block(host: &dyn Host, what: &str, path: &str) -> Result<(), String> {
    if path.is_empty() || !host.is_block(path) {
        return Err(format!("refusing: {what} '{path}' is not a block device"));
    }
    Ok(())
}

/// GPT layout: 1 MiB BIOS-boot (Limine's legacy path), a 512 MiB FAT32 ESP,
/// and the rest as ext4 root, so one disk boots both BIOS and UEFI.
pub fn erase(host: &mut dyn Host, disk: &str, target: &str) -> Result<Layout, String> {
    host.log(&format!("partition_disk: start disk={disk}"));
    require_block(host, "disk", disk)?;
    release_target(host, target);

    let steps: [&[&str]; 7] = [
        &["wipefs", "-af", disk],
        &["parted", "-s", disk, "mklabel", "gpt"],
        &[
            "parted", "-s", disk, "unit", "MiB", "mkpart", "BIOSBOOT", "1", "3",
        ],
        &["parted", "-s", disk, "set", "1", "bios_grub", "on"],
        &[
            "parted", "-s", disk, "unit", "MiB", "mkpart", "ESP", "fat32", "3", "515",
        ],
        &["parted", "-s", disk, "set", "2", "esp", "on"],
        &[
            "parted", "-s", disk, "unit", "MiB", "mkpart", "primary", "ext4", "515", "100%",
        ],
    ];
    for argv in steps {
        host.run(30, argv)?;
    }
    reread_table(host, disk);

    let layout = Layout {
        efi: partition_path(disk, 2),
        root: partition_path(disk, 3),
    };
    host.log(&format!(
        "partition_disk: efi={} root={}",
        layout.efi, layout.root
    ));

    for _ in 0..5 {
        if host.is_block(&layout.efi) && host.is_block(&layout.root) {
            break;
        }
        host.sleep(1);
        reread_table(host, disk);
    }
    require_block(host, "new EFI partition", &layout.efi)?;
    require_block(host, "new root partition", &layout.root)?;

    host.run(
        120,
        &["mkfs.vfat", "-F", "32", "-n", EFI_LABEL, &layout.efi],
    )?;
    host.run(120, &["mkfs.ext4", "-F", "-L", ROOT_LABEL, &layout.root])?;
    let _ = host.run(60, &["sync"]);
    settle(host);
    ensure_root_label(host, &layout.root)?;
    host.log("partition_disk: format complete");
    Ok(layout)
}

/// Dual-boot path: formats only the chosen root partition and reuses the
/// existing ESP as-is. Never touches the partition table.
pub fn existing(
    host: &mut dyn Host,
    disk: &str,
    root: &str,
    esp: &str,
    target: &str,
) -> Result<Layout, String> {
    host.log(&format!(
        "partition_disk_existing: start disk={disk} target={root} esp={esp}"
    ));
    require_block(host, "root partition", root)?;
    require_block(host, "EFI partition", esp)?;
    if root == disk || esp == disk {
        return Err("refusing: target resolves to the whole disk, not a partition".into());
    }
    if root == esp {
        return Err("refusing: root partition and EFI partition are the same device".into());
    }
    check_esp(host, esp)?;

    // After the release, so a retry isn't blocked by its own earlier mount.
    release_target(host, target);
    if let Some(reason) = partition_in_use(host, root) {
        return Err(format!("refusing: {root} {reason}"));
    }
    host.run(120, &["mkfs.ext4", "-F", "-L", ROOT_LABEL, root])?;
    let _ = host.run(60, &["sync"]);
    settle(host);
    ensure_root_label(host, root)?;
    host.log("partition_disk_existing: format complete (disk otherwise untouched)");
    Ok(Layout {
        efi: esp.to_string(),
        root: root.to_string(),
    })
}

/// The screen hides mounted and in-use partitions; check again right before
/// formatting, since the device list can change while the user is choosing.
fn partition_in_use(host: &mut dyn Host, part: &str) -> Option<String> {
    let mountpoints = host
        .query(&["lsblk", "-nro", "MOUNTPOINTS", part])
        .unwrap_or_default();
    // -r escapes the separator between several mount points as a literal \x0a.
    let first = mountpoints
        .lines()
        .flat_map(|line| line.split("\\x0a"))
        .map(str::trim)
        .find(|mp| !mp.is_empty());
    if let Some(mp) = first {
        return Some(format!("is mounted at {mp}"));
    }
    let types = host
        .query(&["lsblk", "-nro", "TYPE", part])
        .unwrap_or_default();
    let mut lines = types.lines().map(str::trim).filter(|line| !line.is_empty());
    lines.next();
    if let Some(child) = lines.next() {
        return Some(format!("is backing an active {child} device"));
    }
    None
}

pub fn check_esp(host: &mut dyn Host, esp: &str) -> Result<(), String> {
    let first_line = |text: Option<String>| {
        text.and_then(|t| t.lines().next().map(|l| l.trim().to_string()))
            .unwrap_or_default()
    };
    let fstype = first_line(host.query(&["lsblk", "-ndo", "FSTYPE", esp]));
    let size = first_line(host.query(&["lsblk", "-bndo", "SIZE", esp]));

    if !matches!(fstype.as_str(), "vfat" | "fat" | "fat32") {
        let shown = if fstype.is_empty() {
            "unknown"
        } else {
            &fstype
        };
        host.log(&format!(
            "check_existing_esp: {esp} has unsupported fstype '{shown}'"
        ));
        return Err(format!("EFI partition {esp} is not FAT ({shown})."));
    }
    if let Ok(bytes) = size.parse::<u64>() {
        if bytes < MIN_ESP_BYTES {
            host.log(&format!(
                "check_existing_esp: {esp} too small: {bytes} bytes"
            ));
            return Err(format!(
                "EFI partition {esp} is smaller than Abora's 512 MiB requirement."
            ));
        }
    }
    Ok(())
}

pub fn ensure_root_label(host: &mut dyn Host, device: &str) -> Result<(), String> {
    if !host.verifies_writes() {
        return Ok(());
    }
    require_block(host, "root partition", device)?;
    let read_label = |host: &mut dyn Host| {
        host.query(&["blkid", "-s", "LABEL", "-o", "value", device])
            .and_then(|t| t.lines().next().map(|l| l.trim().to_string()))
            .unwrap_or_default()
    };
    for _ in 0..5 {
        let _ = host.run(20, &["udevadm", "settle"]);
        if read_label(host) == ROOT_LABEL {
            host.log(&format!("verified root label {ROOT_LABEL} on {device}"));
            return Ok(());
        }
        let _ = host.run(30, &["e2label", device, ROOT_LABEL]);
        let _ = host.run(60, &["sync"]);
        host.sleep(1);
    }
    if read_label(host) == ROOT_LABEL {
        return Ok(());
    }
    host.log(&format!("root label verification failed for {device}"));
    Err(format!("{device} did not get the {ROOT_LABEL} label"))
}

pub fn mount(host: &mut dyn Host, layout: &Layout, target: &str) -> Result<(), String> {
    host.log(&format!(
        "mount_target: start root={} efi={}",
        layout.root, layout.efi
    ));
    let boot = Path::new(target).join("boot");
    let boot = boot.to_string_lossy();
    host.run(10, &["mkdir", "-p", target])?;
    host.run(60, &["mount", &layout.root, target])?;
    host.run(10, &["mkdir", "-p", &boot])?;
    host.run(60, &["mount", &layout.efi, &boot])?;
    host.log("mount_target: complete");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::{HashMap, HashSet};

    #[derive(Default)]
    struct Fake {
        blocks: HashSet<String>,
        /// Block devices that only appear after the partition table is written.
        appear_after_parted: Vec<String>,
        answers: HashMap<String, String>,
        fail: Option<String>,
        ran: Vec<String>,
    }

    impl Fake {
        fn with_blocks(paths: &[&str]) -> Self {
            Self {
                blocks: paths.iter().map(|p| p.to_string()).collect(),
                ..Self::default()
            }
        }
        fn answer(mut self, argv: &str, out: &str) -> Self {
            self.answers.insert(argv.into(), out.into());
            self
        }
        fn mutations(&self) -> Vec<&str> {
            self.ran
                .iter()
                .map(String::as_str)
                .filter(|c| {
                    !c.starts_with("udevadm")
                        && !c.starts_with("sync")
                        && !c.starts_with("partprobe")
                })
                .collect()
        }
    }

    impl Host for Fake {
        fn is_block(&self, path: &str) -> bool {
            self.blocks.contains(path)
        }
        fn run(&mut self, _timeout: u32, argv: &[&str]) -> Result<(), String> {
            let line = argv.join(" ");
            self.ran.push(line.clone());
            if argv[0] == "parted" {
                for dev in self.appear_after_parted.drain(..) {
                    self.blocks.insert(dev);
                }
            }
            match &self.fail {
                Some(prefix) if line.starts_with(prefix.as_str()) => Err(format!("{line} failed")),
                _ => Ok(()),
            }
        }
        fn query(&mut self, argv: &[&str]) -> Option<String> {
            self.answers.get(&argv.join(" ")).cloned()
        }
        fn sleep(&mut self, _secs: u64) {}
        fn log(&mut self, _message: &str) {}
    }

    #[test]
    fn suffix_follows_kernel_naming() {
        assert_eq!(partition_path("/dev/sda", 2), "/dev/sda2");
        assert_eq!(partition_path("/dev/vda", 3), "/dev/vda3");
        assert_eq!(partition_path("/dev/nvme0n1", 2), "/dev/nvme0n1p2");
        assert_eq!(partition_path("/dev/mmcblk0", 3), "/dev/mmcblk0p3");
        assert_eq!(partition_path("/dev/loop7", 2), "/dev/loop7p2");
    }

    #[test]
    fn erase_writes_the_bios_and_uefi_layout_then_formats() {
        let mut host = Fake::with_blocks(&["/dev/nvme0n1"])
            .answer("blkid -s LABEL -o value /dev/nvme0n1p3", "ABORA_ROOT\n");
        host.appear_after_parted = vec!["/dev/nvme0n1p2".into(), "/dev/nvme0n1p3".into()];

        let layout = erase(&mut host, "/dev/nvme0n1", "/mnt").expect("erase");
        assert_eq!(layout.efi, "/dev/nvme0n1p2");
        assert_eq!(layout.root, "/dev/nvme0n1p3");
        assert_eq!(
            host.mutations(),
            vec![
                "umount -R /mnt",
                "wipefs -af /dev/nvme0n1",
                "parted -s /dev/nvme0n1 mklabel gpt",
                "parted -s /dev/nvme0n1 unit MiB mkpart BIOSBOOT 1 3",
                "parted -s /dev/nvme0n1 set 1 bios_grub on",
                "parted -s /dev/nvme0n1 unit MiB mkpart ESP fat32 3 515",
                "parted -s /dev/nvme0n1 set 2 esp on",
                "parted -s /dev/nvme0n1 unit MiB mkpart primary ext4 515 100%",
                "mkfs.vfat -F 32 -n ABORA_EFI /dev/nvme0n1p2",
                "mkfs.ext4 -F -L ABORA_ROOT /dev/nvme0n1p3",
            ]
        );
    }

    #[test]
    fn erase_refuses_a_path_that_is_not_a_disk() {
        let mut host = Fake::default();
        let err = erase(&mut host, "/dev/sdz", "/mnt").unwrap_err();
        assert!(err.contains("not a block device"));
        assert!(host.ran.is_empty());
    }

    #[test]
    fn erase_stops_at_the_first_failed_step() {
        let mut host = Fake::with_blocks(&["/dev/sda"]);
        host.fail = Some("parted -s /dev/sda mklabel".into());
        assert!(erase(&mut host, "/dev/sda", "/mnt").is_err());
        assert!(!host.ran.iter().any(|c| c.starts_with("mkfs")));
        assert!(!host.ran.iter().any(|c| c.contains("mkpart")));
    }

    #[test]
    fn erase_fails_when_partitions_never_appear() {
        let mut host = Fake::with_blocks(&["/dev/sda"]);
        let err = erase(&mut host, "/dev/sda", "/mnt").unwrap_err();
        assert!(err.contains("/dev/sda2"));
        assert!(!host.ran.iter().any(|c| c.starts_with("mkfs")));
    }

    fn dual_boot_host() -> Fake {
        Fake::with_blocks(&["/dev/sda", "/dev/sda1", "/dev/sda4"])
            .answer("lsblk -ndo FSTYPE /dev/sda1", "vfat\n")
            .answer("lsblk -bndo SIZE /dev/sda1", "629145600\n")
            .answer("lsblk -nro TYPE /dev/sda4", "part\n")
            .answer("blkid -s LABEL -o value /dev/sda4", "ABORA_ROOT\n")
    }

    #[test]
    fn existing_formats_only_the_chosen_partition() {
        let mut host = dual_boot_host();
        let layout =
            existing(&mut host, "/dev/sda", "/dev/sda4", "/dev/sda1", "/mnt").expect("existing");
        assert_eq!(
            layout,
            Layout {
                efi: "/dev/sda1".into(),
                root: "/dev/sda4".into()
            }
        );
        assert_eq!(
            host.mutations(),
            vec!["umount -R /mnt", "mkfs.ext4 -F -L ABORA_ROOT /dev/sda4"]
        );
    }

    #[test]
    fn existing_refuses_whole_disk_and_same_device() {
        let mut host = dual_boot_host();
        assert!(existing(&mut host, "/dev/sda", "/dev/sda", "/dev/sda1", "/mnt").is_err());
        assert!(existing(&mut host, "/dev/sda", "/dev/sda1", "/dev/sda1", "/mnt").is_err());
        assert!(host.ran.is_empty());
    }

    #[test]
    fn existing_refuses_a_small_or_non_fat_esp() {
        let mut host = dual_boot_host().answer("lsblk -bndo SIZE /dev/sda1", "104857600\n");
        let err = existing(&mut host, "/dev/sda", "/dev/sda4", "/dev/sda1", "/mnt").unwrap_err();
        assert!(err.contains("512 MiB"));

        let mut host = dual_boot_host().answer("lsblk -ndo FSTYPE /dev/sda1", "ntfs\n");
        let err = existing(&mut host, "/dev/sda", "/dev/sda4", "/dev/sda1", "/mnt").unwrap_err();
        assert!(err.contains("not FAT"));
        assert!(host.ran.is_empty());
    }

    #[test]
    fn existing_refuses_a_mounted_or_busy_partition() {
        let mut host =
            dual_boot_host().answer("lsblk -nro MOUNTPOINTS /dev/sda4", "/home\\x0a/srv\n");
        let err = existing(&mut host, "/dev/sda", "/dev/sda4", "/dev/sda1", "/mnt").unwrap_err();
        assert!(err.contains("mounted at /home"));

        let mut host = dual_boot_host().answer("lsblk -nro TYPE /dev/sda4", "part\ncrypt\n");
        let err = existing(&mut host, "/dev/sda", "/dev/sda4", "/dev/sda1", "/mnt").unwrap_err();
        assert!(err.contains("crypt"));
        assert_eq!(host.mutations(), vec!["umount -R /mnt"]);
    }

    #[test]
    fn label_is_repaired_then_verified() {
        let mut host = Fake::with_blocks(&["/dev/sda3"]);
        assert!(ensure_root_label(&mut host, "/dev/sda3").is_err());
        assert!(host.ran.iter().any(|c| c == "e2label /dev/sda3 ABORA_ROOT"));
    }

    #[test]
    fn mount_puts_the_esp_under_boot() {
        let mut host = Fake::default();
        let layout = Layout {
            efi: "/dev/sda2".into(),
            root: "/dev/sda3".into(),
        };
        mount(&mut host, &layout, "/mnt").expect("mount");
        assert_eq!(
            host.ran,
            vec![
                "mkdir -p /mnt",
                "mount /dev/sda3 /mnt",
                "mkdir -p /mnt/boot",
                "mount /dev/sda2 /mnt/boot",
            ]
        );
    }
}
