//! Port of `yandex_music/_client/pins.py`.

use serde_json::json;
use serde_json::Value;

use super::Client;
use crate::http::{from_value, from_value_opt, is_ok};
use crate::models::pin::{Pin, PinsList};

impl Client {
    /// Get the list of pinned items.
    pub async fn pins(&self) -> crate::Result<Option<PinsList>> {
        let result = self.http.get(&self.url("/pins"), &[]).await?;
        from_value_opt(result)
    }

    /// Pin an album.
    pub async fn pin_album(&self, album_id: &str) -> crate::Result<Pin> {
        let result = self
            .http
            .put_json(&self.url("/pin/album"), &[], &json!({ "id": album_id }))
            .await?;
        from_value(result)
    }

    /// Unpin an album.
    pub async fn unpin_album(&self, album_id: &str) -> crate::Result<bool> {
        let result = self
            .http
            .delete(&self.url("/pin/album"), &[("id", album_id.to_string())])
            .await?;
        Ok(is_ok(&result))
    }

    /// Pin an artist.
    pub async fn pin_artist(&self, artist_id: &str) -> crate::Result<Pin> {
        let result = self
            .http
            .put_json(&self.url("/pin/artist"), &[], &json!({ "id": artist_id }))
            .await?;
        from_value(result)
    }

    /// Unpin an artist.
    pub async fn unpin_artist(&self, artist_id: &str) -> crate::Result<bool> {
        let result = self
            .http
            .delete(&self.url("/pin/artist"), &[("id", artist_id.to_string())])
            .await?;
        Ok(is_ok(&result))
    }

    /// Pin a playlist.
    pub async fn pin_playlist(&self, uid: &str, kind: &str) -> crate::Result<Pin> {
        let result = self
            .http
            .put_json(
                &self.url("/pin/playlist"),
                &[],
                &json!({ "uid": uid, "kind": kind }),
            )
            .await?;
        from_value(result)
    }

    /// Unpin a playlist.
    pub async fn unpin_playlist(&self, uid: &str, kind: &str) -> crate::Result<bool> {
        let result = self
            .http
            .delete(
                &self.url("/pin/playlist"),
                &[("uid", uid.to_string()), ("kind", kind.to_string())],
            )
            .await?;
        Ok(is_ok(&result))
    }

    /// Pin a wave.
    pub async fn pin_wave(&self, seeds: &str) -> crate::Result<Pin> {
        let result = self
            .http
            .put_json(&self.url("/pin/wave"), &[], &json!({ "seeds": seeds }))
            .await?;
        from_value(result)
    }

    /// Unpin a wave.
    pub async fn unpin_wave(&self, seeds: &str) -> crate::Result<bool> {
        let result = self
            .http
            .delete(&self.url("/pin/wave"), &[("seeds", seeds.to_string())])
            .await?;
        Ok(is_ok(&result))
    }
}

#[allow(dead_code)]
fn _assert_value(_: Value) {}
