use std::{env, process::Command};
fn main() {
    for name in ["VERSION", "COMMIT"] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    let commit = env::var("COMMIT")
        .ok()
        .or_else(|| {
            let result = Command::new("git")
                .args(["rev-parse", "HEAD"])
                .output()
                .ok()?;
            result
                .status
                .success()
                .then(|| String::from_utf8_lossy(&result.stdout).trim().into())
        })
        .unwrap_or_else(|| "unknown".into());
    for (name, value) in [
        (
            "GDPW_VERSION",
            env::var("VERSION").unwrap_or_else(|_| "dev".into()),
        ),
        ("GDPW_COMMIT", commit),
    ] {
        assert!(!value.contains(['\r', '\n']));
        println!("cargo:rustc-env={name}={value}");
    }
    println!("cargo:rerun-if-changed=../.git");
}
