#!/bin/sh
# ─────────────────────────────────────────────────────────────
# Builds the Rust crypto crate for iOS (the counterpart of the `cargo ndk` Android build in the
# README) and packages it as ios/Frameworks/cluborbit_matrix_native.xcframework, which
# ios/cluborbit_matrix.podspec embeds in the app.
#
# Dart loads it as `cluborbit_matrix_native.framework/cluborbit_matrix_native` (flutter_rust_bridge's
# default on iOS), so each slice is a dynamic framework with that name.
#
# Needs Rust (https://rustup.rs) and Xcode. Run on a Mac after changing the Rust code:
#   cluborbit_matrix/rust/build_ios.sh
# then `pod install` (or any flutter build) in the app.
# ─────────────────────────────────────────────────────────────
set -eu

NAME=cluborbit_matrix_native
MIN_IOS=15.0
RUST_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(dirname "$RUST_DIR")/ios/Frameworks"
WORK_DIR="$RUST_DIR/target/ios-framework"

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
command -v cargo >/dev/null || { echo "error: Rust not found - install it from https://rustup.rs" >&2; exit 1; }
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios >/dev/null

cd "$RUST_DIR"
export IPHONEOS_DEPLOYMENT_TARGET=$MIN_IOS
for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  echo "▸ cargo build --release --target $target"
  cargo build --release --target "$target"
done

# make_framework <dir> <dylib> <platform: iPhoneOS|iPhoneSimulator>
make_framework() {
  fw="$1/$NAME.framework"
  rm -rf "$fw"
  mkdir -p "$fw"
  cp "$2" "$fw/$NAME"
  install_name_tool -id "@rpath/$NAME.framework/$NAME" "$fw/$NAME"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$NAME</string>
	<key>CFBundleIdentifier</key>
	<string>com.cluborbit.matrix.native</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$3</string>
	</array>
	<key>MinimumOSVersion</key>
	<string>$MIN_IOS</string>
</dict>
</plist>
PLIST
}

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/device" "$WORK_DIR/simulator"

make_framework "$WORK_DIR/device" "target/aarch64-apple-ios/release/lib$NAME.dylib" iPhoneOS

# One simulator slice holding both Apple-silicon and Intel Macs.
lipo -create \
  "target/aarch64-apple-ios-sim/release/lib$NAME.dylib" \
  "target/x86_64-apple-ios/release/lib$NAME.dylib" \
  -output "$WORK_DIR/lib$NAME-sim.dylib"
make_framework "$WORK_DIR/simulator" "$WORK_DIR/lib$NAME-sim.dylib" iPhoneSimulator

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/$NAME.xcframework"
xcodebuild -create-xcframework \
  -framework "$WORK_DIR/device/$NAME.framework" \
  -framework "$WORK_DIR/simulator/$NAME.framework" \
  -output "$OUT_DIR/$NAME.xcframework"

echo "✓ $OUT_DIR/$NAME.xcframework"
