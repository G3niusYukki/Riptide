//! Proxy engine abstraction — see ADR-0005.
//!
//! Provides:
//! - [`ProxyEngineKind`] — enum of engines we know how to route to
//!   (mihomo, singbox, swift).
//! - [`ProxyEngine`] — trait every engine implements. The trait is
//!   intentionally narrow: name, kind, supported proxy kinds, and
//!   config generation. Anything stateful (process lifecycle, port
//!   management) lives in the engine's dedicated module
//!   (`core::mihomo`, `core::singbox`) and is wrapped by an impl.
//! - [`EngineRouter`] — pure routing policy that maps a [`ProxyKind`]
//!   to a [`ProxyEngineKind`]. Centralised so adding a new engine
//!   only touches this one file.
//!
//! Mirrors `Sources/Riptide/Engines/` on the macOS side. The Windows
//! port only ships the mihomo + singbox impls (no Swift in-process
//! engine on Windows; see ADR-0007).
//!
//! Tests live in [`router`].

pub mod mihomo_engine;
pub mod proxy_engine;
pub mod router;

pub use mihomo_engine::MihomoEngine;
pub use proxy_engine::{Config, EngineError, ProxyEngine, ProxyEngineKind, ProxyKind, ProxyNode};
pub use router::{EngineRouter, Policy};
