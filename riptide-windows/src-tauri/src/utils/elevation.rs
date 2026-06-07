//! Elevation helpers — detect admin-ness, and re-launch the current binary
//! elevated to run a single command (install/uninstall the service).
//!
//! We deliberately do *not* re-launch the entire UI elevated, just a one-shot
//! invocation that performs the privileged action and exits. The user sees the
//! UAC prompt exactly once per install/uninstall.

#[cfg(target_os = "windows")]
pub fn is_elevated() -> bool {
    use std::mem;
    use winapi::shared::minwindef::DWORD;
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processthreadsapi::{GetCurrentProcess, OpenProcessToken};
    use winapi::um::securitybaseapi::GetTokenInformation;
    use winapi::um::winnt::{TokenElevation, HANDLE, TOKEN_QUERY};

    #[repr(C)]
    struct TokenElevationInfo {
        token_is_elevated: DWORD,
    }

    unsafe {
        let mut token: HANDLE = std::ptr::null_mut();
        if OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) == 0 {
            return false;
        }
        let mut info: TokenElevationInfo = TokenElevationInfo {
            token_is_elevated: 0,
        };
        let mut size: DWORD = 0;
        let ok = GetTokenInformation(
            token,
            TokenElevation,
            &mut info as *mut _ as *mut _,
            mem::size_of::<TokenElevationInfo>() as DWORD,
            &mut size,
        );
        CloseHandle(token);
        ok != 0 && info.token_is_elevated != 0
    }
}

#[cfg(not(target_os = "windows"))]
pub fn is_elevated() -> bool {
    false
}

/// Re-launch the current executable with elevation (UAC prompt) passing the
/// supplied CLI arguments. Blocks until the child exits; returns the child's
/// exit code on success.
///
/// Implementation note: ShellExecuteExW with `lpVerb = L"runas"` is the standard
/// path. We synthesize a wide-char command line and wait for the resulting
/// process. Failure modes: user dismissed the UAC prompt (returns Err with
/// ERROR_CANCELLED), or the binary path can't be resolved.
#[cfg(target_os = "windows")]
pub fn relaunch_elevated(args: &[&str]) -> anyhow::Result<i32> {
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use winapi::shared::minwindef::DWORD;
    use winapi::um::handleapi::CloseHandle;
    use winapi::um::processthreadsapi::GetExitCodeProcess;
    use winapi::um::shellapi::{ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW};
    use winapi::um::synchapi::WaitForSingleObject;
    use winapi::um::winbase::INFINITE;

    let exe = std::env::current_exe()?;

    let to_wide = |s: &OsStr| -> Vec<u16> { s.encode_wide().chain(std::iter::once(0)).collect() };

    let verb: Vec<u16> = "runas\0".encode_utf16().collect();
    let file = to_wide(exe.as_os_str());

    // Join args with spaces, quoting paths that contain spaces. Each --install-service
    // style flag is space-separated; we trust the caller's quoting.
    let joined: String = args.join(" ");
    let parameters = to_wide(OsStr::new(&joined));

    let mut info = SHELLEXECUTEINFOW {
        cbSize: std::mem::size_of::<SHELLEXECUTEINFOW>() as DWORD,
        fMask: SEE_MASK_NOCLOSEPROCESS,
        hwnd: std::ptr::null_mut(),
        lpVerb: verb.as_ptr(),
        lpFile: file.as_ptr(),
        lpParameters: parameters.as_ptr(),
        lpDirectory: std::ptr::null(),
        nShow: 1, // SW_SHOWNORMAL
        hInstApp: std::ptr::null_mut(),
        lpIDList: std::ptr::null_mut(),
        lpClass: std::ptr::null(),
        hkeyClass: std::ptr::null_mut(),
        dwHotKey: 0,
        hMonitor: std::ptr::null_mut(),
        hProcess: std::ptr::null_mut(),
    };

    let ok = unsafe { ShellExecuteExW(&mut info) };
    if ok == 0 {
        let err = std::io::Error::last_os_error();
        return Err(anyhow::anyhow!("ShellExecuteExW failed: {}", err));
    }
    if info.hProcess.is_null() {
        return Err(anyhow::anyhow!(
            "ShellExecuteExW returned no process handle"
        ));
    }

    unsafe {
        WaitForSingleObject(info.hProcess, INFINITE);
        let mut code: DWORD = 0;
        let got = GetExitCodeProcess(info.hProcess, &mut code);
        CloseHandle(info.hProcess);
        if got == 0 {
            return Err(anyhow::anyhow!("GetExitCodeProcess failed"));
        }
        Ok(code as i32)
    }
}

#[cfg(not(target_os = "windows"))]
pub fn relaunch_elevated(_args: &[&str]) -> anyhow::Result<i32> {
    Err(anyhow::anyhow!("Elevation only supported on Windows"))
}
