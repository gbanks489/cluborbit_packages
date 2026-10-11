// Plain C entry points for the iOS Notification Service Extension (ios/NotificationService in the
// app), which can't run Flutter: it opens this device's existing crypto store - the same one the
// app uses, kept in the App Group container - decrypts one pushed chat event, and closes it again.
// The iOS counterpart of BackgroundNotificationDecryptor.decryptNotificationText on Android.
//
// Not part of the Dart API: these are ignored by flutter_rust_bridge and called from Swift via
// dlopen/dlsym. Strings are UTF-8, NUL-terminated; every returned string must be released with
// `cluborbit_nse_free_string`.

use std::ffi::{c_char, CStr, CString};

use crate::CryptoSession;

/// Decrypts an `m.room.encrypted` event (the full event JSON, as returned by
/// GET /rooms/{roomId}/event/{eventId}). Returns `{"event": <decrypted event JSON>}` on success or
/// `{"error": "<message>"}` - never null unless an argument is null.
#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn cluborbit_nse_decrypt_event(
    user_id: *const c_char,
    device_id: *const c_char,
    store_path: *const c_char,
    passphrase: *const c_char,
    room_id: *const c_char,
    event_json: *const c_char,
) -> *mut c_char {
    let args = [user_id, device_id, store_path, passphrase, room_id, event_json];
    let Some(args) = args.iter().map(|p| read(*p)).collect::<Option<Vec<String>>>() else {
        return std::ptr::null_mut();
    };
    let [user_id, device_id, store_path, passphrase, room_id, event_json] =
        <[String; 6]>::try_from(args).expect("six arguments");

    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())
        .and_then(|runtime| {
            runtime.block_on(async {
                // Opened and dropped inside the runtime: the SQLite pool must be released in one
                // (see CryptoSession's Drop).
                let session = CryptoSession::create(user_id, device_id, store_path, passphrase)
                    .await
                    .map_err(|e| e.message)?;
                let decrypted = session.decrypt_room_event(room_id, event_json).await;
                drop(session);
                decrypted.map_err(|e| e.message)
            })
        });

    let json = match result {
        Ok(event) => format!("{{\"event\":{event}}}"),
        Err(message) => serde_json::json!({ "error": message }).to_string(),
    };
    CString::new(json).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

/// Releases a string returned by `cluborbit_nse_decrypt_event`.
#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn cluborbit_nse_free_string(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: only ever called with pointers produced by CString::into_raw above.
        unsafe { drop(CString::from_raw(value)) };
    }
}

fn read(value: *const c_char) -> Option<String> {
    if value.is_null() {
        return None;
    }
    // SAFETY: the caller passes valid NUL-terminated strings.
    unsafe { CStr::from_ptr(value) }.to_str().ok().map(str::to_owned)
}
