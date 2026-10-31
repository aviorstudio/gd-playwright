mod action;
mod cdp;
mod commands;
mod config;
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const HELP: &str = "gdpw: query Godot elements and state through CDP\n\nUsage: gdpw <get|list|status|events|wait|watch|state|script> [arguments] [flags]\n\nConnection: --cdp URL, --port PORT, GDPW_CDP, GDPW_PORT, then local browser discovery.\nget KEY...: --json --force --script\nlist: --visible --filter PREFIX --json\nevents: --last COUNT --name EVENT --filter key=value --since TIMESTAMP\nwait EVENT: --timeout MILLISECONDS --include-past --since TIMESTAMP --filter key=value\nwatch: --name EVENT --filter key=value --quiet\nscript click KEY: --force --expect-event EVENT --filter key=value --timeout MILLISECONDS --retries COUNT --retry-delay MILLISECONDS\nscript drag KEY: same flags plus --to X,Y or --to-key KEY, --steps COUNT\n\ngdpw reads browser state and prints Playwright action scripts. It does not execute input.\n";

#[tokio::main]
async fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.is_empty()
        || args.first().is_some_and(|arg| arg == "help")
        || args
            .iter()
            .any(|arg| matches!(arg.as_str(), "--help" | "-h"))
    {
        print!("{HELP}");
        return;
    }
    if args == ["--version"] {
        println!("gdpw version {}", env!("GDPW_VERSION"));
        return;
    }
    if args == ["--build-info"] {
        println!(
            "{}",
            serde_json::json!({"version":env!("GDPW_VERSION"),"commit":env!("GDPW_COMMIT")})
        );
        return;
    }
    let config = match config::Config::parse(&args) {
        Ok(config) => config,
        Err(error) => {
            eprintln!("Error: {error}");
            std::process::exit(1);
        }
    };
    let result = tokio::select! {result=commands::run(&config)=>result,signal=tokio::signal::ctrl_c()=>{if config.command=="watch"{eprintln!("\nstopped");}signal.map_err(Into::into)}};
    if let Err(error) = result {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}
