//! Port of `yandex_music/_client/presaves.py`.

use super::Client;
use crate::error::Result;
use crate::http::{from_value_opt, is_ok};
use crate::models::presave::Presaves;

impl Client {
    /// GET `/users/{uid}/presaves` with `includeReleased`/`includeUpcoming`.
    pub async fn users_presaves(
        &self,
        include_released: bool,
        include_upcoming: bool,
        user_id: Option<&str>,
    ) -> Result<Option<Presaves>> {
        let uid = self.uid(user_id)?;
        let v = self
            .http
            .get(
                &self.url(&format!("/users/{uid}/presaves")),
                &[
                    ("includeReleased", include_released.to_string()),
                    ("includeUpcoming", include_upcoming.to_string()),
                ],
            )
            .await?;
        from_value_opt(v)
    }

    /// POST `/users/{uid}/presaves/add` with `albumId`/`likeAfterRelease`; true on `"ok"`.
    pub async fn users_presaves_add(
        &self,
        album_id: &str,
        like_after_release: bool,
        user_id: Option<&str>,
    ) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let v = self
            .http
            .post(
                &self.url(&format!("/users/{uid}/presaves/add")),
                &[
                    ("albumId", album_id.to_owned()),
                    ("likeAfterRelease", like_after_release.to_string()),
                ],
            )
            .await?;
        Ok(is_ok(&v))
    }

    /// POST `/users/{uid}/presaves/remove` with `albumId`; true on `"ok"`.
    pub async fn users_presaves_remove(&self, album_id: &str, user_id: Option<&str>) -> Result<bool> {
        let uid = self.uid(user_id)?;
        let v = self
            .http
            .post(
                &self.url(&format!("/users/{uid}/presaves/remove")),
                &[("albumId", album_id.to_owned())],
            )
            .await?;
        Ok(is_ok(&v))
    }
}
