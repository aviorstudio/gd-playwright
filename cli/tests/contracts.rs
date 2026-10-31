use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use std::{
    process::{Command, Output, Stdio},
    time::Duration,
};
use tokio::{net::TcpListener, time::timeout};
use tokio_tungstenite::{accept_async, tungstenite::Message};

fn command(args: &[&str]) -> Command {
    let mut command = Command::new(
        std::env::var("GDPW_TEST_BINARY").unwrap_or_else(|_| env!("CARGO_BIN_EXE_gdpw").into()),
    );
    command
        .args(args)
        .env_remove("GDPW_PORT")
        .env_remove("GDPW_CDP");
    command
}
async fn output(mut command: Command) -> Output {
    let child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    timeout(
        Duration::from_secs(5),
        tokio::task::spawn_blocking(move || child.wait_with_output()),
    )
    .await
    .unwrap()
    .unwrap()
    .unwrap()
}

async fn query(
    args: &[&str],
    reply: impl Fn(&str, usize) -> Value + Send + 'static,
) -> (Output, Vec<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("ws://{}", listener.local_addr().unwrap());
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let mut socket = accept_async(stream).await.unwrap();
        let mut expressions = Vec::new();
        while let Some(Ok(message)) = socket.next().await {
            if message.is_close() {
                break;
            }
            if !message.is_text() {
                continue;
            }
            let request: Value = serde_json::from_slice(&message.into_data()).unwrap();
            assert_eq!(request["method"], "Runtime.evaluate");
            assert_eq!(request["params"]["returnByValue"], true);
            let expression = request["params"]["expression"].as_str().unwrap();
            let value = reply(expression, expressions.len());
            expressions.push(expression.to_owned());
            for response in [
                json!({"method":"Runtime.consoleAPICalled","params":{}}),
                json!({"id":999,"result":{"result":{"value":"wrong"}}}),
                json!({"id":request["id"],"result":{"result":{"type":"string","value":value.to_string()}}}),
            ] {
                if socket
                    .send(Message::Text(response.to_string().into()))
                    .await
                    .is_err()
                {
                    return expressions;
                }
            }
        }
        expressions
    });
    let mut cmd = command(args);
    cmd.args(["--cdp", &url]);
    let result = output(cmd).await;
    let expressions = timeout(Duration::from_secs(2), server)
        .await
        .unwrap()
        .unwrap();
    (result, expressions)
}

#[tokio::test]
async fn coordinate_queries_correlate_responses_and_preserve_scaling_and_visibility() {
    let (result,expressions)=query(&["get","button","--json"],|_,_|json!({"elements":{"button":{"x":360,"y":640,"w":100,"h":50,"visible":true}},"vp":{"width":720,"height":1280},"canvas":{"x":10,"y":20,"width":360,"height":1280}})).await;
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(
        serde_json::from_slice::<Value>(&result.stdout).unwrap(),
        json!({"key":"button","x":190,"y":660,"w":50,"h":50,"visible":true})
    );
    assert_eq!(expressions.len(), 1);
    let (result, _) = query(
        &["get", "hidden"],
        |_, _| json!({"elements":{"hidden":{"x":1,"visible":false}}}),
    )
    .await;
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("not visible"));
}

#[tokio::test]
async fn list_and_events_keep_typed_json_filtering() {
    let (result,_)=query(&["list","--visible","--filter","unit_","--json"],|_,_|json!({"unit_1":{"x":1,"visible":true},"unit_2":{"visible":false},"other":{"visible":true}})).await;
    assert!(result.status.success());
    let result: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(result.as_object().unwrap().len(), 1);
    for (field, expected) in [("x", 1.), ("y", 0.), ("w", 0.), ("h", 0.)] {
        assert_eq!(result["unit_1"][field].as_f64(), Some(expected));
    }
    assert_eq!(result["unit_1"]["visible"], true);
    let (result, _) = query(&["events", "--name", "ready", "--since", "10", "--filter", "id=2"], |expression, _| {
        assert!(expression.contains("slice(-100)"));
        json!([{"event":"ready","timestamp":5,"data":{"id":2}},{"event":"ready","timestamp":20,"data":{"id":2}},{"event":"other","timestamp":30,"data":{"id":2}}])
    }).await;
    assert!(result.status.success());
    let events: Value = serde_json::from_slice(&result.stdout).unwrap();
    assert_eq!(events.as_array().unwrap().len(), 1);
    assert_eq!(events[0]["timestamp"], 20);
}

#[tokio::test]
async fn fresh_wait_skips_buffered_events_and_times_out_with_nonmatching_payloads() {
    let (result, expressions) = query(
        &["wait", "ready", "--timeout", "500", "--filter", "ok=true"],
        |expression, index| {
            if index == 0 {
                assert!(expression.contains(".length"));
                json!(7)
            } else {
                assert!(
                    expression
                        .split_whitespace()
                        .collect::<String>()
                        .contains("i=7")
                );
                json!([{"event":"ready","timestamp":20,"data":{"ok":true}}])
            }
        },
    )
    .await;
    assert!(result.status.success());
    assert_eq!(expressions.len(), 2);
    let (result, _) = query(
        &["wait", "never", "--include-past", "--timeout", "30"],
        |_, _| json!([]),
    )
    .await;
    assert!(!result.status.success());
    assert!(String::from_utf8_lossy(&result.stderr).contains("timeout waiting for event"));
}

#[tokio::test]
async fn state_includes_namespaced_state_and_status_reports_readiness() {
    let (result, _) = query(&["state"], |expression, _| {
        assert!(expression.contains("window.godotTestState"));
        json!({"test_state":{"fixture":{"ready":true}},"latest_events":{}})
    })
    .await;
    assert!(result.status.success());
    assert_eq!(
        serde_json::from_slice::<Value>(&result.stdout).unwrap()["test_state"]["fixture"]["ready"],
        true
    );
    let (result,_)=query(&["status"],|_,_|json!({"element_count":4,"visible_count":2,"event_count":3,"viewport":{"width":720,"height":1280}})).await;
    assert!(result.status.success());
    assert_eq!(
        String::from_utf8(result.stdout).unwrap(),
        "connected: true\nelements: 4 (2 visible)\nevents: 3\nviewport: 720x1280\n"
    );
}

#[tokio::test]
async fn script_commands_are_offline_and_keep_safe_retry_options() {
    let result = output(command(&[
        "script",
        "drag",
        "enemy'1",
        "--to",
        "1000.5,260",
        "--expect-event",
        "released",
        "--filter",
        "id=1",
        "--retries",
        "2",
    ]))
    .await;
    assert!(result.status.success());
    let command = String::from_utf8(result.stdout).unwrap();
    assert!(command.starts_with("playwright-cli run-code 'async page =>"));
    assert!(command.contains("'\"'\"'"));
    assert!(command.contains("window.addEventListener"));
    assert!(command.contains("\"retries\":2"));
    assert!(command.contains("\"id\":\"1\""));
    let result = output(self::command(&[
        "script",
        "click",
        "button",
        "--retries",
        "2",
    ]))
    .await;
    assert!(!result.status.success());
}
