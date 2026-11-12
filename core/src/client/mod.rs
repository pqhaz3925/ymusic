//! API client, mirroring `yandex_music/client.py` + `_client/*` mixins.
//! Each submodule adds an `impl Client { ... }` block.

use std::sync::RwLock;

use serde_json::Value;

use crate::error::{Error, Result};
use crate::http::{join, Http};

pub mod account;
pub mod albums;
pub mod artists;
pub mod clips;
pub mod concerts;
pub mod credits;
pub mod device_auth;
pub mod disclaimers;
pub mod labels;
pub mod landing;
pub mod likes;
pub mod metatags;
pub mod music_history;
pub mod pins;
pub mod playlists;
pub mod presaves;
pub mod queue;
pub mod radio;
pub mod rotor_sessions;
pub mod search;
pub mod tracks;
pub mod wave;

pub const BASE_URL: &str = "https://api.music.yandex.net";

pub struct Client {
    pub(crate) http: Http,
    pub base_url: String,
    pub language: String,
    pub(crate) account_uid: RwLock<Option<i64>>,
}

impl Client {
    pub fn new(token: Option<String>) -> Result<Self> {
        Self::with_options(token, BASE_URL, "ru")
    }

    pub fn with_options(token: Option<String>, base_url: &str, language: &str) -> Result<Self> {
        Ok(Self {
            http: Http::new(token, language)?,
            base_url: base_url.trim_end_matches('/').to_owned(),
            language: language.to_owned(),
            account_uid: RwLock::new(None),
        })
    }

    pub fn http(&self) -> &Http {
        &self.http
    }

    /// `base_url + path`; `path` must start with `/`.
    pub(crate) fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    pub fn account_uid(&self) -> Option<i64> {
        *self.account_uid.read().unwrap()
    }

    pub(crate) fn set_account_uid(&self, uid: Option<i64>) {
        *self.account_uid.write().unwrap() = uid;
    }

    /// Resolve `user_id` the way the Python mixins do: explicit value, else the logged-in uid.
    pub(crate) fn uid(&self, user_id: Option<&str>) -> Result<String> {
        match user_id {
            Some(u) => Ok(u.to_owned()),
            None => self
                .account_uid()
                .map(|u| u.to_string())
                .ok_or_else(|| Error::IdMissing("user_id is required; call Client::init first".into())),
        }
    }

    /// Port of `_BatchMixin._get_list`: POST `/{type}s` (`/playlists/list`) with `{type}-ids`.
    /// Returns the raw list; callers deserialize into the concrete model.
    pub(crate) async fn get_list_raw<S: AsRef<str>>(&self, object_type: &str, ids: &[S]) -> Result<Value> {
        let suffix = if object_type == "playlist" { "/list" } else { "" };
        let url = self.url(&format!("/{object_type}s{suffix}"));
        let key = format!("{object_type}-ids");
        self.http.post(&url, &[(key.as_str(), join(ids))]).await
    }
}
