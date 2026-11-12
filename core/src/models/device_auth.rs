//! Port of `yandex_music/device_auth` (OAuth device flow).

use serde::{Deserialize, Serialize};

/// Device code for OAuth Device Flow.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", default)]
pub struct DeviceCode {
    #[serde(rename = "device_code", alias = "deviceCode")]
    pub device_code: Option<String>,
    #[serde(rename = "user_code", alias = "userCode")]
    pub user_code: Option<String>,
    #[serde(rename = "verification_url", alias = "verificationUrl")]
    pub verification_url: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub expires_in: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub interval: Option<i64>,
}

/// OAuth token obtained via Device Flow.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", default)]
pub struct OAuthToken {
    #[serde(rename = "access_token", alias = "accessToken")]
    pub access_token: Option<String>,
    #[serde(rename = "refresh_token", alias = "refreshToken")]
    pub refresh_token: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub expires_in: Option<i64>,
    #[serde(rename = "token_type", alias = "tokenType")]
    pub token_type: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_device_code() {
        let json = r#"{
            "device_code": "abcdef0123456789",
            "user_code": "ABCDEFG",
            "verification_url": "https://oauth.yandex.ru/authorize/device",
            "expires_in": 300,
            "interval": 5
        }"#;
        let c: DeviceCode = serde_json::from_str(json).unwrap();
        assert_eq!(c.device_code.as_deref(), Some("abcdef0123456789"));
        assert_eq!(c.expires_in, Some(300));
        assert_eq!(c.interval, Some(5));
    }

    #[test]
    fn deserialize_oauth_token() {
        let json = r#"{
            "access_token": "y0_AgAAAAB",
            "refresh_token": "1:refresh",
            "expires_in": 31536000,
            "token_type": "bearer"
        }"#;
        let t: OAuthToken = serde_json::from_str(json).unwrap();
        assert_eq!(t.access_token.as_deref(), Some("y0_AgAAAAB"));
        assert_eq!(t.token_type.as_deref(), Some("bearer"));
    }
}
