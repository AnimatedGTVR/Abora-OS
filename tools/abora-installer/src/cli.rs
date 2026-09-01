use std::ffi::OsString;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Args {
    pub help: bool,
    pub version: bool,
    pub dry_run: bool,
    pub smoke_test: bool,
    pub legacy_script: PathBuf,
    pub passthrough: Vec<OsString>,
}

impl Args {
    pub fn parse<I>(iter: I) -> Result<Self, String>
    where
        I: IntoIterator<Item = OsString>,
    {
        let mut args = Self {
            help: false,
            version: false,
            dry_run: false,
            smoke_test: false,
            legacy_script: crate::config::default_legacy_script(),
            passthrough: Vec::new(),
        };

        let mut iter = iter.into_iter();
        while let Some(arg) = iter.next() {
            match arg.to_string_lossy().as_ref() {
                "-h" | "--help" => args.help = true,
                "-V" | "--version" => args.version = true,
                "--dry-run" => args.dry_run = true,
                "--smoke-test" => args.smoke_test = true,
                "--legacy-script" => {
                    let Some(path) = iter.next() else {
                        return Err("--legacy-script needs a path".to_string());
                    };
                    args.legacy_script = PathBuf::from(path);
                }
                "--" => {
                    args.passthrough.extend(iter);
                    break;
                }
                _ => args.passthrough.push(arg),
            }
        }

        Ok(args)
    }
}

#[cfg(test)]
mod tests {
    use super::Args;
    use std::ffi::OsString;
    use std::path::PathBuf;

    fn parse(items: &[&str]) -> Args {
        Args::parse(items.iter().map(OsString::from)).expect("args should parse")
    }

    #[test]
    fn parses_legacy_script_and_passthrough() {
        let args = parse(&["--legacy-script", "/tmp/install.sh", "--force"]);
        assert_eq!(args.legacy_script, PathBuf::from("/tmp/install.sh"));
        assert_eq!(args.passthrough, vec![OsString::from("--force")]);
    }

    #[test]
    fn stops_at_double_dash() {
        let args = parse(&["--", "--legacy-script", "kept"]);
        assert_eq!(
            args.passthrough,
            vec![OsString::from("--legacy-script"), OsString::from("kept")]
        );
    }
}
