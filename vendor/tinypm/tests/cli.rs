#[cfg(unix)]
mod unix {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::process::Command;

    fn fake_provider(name: &str) -> tempfile::TempDir {
        let temp = tempfile::tempdir().unwrap();
        let executable = temp.path().join(name);
        fs::write(&executable, "#!/bin/sh\nexit 99\n").unwrap();
        let mut permissions = fs::metadata(&executable).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(executable, permissions).unwrap();
        temp
    }

    #[test]
    fn version_is_successful_and_uses_alpha_version() {
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .arg("--version")
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(
            String::from_utf8(output.stdout).unwrap(),
            "tinypm 0.8.1-alpha\n"
        );
    }

    #[test]
    fn dry_run_never_executes_provider() {
        let bin = fake_provider("pacman");
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "pacman", "--dry-run", "install", "curl"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(
            String::from_utf8(output.stdout)
                .unwrap()
                .contains("pacman -S --noconfirm curl")
        );
    }

    #[test]
    fn grab_defaults_to_install_at_the_process_boundary() {
        let bin = fake_provider("apk");
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "apk", "--dry-run", "gcc++"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(
            String::from_utf8(output.stdout)
                .unwrap()
                .contains("apk add g++")
        );
    }

    #[test]
    fn grab_uninstall_is_not_treated_as_a_package_name() {
        let bin = fake_provider("brew");
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "brew", "--dry-run", "uninstall", "steam"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains("brew uninstall steam"));
        assert!(!stdout.contains("brew install uninstall steam"));
    }

    #[test]
    fn history_is_empty_in_a_fresh_state_directory() {
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .arg("history")
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(
            String::from_utf8(output.stdout).unwrap(),
            "No TinyPM transactions recorded.\n"
        );
    }

    #[test]
    fn undo_is_preview_only_without_confirmation() {
        let bin = fake_provider("pacman");
        let state = tempfile::tempdir().unwrap();
        let state_dir = state.path().join("tinypm");
        fs::create_dir(&state_dir).unwrap();
        fs::write(
            state_dir.join("history.jsonl"),
            r#"{"id":1,"timestamp":1,"action":"install","requested":"curl","resolved":"curl","provider":"pacman","reverts":null}
"#,
        )
        .unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .arg("undo")
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains("pacman -Rns --noconfirm curl"));
        assert!(stdout.contains("Preview only"));
        assert_eq!(
            fs::read_to_string(state_dir.join("history.jsonl"))
                .unwrap()
                .lines()
                .count(),
            1
        );

        let json = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["undo", "--json"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(json.status.success());
        let report: serde_json::Value = serde_json::from_slice(&json.stdout).unwrap();
        assert_eq!(report["transaction_id"], "1");
        assert_eq!(report["original_action"], "install");
        assert_eq!(report["reversal_action"], "remove");
        assert_eq!(report["requested"], "curl");
        assert_eq!(report["provider_key"], "pacman");
        assert!(
            report["command"]
                .as_str()
                .unwrap()
                .ends_with("pacman -Rns --noconfirm curl")
        );
        assert_eq!(
            fs::read_to_string(state_dir.join("history.jsonl"))
                .unwrap()
                .lines()
                .count(),
            1
        );
    }

    #[test]
    fn empty_undo_json_is_null() {
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["undo", "--json"])
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert!(report.is_null());
    }

    #[test]
    fn undo_preview_does_not_require_recorded_provider() {
        let state = tempfile::tempdir().unwrap();
        let state_dir = state.path().join("tinypm");
        fs::create_dir(&state_dir).unwrap();
        let history_path = state_dir.join("history.jsonl");
        fs::write(
            &history_path,
            r#"{"id":"old","timestamp":1,"action":"install","requested":"curl","resolved":"curl","provider":"eopkg","reverts":null}
"#,
        )
        .unwrap();

        let preview = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .arg("undo")
            .env("PATH", "")
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(preview.status.success());
        assert!(
            String::from_utf8(preview.stdout)
                .unwrap()
                .contains("eopkg remove -y curl")
        );

        let execute = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["undo", "--yes"])
            .env("PATH", "")
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert_eq!(execute.status.code(), Some(1));
        assert!(
            String::from_utf8(execute.stderr)
                .unwrap()
                .contains("eopkg is not installed")
        );
        assert_eq!(fs::read_to_string(history_path).unwrap().lines().count(), 1);
    }

    #[test]
    fn provider_failure_is_returned_to_the_caller() {
        let bin = fake_provider("brew");
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "search", "curl"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(
            String::from_utf8(output.stderr)
                .unwrap()
                .contains("brew exited with")
        );
    }

    #[test]
    fn completions_are_generated_from_the_current_command_tree() {
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["completions", "bash"])
            .output()
            .unwrap();
        assert!(output.status.success());
        let completion = String::from_utf8(output.stdout).unwrap();
        assert!(completion.contains("completions"));
        assert!(completion.contains("managed"));
        assert!(completion.contains("undo"));
        assert!(!completion.contains("bundle"));
        assert!(!completion.contains("tinypm__subcmd__install"));
        assert!(!completion.contains("tinypm__subcmd__remove"));
        assert!(!completion.contains("tinypm__subcmd__update"));
    }

    #[test]
    fn grab_completions_include_package_changing_commands() {
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["completions", "bash"])
            .output()
            .unwrap();
        assert!(output.status.success());
        let completion = String::from_utf8(output.stdout).unwrap();
        assert!(completion.contains("grab__subcmd__add"));
        assert!(completion.contains("grab__subcmd__remove"));
        assert!(completion.contains("grab__subcmd__update"));
    }

    #[test]
    fn already_installed_package_is_not_reinstalled_or_recorded() {
        let bin = tempfile::tempdir().unwrap();
        let pacman = bin.path().join("pacman");
        fs::write(
            &pacman,
            "#!/bin/sh\nif [ \"$1\" = \"-Q\" ]; then exit 0; fi\nexit 88\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&pacman).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(pacman, permissions).unwrap();
        let sudo = bin.path().join("sudo");
        fs::write(&sudo, "#!/bin/sh\nexec \"$@\"\n").unwrap();
        let mut permissions = fs::metadata(&sudo).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(sudo, permissions).unwrap();
        let state = tempfile::tempdir().unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "pacman", "install", "curl"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains("Already installed"));
        assert!(stdout.contains("Nothing to do"));
        assert!(!state.path().join("tinypm/history.jsonl").exists());
    }

    #[test]
    fn partial_batch_failure_records_only_successful_packages() {
        let bin = tempfile::tempdir().unwrap();
        let pacman = bin.path().join("pacman");
        fs::write(
            &pacman,
            "#!/bin/sh\nif [ \"$1\" = \"-Q\" ]; then exit 1; fi\nprintf '%s\\n' \"$*\" >> \"$TINYPM_TEST_LOG\"\ncase \"$*\" in *broken*) exit 42;; esac\nexit 0\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&pacman).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(pacman, permissions).unwrap();
        let sudo = bin.path().join("sudo");
        fs::write(&sudo, "#!/bin/sh\nexec \"$@\"\n").unwrap();
        let mut permissions = fs::metadata(&sudo).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(sudo, permissions).unwrap();
        let state = tempfile::tempdir().unwrap();
        let log = state.path().join("provider.log");

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args([
                "--provider",
                "pacman",
                "install",
                "curl",
                "broken",
                "ripgrep",
            ])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .env("TINYPM_TEST_LOG", &log)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        let commands = fs::read_to_string(log).unwrap();
        assert_eq!(commands.lines().count(), 3);
        assert!(commands.contains("curl"));
        assert!(commands.contains("broken"));
        assert!(commands.contains("ripgrep"));

        let history = fs::read_to_string(state.path().join("tinypm/history.jsonl")).unwrap();
        assert_eq!(history.lines().count(), 2);
        assert!(history.contains("curl"));
        assert!(history.contains("ripgrep"));
        assert!(!history.contains("broken"));
    }

    #[test]
    fn check_has_clear_availability_and_exit_semantics() {
        let bin = tempfile::tempdir().unwrap();
        let brew = bin.path().join("brew");
        fs::write(
            &brew,
            "#!/bin/sh\ncase \"$*\" in 'info present') exit 0;; *) exit 1;; esac\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&brew).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(brew, permissions).unwrap();

        let available = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "check", "present"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(available.status.success());
        assert!(
            String::from_utf8(available.stdout)
                .unwrap()
                .contains("Available: present")
        );

        let unavailable = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "check", "missing"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert_eq!(unavailable.status.code(), Some(1));
        assert!(
            String::from_utf8(unavailable.stderr)
                .unwrap()
                .contains("package not available: missing")
        );

        let available_json = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "check", "present", "--json"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(available_json.status.success());
        let report: serde_json::Value = serde_json::from_slice(&available_json.stdout).unwrap();
        assert_eq!(report["requested"], "present");
        assert_eq!(report["resolved"], "present");
        assert_eq!(report["provider_key"], "brew");
        assert_eq!(report["available"], true);

        let unavailable_json = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "check", "missing", "--json"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert_eq!(unavailable_json.status.code(), Some(1));
        let report: serde_json::Value = serde_json::from_slice(&unavailable_json.stdout).unwrap();
        assert_eq!(report["requested"], "missing");
        assert_eq!(report["available"], false);
        assert!(
            String::from_utf8(unavailable_json.stderr)
                .unwrap()
                .contains("package not available: missing")
        );
    }

    #[test]
    fn doctor_detects_missing_provider_companion_tools() {
        let bin = fake_provider("apt-get");
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "apt", "doctor", "--json"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(report["provider_key"], "apt");
        assert_eq!(report["provider_healthy"], false);
        assert_eq!(
            report["missing_executables"],
            serde_json::json!(["apt-cache", "dpkg-query"])
        );
        assert!(
            report["provider_error"]
                .as_str()
                .unwrap()
                .contains("apt-cache, dpkg-query")
        );
    }

    #[test]
    fn doctor_preserves_explicit_provider_context_when_it_is_missing() {
        let bin = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "doctor", "--json"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(report["provider"], "Homebrew");
        assert_eq!(report["provider_key"], "brew");
        assert_eq!(report["provider_validation"], "command-contract");
        assert_eq!(report["missing_executables"], serde_json::json!(["brew"]));
        assert_eq!(report["provider_healthy"], false);
    }

    #[test]
    fn no_progress_flag_keeps_machine_readable_status_output() {
        let bin = tempfile::tempdir().unwrap();
        let brew = bin.path().join("brew");
        fs::write(
            &brew,
            "#!/bin/sh\nif [ \"$1\" = \"list\" ]; then exit 1; fi\nexit 0\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&brew).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(brew, permissions).unwrap();
        let state = tempfile::tempdir().unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "brew", "--no-progress", "new-package"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains("✓ new-package installed"));
        assert!(!stdout.contains('⠋'));
    }

    #[test]
    fn removal_skips_absent_packages_and_records_only_successes() {
        let bin = tempfile::tempdir().unwrap();
        let brew = bin.path().join("brew");
        let log_dir = tempfile::tempdir().unwrap();
        let log = log_dir.path().join("provider.log");
        fs::write(
            &brew,
            "#!/bin/sh\nif [ \"$1\" = \"list\" ]; then [ \"$3\" = \"present\" ]; exit; fi\nprintf '%s\\n' \"$*\" >> \"$TINYPM_TEST_LOG\"\nexit 0\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&brew).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(brew, permissions).unwrap();
        let state = tempfile::tempdir().unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args([
                "--provider",
                "brew",
                "--no-progress",
                "remove",
                "missing",
                "present",
            ])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .env("TINYPM_TEST_LOG", &log)
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(
            String::from_utf8(output.stdout)
                .unwrap()
                .contains("Not installed: missing")
        );
        let commands = fs::read_to_string(log).unwrap();
        assert_eq!(commands.trim(), "uninstall present");
        let history = fs::read_to_string(state.path().join("tinypm/history.jsonl")).unwrap();
        assert_eq!(history.lines().count(), 1);
        assert!(history.contains("present"));
        assert!(!history.contains("missing"));
    }

    #[test]
    fn history_json_is_valid_and_honors_limit() {
        let state = tempfile::tempdir().unwrap();
        let state_dir = state.path().join("tinypm");
        fs::create_dir(&state_dir).unwrap();
        fs::write(
            state_dir.join("history.jsonl"),
            concat!(
                "{\"id\":1,\"timestamp\":1,\"action\":\"install\",\"requested\":\"curl\",\"resolved\":\"curl\",\"provider\":\"apt\",\"reverts\":null}\n",
                "{\"id\":2,\"timestamp\":2,\"action\":\"install\",\"requested\":\"git\",\"resolved\":\"git\",\"provider\":\"apt\",\"reverts\":null}\n"
            ),
        )
        .unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["history", "1", "--json"])
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let records: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        let records = records.as_array().unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0]["requested"], "git");
    }

    #[test]
    fn empty_managed_json_is_an_empty_array() {
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["managed", "--json"])
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let records: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(records, serde_json::json!([]));
    }

    #[test]
    fn tinypm_rejects_package_changes_and_points_to_grab() {
        for arguments in [
            &["install", "curl"][..],
            &["remove", "curl"][..],
            &["update"][..],
            &["undo", "--yes"][..],
        ] {
            let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
                .args(arguments)
                .output()
                .unwrap();
            assert_eq!(output.status.code(), Some(1));
            let stderr = String::from_utf8(output.stderr).unwrap();
            assert!(
                stderr.contains("belongs to grab"),
                "unexpected stderr: {stderr}"
            );
        }
    }

    #[test]
    fn tinypm_help_hides_package_changing_commands() {
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .arg("--help")
            .output()
            .unwrap();
        assert!(output.status.success());
        let help = String::from_utf8(output.stdout).unwrap();
        assert!(!help.contains("  install"));
        assert!(!help.contains("  remove"));
        assert!(!help.contains("  update"));
        assert!(help.contains("  info"));
        assert!(help.contains("  check"));
        assert!(help.contains("  doctor"));
        assert!(help.contains("  providers"));
    }

    #[test]
    fn doctor_json_reports_provider_and_state_health() {
        let bin = fake_provider("brew");
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "doctor", "--json"])
            .env("PATH", bin.path())
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(report["version"], "0.8.1-alpha");
        assert_eq!(report["requested_provider"], "brew");
        assert_eq!(report["provider"], "Homebrew");
        assert_eq!(report["provider_key"], "brew");
        assert_eq!(report["provider_validation"], "command-contract");
        assert_eq!(report["missing_executables"], serde_json::json!([]));
        assert_eq!(report["provider_healthy"], true);
        assert_eq!(report["state_healthy"], true);
        assert_eq!(report["history_records"], 0);
        assert!(report["executable"].as_str().unwrap().ends_with("/brew"));
        assert!(
            report["state_path"]
                .as_str()
                .unwrap()
                .ends_with("/tinypm/history.jsonl")
        );
    }

    #[test]
    fn doctor_reports_missing_provider_and_broken_history_context() {
        let state = tempfile::tempdir().unwrap();
        let state_dir = state.path().join("tinypm");
        fs::create_dir(&state_dir).unwrap();
        fs::write(state_dir.join("history.jsonl"), "not-json\n").unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "brew", "doctor", "--json"])
            .env("PATH", "")
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(report["requested_provider"], "brew");
        assert_eq!(report["provider"], "Homebrew");
        assert_eq!(report["provider_key"], "brew");
        assert_eq!(report["provider_validation"], "command-contract");
        assert_eq!(report["missing_executables"], serde_json::json!(["brew"]));
        assert_eq!(report["provider_healthy"], false);
        assert_eq!(report["state_healthy"], false);
        assert!(
            report["state_path"]
                .as_str()
                .unwrap()
                .ends_with("/tinypm/history.jsonl")
        );
        assert!(
            report["provider_error"]
                .as_str()
                .unwrap()
                .contains("brew is not installed")
        );
        assert!(
            report["state_error"]
                .as_str()
                .unwrap()
                .contains("invalid history record on line 1")
        );
    }

    #[test]
    fn providers_json_reports_all_backends_and_resolved_paths() {
        let bin = fake_provider("brew");
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["providers", "--json"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let reports: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        let reports = reports.as_array().unwrap();
        assert_eq!(reports.len(), 20);
        let brew = reports
            .iter()
            .find(|report| report["key"] == "brew")
            .unwrap();
        assert_eq!(brew["available"], true);
        assert_eq!(brew["ready"], true);
        assert_eq!(brew["validation"], "command-contract");
        assert_eq!(brew["missing_executables"], serde_json::json!([]));
        assert!(brew["path"].as_str().unwrap().ends_with("/brew"));
        let apt = reports
            .iter()
            .find(|report| report["key"] == "apt")
            .unwrap();
        assert_eq!(apt["available"], false);
        assert_eq!(apt["ready"], false);
        assert_eq!(apt["validation"], "transaction-tested");
        assert_eq!(apt["path"], serde_json::Value::Null);
    }

    #[test]
    fn providers_reports_incomplete_backends() {
        let bin = fake_provider("apt-get");
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["providers", "--json"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let reports: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        let apt = reports
            .as_array()
            .unwrap()
            .iter()
            .find(|report| report["key"] == "apt")
            .unwrap();
        assert_eq!(apt["available"], true);
        assert_eq!(apt["ready"], false);
        assert_eq!(
            apt["missing_executables"],
            serde_json::json!(["apt-cache", "dpkg-query"])
        );
    }

    #[test]
    fn provider_environment_override_is_honored() {
        let bin = tempfile::tempdir().unwrap();
        let brew = bin.path().join("brew");
        fs::write(&brew, "#!/bin/sh\n[ \"$*\" = \"info present\" ]\n").unwrap();
        let mut permissions = fs::metadata(&brew).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(brew, permissions).unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["check", "present"])
            .env("PATH", bin.path())
            .env("TINYPM_PROVIDER", "brew")
            .output()
            .unwrap();
        assert!(output.status.success());
        assert!(
            String::from_utf8(output.stdout)
                .unwrap()
                .contains("via Homebrew")
        );
    }

    #[test]
    fn auto_detection_uses_universal_provider_fallbacks() {
        for provider in ["flatpak", "snap"] {
            let bin = fake_provider(provider);
            let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
                .args(["explain", "firefox", "--json"])
                .env("PATH", bin.path())
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{provider} fallback failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
            assert_eq!(report["provider_key"], provider);
        }
    }

    #[test]
    fn apk_update_dry_run_shows_both_ordered_steps() {
        let bin = fake_provider("apk");
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "apk", "--dry-run", "update"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let stdout = String::from_utf8(output.stdout).unwrap();
        assert!(stdout.contains("Dry run (2 steps)"));
        let refresh = stdout.find("apk update").unwrap();
        let upgrade = stdout.find("apk upgrade").unwrap();
        assert!(refresh < upgrade);
    }

    #[test]
    fn update_has_stable_noninteractive_progress_output() {
        let bin = tempfile::tempdir().unwrap();
        let brew = bin.path().join("brew");
        fs::write(&brew, "#!/bin/sh\nexit 0\n").unwrap();
        let mut permissions = fs::metadata(&brew).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(brew, permissions).unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "brew", "--no-progress", "update"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(
            String::from_utf8(output.stdout).unwrap(),
            "✓ Homebrew packages updated\n"
        );
    }

    #[test]
    fn every_provider_has_a_working_grab_dry_run_contract() {
        let contracts = [
            ("apt", "apt-get", "apt-get install -y example"),
            ("dnf", "dnf", "dnf install -y example"),
            ("pacman", "pacman", "pacman -S --noconfirm example"),
            ("apk", "apk", "apk add example"),
            (
                "zypper",
                "zypper",
                "zypper --non-interactive install example",
            ),
            ("xbps", "xbps-install", "xbps-install -Sy example"),
            ("portage", "emerge", "emerge --ask=n example"),
            ("eopkg", "eopkg", "eopkg install -y example"),
            ("swupd", "swupd", "swupd bundle-add example"),
            (
                "slackpkg",
                "slackpkg",
                "slackpkg -batch=on -default_answer=y install example",
            ),
            ("opkg", "opkg", "opkg install example"),
            ("urpmi", "urpmi", "urpmi --auto example"),
            ("guix", "guix", "guix install example"),
            ("flatpak", "flatpak", "flatpak install -y example"),
            ("snap", "snap", "snap install example"),
            ("nix", "nix", "nix profile install nixpkgs#example"),
            ("brew", "brew", "brew install example"),
        ];

        for (provider, executable, expected) in contracts {
            let bin = fake_provider(executable);
            let output = Command::new(env!("CARGO_BIN_EXE_grab"))
                .args(["--provider", provider, "--dry-run", "example"])
                .env("PATH", bin.path())
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{provider} failed: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            let stdout = String::from_utf8(output.stdout).unwrap();
            assert!(
                stdout.contains(expected),
                "{provider} output `{stdout}` did not contain `{expected}`"
            );
        }
    }

    #[test]
    fn explain_reports_alias_reason_and_passthrough_status() {
        let bin = fake_provider("pacman");
        let aliased = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "pacman", "explain", "gcc++"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(aliased.status.success());
        let aliased = String::from_utf8(aliased.stdout).unwrap();
        assert!(aliased.contains("Resolved     gcc"));
        assert!(aliased.contains("Alias        yes"));
        assert!(aliased.contains("Arch provides GCC and G++ together"));

        let passthrough = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "pacman", "explain", "curl"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(passthrough.status.success());
        let passthrough = String::from_utf8(passthrough.stdout).unwrap();
        assert!(passthrough.contains("Resolved     curl"));
        assert!(passthrough.contains("Alias        no"));
        assert!(passthrough.contains("passed through unchanged"));
    }

    #[test]
    fn explain_json_has_stable_resolution_fields() {
        let bin = fake_provider("dnf");
        let output = Command::new(env!("CARGO_BIN_EXE_tinypm"))
            .args(["--provider", "dnf", "explain", "gcc++", "--json"])
            .env("PATH", bin.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        let report: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
        assert_eq!(report["requested"], "gcc++");
        assert_eq!(report["resolved"], "gcc-c++");
        assert_eq!(report["alias"], true);
        assert_eq!(report["provider"], "DNF");
        assert_eq!(report["provider_key"], "dnf");
        assert_eq!(report["command"], "sudo dnf install -y gcc-c++");
        assert!(report["reason"].as_str().unwrap().contains("Fedora-family"));
    }

    #[test]
    fn provider_manager_aliases_are_accepted() {
        for (provider, executable, expected) in [
            ("emerge", "emerge", "emerge --ask=n example"),
            ("xbps-install", "xbps-install", "xbps-install -Sy example"),
        ] {
            let bin = fake_provider(executable);
            let output = Command::new(env!("CARGO_BIN_EXE_grab"))
                .args(["--provider", provider, "--dry-run", "example"])
                .env("PATH", bin.path())
                .output()
                .unwrap();
            assert!(output.status.success());
            assert!(String::from_utf8(output.stdout).unwrap().contains(expected));
        }
    }

    #[test]
    fn doas_is_used_when_sudo_is_unavailable() {
        if unsafe { libc::geteuid() } == 0 {
            return;
        }
        let bin = tempfile::tempdir().unwrap();
        let log_dir = tempfile::tempdir().unwrap();
        let log = log_dir.path().join("apk.log");
        for (name, source) in [
            (
                "apk",
                "#!/bin/sh\nif [ \"$1\" = \"info\" ]; then exit 1; fi\nprintf '%s\\n' \"$*\" >> \"$TINYPM_TEST_LOG\"\n",
            ),
            ("doas", "#!/bin/sh\nexec \"$@\"\n"),
        ] {
            let executable = bin.path().join(name);
            fs::write(&executable, source).unwrap();
            let mut permissions = fs::metadata(&executable).unwrap().permissions();
            permissions.set_mode(0o755);
            fs::set_permissions(executable, permissions).unwrap();
        }
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "apk", "--no-progress", "example"])
            .env("PATH", bin.path())
            .env("TINYPM_TEST_LOG", &log)
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert!(output.status.success());
        assert_eq!(fs::read_to_string(log).unwrap().trim(), "add example");
    }

    #[test]
    fn missing_privilege_helper_fails_before_provider_execution() {
        if unsafe { libc::geteuid() } == 0 {
            return;
        }
        let bin = tempfile::tempdir().unwrap();
        let marker_dir = tempfile::tempdir().unwrap();
        let marker = marker_dir.path().join("called");
        let apk = bin.path().join("apk");
        fs::write(
            &apk,
            "#!/bin/sh\nif [ \"$1\" = \"info\" ]; then exit 1; fi\nprintf called > \"$TINYPM_TEST_MARKER\"\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&apk).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(apk, permissions).unwrap();
        let state = tempfile::tempdir().unwrap();
        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "apk", "--no-progress", "example"])
            .env("PATH", bin.path())
            .env("TINYPM_TEST_MARKER", &marker)
            .env("XDG_STATE_HOME", state.path())
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(
            String::from_utf8(output.stderr)
                .unwrap()
                .contains("install sudo or doas")
        );
        assert!(!marker.exists());
    }

    #[test]
    fn option_like_package_never_reaches_provider() {
        let bin = tempfile::tempdir().unwrap();
        let marker_dir = tempfile::tempdir().unwrap();
        let marker = marker_dir.path().join("called");
        let pacman = bin.path().join("pacman");
        fs::write(
            &pacman,
            "#!/bin/sh\nprintf called > \"$TINYPM_TEST_MARKER\"\nexit 0\n",
        )
        .unwrap();
        let mut permissions = fs::metadata(&pacman).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(pacman, permissions).unwrap();

        let output = Command::new(env!("CARGO_BIN_EXE_grab"))
            .args(["--provider", "pacman", "--", "--noconfirm"])
            .env("PATH", bin.path())
            .env("TINYPM_TEST_MARKER", &marker)
            .output()
            .unwrap();
        assert_eq!(output.status.code(), Some(1));
        assert!(
            String::from_utf8(output.stderr)
                .unwrap()
                .contains("names cannot begin with '-'")
        );
        assert!(!marker.exists());
    }
}
