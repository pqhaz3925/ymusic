//! Port of `yandex_music/_client/clips.py`.

use crate::error::Result;
use crate::http::{from_value, from_value_opt, join};
use crate::models::clip::{Clip, ClipsWillLike};

use super::Client;

impl Client {
    /// Get clips by identifiers (`GET /clips`).
    pub async fn clips<S: AsRef<str>>(&self, clip_ids: &[S]) -> Result<Vec<Clip>> {
        let url = self.url("/clips");
        let value = self.http.get(&url, &[("clipIds", join(clip_ids))]).await?;
        from_value(value)
    }

    /// Get the recommended clips collection (`GET /clips/will/like`).
    pub async fn clips_will_like(&self, page: i64, page_size: i64) -> Result<Option<ClipsWillLike>> {
        let url = self.url("/clips/will/like");
        let value = self
            .http
            .get(
                &url,
                &[("page", page.to_string()), ("pageSize", page_size.to_string())],
            )
            .await?;
        from_value_opt(value)
    }
}
