//! ANIX Native (`.anix`): one `set`/`enable`/`disable`/`package add|remove`
//! command per line, turned into Plan JSON.

use serde_json::{json, Map, Value};

fn operation(line: &str) -> Result<Value, String> {
    let words: Vec<&str> = line.split_whitespace().collect();
    match words.first().copied().unwrap_or_default() {
        "set" => {
            // A value may contain spaces (a gc.dates spec like "Sun 03:00:00"),
            // so only the first two words are split off.
            let rest = line.trim_start().strip_prefix("set").unwrap_or_default();
            let rest = rest.trim_start();
            let Some(split) = rest.find(char::is_whitespace) else {
                return Err("usage: set <key> <value>".into());
            };
            let (key, value) = (&rest[..split], rest[split..].trim_start());
            if value.is_empty() {
                return Err("usage: set <key> <value>".into());
            }
            Ok(json!({ "op": "set", "key": key, "value": value }))
        }
        verb @ ("enable" | "disable") => match words.as_slice() {
            [_, feature] => Ok(json!({ "op": verb, "feature": feature })),
            _ => Err(format!("usage: {verb} <feature>")),
        },
        "package" => match words.as_slice() {
            [_, "add", name] => Ok(json!({ "op": "package.add", "name": name })),
            [_, "remove", name] => Ok(json!({ "op": "package.remove", "name": name })),
            [_, _, _] => Err("package action must be add or remove".into()),
            _ => Err("usage: package <add|remove> <name>".into()),
        },
        other => Err(format!("unknown ANIX Native command: {other}")),
    }
}

/// Returns the Plan JSON, or `<line>: <error>` for the first bad line.
pub fn build(content: &str, version: &str) -> Result<String, String> {
    let mut operations = Vec::new();
    for (index, raw) in content.split('\n').enumerate() {
        // Only the CR of a CRLF file is dropped: a set value keeps its own spacing.
        let line = raw.trim_start().trim_end_matches('\r');
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        operations.push(operation(line).map_err(|e| format!("{}: {e}", index + 1))?);
    }

    let mut plan = Map::new();
    plan.insert(
        "planVersion".into(),
        version
            .parse::<i64>()
            .map(Value::from)
            .unwrap_or_else(|_| Value::from(version)),
    );
    plan.insert("language".into(), Value::from("anix"));
    plan.insert("operations".into(), Value::Array(operations));
    Ok(Value::Object(plan).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ops(content: &str) -> Vec<Value> {
        let plan: Value = serde_json::from_str(&build(content, "1").unwrap()).unwrap();
        assert_eq!(plan["planVersion"], 1);
        assert_eq!(plan["language"], "anix");
        plan["operations"].as_array().unwrap().clone()
    }

    #[test]
    fn builds_every_command_type() {
        let ops = ops("set hostname nativehost\nenable bluetooth\ndisable openssh\npackage add git\npackage remove vim\n");
        assert_eq!(ops.len(), 5);
        assert_eq!(
            ops[0],
            json!({"op":"set","key":"hostname","value":"nativehost"})
        );
        assert_eq!(ops[1], json!({"op":"enable","feature":"bluetooth"}));
        assert_eq!(ops[2], json!({"op":"disable","feature":"openssh"}));
        assert_eq!(ops[3], json!({"op":"package.add","name":"git"}));
        assert_eq!(ops[4], json!({"op":"package.remove","name":"vim"}));
    }

    #[test]
    fn keeps_key_order_anix_expects() {
        let json = build("set hostname h\n", "1").unwrap();
        assert_eq!(
            json,
            r#"{"planVersion":1,"language":"anix","operations":[{"op":"set","key":"hostname","value":"h"}]}"#
        );
    }

    #[test]
    fn skips_blank_lines_and_comments() {
        assert_eq!(ops("\n  # a comment\nenable bluetooth\n   \n").len(), 1);
    }

    #[test]
    fn reports_the_line_number_and_stops_at_the_first_error() {
        let err = build("enable bluetooth\nset onlyonearg\n", "1").unwrap_err();
        assert!(
            err.starts_with("2:") && err.contains("usage: set <key> <value>"),
            "{err}"
        );
        assert!(build("enable bluetooth\nbadcommand\nenable audio\n", "1")
            .unwrap_err()
            .starts_with("2:"));
    }

    #[test]
    fn rejects_unknown_commands_and_package_actions() {
        assert!(build("launch-missiles now\n", "1")
            .unwrap_err()
            .contains("unknown ANIX Native command: launch-missiles"));
        assert!(build("package frobnicate git\n", "1")
            .unwrap_err()
            .contains("package action must be add or remove"));
        assert!(build("enable a b\n", "1")
            .unwrap_err()
            .contains("usage: enable <feature>"));
    }

    #[test]
    fn strips_only_the_carriage_return_of_crlf_lines() {
        let ops = ops("set hostname myhost\r\nset gc.dates Sun 03:00:00\r\nenable bluetooth\r\n");
        assert_eq!(ops[0]["value"], "myhost");
        assert_eq!(ops[1]["value"], "Sun 03:00:00");
        assert_eq!(ops[2]["feature"], "bluetooth");
    }

    #[test]
    fn non_numeric_versions_stay_strings() {
        let plan: Value = serde_json::from_str(&build("", "2-beta").unwrap()).unwrap();
        assert_eq!(plan["planVersion"], "2-beta");
    }
}
