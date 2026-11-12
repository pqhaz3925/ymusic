//! Port of `yandex_music/experiment` (account experiment details).

use serde::{Deserialize, Serialize};

/// Value (configuration) of an experiment group; `extra` keeps per-experiment keys.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ExperimentDetailValue {
    pub title: Option<String>,
    /// Remaining per-experiment configuration fields.
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

/// One experiment in a detailed response.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ExperimentDetail {
    pub group: Option<String>,
    pub value: Option<ExperimentDetailValue>,
}

/// Detailed values of account experiments; keys are experiment names.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ExperimentsDetails {
    pub experiments: std::collections::HashMap<String, ExperimentDetail>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_experiments_details() {
        let json = r#"{
            "AliceTest": {
                "group": "control",
                "value": {"title": "control", "enabled": true, "threshold": 0.5, "ids": [1, 2]}
            },
            "3dsRubilnik": {
                "group": "on",
                "value": {"title": "on"}
            }
        }"#;
        let d: ExperimentsDetails = serde_json::from_str(json).unwrap();
        let alice = &d.experiments["AliceTest"];
        assert_eq!(alice.group.as_deref(), Some("control"));
        let v = alice.value.as_ref().unwrap();
        assert_eq!(v.title.as_deref(), Some("control"));
        assert_eq!(v.extra["enabled"], serde_json::json!(true));
        assert!(d.experiments.contains_key("3dsRubilnik"));
    }
}
