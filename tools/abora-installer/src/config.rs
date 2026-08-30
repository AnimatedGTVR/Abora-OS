use std::path::PathBuf;

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const DEFAULT_LEGACY_SCRIPT: &str = "/etc/abora/installer.sh";
pub const DEFAULT_LOG_PATH: &str = "/tmp/abora-install.log";

pub fn default_legacy_script() -> PathBuf {
    std::env::var_os("ABORA_INSTALLER_LEGACY_SCRIPT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_LEGACY_SCRIPT))
}

pub fn log_path() -> PathBuf {
    std::env::var_os("ABORA_INSTALL_LOG")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_LOG_PATH))
}
