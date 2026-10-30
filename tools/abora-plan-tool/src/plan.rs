//! Shape validation for ANIX Plan JSON. Two rules deliberately stay in anix.sh,
//! where other commands share them: feature names (feature_to_anix_key) and
//! what each `set` value must look like (do_set).

use serde_json::Value;

const SET_KEYS: &[&str] = &[
    "hostname",
    "timezone",
    "keyboard",
    "keyboard.console",
    "keyboard.xkb",
    "desktop",
    "wallpaper",
    "shell",
    "gc.days",
    "garbageCollect.dates",
    "gc.dates",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Operation {
    pub op: String,
    pub field1: String,
    pub field2: String,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Plan {
    pub language: String,
    pub operations: Vec<Operation>,
}

/// anix.sh splits the output on tabs and newlines, so a value containing one
/// would corrupt that framing instead of failing.
fn has_control_chars(s: &str) -> bool {
    s.contains(['\t', '\n', '\r'])
}

pub fn valid_package_name(name: &str) -> bool {
    !name.is_empty()
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '+' | '-'))
}

fn string_field(entry: &Value, name: &str) -> String {
    entry
        .get(name)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn plan_version(root: &Value) -> String {
    match root.get("planVersion") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    }
}

pub fn parse(json: &str, expected_version: &str) -> Result<Plan, Vec<String>> {
    let root: Value = match serde_json::from_str(json) {
        Ok(v @ Value::Object(_)) => v,
        _ => return Err(vec!["Plan is not valid JSON.".into()]),
    };

    let version = plan_version(&root);
    if version != expected_version {
        let shown = if version.is_empty() {
            "missing"
        } else {
            &version
        };
        return Err(vec![format!(
            "Unsupported plan version: '{shown}' (expected {expected_version})."
        )]);
    }
    let Some(entries) = root.get("operations").and_then(Value::as_array) else {
        return Err(vec!["Plan is missing an 'operations' array.".into()]);
    };

    let language = string_field(&root, "language");
    let mut errors = Vec::new();
    if has_control_chars(&language) {
        errors
            .push("language must not contain tab, newline, or carriage return characters.".into());
    }

    let mut operations = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        let op = string_field(entry, "op");
        match op.as_str() {
            "set" => {
                let key = string_field(entry, "key");
                let value = string_field(entry, "value");
                if !SET_KEYS.contains(&key.as_str()) {
                    errors.push(format!("operation {index}: unknown set key '{key}'"));
                }
                if value.is_empty() {
                    errors.push(format!("operation {index}: set requires a value"));
                } else if has_control_chars(&value) {
                    errors.push(format!(
                        "operation {index}: set value must not contain tab, newline, or carriage return characters"
                    ));
                }
                operations.push(Operation {
                    op,
                    field1: key,
                    field2: value,
                });
            }
            "enable" | "disable" => {
                let feature = string_field(entry, "feature");
                if has_control_chars(&feature) {
                    errors.push(format!(
                        "operation {index}: feature must not contain tab, newline, or carriage return characters"
                    ));
                }
                operations.push(Operation {
                    op,
                    field1: feature,
                    field2: String::new(),
                });
            }
            "package.add" | "package.remove" => {
                let name = string_field(entry, "name");
                if !valid_package_name(&name) {
                    errors.push(format!("operation {index}: invalid package name '{name}'"));
                }
                operations.push(Operation {
                    op,
                    field1: name,
                    field2: String::new(),
                });
            }
            _ => errors.push(format!("operation {index}: unknown op '{op}'")),
        }
    }

    if errors.is_empty() {
        Ok(Plan {
            language,
            operations,
        })
    } else {
        Err(errors)
    }
}

/// The line format anix.sh reads: a language header, then one tab-separated
/// line per operation.
pub fn render(plan: &Plan) -> String {
    let mut out = format!("language\t{}\n", plan.language);
    for op in &plan.operations {
        out.push_str(&format!("{}\t{}\t{}\n", op.op, op.field1, op.field2));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn op(op: &str, f1: &str, f2: &str) -> Operation {
        Operation {
            op: op.into(),
            field1: f1.into(),
            field2: f2.into(),
        }
    }

    fn errors(json: &str) -> Vec<String> {
        parse(json, "1").expect_err("plan should be rejected")
    }

    #[test]
    fn accepts_a_well_formed_plan() {
        let plan = parse(
            r#"{"planVersion":1,"language":"test","operations":[
              {"op":"set","key":"hostname","value":"planhost"},
              {"op":"enable","feature":"bluetooth"},
              {"op":"package.add","name":"firefox"}
            ]}"#,
            "1",
        )
        .unwrap();
        assert_eq!(plan.language, "test");
        assert_eq!(
            plan.operations,
            vec![
                op("set", "hostname", "planhost"),
                op("enable", "bluetooth", ""),
                op("package.add", "firefox", ""),
            ]
        );
        assert_eq!(
            render(&plan),
            "language\ttest\nset\thostname\tplanhost\nenable\tbluetooth\t\npackage.add\tfirefox\t\n"
        );
    }

    #[test]
    fn rejects_malformed_json_and_non_objects() {
        assert!(errors("{not json")[0].contains("not valid JSON"));
        assert!(errors("[1,2]")[0].contains("not valid JSON"));
    }

    #[test]
    fn rejects_wrong_or_missing_plan_version() {
        assert!(
            errors(r#"{"planVersion":2,"operations":[]}"#)[0].contains("Unsupported plan version")
        );
        assert!(errors(r#"{"operations":[]}"#)[0].contains("missing"));
        assert!(parse(r#"{"planVersion":"1","operations":[]}"#, "1").is_ok());
    }

    #[test]
    fn rejects_missing_operations_array() {
        assert!(errors(r#"{"planVersion":1}"#)[0].contains("operations"));
    }

    #[test]
    fn rejects_unknown_set_key_and_missing_value() {
        assert!(errors(
            r#"{"planVersion":1,"operations":[{"op":"set","key":"not-a-real-key","value":"x"}]}"#
        )[0]
        .contains("unknown set key"));
        assert!(
            errors(r#"{"planVersion":1,"operations":[{"op":"set","key":"hostname"}]}"#)[0]
                .contains("requires a value")
        );
    }

    #[test]
    fn rejects_framing_characters() {
        assert!(errors(
            r#"{"planVersion":1,"operations":[{"op":"set","key":"wallpaper","value":"foo\nbar"}]}"#
        )[0]
        .contains("must not contain tab, newline"));
        assert!(errors(
            r#"{"planVersion":1,"operations":[{"op":"enable","feature":"blue\ttooth"}]}"#
        )[0]
        .contains("must not contain tab, newline"));
        assert!(errors(r#"{"planVersion":1,"language":"te\rst","operations":[{"op":"package.add","name":"firefox"}]}"#)[0]
            .contains("language must not contain"));
    }

    #[test]
    fn rejects_invalid_package_names_and_unknown_ops() {
        assert!(errors(
            r#"{"planVersion":1,"operations":[{"op":"package.add","name":"firefox; rm -rf /"}]}"#
        )[0]
        .contains("invalid package name"));
        assert!(
            errors(r#"{"planVersion":1,"operations":[{"op":"launch-missiles"}]}"#)[0]
                .contains("unknown op")
        );
        assert!(errors(r#"{"planVersion":1,"operations":[42]}"#)[0].contains("unknown op ''"));
    }

    #[test]
    fn passes_unknown_feature_names_through() {
        let plan = parse(
            r#"{"planVersion":1,"operations":[{"op":"enable","feature":"totally-made-up"}]}"#,
            "1",
        )
        .unwrap();
        assert_eq!(plan.operations[0].field1, "totally-made-up");
    }

    #[test]
    fn reports_every_failure_in_one_run() {
        let errs = errors(
            r#"{"planVersion":1,"operations":[
              {"op":"set","key":"bogus","value":"x"},
              {"op":"package.add","name":"bad name!"}
            ]}"#,
        );
        assert_eq!(errs.len(), 2);
    }

    #[test]
    fn language_defaults_to_empty() {
        let plan = parse(r#"{"planVersion":1,"operations":[]}"#, "1").unwrap();
        assert_eq!(
            plan,
            Plan {
                language: String::new(),
                operations: vec![]
            }
        );
    }
}
