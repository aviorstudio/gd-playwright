mod action;
mod cdp;
mod commands;
mod config;
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const HELP: &str = "gdpw: query Godot elements and state through CDP\n\nUsage: gdpw <get|list|status|events|wait|watch|state|script> [arguments] [flags]\n\nConnection: --cdp URL, --port PORT, GDPW_CDP, GDPW_PORT, then local browser discovery.\nMachine results: --json supports finite commands; multi-key get returns one elements/errors document.\nget KEY...: --json --force --script\nlist: --visible --filter PREFIX --json\nevents: --last COUNT --name EVENT --filter key=value --since TIMESTAMP\nwait EVENT: --timeout MILLISECONDS --include-past --since TIMESTAMP --filter key=value\nwatch: --name EVENT --filter key=value --quiet\nscript click KEY: --force --expect-event EVENT --filter key=value --timeout MILLISECONDS --retries COUNT --retry-delay MILLISECONDS\nscript drag KEY: same flags plus --to X,Y or --to-key KEY, --steps COUNT\n\ngdpw reads browser state and prints Playwright action scripts. It does not execute input.\n";

#[tokio::main]
async fn main() {
    let mut args: Vec<_> = std::env::args().skip(1).collect();
    let global_json = args.first().is_some_and(|arg| arg == "--json");
    if global_json {
        args.remove(0);
    }
    let machine = global_json
        || args
            .iter()
            .take_while(|arg| arg.as_str() != "--")
            .any(|arg| arg == "--json");
    if args.is_empty()
        || args.first().is_some_and(|arg| arg == "help")
        || args
            .iter()
            .any(|arg| matches!(arg.as_str(), "--help" | "-h"))
    {
        if machine {
            println!("{}", serde_json::json!({"help":HELP}));
        } else {
            print!("{HELP}");
        }
        return;
    }
    if args == ["--version"] {
        if machine {
            println!(
                "{}",
                serde_json::json!({"version":env!("GDPW_VERSION"),"commit":env!("GDPW_COMMIT")})
            );
        } else {
            println!("gdpw version {}", env!("GDPW_VERSION"));
        }
        return;
    }
    if args == ["--build-info"] {
        println!(
            "{}",
            serde_json::json!({"version":env!("GDPW_VERSION"),"commit":env!("GDPW_COMMIT")})
        );
        return;
    }
    let mut config = match config::Config::parse(&args) {
        Ok(config) => config,
        Err(error) => {
            eprintln!("Error: {error}");
            if machine {
                println!(
                    "{}",
                    serde_json::json!({"ok":false,"error":{"code":"invalid_usage","message":error.to_string()}})
                );
            }
            std::process::exit(1);
        }
    };
    if global_json {
        config.flags.insert("json".into());
    }
    if config.flag("json") && config.command == "watch" {
        println!(
            "{}",
            serde_json::json!({"ok":false,"error":{"code":"invalid_usage","message":"--json requires a finite command; watch retains its event stream"}})
        );
        std::process::exit(1);
    }
    let result = tokio::select! {result=commands::run(&config)=>result,signal=tokio::signal::ctrl_c()=>{if config.command=="watch"{eprintln!("\nstopped");}match signal { Ok(()) if config.flag("json") => Err("operation cancelled".into()), other => other.map_err(Into::into) }}};
    if let Err(error) = result {
        eprintln!("Error: {error}");
        if config.flag("json") && !commands::output_emitted() {
            println!(
                "{}",
                serde_json::json!({"ok":false,"error":{"code":"operation_failed","message":error.to_string()}})
            );
        }
        std::process::exit(1);
    }
}
