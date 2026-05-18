//! One-shot CLI handling for elevated relaunches.
//!
//! When the UI needs to do something privileged (install/uninstall the Windows
//! service), it spawns itself elevated with a flag like `--install-service`.
//! That elevated process should NOT start the UI — it should perform the
//! action, log the result, and exit. This module owns that decision.

pub enum OneShotResult {
    /// No one-shot flag was passed; proceed with normal UI launch.
    Continue,
    /// A one-shot flag was handled. Caller should exit with this code.
    Exit(i32),
}

pub fn handle_one_shot_cli() -> OneShotResult {
    let args: Vec<String> = std::env::args().collect();
    let flag = args.iter().skip(1).find_map(|a| match a.as_str() {
        "--install-service" => Some(Action::Install),
        "--uninstall-service" => Some(Action::Uninstall),
        _ => None,
    });

    let Some(action) = flag else {
        return OneShotResult::Continue;
    };

    // Initialise logging so we can record the result somewhere persistent.
    // Errors here are non-fatal — the action still runs.
    let _ = crate::utils::logger::init_logger();

    let result = match action {
        Action::Install => crate::core::service::install_service(),
        Action::Uninstall => crate::core::service::uninstall_service(),
    };

    match result {
        Ok(()) => {
            log::info!("One-shot action completed successfully");
            OneShotResult::Exit(0)
        }
        Err(e) => {
            log::error!("One-shot action failed: {}", e);
            // Exit code 1 — the caller (UI) interprets non-zero as failure.
            OneShotResult::Exit(1)
        }
    }
}

enum Action {
    Install,
    Uninstall,
}
