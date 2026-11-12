//! Dev helper: OAuth device flow. Prints the user code, polls, writes the token to a file.
//!   cargo run --example devauth -- <token-output-file>
use ymusic_core::Client;

#[tokio::main]
async fn main() {
    let out = std::env::args().nth(1).expect("token output path");
    let mut client = Client::new(None).expect("client");
    let token = client
        .device_auth(
            |code| async move {
                println!(
                    "CODE={} URL={} EXPIRES_IN={:?}",
                    code.user_code.unwrap_or_default(),
                    code.verification_url.unwrap_or_default(),
                    code.expires_in
                );
            },
            Some(5.0),
            None,
            None::<fn() -> bool>,
            None,
            Some("ymusic dev probe"),
            None,
            None,
        )
        .await;
    match token {
        Ok(t) => {
            std::fs::write(&out, t.access_token.unwrap_or_default()).expect("write token");
            println!("TOKEN_SAVED");
        }
        Err(e) => println!("FAILED {e}"),
    }
}
