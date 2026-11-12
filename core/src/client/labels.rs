//! Port of `yandex_music/_client/labels.py`.

use crate::error::Result;
use crate::http::{from_value_opt, Params};
use crate::models::label::{Label, LabelAlbums, LabelArtists};

use super::Client;

impl Client {
    /// Get information about a label.
    pub async fn label(&self, label_id: &str) -> Result<Option<Label>> {
        let v = self.http.get(&self.url(&format!("/labels/{label_id}")), &[]).await?;
        from_value_opt(v)
    }

    /// Get a page of a label's albums (`sort_by`: `year`|`rating`, `sort_order`: `asc`|`desc`).
    pub async fn label_albums(
        &self,
        label_id: &str,
        page: u32,
        page_size: u32,
        sort_by: Option<&str>,
        sort_order: Option<&str>,
    ) -> Result<Option<LabelAlbums>> {
        let mut params: Vec<(&str, String)> = vec![
            ("page", page.to_string()),
            ("pageSize", page_size.to_string()),
        ];
        if let Some(s) = sort_by {
            params.push(("sortBy", s.to_owned()));
        }
        if let Some(s) = sort_order {
            params.push(("sortOrder", s.to_owned()));
        }
        let v = self
            .http
            .get(&self.url(&format!("/labels/{label_id}/albums")), &params)
            .await?;
        from_value_opt(v)
    }

    /// Get a page of a label's artists.
    pub async fn label_artists(
        &self,
        label_id: &str,
        page: u32,
        page_size: u32,
    ) -> Result<Option<LabelArtists>> {
        let params: Params = &[
            ("page", page.to_string()),
            ("pageSize", page_size.to_string()),
        ];
        let v = self
            .http
            .get(&self.url(&format!("/labels/{label_id}/artists")), params)
            .await?;
        from_value_opt(v)
    }
}
