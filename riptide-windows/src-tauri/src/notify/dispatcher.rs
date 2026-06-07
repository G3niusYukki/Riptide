//! `NotificationDispatcher` — the Rust side of the cross-platform
//! Notification subsystem.
//!
//! The dispatcher is a small `Arc<dyn NotifySink>`-backed struct that emits
//! one of five structured events and tries to show a native OS toast. It
//! is *not* stored on `AppState`; instead, it lives as a `tauri::State` so
//! any Tauri command (and any module with an `AppHandle`) can reach it via
//! `app.state::<NotificationDispatcher>()`.
//!
//! ```ignore
//! // in lib.rs setup():
//! let dispatcher = NotificationDispatcher::with_sink(Arc::new(TauriNotifySink::new(
//!     app_handle.clone(),
//! )));
//! app.manage(dispatcher);
//! ```
//!
//! Then any business module can fan into it:
//! ```ignore
//! let dispatcher = app_handle.state::<NotificationDispatcher>();
//! dispatcher.helper_install_error("RiptideTUN failed to start: timeout".into());
//! ```
//!
//! `MockSink` (below) is the testing seam — production code never
//! touches it. The three unit tests at the bottom of this file use it to
//! assert (1) all five emit paths fire, (2) duplicate emissions within
//! the dedup window are suppressed, and (3) a permission-denied native
//! toast does not block the front-end event.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Runtime};
use tauri_plugin_notification::NotificationExt;

/// Dedup window — two emissions with the same `(kind, body)` within this
/// duration collapse into a single event. Tuned to be wider than the
/// recovery watchdog's 3-second tick so a 2-retry failure does not double
/// the user's notification count.
pub const DEDUP_WINDOW: Duration = Duration::from_secs(5);

/// One of the five structured event names. The string form is the
/// `notify:<name>` Tauri event the front-end subscribes to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DispatcherEvent {
    HelperInstallError,
    SubscriptionExpiring,
    ConfigReloaded,
    ModeChanged,
    StartupComplete,
}

impl DispatcherEvent {
    /// Wire form — `notify:<snake_case>`. Stable across versions; the
    /// front-end `useNotification` hook hard-codes the same five strings.
    pub fn as_str(self) -> &'static str {
        match self {
            DispatcherEvent::HelperInstallError => "notify:helper_install_error",
            DispatcherEvent::SubscriptionExpiring => "notify:subscription_expiring",
            DispatcherEvent::ConfigReloaded => "notify:config_reloaded",
            DispatcherEvent::ModeChanged => "notify:mode_changed",
            DispatcherEvent::StartupComplete => "notify:startup_complete",
        }
    }
}

/// Payload shipped to the front-end on every `notify:*` event. The
/// `useNotification` hook uses `kind` to pick a toast colour and `body`
/// as the toast text; `title` is the larger header line.
#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
pub struct NotifyPayload {
    pub kind: DispatcherEvent,
    pub title: String,
    pub body: String,
}

/// Sink abstraction — production code uses [`TauriNotifySink`], tests use
/// [`MockSink`]. Keeps the dispatcher's IO concerns separable from its
/// dedup/state machine, which is what the three unit tests assert.
pub trait NotifySink: Send + Sync {
    /// Show a native OS toast. Returning `Err` is non-fatal — the front-end
    /// event has already been (or will be) emitted by the dispatcher.
    fn show_toast(&self, title: &str, body: &str) -> Result<(), String>;

    /// Emit a structured event on the Tauri event bus. Failure is logged
    /// and otherwise ignored — the front-end is the only consumer.
    fn emit(&self, event: DispatcherEvent, payload: &NotifyPayload) -> Result<(), String>;
}

/// Production sink — wraps an `AppHandle` and forwards to the real
/// `tauri-plugin-notification` plugin + the Tauri event bus.
pub struct TauriNotifySink<R: Runtime> {
    app: AppHandle<R>,
}

impl<R: Runtime> TauriNotifySink<R> {
    pub fn new(app: AppHandle<R>) -> Self {
        Self { app }
    }
}

impl<R: Runtime> NotifySink for TauriNotifySink<R> {
    fn show_toast(&self, title: &str, body: &str) -> Result<(), String> {
        let n = self.app.notification();
        // `permission_state` is `Ok(Granted)` on every desktop target by
        // default (the plugin does not gate desktop). We still call it so
        // a future permission model changes the behaviour in lock-step.
        let state = n
            .permission_state()
            .map_err(|e| format!("permission_state failed: {e}"))?;
        if !matches!(state, tauri::plugin::PermissionState::Granted) {
            return Err(format!("notification permission not granted: {state:?}"));
        }
        n.builder()
            .title(title.to_string())
            .body(body.to_string())
            .show()
            .map_err(|e| format!("notification show failed: {e}"))
    }

    fn emit(&self, event: DispatcherEvent, payload: &NotifyPayload) -> Result<(), String> {
        self.app
            .emit(event.as_str(), payload.clone())
            .map_err(|e| format!("emit {} failed: {e}", event.as_str()))
    }
}

/// In-memory sink for tests. Records every `show_toast` and `emit` call;
/// `fail_toast` lets a test simulate "the user denied notification
/// permission" so we can assert the dispatcher still emits the event.
#[derive(Debug, Default)]
pub struct MockSink {
    /// `(event_kind, title, body)` triples, in insertion order.
    pub emitted: Mutex<Vec<(DispatcherEvent, String, String)>>,
    /// Toast attempts, regardless of `fail_toast`.
    pub toast_attempts: Mutex<Vec<(String, String)>>,
    pub fail_toast: Mutex<bool>,
}

impl MockSink {
    pub fn new() -> Self {
        Self::default()
    }

    /// Convenience constructor — start in "toast fails" mode.
    pub fn with_failing_toast() -> Self {
        let s = Self::new();
        *s.fail_toast.lock().unwrap() = true;
        s
    }

    /// Total number of `emit` calls (one per NotifyPayload, not
    /// deduplicated).
    pub fn emit_count(&self) -> usize {
        self.emitted.lock().unwrap().len()
    }

    /// Snapshot of the emitted events for assertions.
    pub fn snapshot(&self) -> Vec<(DispatcherEvent, String, String)> {
        self.emitted.lock().unwrap().clone()
    }
}

impl NotifySink for MockSink {
    fn show_toast(&self, title: &str, body: &str) -> Result<(), String> {
        self.toast_attempts
            .lock()
            .unwrap()
            .push((title.to_string(), body.to_string()));
        if *self.fail_toast.lock().unwrap() {
            Err("simulated permission denied".to_string())
        } else {
            Ok(())
        }
    }

    fn emit(&self, event: DispatcherEvent, payload: &NotifyPayload) -> Result<(), String> {
        self.emitted
            .lock()
            .unwrap()
            .push((event, payload.title.clone(), payload.body.clone()));
        Ok(())
    }
}

/// The dispatcher itself. Cheap to clone via `Arc<NotificationDispatcher>`
/// — the sink is shared, the dedup map is behind a `Mutex` (held for
/// microseconds; never across `.await`).
pub struct NotificationDispatcher {
    sink: Arc<dyn NotifySink>,
    /// `(kind, body) → last-emitted Instant`. A second emission with
    /// the same key inside [`DEDUP_WINDOW`] is suppressed.
    last: Mutex<HashMap<(DispatcherEvent, String), Instant>>,
}

impl NotificationDispatcher {
    /// Build a dispatcher around a custom sink (used by tests).
    pub fn with_sink(sink: Arc<dyn NotifySink>) -> Self {
        Self {
            sink,
            last: Mutex::new(HashMap::new()),
        }
    }

    /// Build a dispatcher that emits to a live Tauri app. Convenience
    /// wrapper used by `lib.rs` setup.
    pub fn new<R: Runtime>(app: AppHandle<R>) -> Self {
        Self::with_sink(Arc::new(TauriNotifySink::new(app)))
    }

    /// Number of unique `(kind, body)` pairs still suppressed by the
    /// dedup map. Used by the unit tests; not part of the public API.
    #[cfg(test)]
    fn dedup_len(&self) -> usize {
        self.last.lock().unwrap().len()
    }

    /// `true` iff a call with the same `(kind, body)` *right now* would
    /// be suppressed. Tests use this; production code goes through the
    /// `emit_*` methods.
    #[cfg(test)]
    fn would_dedupe(&self, kind: DispatcherEvent, body: &str) -> bool {
        let key = (kind, body.to_string());
        if let Some(prev) = self.last.lock().unwrap().get(&key).copied() {
            prev.elapsed() < DEDUP_WINDOW
        } else {
            false
        }
    }

    fn dispatch(&self, event: DispatcherEvent, title: impl Into<String>, body: impl Into<String>) {
        let title = title.into();
        let body = body.into();

        // Dedup gate. Take the lock, check, insert, drop the lock
        // before calling into the sink (which can be arbitrarily slow
        // on a real OS toast call).
        {
            let mut last = self.last.lock().unwrap();
            let key = (event, body.clone());
            if let Some(prev) = last.get(&key).copied() {
                if prev.elapsed() < DEDUP_WINDOW {
                    log::debug!(
                        "NotificationDispatcher: dropping dedup'd emit for {}",
                        event.as_str()
                    );
                    return;
                }
            }
            last.insert(key, Instant::now());
        }

        let payload = NotifyPayload {
            kind: event,
            title: title.clone(),
            body: body.clone(),
        };

        // Front-end event is the canonical surface. Failure to emit is
        // logged but not surfaced — the user still has the native toast.
        if let Err(e) = self.sink.emit(event, &payload) {
            log::warn!(
                "NotificationDispatcher: emit {} failed: {}",
                event.as_str(),
                e
            );
        }

        // Native toast is best-effort. Permission-denied → swallow the
        // error; the front-end hook is the fallback path.
        if let Err(e) = self.sink.show_toast(&title, &body) {
            log::debug!(
                "NotificationDispatcher: native toast for {} suppressed: {}",
                event.as_str(),
                e
            );
        }
    }

    // ── 5 emit paths ────────────────────────────────────────────────

    /// TUN / helper service install or start failure. `reason` is the
    /// user-facing description (the installer already has the technical
    /// details in the log file).
    pub fn helper_install_error(&self, reason: impl Into<String>) {
        self.dispatch(
            DispatcherEvent::HelperInstallError,
            "Helper service failed",
            format!("RiptideTUN could not be started: {}", reason.into()),
        );
    }

    /// A subscription profile is about to expire. `days_left` is the
    /// number of days until the next refresh window (negative = already
    /// past due; the body adjusts the wording).
    pub fn subscription_expiring(&self, profile: impl Into<String>, days_left: i64) {
        let profile = profile.into();
        let body = if days_left <= 0 {
            format!("'{profile}' is past due and needs to be refreshed")
        } else {
            format!("'{profile}' will refresh in {days_left} day(s)")
        };
        self.dispatch(
            DispatcherEvent::SubscriptionExpiring,
            "Subscription expiring",
            body,
        );
    }

    /// A profile finished (re)loading. `profile` is the human-readable
    /// name (not the UUID — the front-end renders this directly in the
    /// toast).
    pub fn config_reloaded(&self, profile: impl Into<String>) {
        self.dispatch(
            DispatcherEvent::ConfigReloaded,
            "Profile reloaded",
            format!("'{}' is now active", profile.into()),
        );
    }

    /// The active tunnel mode flipped. `transitioning=true` means the
    /// switch is still in flight (the `mode_state` event already covers
    /// the canonical state machine; this notification is the lightweight
    /// "user-visible" mirror).
    pub fn mode_changed(&self, mode: impl Into<String>, transitioning: bool) {
        let mode = mode.into();
        let body = if transitioning {
            format!("Switching to {mode}…")
        } else {
            format!("Mode is now {mode}")
        };
        self.dispatch(DispatcherEvent::ModeChanged, "Mode changed", body);
    }

    /// Initial app boot finished. Called once after the setup phase.
    pub fn startup_complete(&self, version: impl Into<String>) {
        self.dispatch(
            DispatcherEvent::StartupComplete,
            "Riptide is ready",
            format!("v{} loaded", version.into()),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    // ── Test 1: all 5 emit paths produce a front-end event ───────────
    //
    // The dispatcher must surface every kind to the bus — if any of the
    // 5 paths silently no-op (typo, wrong `as_str`, missing match arm),
    // the front-end `useNotification` hook would never render the toast
    // and the user would never know about a TUN install failure.
    #[test]
    fn all_five_emit_paths_produce_event() {
        let sink = Arc::new(MockSink::new());
        let d = NotificationDispatcher::with_sink(sink.clone());

        d.helper_install_error("timeout");
        d.subscription_expiring("my-vpn", 3);
        d.config_reloaded("my-vpn");
        d.mode_changed("system_proxy", false);
        d.startup_complete("2.4.1");

        let snapshot = sink.snapshot();
        assert_eq!(
            snapshot.len(),
            5,
            "all 5 emit paths must produce an event, got {snapshot:?}"
        );
        // Spot-check the wire form lands on each event.
        let kinds: Vec<DispatcherEvent> = snapshot.iter().map(|(k, _, _)| *k).collect();
        assert!(kinds.contains(&DispatcherEvent::HelperInstallError));
        assert!(kinds.contains(&DispatcherEvent::SubscriptionExpiring));
        assert!(kinds.contains(&DispatcherEvent::ConfigReloaded));
        assert!(kinds.contains(&DispatcherEvent::ModeChanged));
        assert!(kinds.contains(&DispatcherEvent::StartupComplete));

        // Toast attempts are best-effort: with `MockSink::new()` they
        // all succeed, so we expect 5.
        assert_eq!(sink.toast_attempts.lock().unwrap().len(), 5);
    }

    // ── Test 2: dedup suppresses repeats within the window ──────────
    //
    // A typical user-facing scenario: the recovery watchdog ticks every
    // 3s, finds mihomo dead, calls `helper_install_error` — but the
    // installer is also retrying, and 4s later the user sees *another*
    // failure. Two toasts for the same underlying problem is annoying;
    // we suppress the second one within the 5s window.
    #[test]
    fn dedup_suppresses_repeats_within_window() {
        let sink = Arc::new(MockSink::new());
        let d = NotificationDispatcher::with_sink(sink.clone());

        // Sanity: helper would_dedupe is false on a fresh dispatcher.
        assert!(!d.would_dedupe(DispatcherEvent::HelperInstallError, "timeout"));

        d.helper_install_error("timeout");
        assert_eq!(sink.emit_count(), 1, "first call always emits");

        // Same kind + body, immediately after. Must suppress.
        d.helper_install_error("timeout");
        assert_eq!(sink.emit_count(), 1, "second call within window is dedup'd");

        // Different body — must NOT suppress (different error reason).
        d.helper_install_error("refused");
        assert_eq!(sink.emit_count(), 2, "different body is a different event");

        // Different kind, even with the same body — must NOT suppress.
        d.mode_changed("timeout", false);
        assert_eq!(sink.emit_count(), 3, "different kind is a different event");

        // The dedup map should now hold 3 entries (one per unique key).
        assert_eq!(d.dedup_len(), 3);
    }

    // ── Test 3: native toast failure does not block the event ───────
    //
    // If the user denies notification permission, the front-end hook
    // (which subscribes to the Tauri event bus) is the fallback path.
    // The dispatcher must still emit the event so the in-app toast
    // surfaces. We simulate "permission denied" by configuring a MockSink
    // that always fails `show_toast`.
    #[test]
    fn permission_denied_still_emits_event() {
        let sink = Arc::new(MockSink::with_failing_toast());
        let d = NotificationDispatcher::with_sink(sink.clone());

        d.helper_install_error("access denied");
        d.startup_complete("2.4.1");

        // Both emit() calls succeeded — the event is the canonical
        // surface, the native toast is purely additive.
        assert_eq!(
            sink.emit_count(),
            2,
            "events must still emit when native toast fails"
        );

        // The two toast *attempts* are recorded, but both return Err.
        // (We do not assert on the Err value — `log::debug!` swallowed
        // it. The contract under test is "emit survives toast failure".)
        let attempts = sink.toast_attempts.lock().unwrap();
        assert_eq!(attempts.len(), 2);
        drop(attempts);

        // Payload contents survive too — the front-end gets a usable
        // title/body even when the OS toast is dropped.
        let snapshot = sink.snapshot();
        assert_eq!(snapshot[0].0, DispatcherEvent::HelperInstallError);
        assert!(snapshot[0].1.contains("Helper"));
        assert!(snapshot[0].2.contains("access denied"));
        assert_eq!(snapshot[1].0, DispatcherEvent::StartupComplete);
        assert!(snapshot[1].2.contains("2.4.1"));
    }
}
