//! Models of the `yandex_music/wave` package: the "Wave" (personal radio) feature.

use serde::{Deserialize, Serialize};

/// Wave description.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Wave {
    pub name: Option<String>,
    pub description: Option<String>,
    pub seeds: Option<Vec<String>>,
    pub station_id: Option<String>,
    pub id_for_from: Option<String>,
    pub r#type: Option<String>,
}

/// Entity (album or artist) a wave agent is built from.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WaveAgentEntity {
    pub r#type: Option<String>,
}

/// Animated cover agent of a wave.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WaveAgent {
    pub animation_uri: Option<String>,
    pub cover: Option<crate::models::common::Cover>,
    pub entity: Option<WaveAgentEntity>,
}

/// Data of a similar entity item (wave and agent).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SimilarEntityData {
    pub wave: Option<Wave>,
    pub agent: Option<WaveAgent>,
}

/// A similar entity item (type `wave_agent_item`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SimilarEntityItem {
    pub r#type: Option<String>,
    pub data: Option<SimilarEntityData>,
}

/// Default station of a wave.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WaveDefaultStation {
    pub station_id: Option<String>,
    pub title: Option<String>,
    pub rup_title: Option<String>,
    pub rup_description: Option<String>,
}

/// A block of wave settings (type `contexts`).
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WaveSettingsBlock {
    pub r#type: Option<String>,
    pub items: Option<Vec<crate::models::rotor::Station>>,
}

/// Wave settings: default station, blocks and setting restrictions.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WaveSettings {
    pub default_station: Option<WaveDefaultStation>,
    pub blocks: Option<Vec<WaveSettingsBlock>>,
    pub setting_restrictions: Option<crate::models::rotor::Restrictions>,
}

#[cfg(test)]
mod tests {
    #[test]
    fn wave_de() {
        let v = r#"{"name":"Wave","description":"d","seeds":["artist:1"],"stationId":"user:onyourwave",
            "idForFrom":"user:onyourwave","type":"DEFAULT"}"#;
        let w: super::Wave = serde_json::from_str(v).unwrap();
        assert_eq!(w.seeds.unwrap(), vec!["artist:1".to_string()]);
        assert_eq!(w.id_for_from.as_deref(), Some("user:onyourwave"));
        let s: super::WaveSettings = serde_json::from_str(
            r#"{"defaultStation":{"stationId":"s","title":"t","rupTitle":"r","rupDescription":"d"},
                "blocks":[{"type":"contexts","items":[]}],"settingRestrictions":{"language":{}}}"#,
        )
        .unwrap();
        assert_eq!(s.default_station.unwrap().rup_title.as_deref(), Some("r"));
        assert_eq!(s.blocks.unwrap()[0].r#type.as_deref(), Some("contexts"));
    }
}
