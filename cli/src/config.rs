use crate::Result;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Default)]
pub struct Config {
    pub command: String,
    pub args: Vec<String>,
    pub values: BTreeMap<String, String>,
    pub flags: BTreeSet<String>,
    pub filters: Vec<String>,
}
impl Config {
    pub fn value(&self, name: &str) -> &str {
        self.values.get(name).map(String::as_str).unwrap_or("")
    }
    pub fn number(&self, name: &str, default: i64) -> Result<i64> {
        if self.value(name).is_empty() {
            Ok(default)
        } else {
            Ok(self.value(name).parse()?)
        }
    }
    pub fn flag(&self, name: &str) -> bool {
        self.flags.contains(name)
    }
    pub fn parse(args: &[String]) -> Result<Self> {
        let mut config = Self::default();
        let mut index = 0;
        let mut terminated = false;
        let mut used = BTreeSet::new();
        while index < args.len() {
            let arg = &args[index];
            index += 1;
            if !terminated && arg == "--" {
                terminated = true;
                continue;
            }
            if !terminated && arg.starts_with('-') && arg != "-" {
                let (key, value) = arg
                    .trim_start_matches('-')
                    .split_once('=')
                    .map_or((arg.trim_start_matches('-'), None), |(k, v)| (k, Some(v)));
                used.insert(key.to_owned());
                if matches!(
                    key,
                    "json" | "visible" | "force" | "script" | "quiet" | "include-past"
                ) {
                    let enabled = match value.unwrap_or("true") {
                        "true" | "1" | "t" => true,
                        "false" | "0" | "f" => false,
                        _ => return Err(format!("invalid boolean for --{key}").into()),
                    };
                    if enabled {
                        config.flags.insert(key.into());
                    }
                    continue;
                }
                if !matches!(
                    key,
                    "cdp"
                        | "port"
                        | "filter"
                        | "last"
                        | "name"
                        | "since"
                        | "timeout"
                        | "expect-event"
                        | "retries"
                        | "retry-delay"
                        | "to"
                        | "to-key"
                        | "steps"
                ) {
                    return Err(format!("unknown flag --{key}").into());
                }
                let value = if let Some(value) = value {
                    value.into()
                } else {
                    let value = args
                        .get(index)
                        .ok_or_else(|| format!("--{key} needs a value"))?
                        .clone();
                    index += 1;
                    value
                };
                if key == "filter" {
                    config.filters.push(value);
                } else {
                    config.values.insert(key.into(), value);
                }
                continue;
            }
            if config.command.is_empty() {
                config.command = arg.clone();
            } else {
                config.args.push(arg.clone());
            }
        }
        let allowed: &[&str] = match config.command.as_str() {
            "get" => &["json", "force", "script"],
            "list" => &["visible", "filter", "json"],
            "events" => &["last", "name", "filter", "since"],
            "wait" => &["timeout", "include-past", "since", "filter"],
            "watch" => &["name", "filter", "quiet"],
            "script" => &[
                "force",
                "expect-event",
                "filter",
                "timeout",
                "retries",
                "retry-delay",
                "to",
                "to-key",
                "steps",
            ],
            "state" | "status" => &[],
            other => return Err(format!("unknown command {other:?}").into()),
        };
        for key in used.iter().map(String::as_str) {
            if !allowed.contains(&key) && !matches!(key, "cdp" | "port") {
                return Err(format!("unknown flag --{key} for {}", config.command).into());
            }
            if config.command == "script"
                && config.args.first().is_some_and(|v| v == "click")
                && matches!(key, "to" | "to-key" | "steps")
            {
                return Err(format!("unknown flag --{key} for script click").into());
            }
        }
        for key in [
            "port",
            "last",
            "since",
            "timeout",
            "retries",
            "retry-delay",
            "steps",
        ] {
            let _ = config.number(key, 0)?;
        }
        match config.command.as_str() {
            "get" if config.args.is_empty() => {
                return Err("get requires at least one element key".into());
            }
            "wait" if config.args.len() != 1 => return Err("wait requires one event name".into()),
            "script" if config.args.len() != 2 => {
                return Err("script requires click/drag and one element key".into());
            }
            _ => {}
        }
        Ok(config)
    }
    pub fn filters(&self) -> BTreeMap<String, String> {
        self.filters
            .iter()
            .filter_map(|v| v.split_once('=').map(|(k, v)| (k.into(), v.into())))
            .collect()
    }
}
