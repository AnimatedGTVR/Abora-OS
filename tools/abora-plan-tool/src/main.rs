//! `abora-plan-tool parse|build-native --expected-version <v>`, called by anix.sh.
//! parse: Plan JSON on stdin -> `language\t<lang>` plus `op\tfield1\tfield2` lines.
//! build-native: ANIX Native on stdin -> Plan JSON.

mod native;
mod plan;

use std::io::Read;
use std::process::ExitCode;

const EX_USAGE: u8 = 64;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let Some(command) = args
        .first()
        .filter(|c| *c == "parse" || *c == "build-native")
    else {
        eprintln!("Usage: abora-plan-tool <parse|build-native> --expected-version <version>");
        return ExitCode::from(EX_USAGE);
    };
    let expected = args
        .windows(2)
        .skip(1)
        .find(|pair| pair[0] == "--expected-version")
        .map(|pair| pair[1].clone());
    let Some(expected) = expected else {
        eprintln!("Missing required option: --expected-version");
        return ExitCode::from(EX_USAGE);
    };

    let mut input = String::new();
    if let Err(err) = std::io::stdin().read_to_string(&mut input) {
        eprintln!("Could not read stdin: {err}");
        return ExitCode::FAILURE;
    }

    let result = if command == "parse" {
        plan::parse(&input, &expected)
            .map(|p| plan::render(&p))
            .map_err(|errors| errors.join("\n"))
    } else {
        native::build(&input, &expected).map(|json| json + "\n")
    };
    match result {
        Ok(out) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("{err}");
            ExitCode::FAILURE
        }
    }
}
