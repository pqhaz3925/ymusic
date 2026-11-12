//! Port of `yandex_music/_client/device_auth.py` (OAuth Device Flow).

use std::future::Future;
use std::time::{Duration, Instant};

use crate::error::{Error, Result};
use crate::http::from_value_opt;
use crate::models::device_auth::{DeviceCode, OAuthToken};

use super::Client;

/// Public OAuth client_id of the official Android Yandex.Music app.
pub const DEFAULT_CLIENT_ID: &str = "23cabbbdc6cd418abb4b39c32c41195d";
/// Public OAuth client_secret of the official Android Yandex.Music app.
pub const DEFAULT_CLIENT_SECRET: &str = "53bc75238f0c4d08a118e51fe9203300";
/// Default human-readable device name.
pub const DEFAULT_DEVICE_NAME: &str = "YandexMusicAPI";
/// OAuth host.
pub const OAUTH_BASE_URL: &str = "https://oauth.yandex.ru";

/// Random 10-character alphanumeric device id.
fn rand_device_id() -> String {
    const ALNUM: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
        ^ (std::process::id() as u64).rotate_left(32);
    (0..10)
        .map(|_| {
            // xorshift64
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            ALNUM[(seed % ALNUM.len() as u64) as usize] as char
        })
        .collect()
}

fn or_default<'a>(value: Option<&'a str>, default: &'a str) -> &'a str {
    match value {
        Some(v) if !v.is_empty() => v,
        _ => default,
    }
}

impl Client {
    /// Request a device code for OAuth Device Flow (defaults: random id, `YandexMusicAPI`).
    pub async fn request_device_code(
        &self,
        device_id: Option<&str>,
        device_name: Option<&str>,
        client_id: Option<&str>,
    ) -> Result<DeviceCode> {
        let device_id = match device_id {
            Some(v) if !v.is_empty() => v.to_owned(),
            _ => rand_device_id(),
        };
        let data = [
            ("client_id", or_default(client_id, DEFAULT_CLIENT_ID).to_owned()),
            ("device_id", device_id),
            ("device_name", or_default(device_name, DEFAULT_DEVICE_NAME).to_owned()),
        ];
        let result = self.http.post(&format!("{OAUTH_BASE_URL}/device/code"), &data).await?;
        from_value_opt::<DeviceCode>(result)?
            .ok_or_else(|| Error::DeviceAuth("failed to parse device code response".into()))
    }

    /// Poll the token once; `Ok(None)` means the user has not confirmed yet (`authorization_pending`).
    pub async fn poll_device_token(
        &self,
        device_code: &str,
        client_id: Option<&str>,
        client_secret: Option<&str>,
    ) -> Result<Option<OAuthToken>> {
        let data = [
            ("grant_type", "device_code".to_owned()),
            ("code", device_code.to_owned()),
            ("client_id", or_default(client_id, DEFAULT_CLIENT_ID).to_owned()),
            ("client_secret", or_default(client_secret, DEFAULT_CLIENT_SECRET).to_owned()),
        ];
        let result = match self.http.post(&format!("{OAUTH_BASE_URL}/token"), &data).await {
            Ok(v) => v,
            Err(Error::BadRequest(msg)) if msg.contains("authorization_pending") => return Ok(None),
            Err(Error::BadRequest(msg)) => return Err(Error::DeviceAuth(msg)),
            Err(e) => return Err(e),
        };
        from_value_opt::<OAuthToken>(result)
    }

    /// Blocking OAuth Device Flow: request the code, call `on_code`, poll until confirmed, set the token.
    pub async fn device_auth<F, Fut, C>(
        &mut self,
        on_code: F,
        poll_interval: Option<f64>,
        timeout: Option<f64>,
        should_cancel: Option<C>,
        device_id: Option<&str>,
        device_name: Option<&str>,
        client_id: Option<&str>,
        client_secret: Option<&str>,
    ) -> Result<OAuthToken>
    where
        F: FnOnce(DeviceCode) -> Fut,
        Fut: Future<Output = ()>,
        C: Fn() -> bool,
    {
        let code = self.request_device_code(device_id, device_name, client_id).await?;
        on_code(code.clone()).await;

        let interval = poll_interval.unwrap_or(code.interval.unwrap_or(0) as f64);
        let total = timeout.unwrap_or(code.expires_in.unwrap_or(0) as f64);
        let deadline = Instant::now() + Duration::from_secs_f64(total.max(0.0));
        let device_code = code.device_code.clone().unwrap_or_default();

        loop {
            if let Some(cancel) = &should_cancel {
                if cancel() {
                    return Err(Error::DeviceAuth("cancelled by caller".into()));
                }
            }

            if let Some(token) = self.poll_device_token(&device_code, client_id, client_secret).await? {
                self.http = crate::http::Http::new(token.access_token.clone(), &self.language)?;
                return Ok(token);
            }

            if Instant::now() >= deadline {
                return Err(Error::DeviceAuth(format!(
                    "timed out after {total}s waiting for user confirmation"
                )));
            }

            tokio::time::sleep(Duration::from_secs_f64(interval.max(0.0))).await;
        }
    }
}
