//! Port of `yandex_music/_client/landing.py`.

use serde_json::Value;

use crate::http::{from_value, from_value_opt, is_ok};
use crate::models::feed::Feed;
use crate::models::genre::Genre;
use crate::models::landing::{ChartInfo, Landing, LandingList};
use crate::models::playlist::TagResult;

use super::Client;

impl Client {
    /// Get the user's feed (`GET /feed`).
    pub async fn feed(&self) -> crate::Result<Option<Feed>> {
        let v = self.http.get(&self.url("/feed"), &[]).await?;
        from_value_opt(v)
    }

    /// Whether the user has passed the wizard (`GET /feed/wizard/is-passed`).
    pub async fn feed_wizard_is_passed(&self) -> crate::Result<bool> {
        let v = self.http.get(&self.url("/feed/wizard/is-passed"), &[]).await?;
        if is_ok(&v) {
            return Ok(v.get("isWizardPassed").and_then(Value::as_bool).unwrap_or(false));
        }
        Ok(false)
    }

    /// Get landing page blocks (`GET /landing3`).
    pub async fn landing<S: AsRef<str>>(&self, blocks: &[S]) -> crate::Result<Option<Landing>> {
        let blocks: Vec<&str> = blocks.iter().map(AsRef::as_ref).collect();
        let v = self
            .http
            .get(
                &self.url("/landing3"),
                &[
                    ("blocks", blocks.join(",")),
                    ("eitherUserId", "10254713668400548221".to_owned()),
                ],
            )
            .await?;
        from_value_opt(v)
    }

    /// Get chart, optionally for a chart option such as `world` or `russia` (`GET /landing3/chart`).
    pub async fn chart(&self, chart_option: &str) -> crate::Result<Option<ChartInfo>> {
        let path = if chart_option.is_empty() {
            "/landing3/chart".to_owned()
        } else {
            format!("/landing3/chart/{chart_option}")
        };
        let v = self.http.get(&self.url(&path), &[]).await?;
        from_value_opt(v)
    }

    /// Get all new releases (`GET /landing3/new-releases`).
    pub async fn new_releases(&self) -> crate::Result<Option<LandingList>> {
        let v = self.http.get(&self.url("/landing3/new-releases"), &[]).await?;
        from_value_opt(v)
    }

    /// Get all new playlists (`GET /landing3/new-playlists`).
    pub async fn new_playlists(&self) -> crate::Result<Option<LandingList>> {
        let v = self.http.get(&self.url("/landing3/new-playlists"), &[]).await?;
        from_value_opt(v)
    }

    /// Get podcasts from the landing page (`GET /landing3/podcasts`).
    pub async fn podcasts(&self) -> crate::Result<Option<LandingList>> {
        let v = self.http.get(&self.url("/landing3/podcasts"), &[]).await?;
        from_value_opt(v)
    }

    /// Get music genres (`GET /genres`).
    pub async fn genres(&self) -> crate::Result<Vec<Genre>> {
        let v = self.http.get(&self.url("/genres"), &[]).await?;
        from_value(v)
    }

    /// Get tag playlists (`GET /tags/{tag_id}/playlist-ids`).
    pub async fn tags(&self, tag_id: &str) -> crate::Result<Option<TagResult>> {
        let v = self.http.get(&self.url(&format!("/tags/{tag_id}/playlist-ids")), &[]).await?;
        from_value_opt(v)
    }
}
