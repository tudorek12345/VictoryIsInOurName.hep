//! Repository maintenance. Run with `cargo xtask <command>`.

mod policy;

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "xtask")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Enforce the asset policy: the repository holds only small text files
    /// we wrote. Checks tracked and untracked-but-not-ignored files.
    Policy {
        /// Check only what is staged for commit (used by the pre-commit hook).
        #[arg(long)]
        staged: bool,
    },
    /// Point git at .githooks/ so every commit runs the policy check.
    InstallHooks,
}

fn main() -> Result<()> {
    let root = workspace_root();
    match Cli::parse().command {
        Cmd::Policy { staged } => policy::run(&root, staged),
        Cmd::InstallHooks => {
            ensure_standalone_repository(&root)?;
            let status = Command::new("git")
                .args(["config", "core.hooksPath", ".githooks"])
                .current_dir(&root)
                .status()
                .context("running git")?;
            anyhow::ensure!(
                status.success(),
                "git config failed (is this a git repository?)"
            );
            println!("hooks installed: commits now run `cargo xtask policy --staged`");
            Ok(())
        }
    }
}

fn ensure_standalone_repository(root: &Path) -> Result<()> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .current_dir(root)
        .output()
        .context("locating the git repository before installing hooks")?;
    anyhow::ensure!(
        output.status.success(),
        "install-hooks needs a git repository"
    );
    let git_root = String::from_utf8(output.stdout).context("reading the git repository path")?;
    let git_root =
        std::fs::canonicalize(git_root.trim()).context("resolving the git repository root")?;
    let workspace = std::fs::canonicalize(root).context("resolving the VIctory workspace root")?;
    anyhow::ensure!(
        git_root == workspace,
        "VIctory is vendored inside a parent repository; refusing to replace its hooks. \
         Use the Leonida parent workflow or run `cargo xtask policy` from runtimes/victory."
    );
    Ok(())
}

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("xtask lives in the workspace")
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_standalone_workspaces_may_install_hooks() {
        let temp = tempfile::tempdir().unwrap();
        assert!(
            Command::new("git")
                .args(["init", "--quiet"])
                .current_dir(temp.path())
                .status()
                .unwrap()
                .success()
        );
        ensure_standalone_repository(temp.path()).unwrap();
        let nested = temp.path().join("runtimes/victory");
        std::fs::create_dir_all(&nested).unwrap();
        let error = ensure_standalone_repository(&nested).unwrap_err();
        assert!(error.to_string().contains("refusing to replace its hooks"));
        let hooks = Command::new("git")
            .args(["config", "--local", "--get", "core.hooksPath"])
            .current_dir(temp.path())
            .output()
            .unwrap();
        assert!(!hooks.status.success());
    }
}
