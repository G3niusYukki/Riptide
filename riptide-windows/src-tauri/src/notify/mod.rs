//! Cross-platform Notification subsystem.
//!
//! Mirrors the macOS `Sources/Riptide/NotificationManager/` at the MVP level.
//! Five emit paths cover the events the user actually needs to know about:
//!
//! 1. `helper_install_error`    — TUN / helper service install or start failure
//! 2. `subscription_expiring`   — a subscription profile is about to expire
//! 3. `config_reloaded`         — a profile finished (re)loading
//! 4. `mode_changed`            — the active tunnel mode flipped
//! 5. `startup_complete`        — initial app boot finished
//!
//! Each path:
//!   1. Emits a structured `notify:<kind>` event on the Tauri event bus with
//!      `{ title, body }` — the front-end `useNotification` hook picks these
//!      up and renders in-app toasts.
//!   2. Best-effort shows a native OS toast via `tauri-plugin-notification`
//!      (Windows Action Center). If the platform refuses (permission denied,
//!      or the host has notifications disabled), the failure is *silently*
//!      swallowed — the front-end toast is the canonical surface, the native
//!      toast is purely additive.
//!   3. Dedupes within a 5-second window keyed by `(kind, body)` so a tight
//!      retry loop (e.g. the recovery watchdog kicking the TUN service) does
//!      not spam the user.
//!
//! Tests live at the bottom of [`dispatcher`] and run against an
//! in-memory [`MockSink`] — no live `AppHandle` is required, so they
//! stay green under `cargo test --lib` even with the
//! `muda → comctl32` delay-load workaround in place.

pub mod dispatcher;

pub use dispatcher::{
    DEDUP_WINDOW, DispatcherEvent, MockSink, NotificationDispatcher, NotifySink, TauriNotifySink,
};
