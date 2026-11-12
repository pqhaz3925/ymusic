//! Lenient deserializers. The API is inconsistent: ids come as numbers or strings,
//! numbers sometimes arrive as strings, booleans as 0/1.

use serde::{Deserialize, Deserializer};
use serde_json::Value;

/// `Option<String>` from a string, number or null. Use for every id-like field:
/// `#[serde(deserialize_with = "crate::models::de::opt_id")]`
pub fn opt_id<'de, D: Deserializer<'de>>(d: D) -> Result<Option<String>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::String(s) => Some(s),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    })
}

/// `Option<i64>` from a number, numeric string or null.
pub fn opt_i64<'de, D: Deserializer<'de>>(d: D) -> Result<Option<i64>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    })
}

/// `Option<f64>` from a number, numeric string or null.
pub fn opt_f64<'de, D: Deserializer<'de>>(d: D) -> Result<Option<f64>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().parse().ok(),
        _ => None,
    })
}

/// `Option<bool>` from a bool, 0/1, "true"/"false" or null.
pub fn opt_bool<'de, D: Deserializer<'de>>(d: D) -> Result<Option<bool>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Bool(b) => Some(b),
        Value::Number(n) => n.as_i64().map(|i| i != 0),
        Value::String(s) => match s.as_str() {
            "true" | "1" => Some(true),
            "false" | "0" => Some(false),
            _ => None,
        },
        _ => None,
    })
}

/// `Option<Vec<String>>` where items may be numbers or strings.
pub fn opt_ids<'de, D: Deserializer<'de>>(d: D) -> Result<Option<Vec<String>>, D::Error> {
    Ok(match Value::deserialize(d)? {
        Value::Array(a) => Some(
            a.into_iter()
                .filter_map(|v| match v {
                    Value::String(s) => Some(s),
                    Value::Number(n) => Some(n.to_string()),
                    _ => None,
                })
                .collect(),
        ),
        _ => None,
    })
}

/// `Vec<String>` where items may be numbers or strings; anything else (incl. `null`) is empty.
pub fn ids<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<String>, D::Error> {
    Ok(opt_ids(d)?.unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use serde::Deserialize;

    #[derive(Deserialize, Default)]
    #[serde(default)]
    struct T {
        #[serde(deserialize_with = "super::opt_id")]
        id: Option<String>,
        #[serde(deserialize_with = "super::opt_i64")]
        n: Option<i64>,
    }

    #[test]
    fn lenient() {
        let t: T = serde_json::from_str(r#"{"id":123,"n":"45"}"#).unwrap();
        assert_eq!(t.id.as_deref(), Some("123"));
        assert_eq!(t.n, Some(45));
        let t: T = serde_json::from_str(r#"{"id":null}"#).unwrap();
        assert!(t.id.is_none());
    }
}
