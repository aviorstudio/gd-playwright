use crate::{Result, action, cdp, config::Config};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io::{self, Write},
    time::Duration,
};
use tokio::time::{Instant, sleep};

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct Element {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    visible: bool,
}
#[derive(Default, Deserialize)]
#[serde(default)]
struct Viewport {
    width: f64,
    height: f64,
}
#[derive(Default, Deserialize)]
#[serde(default)]
struct Canvas {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}
#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct Event {
    event: String,
    timestamp: i64,
    data: Option<BTreeMap<String, Value>>,
}

fn print(value: &impl Serialize, pretty: bool) -> Result<()> {
    let mut out = io::stdout().lock();
    if pretty {
        serde_json::to_writer_pretty(&mut out, value)?;
    } else {
        serde_json::to_writer(&mut out, value)?;
    }
    writeln!(out)?;
    out.flush()?;
    Ok(())
}
fn string(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => "<nil>".into(),
        Value::Array(v) => format!("[{}]", v.iter().map(string).collect::<Vec<_>>().join(" ")),
        Value::Object(v) => format!(
            "map[{}]",
            v.iter()
                .map(|(k, v)| format!("{k}:{}", string(v)))
                .collect::<Vec<_>>()
                .join(" ")
        ),
        other => other.to_string(),
    }
}
fn matches(event: &Event, filters: &BTreeMap<String, String>) -> bool {
    filters.iter().all(|(k, expected)| {
        event
            .data
            .as_ref()
            .and_then(|data| data.get(k))
            .is_some_and(|v| string(v) == *expected)
    })
}
fn scaled(element: &Element, vp: &Viewport, canvas: &Canvas) -> [i64; 4] {
    if vp.width == 0. || vp.height == 0. {
        [
            element.x.round() as i64,
            element.y.round() as i64,
            element.w.round() as i64,
            element.h.round() as i64,
        ]
    } else {
        [
            (canvas.x + element.x * canvas.width / vp.width).round() as i64,
            (canvas.y + element.y * canvas.height / vp.height).round() as i64,
            (element.w * canvas.width / vp.width).round() as i64,
            (element.h * canvas.height / vp.height).round() as i64,
        ]
    }
}

async fn get(config: &Config, client: &mut cdp::Client) -> Result<()> {
    let keys = serde_json::to_string(&config.args)?;
    let js = format!(
        "JSON.stringify((function() {{ var els=window.godotElements || {{}}; var keys={keys};var results={{}};for(var i=0;i<keys.length;i++){{results[keys[i]]=els[keys[i]]||null;}}return {{elements:results,vp:window.godotElementsViewport||null,canvas:document.querySelector('canvas')?document.querySelector('canvas').getBoundingClientRect():null}};}})())"
    );
    let result = client.json(&js).await?;
    let viewport: Viewport = if result["vp"].is_null() {
        Viewport {
            width: 720.,
            height: 1280.,
        }
    } else {
        serde_json::from_value(result["vp"].clone())?
    };
    let canvas: Canvas = if result["canvas"].is_null() {
        Canvas {
            x: 0.,
            y: 0.,
            width: viewport.width,
            height: viewport.height,
        }
    } else {
        serde_json::from_value(result["canvas"].clone())?
    };
    let mut errors = Vec::new();
    for key in &config.args {
        let value = &result["elements"][key];
        if value.is_null() {
            let keys = client
                .json("JSON.stringify(Object.keys(window.godotElements || {}).sort())")
                .await
                .ok()
                .and_then(|v| serde_json::from_value::<Vec<String>>(v).ok())
                .unwrap_or_default();
            let hint = keys.join(", ");
            let hint = if hint.chars().count() > 200 {
                format!("{}...", hint.chars().take(200).collect::<String>())
            } else {
                hint
            };
            errors.push(if keys.is_empty() {
                format!("element {key:?} not found — run `gdpw list` to see available elements")
            } else {
                format!("element {key:?} not found — available: {hint}")
            });
            continue;
        }
        let element: Element = serde_json::from_value(value.clone())?;
        if !element.visible && !config.flag("force") {
            if config.args.len() == 1 {
                errors.push(format!(
                    "element {key:?} is not visible (use --force to get coordinates anyway)"
                ));
            }
            continue;
        }
        let [x, y, w, h] = scaled(&element, &viewport, &canvas);
        if config.flag("json") {
            print(
                &json!({"key":key,"x":x,"y":y,"w":w,"h":h,"visible":element.visible}),
                false,
            )?;
        } else if config.args.len() > 1 {
            println!("{key} {x} {y}");
        } else {
            println!("{x} {y}");
        }
    }
    if !errors.is_empty() {
        return Err(errors.join("\n").into());
    }
    Ok(())
}

async fn count(client: &mut cdp::Client) -> i64 {
    client
        .json("JSON.stringify((window.godotEvents || []).length)")
        .await
        .ok()
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
}

async fn wait(config: &Config, client: &mut cdp::Client) -> Result<()> {
    let start = if config.flag("include-past") {
        0
    } else {
        count(client).await
    };
    let duration = config.number("timeout", 10000)?;
    let since = config.number("since", 0)?;
    let name = &config.args[0];
    let filters = config.filters();
    let deadline = Instant::now()
        .checked_add(Duration::from_millis(duration.max(0) as u64))
        .ok_or("wait timeout is too large")?;
    let js = format!(
        "JSON.stringify((function() {{var evts=window.godotEvents||[];var result=[];for(var i={start};i<evts.length;i++){{var e=evts[i];if(e.event!=={})continue;if({since}>0&&e.timestamp<={since})continue;result.push(e);}}return result;}})())",
        serde_json::to_string(name)?
    );
    loop {
        let remaining = deadline
            .saturating_duration_since(Instant::now())
            .max(Duration::from_millis(1));
        if let Ok(value) = client.json_for(&js, remaining).await
            && let Ok(events) = serde_json::from_value::<Vec<Event>>(value)
            && let Some(event) = events.iter().find(|event| matches(event, &filters))
        {
            print(event, true)?;
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err(format!("timeout waiting for event {name:?} after {duration}ms").into());
        }
        sleep(Duration::from_millis(200).min(deadline.saturating_duration_since(Instant::now())))
            .await;
    }
}

pub async fn run(config: &Config) -> Result<()> {
    if config.command == "script" {
        println!(
            "{}",
            action::shell(&action::render(config, &config.args[0], &config.args[1])?)
        );
        return Ok(());
    }
    if config.command == "get" && config.flag("script") && !config.flag("json") {
        for key in &config.args {
            println!("{}", action::shell(&action::render(config, "click", key)?));
        }
        return Ok(());
    }
    let mut client = match cdp::connect(config).await {
        Ok(client) => client,
        Err(error) if config.command == "status" => {
            println!(
                "connected: false\nerror: {error}\n\nhint: set GDPW_PORT=<port> or pass --port=<port>"
            );
            return Ok(());
        }
        Err(error) => return Err(error),
    };
    match config.command.as_str() {
        "get" => get(config, &mut client).await?,
        "list" => {
            let elements: BTreeMap<String, Element> = serde_json::from_value(
                client
                    .json("JSON.stringify(window.godotElements || {})")
                    .await?,
            )?;
            let filtered: BTreeMap<_, _> = elements
                .into_iter()
                .filter(|(key, element)| {
                    (!config.flag("visible") || element.visible)
                        && key.starts_with(config.filters.last().map(String::as_str).unwrap_or(""))
                })
                .collect();
            if config.flag("json") {
                print(&filtered, true)?;
            } else {
                for key in filtered.keys() {
                    println!("{key}");
                }
            }
        }
        "state" => print(&client.json(include_str!("state.js")).await?, true)?,
        "status" => {
            match client
                .evaluate(include_str!("status.js"), Duration::from_secs(5))
                .await
            {
                Err(_) => println!("connected: true\ngd-playwright: not ready"),
                Ok(value) => {
                    if let Some(value) = value
                        .as_str()
                        .and_then(|s| serde_json::from_str::<Value>(s).ok())
                        .filter(Value::is_object)
                    {
                        println!(
                            "connected: true\nelements: {} ({} visible)\nevents: {}",
                            value["element_count"].as_i64().unwrap_or(0),
                            value["visible_count"].as_i64().unwrap_or(0),
                            value["event_count"].as_i64().unwrap_or(0)
                        );
                        if let Ok(viewport) =
                            serde_json::from_value::<Viewport>(value["viewport"].clone())
                        {
                            println!(
                                "viewport: {}x{}",
                                viewport.width as i64, viewport.height as i64
                            );
                        } else {
                            println!("viewport: not set");
                        }
                    } else {
                        println!("connected: true\ngd-playwright: parse error");
                    }
                }
            }
        }
        "events" => {
            let last = config.number("last", 100)?;
            let since = config.number("since", 0)?;
            let filters = config.filters();
            let events: Vec<Event> = serde_json::from_value(
                client
                    .json(&format!(
                        "JSON.stringify((window.godotEvents || []).slice(-{last}))"
                    ))
                    .await?,
            )?;
            let events: Vec<_> = events
                .into_iter()
                .filter(|event| {
                    (config.value("name").is_empty() || event.event == config.value("name"))
                        && (since <= 0 || event.timestamp > since)
                        && matches(event, &filters)
                })
                .collect();
            if events.is_empty() {
                println!("no events");
            } else {
                print(&events, true)?;
            }
        }
        "wait" => wait(config, &mut client).await?,
        "watch" => {
            let mut index = count(&mut client).await;
            let filters = config.filters();
            eprintln!("watching events... (Ctrl+C to stop)");
            loop {
                sleep(Duration::from_millis(200)).await;
                let js = format!(
                    "JSON.stringify((function(){{var evts=window.godotEvents||[];return {{events:evts.slice({index}),length:evts.length}};}})())"
                );
                let Ok(value) = client.json(&js).await else {
                    continue;
                };
                let Ok(events) = serde_json::from_value::<Vec<Event>>(value["events"].clone())
                else {
                    continue;
                };
                index = value["length"].as_i64().unwrap_or(index);
                for event in events {
                    if !config.value("name").is_empty() && event.event != config.value("name") {
                        continue;
                    }
                    if !matches(&event, &filters) {
                        continue;
                    }
                    if config.flag("quiet") {
                        println!("{}", event.event);
                    } else {
                        println!("[{}] {}", event.timestamp, serde_json::to_string(&event)?);
                    }
                }
                io::stdout().flush()?;
            }
        }
        _ => unreachable!(),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn coordinates_preserve_canvas_offsets_nonuniform_scaling_and_rounding() {
        let element = Element {
            x: 360.,
            y: 640.,
            w: 100.,
            h: 50.,
            visible: true,
        };
        assert_eq!(
            scaled(
                &element,
                &Viewport {
                    width: 720.,
                    height: 1280.
                },
                &Canvas {
                    x: 10.,
                    y: 20.,
                    width: 360.,
                    height: 1280.
                }
            ),
            [190, 660, 50, 50]
        );
        assert_eq!(
            scaled(
                &Element { x: -1.5, ..element },
                &Viewport::default(),
                &Canvas::default()
            )[0],
            -2
        );
    }
}
