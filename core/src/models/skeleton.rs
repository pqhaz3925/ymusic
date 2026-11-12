//! Models of the `yandex_music/skeleton` package: UI skeletons of artist and concert pages.

use serde::{Deserialize, Serialize};

/// Source (list) of a skeleton block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkeletonSource {
    pub uri: Option<String>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub count_web: Option<i64>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub count: Option<i64>,
}

/// "View all" action of a skeleton block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkeletonViewAllAction {
    pub deeplink: Option<String>,
    pub weblink: Option<String>,
}

/// Data of a skeleton block.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkeletonBlockData {
    pub tabs: Option<Vec<SkeletonTab>>,
    #[serde(deserialize_with = "crate::models::de::opt_i64")]
    pub selected_tab_index: Option<i64>,
    pub source: Option<SkeletonSource>,
    pub title: Option<String>,
    pub show_policy: Option<String>,
    pub view_all_action: Option<SkeletonViewAllAction>,
}

/// A block of a skeleton.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkeletonBlock {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub r#type: Option<String>,
    pub data: Option<SkeletonBlockData>,
}

/// A tab of a skeleton.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SkeletonTab {
    #[serde(deserialize_with = "crate::models::de::opt_id")]
    pub id: Option<String>,
    pub title: Option<String>,
    pub blocks: Option<Vec<SkeletonBlock>>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn skeleton_de() {
        let v = r#"{"id":"tabs","type":"TABS","data":{"selectedTabIndex":0,"tabs":[
            {"id":"all","title":"All","blocks":[
                {"id":"rel","type":"ARTIST_RELEASE","data":{"title":"Releases",
                 "showPolicy":"default","source":{"uri":"artist:1:releases","countWeb":5,"count":3},
                 "viewAllAction":{"deeplink":"yandexmusic://a","weblink":"https://a"}}}]}]}}"#;
        let b: super::SkeletonBlock = serde_json::from_str(v).unwrap();
        let d = b.data.unwrap();
        let tabs = d.tabs.unwrap();
        let count = tabs[0].blocks.as_ref().unwrap()[0]
            .data
            .as_ref()
            .unwrap()
            .source
            .as_ref()
            .unwrap()
            .count;
        assert_eq!(count, Some(3));
    }
}
