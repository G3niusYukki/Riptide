// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use riptide_windows_lib::cli::{handle_one_shot_cli, OneShotResult};

fn main() {
    // Handle one-shot CLI flags (used by elevated relaunch for service install/
    // uninstall) before booting the Tauri UI. These paths exit immediately.
    match handle_one_shot_cli() {
        OneShotResult::Continue => riptide_windows_lib::run(),
        OneShotResult::Exit(code) => std::process::exit(code),
    }
}
