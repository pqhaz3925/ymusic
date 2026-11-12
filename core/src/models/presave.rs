//! Models of the `yandex_music/presave` package (pre-saved albums).

use serde::Deserialize;
use serde::Serialize;

/// Pre-saved albums split into upcoming and released.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Presaves {
    /// Albums not released yet.
    pub upcoming_albums: Option<Vec<crate::models::album::Album>>,
    /// Already released albums.
    pub released_albums: Option<Vec<crate::models::album::Album>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_presaves() {
        let json = r##"{"upcomingAlbums": [{"id": 1, "title": "Soon"}], "releasedAlbums": [{"id": 2, "title": "Out"}]}"##;
        let p: Presaves = serde_json::from_str(json).unwrap();
        assert_eq!(p.upcoming_albums.unwrap()[0].title.as_deref(), Some("Soon"));
        assert_eq!(p.released_albums.unwrap()[0].id.as_deref(), Some("2"));
    }
}
