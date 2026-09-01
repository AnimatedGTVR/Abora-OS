use std::fs::OpenOptions;
use std::io::Write;
use std::path::Path;

pub fn append(path: &Path, message: &str) {
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(message.as_bytes());
    }
}
