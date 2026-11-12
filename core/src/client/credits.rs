//! Port of `yandex_music/_client/credits.py`.

use super::Client;
use crate::error::Result;
use crate::http::from_value_opt;
use crate::models::common::Credits;

impl Client {
    async fn get_credits(
        &self,
        entity_type: &str,
        entity_id: &str,
    ) -> Result<Option<Credits>> {
        let url = self.url(&format!("/{entity_type}/{entity_id}/credits"));
        let result = self.http.get(&url, &[]).await?;
        from_value_opt(result)
    }

    /// Get credits (contributors) of a track.
    pub async fn tracks_credits<S: AsRef<str>>(&self, track_id: S) -> Result<Option<Credits>> {
        self.get_credits("tracks", track_id.as_ref()).await
    }

    /// Get credits (contributors) of a clip.
    pub async fn clips_credits<S: AsRef<str>>(&self, clip_id: S) -> Result<Option<Credits>> {
        self.get_credits("clips", clip_id.as_ref()).await
    }
}
