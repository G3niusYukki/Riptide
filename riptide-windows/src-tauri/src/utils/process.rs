//! Cross-platform process helpers.
//! Provides a no-op `creation_flags` on non-Windows so callers don't need cfg guards.

use std::process::Command;

/// Extension trait adding `no_window()` to Command on all platforms.
/// On Windows: sets CREATE_NO_WINDOW. On other platforms: no-op.
pub trait CommandExt {
    fn no_window(&mut self) -> &mut Command;
}

impl CommandExt for Command {
    fn no_window(&mut self) -> &mut Command {
        #[cfg(target_os = "windows")]
        {
            use std::os::windows::process::CommandExt as _;
            const CREATE_NO_WINDOW: u32 = 0x08000000;
            self.creation_flags(CREATE_NO_WINDOW);
        }
        self
    }
}
