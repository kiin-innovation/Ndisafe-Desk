#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${VERSION:?Set VERSION to the release version in Cargo.toml}"
python3 tools/check_release_version.py --version "$VERSION"
python3 tools/package_macos.py check-signing
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
(cd flutter && flutter pub get)
"$HOME/.cargo/bin/flutter_rust_bridge_codegen" --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --c-output ./flutter/macos/Runner/bridge_generated.h
./build.py --flutter
arch="$(uname -m)"
if [ "$arch" = "arm64" ]; then arch=aarch64; fi
python3 tools/package_macos.py package \
  --app ./flutter/build/macos/Build/Products/Release/Ndisafe-desk.app \
  --version "$VERSION" --arch "$arch" --output ./build/macos-installers
