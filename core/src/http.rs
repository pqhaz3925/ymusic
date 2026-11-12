//! HTTP transport, mirroring `yandex_music/utils/request*.py`.
//!
//! Every call returns the `result` section of the API envelope, or the whole
//! body when `result` is absent (same rule as `RequestBase._parse`).

use std::time::Duration;

use reqwest::{Method, RequestBuilder, StatusCode};
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::error::{Error, Result};

pub const USER_AGENT: &str = "Yandex-Music-API";
pub const CLIENT_HEADER: &str = "YandexMusicAndroid/24023621";
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(15);
pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(6);
/// Extra attempts after the first one, for failures that are safe to repeat.
pub const RETRIES: u32 = 2;

/// Query / form parameters. Lists must already be joined with `,`.
pub type Params<'a> = &'a [(&'a str, String)];

#[derive(Clone)]
pub struct Http {
    inner: reqwest::Client,
    token: Option<String>,
    language: String,
    client_header: String,
}

impl Http {
    pub fn new(token: Option<String>, language: &str) -> Result<Self> {
        let inner = reqwest::Client::builder()
            .user_agent(USER_AGENT)
            .timeout(DEFAULT_TIMEOUT)
            .connect_timeout(CONNECT_TIMEOUT)
            .pool_idle_timeout(Duration::from_secs(60))
            .tcp_keepalive(Duration::from_secs(30))
            .build()?;
        Ok(Self {
            inner,
            token: token.filter(|t| !t.is_empty()),
            language: language.to_owned(),
            client_header: CLIENT_HEADER.to_owned(),
        })
    }

    pub fn token(&self) -> Option<&str> {
        self.token.as_deref()
    }

    pub fn set_client_header(&mut self, value: &str) {
        self.client_header = value.to_owned();
    }

    /// Request builder with the standard headers applied. Escape hatch for unusual calls.
    pub fn builder(&self, method: Method, url: &str) -> RequestBuilder {
        let mut rb = self
            .inner
            .request(method, url)
            .header("X-Yandex-Music-Client", &self.client_header)
            .header("Accept-Language", &self.language);
        if let Some(t) = &self.token {
            rb = rb.header("Authorization", format!("OAuth {t}"));
        }
        rb
    }

    pub async fn get(&self, url: &str, query: Params<'_>) -> Result<Value> {
        self.send(self.builder(Method::GET, url).query(query)).await
    }

    /// POST with an `application/x-www-form-urlencoded` body (the Python `data=` default).
    pub async fn post(&self, url: &str, form: Params<'_>) -> Result<Value> {
        self.send(self.builder(Method::POST, url).form(form)).await
    }

    pub async fn post_json(&self, url: &str, query: Params<'_>, body: &Value) -> Result<Value> {
        self.send(self.builder(Method::POST, url).query(query).json(body)).await
    }

    pub async fn put_json(&self, url: &str, query: Params<'_>, body: &Value) -> Result<Value> {
        self.send(self.builder(Method::PUT, url).query(query).json(body)).await
    }

    pub async fn delete(&self, url: &str, query: Params<'_>) -> Result<Value> {
        self.send(self.builder(Method::DELETE, url).query(query)).await
    }

    /// Raw bytes without envelope parsing (XML download info, audio, covers).
    pub async fn retrieve(&self, url: &str, query: Params<'_>) -> Result<Vec<u8>> {
        let (status, bytes) = self.execute(self.builder(Method::GET, url).query(query)).await?;
        if !status.is_success() {
            return Err(map_error(status, &bytes));
        }
        Ok(bytes)
    }

    pub async fn send(&self, rb: RequestBuilder) -> Result<Value> {
        let (status, bytes) = self.execute(rb).await?;
        if !status.is_success() {
            return Err(map_error(status, &bytes));
        }
        parse_envelope(&bytes)
    }

    /// Runs the request with a short retry loop, so a flaky mobile link doesn't surface
    /// as an error on the first hiccup.
    ///
    /// - connect failures are retried for every method (the request never left);
    /// - timeouts, broken bodies and 502/503/504 are retried for `GET` only.
    async fn execute(&self, rb: RequestBuilder) -> Result<(StatusCode, Vec<u8>)> {
        let (client, req) = rb.build_split();
        let req = req?;
        let is_get = req.method() == Method::GET;
        let mut attempt = 0u32;
        loop {
            // Bodies here are small in-memory forms/JSON, so cloning always succeeds.
            let Some(this) = req.try_clone() else {
                return Ok(read(client.execute(req).await?).await?);
            };
            let outcome = match client.execute(this).await {
                Ok(resp) => read(resp).await,
                Err(e) => Err(e),
            };
            let retry = attempt < RETRIES
                && match &outcome {
                    Ok((status, _)) => {
                        is_get
                            && matches!(
                                *status,
                                StatusCode::BAD_GATEWAY | StatusCode::SERVICE_UNAVAILABLE | StatusCode::GATEWAY_TIMEOUT
                            )
                    }
                    Err(e) => e.is_connect() || (is_get && (e.is_timeout() || e.is_request() || e.is_body())),
                };
            if !retry {
                return outcome.map_err(Error::from);
            }
            attempt += 1;
            tokio::time::sleep(Duration::from_millis(350 * u64::from(attempt))).await;
        }
    }
}

async fn read(resp: reqwest::Response) -> std::result::Result<(StatusCode, Vec<u8>), reqwest::Error> {
    let status = resp.status();
    let bytes = resp.bytes().await?;
    Ok((status, bytes.to_vec()))
}

/// Extract `result` from the API envelope (or the whole body if there is none).
pub fn parse_envelope(bytes: &[u8]) -> Result<Value> {
    if bytes.is_empty() {
        return Ok(Value::Null);
    }
    let mut data: Value = serde_json::from_slice(bytes)
        .map_err(|e| Error::InvalidResponse(format!("invalid server response: {e}")))?;
    match data.get_mut("result") {
        Some(r) if !r.is_null() => Ok(r.take()),
        _ => Ok(data),
    }
}

fn error_message(bytes: &[u8]) -> String {
    match serde_json::from_slice::<Value>(bytes) {
        Ok(v) => {
            let src = v.get("result").filter(|r| r.is_object()).unwrap_or(&v);
            let err = src
                .get("error")
                .map(|e| match e {
                    Value::String(s) => s.clone(),
                    Value::Object(o) => o.get("name").and_then(Value::as_str).unwrap_or_default().to_owned(),
                    other => other.to_string(),
                })
                .unwrap_or_default();
            let desc = src
                .get("errorDescription")
                .or_else(|| src.get("error").and_then(|e| e.get("message")))
                .and_then(Value::as_str)
                .unwrap_or_default();
            format!("{err} {desc}").trim().to_owned()
        }
        Err(_) => "Unknown HTTPError".to_owned(),
    }
}

fn map_error(status: StatusCode, bytes: &[u8]) -> Error {
    let msg = error_message(bytes);
    match status {
        StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => Error::Unauthorized(msg),
        StatusCode::BAD_REQUEST => Error::BadRequest(msg),
        StatusCode::NOT_FOUND => Error::NotFound(msg),
        StatusCode::BAD_GATEWAY => Error::Network("Bad Gateway".into()),
        _ => Error::Network(format!("{msg} ({status})")),
    }
}

/// Deserialize a `result` value into a model.
pub fn from_value<T: DeserializeOwned>(v: Value) -> Result<T> {
    serde_json::from_value(v).map_err(Error::from)
}

/// Deserialize, treating `null` as `None`.
pub fn from_value_opt<T: DeserializeOwned>(v: Value) -> Result<Option<T>> {
    if v.is_null() {
        Ok(None)
    } else {
        from_value(v).map(Some)
    }
}

/// `true` when the API answered with the literal `"ok"`.
pub fn is_ok(v: &Value) -> bool {
    v.as_str() == Some("ok")
}

/// Join ids for list parameters (`album-ids=1,2,3`).
pub fn join<I, S>(ids: I) -> String
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    ids.into_iter().map(|s| s.as_ref().to_owned()).collect::<Vec<_>>().join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn envelope_result() {
        let v = parse_envelope(br#"{"invocationInfo":{},"result":{"a":1}}"#).unwrap();
        assert_eq!(v["a"], 1);
    }

    #[test]
    fn envelope_without_result() {
        let v = parse_envelope(br#"{"a":2}"#).unwrap();
        assert_eq!(v["a"], 2);
    }

    #[test]
    fn error_text() {
        let m = error_message(br#"{"error":"validate","errorDescription":"bad"}"#);
        assert_eq!(m, "validate bad");
    }
}
