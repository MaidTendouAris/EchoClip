//! Only the current user's EchoClip Run value is managed here.
use std::path::Path;
use std::ptr;
use windows_sys::Win32::Foundation::{ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND, ERROR_SUCCESS};
use windows_sys::Win32::System::Registry::*;

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(Some(0)).collect()
}
const RUN_KEY: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
const VALUE: &str = "EchoClip";

pub fn command(executable: &Path, silent: bool) -> Result<String, String> {
    if !executable.is_absolute() || !executable.is_file() {
        return Err("STARTUP_EXECUTABLE_INVALID".into());
    }
    let value = format!(
        "\"{}\" --autostart{}",
        executable.display(),
        if silent { " --silent" } else { "" }
    );
    if value.encode_utf16().count() > 260 {
        return Err("STARTUP_PATH_TOO_LONG".into());
    }
    Ok(value)
}

struct Key(HKEY);
impl Drop for Key {
    fn drop(&mut self) {
        unsafe {
            RegCloseKey(self.0);
        }
    }
}

pub fn current_value() -> Result<Option<String>, String> {
    let mut handle = ptr::null_mut();
    let result = unsafe {
        RegOpenKeyExW(
            HKEY_CURRENT_USER,
            wide(RUN_KEY).as_ptr(),
            0,
            KEY_QUERY_VALUE,
            &mut handle,
        )
    };
    if result == ERROR_FILE_NOT_FOUND || result == ERROR_PATH_NOT_FOUND {
        return Ok(None);
    }
    if result != ERROR_SUCCESS {
        return Err(format!("STARTUP_READ_FAILED:{result}"));
    }
    let key = Key(handle);
    let mut kind = 0;
    let mut length = 0;
    let result = unsafe {
        RegQueryValueExW(
            key.0,
            wide(VALUE).as_ptr(),
            ptr::null(),
            &mut kind,
            ptr::null_mut(),
            &mut length,
        )
    };
    if result == ERROR_FILE_NOT_FOUND {
        return Ok(None);
    }
    if result != ERROR_SUCCESS || kind != REG_SZ || length > 65536 {
        return Err(format!("STARTUP_READ_FAILED:{result}"));
    }
    let mut buffer = vec![0_u16; (length as usize).div_ceil(2) + 1];
    let result = unsafe {
        RegQueryValueExW(
            key.0,
            wide(VALUE).as_ptr(),
            ptr::null(),
            &mut kind,
            buffer.as_mut_ptr().cast(),
            &mut length,
        )
    };
    if result != ERROR_SUCCESS {
        return Err(format!("STARTUP_READ_FAILED:{result}"));
    }
    let end = buffer.iter().position(|v| *v == 0).unwrap_or(buffer.len());
    Ok(Some(String::from_utf16_lossy(&buffer[..end])))
}

pub fn set_value(value: Option<&str>) -> Result<(), String> {
    let mut handle = ptr::null_mut();
    let result = unsafe {
        RegCreateKeyExW(
            HKEY_CURRENT_USER,
            wide(RUN_KEY).as_ptr(),
            0,
            ptr::null(),
            0,
            KEY_SET_VALUE,
            ptr::null(),
            &mut handle,
            ptr::null_mut(),
        )
    };
    if result != ERROR_SUCCESS {
        return Err(format!("STARTUP_WRITE_FAILED:{result}"));
    }
    let key = Key(handle);
    let result = if let Some(value) = value {
        let data = wide(value);
        unsafe {
            RegSetValueExW(
                key.0,
                wide(VALUE).as_ptr(),
                0,
                REG_SZ,
                data.as_ptr().cast(),
                (data.len() * 2) as u32,
            )
        }
    } else {
        unsafe { RegDeleteValueW(key.0, wide(VALUE).as_ptr()) }
    };
    if result != ERROR_SUCCESS && !(value.is_none() && result == ERROR_FILE_NOT_FOUND) {
        return Err(format!("STARTUP_WRITE_FAILED:{result}"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn silent_startup_has_an_explicit_flag_and_keeps_the_quoted_executable() {
        let exe = std::env::current_exe().unwrap();
        let normal = command(&exe, false).unwrap();
        let silent = command(&exe, true).unwrap();
        assert!(normal.starts_with('"'));
        assert!(normal.ends_with("\" --autostart"));
        assert_eq!(silent, format!("{normal} --silent"));
    }
}
