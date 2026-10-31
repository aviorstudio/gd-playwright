use crate::{Result, config::Config};
use serde_json::{Value, json};

fn point(value: &str) -> Result<Value> {
    let (x, y) = value.split_once(',').ok_or("invalid --to: expected x,y")?;
    let x: f64 = x.trim().parse()?;
    let y: f64 = y.trim().parse()?;
    if !x.is_finite() || !y.is_finite() {
        return Err("destination coordinates must be finite".into());
    }
    Ok(json!({"x":x,"y":y}))
}
pub fn render(config: &Config, action: &str, key: &str) -> Result<String> {
    if !matches!(action, "click" | "drag") {
        return Err(format!("unsupported action {action:?}").into());
    }
    if key.trim().is_empty() {
        return Err("element key is required".into());
    }
    let retries = config.number("retries", 0)?;
    if retries < 0 {
        return Err("retries cannot be negative".into());
    }
    let mut options = json!({"action":action,"key":key,"retries":retries,"retryDelayMs":config.number("retry-delay",50)?.max(1),"steps":config.number("steps",6)?.max(1)});
    if config.number("retry-delay", 50)? <= 0 {
        options["retryDelayMs"] = json!(50);
    }
    if config.number("steps", 6)? <= 0 {
        options["steps"] = json!(6);
    }
    if config.flag("force") {
        options["force"] = json!(true);
    }
    if config.value("expect-event").is_empty() {
        if !config.filters.is_empty() {
            return Err("--filter requires --expect-event".into());
        }
        if retries > 0 {
            return Err("--retries requires --expect-event".into());
        }
    } else {
        let timeout = config.number("timeout", 1000)?;
        let mut confirmation = json!({"event":config.value("expect-event"),"timeoutMs":if timeout>0{timeout}else{1000}});
        let filters = config.filters();
        if !filters.is_empty() {
            confirmation["filters"] = json!(filters);
        }
        options["confirm"] = confirmation;
    }
    if action == "drag" {
        match (config.value("to"), config.value("to-key")) {
            ("", "") => return Err("drag requires --to x,y or --to-key key".into()),
            (to, "") => options["to"] = point(to)?,
            ("", key) => options["toKey"] = json!(key),
            _ => return Err("use either --to or --to-key, not both".into()),
        }
    }
    Ok(
        include_str!("action.js").replacen(
            "__GDPW_OPTIONS__",
            &serde_json::to_string(&options)?,
            1,
        ),
    )
}
pub fn shell(code: &str) -> String {
    format!(
        "playwright-cli run-code '{}'",
        code.replace('\'', "'\"'\"'")
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retries_require_fresh_confirmation_and_shell_quotes_keys() {
        let mut cfg = Config::default();
        cfg.values.insert("retries".into(), "2".into());
        assert!(render(&cfg, "click", "start").is_err());
        cfg.values.insert("expect-event".into(), "ready".into());
        let code = render(&cfg, "click", "a'b").unwrap();
        assert!(code.contains("window.addEventListener(\"godot-event\""));
        assert!(code.contains("if (mouseDown)"));
        assert!(shell(&code).contains("'\"'\"'"));
        assert!(point("NaN,2").is_err());
    }
}
