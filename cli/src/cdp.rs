use crate::{Result, config::Config};
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{Value, json};
use std::{collections::BTreeSet, fs, process::Command, time::Duration};
use tokio::{
    net::TcpStream,
    time::{Instant, sleep, timeout, timeout_at},
};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async_with_config,
    tungstenite::{Message, protocol::WebSocketConfig},
};

pub struct Client {
    socket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    id: u64,
}
impl Client {
    pub async fn connect(url: &str) -> Result<Self> {
        let settings = WebSocketConfig::default()
            .max_message_size(Some(32 << 20))
            .max_frame_size(Some(32 << 20));
        let (socket, _) = timeout(
            Duration::from_secs(5),
            connect_async_with_config(url, Some(settings), true),
        )
        .await??;
        Ok(Self { socket, id: 0 })
    }
    pub async fn evaluate(&mut self, expression: &str, budget: Duration) -> Result<Value> {
        self.id += 1;
        let deadline = Instant::now() + budget;
        timeout_at(deadline,self.socket.send(Message::Text(json!({"id":self.id,"method":"Runtime.evaluate","params":{"expression":expression,"returnByValue":true}}).to_string().into()))).await??;
        loop {
            let message = timeout_at(deadline, self.socket.next())
                .await?
                .ok_or("CDP connection closed")??;
            if matches!(message, Message::Close(_)) {
                return Err("CDP connection closed".into());
            }
            if !matches!(message, Message::Text(_) | Message::Binary(_)) {
                continue;
            }
            let Ok(response) = serde_json::from_slice::<Value>(&message.into_data()) else {
                continue;
            };
            if response["id"].as_u64() != Some(self.id) {
                continue;
            }
            if let Some(error) = response.get("error") {
                return Err(format!(
                    "CDP error: {}",
                    error["message"].as_str().unwrap_or("unknown error")
                )
                .into());
            }
            if let Some(error) = response["result"].get("exceptionDetails") {
                return Err(format!(
                    "JS exception: {}",
                    error["text"].as_str().unwrap_or("unknown exception")
                )
                .into());
            }
            return Ok(response["result"]["result"]["value"].clone());
        }
    }
    pub async fn json(&mut self, expression: &str) -> Result<Value> {
        self.json_for(expression, Duration::from_secs(5)).await
    }
    pub async fn json_for(&mut self, expression: &str, budget: Duration) -> Result<Value> {
        let value = self.evaluate(expression, budget).await?;
        let text = value
            .as_str()
            .ok_or("expression did not return a JSON string")?;
        Ok(serde_json::from_str(text)?)
    }
}

#[derive(Deserialize)]
struct Target {
    #[serde(rename = "type")]
    kind: String,
    #[serde(rename = "webSocketDebuggerUrl", default)]
    url: String,
}
async fn targets(port: i64) -> Result<Vec<Target>> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_millis(500))
        .build()?;
    let mut response = client
        .get(format!("http://localhost:{port}/json"))
        .send()
        .await?;
    let mut bytes = Vec::new();
    while let Some(chunk) = response.chunk().await? {
        if bytes.len() + chunk.len() > 4 << 20 {
            return Err("CDP target list exceeds 4 MiB".into());
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(serde_json::from_slice(&bytes)?)
}
async fn matching(targets: &[Target]) -> Option<Client> {
    for target in targets {
        if target.kind != "page" || target.url.is_empty() {
            continue;
        }
        if let Ok(mut client)=Client::connect(&target.url).await&&client.evaluate("window.godotElements != null || window.godotEvents != null || window.godotTestState != null",Duration::from_secs(5)).await.ok()==Some(json!(true)){return Some(client);}
    }
    None
}
pub fn ports(lines: &[String]) -> Vec<i64> {
    let mut ports = Vec::new();
    let mut seen = BTreeSet::new();
    for line in lines {
        let words: Vec<_> = line
            .split(|c: char| c == '\0' || c.is_whitespace())
            .filter(|v| !v.is_empty())
            .collect();
        for (index, word) in words.iter().enumerate() {
            let value = word.strip_prefix("--remote-debugging-port=").or_else(|| {
                if *word == "--remote-debugging-port" {
                    words.get(index + 1).copied()
                } else {
                    None
                }
            });
            if let Some(value) = value
                && value.bytes().all(|v| v.is_ascii_digit())
                && let Ok(port) = value.parse::<i64>()
                && (1..=65535).contains(&port)
                && seen.insert(port)
            {
                ports.push(port);
            }
        }
    }
    for port in [9222, 9229] {
        if seen.insert(port) {
            ports.push(port);
        }
    }
    ports
}
fn process_lines() -> Vec<String> {
    if cfg!(target_os = "linux") {
        let mut entries: Vec<_> = fs::read_dir("/proc")
            .into_iter()
            .flatten()
            .filter_map(|entry| {
                let entry = entry.ok()?;
                let id = entry.file_name().to_str()?.parse::<u64>().ok()?;
                Some((id, entry.path()))
            })
            .collect();
        entries.sort_by(|a, b| b.0.cmp(&a.0));
        return entries
            .iter()
            .filter_map(|(_, path)| {
                fs::read(path.join("cmdline"))
                    .ok()
                    .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
            })
            .collect();
    }
    let (name, args): (&str, &[&str]) = if cfg!(target_os = "macos") {
        ("ps", &["-ax", "-o", "pid=,command="])
    } else if cfg!(target_os = "windows") {
        (
            "powershell",
            &[
                "-NoProfile",
                "-Command",
                "Get-CimInstance Win32_Process | Sort-Object ProcessId -Descending | Select-Object -ExpandProperty CommandLine",
            ],
        )
    } else {
        return Vec::new();
    };
    let Ok(output) = Command::new(name).args(args).output() else {
        return Vec::new();
    };
    let mut lines: Vec<_> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::to_owned)
        .collect();
    if cfg!(target_os = "macos") {
        lines.reverse();
    }
    lines
}
pub async fn connect(config: &Config) -> Result<Client> {
    let _ = rustls::crypto::ring::default_provider().install_default();
    if !config.value("cdp").is_empty() {
        return Client::connect(config.value("cdp")).await;
    }
    let explicit = config.number("port", 0)?;
    let port = if explicit > 0 {
        Some(explicit)
    } else if let Ok(url) = std::env::var("GDPW_CDP")
        && !url.is_empty()
    {
        return Client::connect(&url).await;
    } else {
        std::env::var("GDPW_PORT")
            .ok()
            .and_then(|value| value.parse().ok())
            .filter(|value: &i64| *value > 0)
    };
    if let Some(port) = port {
        let targets = targets(port).await?;
        if let Some(client) = matching(&targets).await {
            return Ok(client);
        }
        for target in targets {
            if target.kind == "page" && !target.url.is_empty() {
                return Client::connect(&target.url).await;
            }
        }
        return Err(format!("no page target found on port {port}").into());
    }
    let candidates = ports(&process_lines());
    for attempt in 0..30 {
        let mut waiting = false;
        for port in &candidates {
            if let Ok(targets) = targets(*port).await {
                if let Some(client) = matching(&targets).await {
                    return Ok(client);
                }
                if targets
                    .iter()
                    .any(|target| target.kind == "page" && !target.url.is_empty())
                {
                    waiting = true;
                    break;
                }
            }
        }
        if !waiting {
            break;
        }
        if attempt < 29 {
            sleep(Duration::from_millis(100)).await;
        }
    }
    for port in &candidates {
        if let Ok(targets) = targets(*port).await
            && let Some(client) = matching(&targets).await
        {
            return Ok(client);
        }
    }
    Err(format!("could not connect to browser; set GDPW_PORT, pass --port, or run `playwright-cli open <url>` first; no gd-playwright page on ports {candidates:?}").into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn discovered_ports_preserve_newest_first_and_skip_invalid_duplicate_values() {
        assert_eq!(ports(&["chrome\0--remote-debugging-port=40001\0".into(),"chrome --remote-debugging-port 40002 --remote-debugging-port=40001".into(),"chrome --remote-debugging-port=99999 --remote-debugging-port=0 --remote-debugging-port=5x".into()]),vec![40001,40002,9222,9229]);
    }
}
