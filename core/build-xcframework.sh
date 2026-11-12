#!/usr/bin/env bash
# Build ymusic_core for iOS device + simulator + macOS (Apple silicon), generate Swift bindings, pack XCFramework.
set -euo pipefail
cd "$(dirname "$0")"

LIB=ymusic_core
IOS_DIR="$(cd .. && pwd)/ios"
SWIFT_OUT="$IOS_DIR/YaMusic/Core/Generated"
XCF="$IOS_DIR/Frameworks/YmCore.xcframework"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Match the apps' deployment targets, or the linker warns on every C object of the TLS stack.
export IPHONEOS_DEPLOYMENT_TARGET=26.0
export MACOSX_DEPLOYMENT_TARGET=26.0

# 1. Static libs for device and simulator
cargo build --release --lib --target aarch64-apple-ios
cargo build --release --lib --target aarch64-apple-ios-sim
cargo build --release --lib --target aarch64-apple-darwin
DEV_A="target/aarch64-apple-ios/release/lib${LIB}.a"
SIM_A="target/aarch64-apple-ios-sim/release/lib${LIB}.a"
MAC_A="target/aarch64-apple-darwin/release/lib${LIB}.a"

# 2. Swift bindings from the static lib (uniffi 0.32 library mode);
#    fall back to a host dylib if the .a is rejected.
BIND_OUT="$TMP/bindings"
if ! cargo run --release --bin uniffi-bindgen -- generate \
      --library "$DEV_A" --language swift --out-dir "$BIND_OUT"; then
  echo "static lib rejected, using host dylib" >&2
  cargo build --release --lib
  cargo run --release --bin uniffi-bindgen -- generate \
    --library target/release/lib${LIB}.dylib --language swift --out-dir "$BIND_OUT"
fi

# 3. Swift sources go to the app, C header + modulemap go into headers dir
mkdir -p "$SWIFT_OUT"
cp "$BIND_OUT"/*.swift "$SWIFT_OUT"/
HEADERS="$TMP/headers"
mkdir -p "$HEADERS"
cp "$BIND_OUT"/*.h "$HEADERS"/
# uniffi emits <Name>FFI.modulemap -> module.modulemap
cp "$BIND_OUT"/*FFI.modulemap "$HEADERS/module.modulemap"

# 4. Pack XCFramework
rm -rf "$XCF"
mkdir -p "$(dirname "$XCF")"
xcodebuild -create-xcframework \
  -library "$DEV_A" -headers "$HEADERS" \
  -library "$SIM_A" -headers "$HEADERS" \
  -library "$MAC_A" -headers "$HEADERS" \
  -output "$XCF"

echo "OK: $XCF"
