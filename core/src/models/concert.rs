//! Port of `yandex_music/concert`: concerts, feeds, locations and tab configuration.

use serde::{Deserialize, Serialize};

use crate::models::common::Cover;
use crate::models::de::{opt_id, opt_i64};
use crate::models::skeleton::SkeletonBlock;

/// List of an artist's concerts.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ArtistConcerts {
    /// Artist title.
    pub artist_title: Option<String>,
    /// Concerts.
    pub concerts: Vec<crate::models::concert::Concert>,
}

/// Cashback information for a ticket purchase.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertCashback {
    /// Cashback text, e.g. "Кешбэк до 20%".
    pub title: Option<String>,
    /// Cashback percent.
    #[serde(deserialize_with = "opt_i64")]
    pub value_percent: Option<i64>,
}

/// Concert description with its source.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertDescription {
    /// Description text.
    pub text: Option<String>,
    /// Description source (e.g. domain name).
    pub source: Option<String>,
}

/// Event type information (concert, festival).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertEventInfo {
    /// Event type.
    pub r#type: Option<String>,
}

/// Data of a concert feed item.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertFeedItemData {
    /// Concert.
    pub concert: Option<Box<crate::models::concert::Concert>>,
    /// Minimum ticket price.
    pub min_price: Option<crate::models::concert::ConcertMinPrice>,
}

/// Item of the concert feed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertFeedItem {
    /// Feed item type (known: `concert_item`).
    pub r#type: Option<String>,
    /// Feed item data.
    pub data: Option<crate::models::concert::ConcertFeedItemData>,
}

/// Concert feed.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertFeed {
    /// Feed items.
    pub items: Vec<crate::models::concert::ConcertFeedItem>,
}

/// Detailed concert information.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertInfo {
    /// Concert.
    pub concert: Option<Box<crate::models::concert::Concert>>,
    /// Minimum ticket price.
    pub min_price: Option<crate::models::concert::ConcertMinPrice>,
    /// Additional concert covers.
    pub covers: Vec<Cover>,
    /// Concert description.
    pub description: Option<crate::models::concert::ConcertDescription>,
    /// Lead artist id.
    #[serde(deserialize_with = "opt_id")]
    pub lead_artist_id: Option<String>,
}

/// City available for filtering concerts.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertLocation {
    /// Location id (geoId).
    #[serde(deserialize_with = "opt_id")]
    pub id: Option<String>,
    /// Location name.
    pub name: Option<String>,
}

/// List of locations for filtering concerts.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertLocations {
    /// Locations.
    pub locations: Vec<crate::models::concert::ConcertLocation>,
}

/// Minimum ticket price.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertMinPrice {
    /// Price value.
    #[serde(deserialize_with = "opt_i64")]
    pub value: Option<i64>,
    /// Currency code, e.g. "RUB".
    pub currency: Option<String>,
    /// Currency symbol, e.g. "₽".
    pub currency_symbol: Option<String>,
}

/// Skeleton of the concert page.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertSkeleton {
    /// Skeleton id.
    pub id: Option<String>,
    /// Skeleton title.
    pub title: Option<String>,
    /// Skeleton blocks.
    pub blocks: Option<Vec<SkeletonBlock>>,
}

/// Concert tabs configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertTabConfigData {
    /// Range for the "Top" block.
    pub top: Option<crate::models::concert::ConcertTabRange>,
    /// Range for the concert feed.
    pub feed: Option<crate::models::concert::ConcertTabRange>,
}

/// Concert feed tabs configuration.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertTabConfig {
    /// Tabs configuration.
    pub config: Option<crate::models::concert::ConcertTabConfigData>,
}

/// Pagination range of a concert tab.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ConcertTabRange {
    /// Offset from the start.
    #[serde(deserialize_with = "opt_i64")]
    pub offset: Option<i64>,
    /// Items count, `-1` means "until the end".
    #[serde(deserialize_with = "opt_i64")]
    pub limit: Option<i64>,
}

/// Concert or festival event.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Concert {
    /// Concert UUID.
    pub id: Option<String>,
    /// Image URLs.
    pub images: Option<Vec<String>>,
    /// Main image URL.
    pub image_url: Option<String>,
    /// Concert/festival title.
    pub concert_title: Option<String>,
    /// Afisha page link.
    pub afisha_url: Option<String>,
    /// City.
    pub city: Option<String>,
    /// Venue.
    pub place: Option<String>,
    /// Address.
    pub address: Option<String>,
    /// Date and time (ISO 8601).
    pub datetime: Option<String>,
    /// Age rating, e.g. "16+".
    pub content_rating: Option<String>,
    /// Minimum ticket price.
    pub min_price: Option<crate::models::concert::ConcertMinPrice>,
    /// Cashback information.
    pub cashback: Option<crate::models::concert::ConcertCashback>,
    /// Event type information.
    pub event_info: Option<crate::models::concert::ConcertEventInfo>,
    /// Concert cover.
    pub cover: Option<Cover>,
    /// Data session id used by Afisha.
    pub data_session_id: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_concert_feed() {
        let json = r#"{
            "items": [{
                "type": "concert_item",
                "data": {
                    "concert": {
                        "id": "b1f5e5d4-1111-4a2c-9e3b-0c8e1f2a3b4c",
                        "images": ["https://avatars.yandex.net/concert/1/400x400"],
                        "imageUrl": "https://avatars.yandex.net/concert/1/600x600",
                        "concertTitle": "Some Artist",
                        "afishaUrl": "https://afisha.yandex.ru/concert/1",
                        "city": "Москва",
                        "place": "Клуб",
                        "address": "ул. Примерная, 1",
                        "datetime": "2026-11-20T20:00:00+03:00",
                        "contentRating": "16+",
                        "minPrice": {"value": 1500, "currency": "RUB", "currencySymbol": "₽"},
                        "cashback": {"title": "Кешбэк до 20%", "valuePercent": 20},
                        "eventInfo": {"type": "concert"}
                    },
                    "minPrice": {"value": "1500", "currency": "RUB", "currencySymbol": "₽"}
                }
            }]
        }"#;
        let feed: ConcertFeed = serde_json::from_str(json).unwrap();
        assert_eq!(feed.items.len(), 1);
        let data = feed.items[0].data.as_ref().unwrap();
        let concert = data.concert.as_ref().unwrap();
        assert_eq!(concert.city.as_deref(), Some("Москва"));
        assert_eq!(concert.min_price.as_ref().unwrap().value, Some(1500));
        assert_eq!(data.min_price.as_ref().unwrap().value, Some(1500));
        assert_eq!(feed.items[0].r#type.as_deref(), Some("concert_item"));
    }

    #[test]
    fn deserialize_concert_info_and_tabs() {
        let json = r#"{
            "concert": {"id": "c1", "concertTitle": "Fest"},
            "covers": [],
            "description": {"text": "About", "source": "afisha.yandex.ru"},
            "leadArtistId": 12345
        }"#;
        let info: ConcertInfo = serde_json::from_str(json).unwrap();
        assert_eq!(info.lead_artist_id.as_deref(), Some("12345"));
        assert_eq!(info.description.unwrap().source.as_deref(), Some("afisha.yandex.ru"));

        let json = r#"{"config": {"top": {"offset": 0, "limit": -1}, "feed": {"offset": 10, "limit": 20}}}"#;
        let cfg: ConcertTabConfig = serde_json::from_str(json).unwrap();
        let cfg = cfg.config.unwrap();
        assert_eq!(cfg.top.unwrap().limit, Some(-1));
        assert_eq!(cfg.feed.unwrap().offset, Some(10));

        let json = r#"{"artistTitle": "A", "concerts": [{"id": "x"}], "locations": [{"id": 213, "name": "Москва"}]}"#;
        let ac: ArtistConcerts = serde_json::from_str(json).unwrap();
        assert_eq!(ac.concerts.len(), 1);
        let locs: ConcertLocations = serde_json::from_str(r#"{"locations": [{"id": 213, "name": "Москва"}]}"#).unwrap();
        assert_eq!(locs.locations[0].id.as_deref(), Some("213"));

        let sk: ConcertSkeleton = serde_json::from_str(r#"{"id": "s", "title": "t", "blocks": []}"#).unwrap();
        assert_eq!(sk.blocks.unwrap().len(), 0);
    }
}
