use std::ffi::OsString;
use std::path::Path;

pub fn print_help() {
    println!("Abora OS installer");
    println!();
    println!("Usage:");
    println!("  abora-installer [options] [legacy installer args]");
    println!();
    println!("Options:");
    println!("  --legacy-script <path>  Use a different Bash backend");
    println!("  --dry-run               Print what would run");
    println!("  --smoke-test            Check the Rust entry point without installing");
    println!("  -V, --version           Print version");
    println!("  -h, --help              Print help");
}

pub fn print_smoke_status(script: &Path) {
    println!("Abora installer Rust front controller is ready.");
    println!("Legacy backend: {}", script.display());
}

pub fn print_dry_run(script: &Path, passthrough: &[OsString]) {
    println!("Abora installer dry run");
    println!("Legacy backend: {}", script.display());
    if passthrough.is_empty() {
        println!("Args: <none>");
    } else {
        println!("Args: {:?}", passthrough);
    }
}
