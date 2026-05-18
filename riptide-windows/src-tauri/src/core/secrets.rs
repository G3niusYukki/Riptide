//! DPAPI-backed secret storage.
//!
//! `CryptProtectData` produces a ciphertext tied to the current user-and-machine,
//! so a leaked `webdav_config.json` from another machine is useless. The
//! tradeoff: backups don't survive a Windows reinstall — the user has to
//! re-enter the password. That's documented in the WebDAV UI.

#[cfg(target_os = "windows")]
pub fn encrypt(plaintext: &[u8]) -> anyhow::Result<Vec<u8>> {
    use winapi::shared::minwindef::DWORD;
    use winapi::um::dpapi::CryptProtectData;
    use winapi::um::wincrypt::DATA_BLOB;

    let mut input = DATA_BLOB {
        cbData: plaintext.len() as DWORD,
        pbData: plaintext.as_ptr() as *mut u8,
    };
    let mut output = DATA_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };

    unsafe {
        let ok = CryptProtectData(
            &mut input,
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            0, // no UI prompt
            &mut output,
        );
        if ok == 0 {
            let err = std::io::Error::last_os_error();
            return Err(anyhow::anyhow!("CryptProtectData failed: {}", err));
        }
        let slice = std::slice::from_raw_parts(output.pbData, output.cbData as usize);
        let result = slice.to_vec();
        // Free the buffer DPAPI allocated.
        winapi::um::winbase::LocalFree(output.pbData as *mut _);
        Ok(result)
    }
}

#[cfg(target_os = "windows")]
pub fn decrypt(ciphertext: &[u8]) -> anyhow::Result<Vec<u8>> {
    use winapi::shared::minwindef::DWORD;
    use winapi::um::dpapi::CryptUnprotectData;
    use winapi::um::wincrypt::DATA_BLOB;

    let mut input = DATA_BLOB {
        cbData: ciphertext.len() as DWORD,
        pbData: ciphertext.as_ptr() as *mut u8,
    };
    let mut output = DATA_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    };

    unsafe {
        let ok = CryptUnprotectData(
            &mut input,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            0,
            &mut output,
        );
        if ok == 0 {
            let err = std::io::Error::last_os_error();
            return Err(anyhow::anyhow!("CryptUnprotectData failed: {}", err));
        }
        let slice = std::slice::from_raw_parts(output.pbData, output.cbData as usize);
        let result = slice.to_vec();
        winapi::um::winbase::LocalFree(output.pbData as *mut _);
        Ok(result)
    }
}

#[cfg(not(target_os = "windows"))]
pub fn encrypt(plaintext: &[u8]) -> anyhow::Result<Vec<u8>> {
    // Pass-through on non-Windows so the cross-compile path stays functional.
    // Clearly inappropriate for production non-Windows use.
    Ok(plaintext.to_vec())
}

#[cfg(not(target_os = "windows"))]
pub fn decrypt(ciphertext: &[u8]) -> anyhow::Result<Vec<u8>> {
    Ok(ciphertext.to_vec())
}
