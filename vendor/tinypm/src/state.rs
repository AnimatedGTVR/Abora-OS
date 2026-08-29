use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Transaction {
    #[serde(default, deserialize_with = "deserialize_id")]
    pub id: String,
    pub timestamp: u64,
    pub action: String,
    pub requested: String,
    pub resolved: String,
    pub provider: String,
    #[serde(default, deserialize_with = "deserialize_optional_id")]
    pub reverts: Option<String>,
}

impl Transaction {
    pub fn new(action: &str, requested: &str, resolved: &str, provider: &str) -> Self {
        let duration = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default();
        Self {
            id: Uuid::new_v4().simple().to_string(),
            timestamp: duration.as_secs(),
            action: action.to_owned(),
            requested: requested.to_owned(),
            resolved: resolved.to_owned(),
            provider: provider.to_owned(),
            reverts: None,
        }
    }

    pub fn reversing(original: &Self) -> Self {
        let action = if original.action == "install" {
            "remove"
        } else {
            "install"
        };
        let mut transaction = Self::new(
            action,
            &original.requested,
            &original.resolved,
            &original.provider,
        );
        transaction.reverts = Some(original.id.clone());
        transaction
    }
}

pub struct State {
    history_path: PathBuf,
}

impl State {
    pub fn discover() -> Result<Self> {
        let root = if let Some(path) = env::var_os("XDG_STATE_HOME") {
            PathBuf::from(path)
        } else {
            let home = env::var_os("HOME").context("HOME is not set")?;
            PathBuf::from(home).join(".local/state")
        };
        Ok(Self::at(root.join("tinypm")))
    }

    pub fn at(root: PathBuf) -> Self {
        Self {
            history_path: root.join("history.jsonl"),
        }
    }

    pub fn append(&self, transaction: &Transaction) -> Result<()> {
        let parent = self
            .history_path
            .parent()
            .context("history path has no parent directory")?;
        fs::create_dir_all(parent)
            .with_context(|| format!("could not create {}", parent.display()))?;
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .read(true)
            .open(&self.history_path)
            .with_context(|| format!("could not open {}", self.history_path.display()))?;
        FileExt::lock_exclusive(&file).context("could not lock transaction history")?;
        let mut record = serde_json::to_vec(transaction).context("could not encode transaction")?;
        record.push(b'\n');
        file.write_all(&record)
            .context("could not write transaction")?;
        file.sync_data().context("could not persist transaction")?;
        FileExt::unlock(&file).context("could not unlock transaction history")?;
        Ok(())
    }

    pub fn history(&self) -> Result<Vec<Transaction>> {
        if !self.history_path.exists() {
            return Ok(Vec::new());
        }
        let file = File::open(&self.history_path)
            .with_context(|| format!("could not read {}", self.history_path.display()))?;
        FileExt::lock_shared(&file).context("could not lock transaction history")?;
        let mut history = BufReader::new(&file)
            .lines()
            .enumerate()
            .map(|(index, line)| {
                let line =
                    line.with_context(|| format!("could not read history line {}", index + 1))?;
                serde_json::from_str::<Transaction>(&line)
                    .with_context(|| format!("invalid history record on line {}", index + 1))
            })
            .collect::<Result<Vec<_>>>()?;
        FileExt::unlock(&file).context("could not unlock transaction history")?;
        // Records written by the earliest Rust alpha did not contain IDs.
        for (index, transaction) in history.iter_mut().enumerate() {
            if transaction.id.is_empty() {
                transaction.id = format!("legacy-{}", index + 1);
            }
        }
        Ok(history)
    }

    pub fn managed(&self) -> Result<Vec<Transaction>> {
        let mut packages = BTreeMap::<(String, String), Transaction>::new();
        for transaction in self.history()? {
            let key = (transaction.provider.clone(), transaction.resolved.clone());
            match transaction.action.as_str() {
                "install" => {
                    packages.insert(key, transaction);
                }
                "remove" => {
                    packages.remove(&key);
                }
                _ => {}
            }
        }
        Ok(packages.into_values().collect())
    }

    pub fn latest_reversible(&self) -> Result<Option<Transaction>> {
        let history = self.history()?;
        let reverted = history
            .iter()
            .filter_map(|transaction| transaction.reverts.clone())
            .collect::<BTreeSet<_>>();
        Ok(history.into_iter().rev().find(|transaction| {
            transaction.reverts.is_none()
                && matches!(transaction.action.as_str(), "install" | "remove")
                && !reverted.contains(&transaction.id)
        }))
    }

    pub fn history_path(&self) -> &Path {
        &self.history_path
    }
}

fn deserialize_id<'de, D>(deserializer: D) -> std::result::Result<String, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum StoredId {
        String(String),
        Number(u64),
    }
    Ok(match StoredId::deserialize(deserializer)? {
        StoredId::String(id) => id,
        StoredId::Number(id) => id.to_string(),
    })
}

fn deserialize_optional_id<'de, D>(deserializer: D) -> std::result::Result<Option<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum StoredId {
        String(String),
        Number(u64),
    }
    Ok(
        Option::<StoredId>::deserialize(deserializer)?.map(|id| match id {
            StoredId::String(id) => id,
            StoredId::Number(id) => id.to_string(),
        }),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use std::sync::Arc;

    #[test]
    fn history_round_trips_and_managed_reflects_removals() {
        let temp = tempfile::tempdir().unwrap();
        let state = State::at(temp.path().to_owned());
        state
            .append(&Transaction::new("install", "gcc++", "gcc", "pacman"))
            .unwrap();
        state
            .append(&Transaction::new("install", "curl", "curl", "pacman"))
            .unwrap();
        state
            .append(&Transaction::new("remove", "gcc++", "gcc", "pacman"))
            .unwrap();

        assert_eq!(state.history().unwrap().len(), 3);
        let managed = state.managed().unwrap();
        assert_eq!(managed.len(), 1);
        assert_eq!(managed[0].resolved, "curl");
    }

    #[test]
    fn missing_history_is_empty() {
        let temp = tempfile::tempdir().unwrap();
        let state = State::at(temp.path().join("missing"));
        assert!(state.history().unwrap().is_empty());
    }

    #[test]
    fn undo_records_prevent_selecting_the_same_transaction_twice() {
        let temp = tempfile::tempdir().unwrap();
        let state = State::at(temp.path().to_owned());
        let install = Transaction::new("install", "ripgrep", "ripgrep", "apt");
        state.append(&install).unwrap();
        assert_eq!(state.latest_reversible().unwrap(), Some(install.clone()));

        state.append(&Transaction::reversing(&install)).unwrap();
        assert_eq!(state.latest_reversible().unwrap(), None);
        assert!(state.managed().unwrap().is_empty());
    }

    #[test]
    fn concurrent_writers_produce_complete_records() {
        let temp = tempfile::tempdir().unwrap();
        let state = Arc::new(State::at(temp.path().to_owned()));
        let writers = (0..8)
            .map(|writer| {
                let state = Arc::clone(&state);
                std::thread::spawn(move || {
                    for package in 0..25 {
                        let name = format!("package-{writer}-{package}");
                        state
                            .append(&Transaction::new("install", &name, &name, "apt"))
                            .unwrap();
                    }
                })
            })
            .collect::<Vec<_>>();
        for writer in writers {
            writer.join().unwrap();
        }

        let history = state.history().unwrap();
        assert_eq!(history.len(), 200);
        assert!(
            history
                .iter()
                .all(|transaction| transaction.action == "install")
        );
        assert_eq!(
            history
                .iter()
                .map(|transaction| &transaction.id)
                .collect::<HashSet<_>>()
                .len(),
            200
        );
        assert!(history.iter().all(|transaction| transaction.id.len() == 32));
    }

    #[test]
    fn legacy_numeric_and_missing_ids_remain_readable() {
        let temp = tempfile::tempdir().unwrap();
        let state = State::at(temp.path().to_owned());
        fs::create_dir_all(temp.path()).unwrap();
        fs::write(
            temp.path().join("history.jsonl"),
            concat!(
                "{\"id\":123,\"timestamp\":1,\"action\":\"install\",\"requested\":\"curl\",\"resolved\":\"curl\",\"provider\":\"apt\"}\n",
                "{\"timestamp\":2,\"action\":\"install\",\"requested\":\"git\",\"resolved\":\"git\",\"provider\":\"apt\"}\n"
            ),
        )
        .unwrap();
        let history = state.history().unwrap();
        assert_eq!(history[0].id, "123");
        assert_eq!(history[1].id, "legacy-2");
    }
}
