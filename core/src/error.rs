//! Library errors, mirroring `yandex_music/exceptions.py`.

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("unauthorized: {0}")]
    Unauthorized(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("not found: {0}")]
    NotFound(String),
    #[error("network error: {0}")]
    Network(String),
    #[error("timed out")]
    TimedOut,
    #[error("invalid response: {0}")]
    InvalidResponse(String),
    #[error("invalid bitrate")]
    InvalidBitrate,
    #[error("id missing: {0}")]
    IdMissing(String),
    #[error("device auth: {0}")]
    DeviceAuth(String),
    #[error("ynison: {0}")]
    Ynison(String),
    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, Error>;

impl From<reqwest::Error> for Error {
    fn from(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            Error::TimedOut
        } else {
            Error::Network(e.to_string())
        }
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Error::InvalidResponse(e.to_string())
    }
}
