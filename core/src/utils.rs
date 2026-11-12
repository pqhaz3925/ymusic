//! Ports of `yandex_music/utils/{sign_request,decrypt,convert_track_id}.py`.

use std::time::{SystemTime, UNIX_EPOCH};

use aes::cipher::{KeyIvInit, StreamCipher};
use base64::Engine as _;
use hmac::{Hmac, Mac};
use sha2::Sha256;

use crate::error::{Error, Result};

/// Signing key used by the Android app.
pub const DEFAULT_SIGN_KEY: &str = "p93jhgh689SBReK6ghtw62";
/// Signing key used by the Windows desktop app.
pub const DESKTOP_SIGN_KEY: &str = "kzqU4XhfCaY6B6JTHODeq5";
/// `X-Yandex-Music-Client` header value bound to [`DESKTOP_SIGN_KEY`].
pub const DESKTOP_CLIENT: &str = "YandexMusicDesktopAppWindows/5.95.0";

type Aes128Ctr = ctr::Ctr128BE<aes::Aes128>;

/// A request signature: creation time plus base64 value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Sign {
    /// Unix timestamp (seconds) when the signature was made.
    pub timestamp: i64,
    /// Signature value.
    pub value: String,
}

fn now_timestamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn hmac_sha256_b64(key: &str, message: &str) -> String {
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(key.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(message.as_bytes());
    base64::engine::general_purpose::STANDARD.encode(mac.finalize().into_bytes())
}

fn sign_request_at(track_id: &str, key: &str, timestamp: i64) -> Sign {
    let number = convert_track_id_to_number(track_id);
    let message = format!("{}{}", number, timestamp);
    Sign {
        timestamp,
        value: hmac_sha256_b64(key, &message),
    }
}

/// Creates a signature for a request (default key: [`DEFAULT_SIGN_KEY`]).
pub fn get_sign_request(track_id: &str, key: &str) -> Sign {
    sign_request_at(track_id, key, now_timestamp())
}

/// Same as [`get_sign_request`] using [`DEFAULT_SIGN_KEY`].
pub fn get_sign_request_default(track_id: &str) -> Sign {
    get_sign_request(track_id, DEFAULT_SIGN_KEY)
}

#[allow(clippy::too_many_arguments)]
fn file_info_sign_at(
    track_id: &str,
    quality: &str,
    codecs: &[&str],
    transport: &str,
    key: &str,
    timestamp: i64,
) -> Sign {
    let message = format!(
        "{}{}{}{}{}",
        timestamp,
        track_id,
        quality,
        codecs.concat(),
        transport
    );
    // Python drops the trailing '=' padding character.
    let value = hmac_sha256_b64(key, &message);
    let value = value.strip_suffix('=').unwrap_or(&value).to_string();
    Sign { timestamp, value }
}

/// Creates a signature for a track file-info request (default key: [`DESKTOP_SIGN_KEY`]).
pub fn get_file_info_sign(
    track_id: &str,
    quality: &str,
    codecs: &[&str],
    transport: &str,
    key: &str,
) -> Sign {
    file_info_sign_at(track_id, quality, codecs, transport, key, now_timestamp())
}

/// Decrypts a track downloaded with the `encraw` transport (AES-128-CTR, zero IV).
pub fn decrypt_track(data: &[u8], key_hex: &str) -> Result<Vec<u8>> {
    let key = hex_decode(key_hex)?;
    if key.len() != 16 {
        return Err(Error::Other(format!(
            "AES key must be 16 bytes, got {}",
            key.len()
        )));
    }
    let mut cipher = Aes128Ctr::new(key.as_slice().into(), &[0u8; 16].into());
    let mut out = data.to_vec();
    cipher.apply_keystream(&mut out);
    Ok(out)
}

fn hex_decode(s: &str) -> Result<Vec<u8>> {
    let s = s.trim();
    if !s.len().is_multiple_of(2) {
        return Err(Error::Other("odd-length hex string".into()));
    }
    let mut out = Vec::with_capacity(s.len() / 2);
    let bytes = s.as_bytes();
    for pair in bytes.chunks(2) {
        let hi = (pair[0] as char)
            .to_digit(16)
            .ok_or_else(|| Error::Other(format!("invalid hex: {s}")))?;
        let lo = (pair[1] as char)
            .to_digit(16)
            .ok_or_else(|| Error::Other(format!("invalid hex: {s}")))?;
        out.push((hi * 16 + lo) as u8);
    }
    Ok(out)
}

/// Converts `"{track_id}:{album}"` to `"track_id"`; passes plain ids through.
pub fn convert_track_id_to_number(id: &str) -> String {
    match id.split(':').next() {
        Some(n) => n.to_string(),
        None => id.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn convert_track_id() {
        assert_eq!(convert_track_id_to_number("12345:678"), "12345");
        assert_eq!(convert_track_id_to_number("12345"), "12345");
    }

    #[test]
    fn sign_request_deterministic() {
        // Python: hmac.new(b'key', b'12341700000000', sha256) b64
        let s = sign_request_at("1234:5", "key", 1_700_000_000);
        assert_eq!(s.timestamp, 1_700_000_000);
        // Value produced by the Python implementation.
        assert_eq!(s.value, "nz5LPlkEdE5o4OQTaa8VLSx/gWsiB/NoCI62aIQFd5c=");
    }

    #[test]
    fn file_info_sign_strips_padding() {
        let s = file_info_sign_at(
            "1234",
            "lossless",
            &["flac", "mp3"],
            "encraw",
            DESKTOP_SIGN_KEY,
            1_700_000_000,
        );
        // Value produced by the Python implementation (padding '=' removed).
        assert_eq!(s.value, "DmyC5uiWdNBzTYRlxLEnMXA0hUJ+TbhbQ7QB+arBbO0");
        assert!(!s.value.ends_with('='));
    }

    #[test]
    fn decrypt_roundtrip() {
        let key_hex = "00112233445566778899aabbccddeeff";
        let plain: Vec<u8> = (0..64u8).collect();
        let encrypted = decrypt_track(&plain, key_hex).unwrap();
        assert_ne!(encrypted, plain);
        let decrypted = decrypt_track(&encrypted, key_hex).unwrap();
        assert_eq!(decrypted, plain);
        assert!(decrypt_track(&plain, "zz").is_err());
    }
}
