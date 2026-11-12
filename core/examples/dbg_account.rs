//! Dev: what does the account look like (Plus / subscription flags)?
use ymusic_core::Client;

#[tokio::main]
async fn main() {
    let client = Client::new(std::env::var("YM_TOKEN").ok()).expect("client");
    match client.account_status().await {
        Ok(Some(s)) => {
            let v = serde_json::to_value(&s).unwrap_or_default();
            println!("plus = {}", v.get("plus").cloned().unwrap_or_default());
            let sub = v.get("subscription").cloned().unwrap_or_default();
            println!("subscription keys with values = {:?}", sub.as_object().map(|o| o.iter().filter(|(_, x)| !x.is_null()).map(|(k, _)| k.clone()).collect::<Vec<_>>()));
            println!("permissions = {}", v.pointer("/permissions/values").cloned().unwrap_or_default());
        }
        other => println!("{other:?}"),
    }
}
