#!/usr/bin/env bash
set -euo pipefail

# XADMaster xcframework builder
# - Default: build a single XADMaster.xcframework containing
#   macOS (arm64 only) + iOS (Device + Simulator)
# - Optional slices (disabled by default):
#   set INCLUDE_CATALYST=1 for Mac Catalyst, INCLUDE_MACOS_X86_64=1 for macOS x86_64
# - Requires Xcode Command Line Tools (xcodebuild)

ROOT_DIR=$(pwd)
# Optional revision from first CLI arg (tag or commit SHA)
REQUESTED_REV="${1:-}"
SRC_DIR="$ROOT_DIR"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/Build}"
CONFIG="${CONFIGURATION:-Release}"
REPO_XAD="https://github.com/MacPaw/XADMaster.git"
REPO_UDT="https://github.com/MacPaw/universal-detector.git"

echo "==> Output directory: $OUT_DIR (configuration: $CONFIG)"
mkdir -p "$OUT_DIR"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. Please install Xcode Command Line Tools." >&2
  exit 1
fi

cd "$SRC_DIR"

# Detect xcpretty
USE_XCPRETTY=0
if command -v xcpretty >/dev/null 2>&1; then
  USE_XCPRETTY=1
  echo "==> Using xcpretty for build logs."
else
  echo "==> xcpretty not found; showing raw xcodebuild output."
fi

run_xcodebuild() {
  if [ "$USE_XCPRETTY" = "1" ]; then
    xcodebuild "$@" | xcpretty
  else
    xcodebuild "$@"
  fi
}

# 1) Ensure source layout: XADMaster and UniversalDetector must be siblings
JUST_CLONED=0
if [ ! -d XADMaster ]; then
  echo "==> Cloning XADMaster..."
  git clone --depth=1 "$REPO_XAD" XADMaster
  JUST_CLONED=1
else
  echo "==> Found existing XADMaster sources; skipping update."
fi

if [ ! -d UniversalDetector ]; then
  echo "==> Cloning UniversalDetector..."
  git clone --depth=1 "$REPO_UDT" UniversalDetector
else
  echo "==> Found existing UniversalDetector sources; skipping update."
fi

PROJ="XADMaster/XADMaster.xcodeproj"
SCHEME_MAC_FRAMEWORK="XADMaster"
SCHEME_MAC_LIB="libXADMaster.a"
SCHEME_IOS_LIB="libXADMaster.ios.a"

DERIVED_MAC_ARM64="$OUT_DIR/DerivedData-macos-arm64"
DERIVED_MAC_X64="$OUT_DIR/DerivedData-macos-x86_64"

MAC_ARM64_LIB="$DERIVED_MAC_ARM64/Build/Products/$CONFIG/libXADMaster.a"
MAC_X64_LIB="$DERIVED_MAC_X64/Build/Products/$CONFIG/libXADMaster.a"
MAC_UNI_LIB_DIR="$OUT_DIR/Universal-macos-lib"
MAC_UNI_LIB="$MAC_UNI_LIB_DIR/libXADMaster.a"
MAC_FINAL_LIB=""

# If a revision is provided, try to checkout XADMaster to that revision
if [ -n "$REQUESTED_REV" ]; then
  if [ "$JUST_CLONED" = "1" ]; then
    echo "==> Resolving XADMaster revision: $REQUESTED_REV"
    # Try to fetch the specific tag/commit for newly cloned repo to ensure it exists locally
    git -C XADMaster fetch --tags --depth=1 origin "$REQUESTED_REV" >/dev/null 2>&1 || true
    if git -C XADMaster rev-parse --verify --quiet "$REQUESTED_REV^{commit}"; then
      git -C XADMaster checkout -q "$REQUESTED_REV"
      echo "==> Checked out XADMaster at: $REQUESTED_REV"
    else
      echo "error: revision '$REQUESTED_REV' not found in origin (after clone)." >&2
      exit 1
    fi
  else
    echo "==> Attempting checkout of XADMaster at: $REQUESTED_REV (no fetch)"
    if git -C XADMaster rev-parse --verify --quiet "$REQUESTED_REV^{commit}"; then
      git -C XADMaster checkout -q "$REQUESTED_REV"
      echo "==> Checked out XADMaster at: $REQUESTED_REV"
    else
      echo "error: revision '$REQUESTED_REV' not present in local XADMaster repository." >&2
      echo "hint: remove the 'XADMaster' directory to allow fresh clone, or fetch the revision manually." >&2
      exit 1
    fi
  fi
fi

echo "==> Cleaning previous build artifacts..."
rm -rf "$OUT_DIR/XADMaster.xcframework" "$DERIVED_MAC_ARM64" "$DERIVED_MAC_X64" "$MAC_UNI_LIB_DIR"

# Prepare a shared headers directory for all slices
HEADERS_DIR="$OUT_DIR/Headers-XADMaster"
rm -rf "$HEADERS_DIR" && mkdir -p "$HEADERS_DIR"
rsync -a --include='*/' --include='*.h' --exclude='*' XADMaster/ "$HEADERS_DIR/"
# Include UniversalDetector headers as well, to satisfy public headers dependency
rsync -a --include='*.h' --exclude='*' UniversalDetector/ "$HEADERS_DIR/" || true

# Optionally generate a modulemap so Swift can `import XADMaster`
if [[ "${GENERATE_MODULEMAP:-1}" == "1" ]]; then
  cat >"$HEADERS_DIR/module.modulemap" <<'MM'
module XADMaster {
  umbrella "."
  export *
  module * { export * }
}
MM
fi

# 2) Build macOS static library - arm64
echo "==> Building macOS static library (arm64)..."
run_xcodebuild \
  -project "$PROJ" \
  -scheme "$SCHEME_MAC_LIB" \
  -configuration "$CONFIG" \
  -sdk macosx \
  -derivedDataPath "$DERIVED_MAC_ARM64" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  MACOSX_DEPLOYMENT_TARGET=10.13 \
  build
[ -f "$MAC_ARM64_LIB" ] || { echo "error: macOS arm64 static library not found: $MAC_ARM64_LIB" >&2; exit 1; }

# 3) Optionally build macOS static library - x86_64, then merge with arm64
if [[ "${INCLUDE_MACOS_X86_64:-0}" == "1" ]]; then
  echo "==> Building macOS static library (x86_64)..."
  run_xcodebuild \
    -project "$PROJ" \
    -scheme "$SCHEME_MAC_LIB" \
    -configuration "$CONFIG" \
    -sdk macosx \
    -derivedDataPath "$DERIVED_MAC_X64" \
    ARCHS=x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    MACOSX_DEPLOYMENT_TARGET=10.13 \
    build
  [ -f "$MAC_X64_LIB" ] || { echo "error: macOS x86_64 static library not found: $MAC_X64_LIB" >&2; exit 1; }

  echo "==> Merging macOS static libraries into a universal binary..."
  mkdir -p "$MAC_UNI_LIB_DIR"
  "/usr/bin/lipo" -create "$MAC_ARM64_LIB" "$MAC_X64_LIB" -output "$MAC_UNI_LIB"
  MAC_FINAL_LIB="$MAC_UNI_LIB"
else
  MAC_FINAL_LIB="$MAC_ARM64_LIB"
fi

# 4) Compose base xcframework (macOS static lib: arm64 by default, universal if enabled)
CMD_CREATE=( xcodebuild -create-xcframework -library "$MAC_FINAL_LIB" -headers "$OUT_DIR/Headers-XADMaster" )

# 6) iOS static libraries (device + simulator), then add -library entries
if [[ "${INCLUDE_IOS:-1}" == "1" ]]; then
  echo "==> Building iOS static libraries (libXADMaster.ios.a)..."
  DERIVED_IOS_DEV="$OUT_DIR/DerivedData-ios-device"
  DERIVED_IOS_SIM_ARM64="$OUT_DIR/DerivedData-ios-sim-arm64"
  DERIVED_IOS_SIM_X64="$OUT_DIR/DerivedData-ios-sim-x86_64"
  rm -rf "$DERIVED_IOS_DEV" "$DERIVED_IOS_SIM_ARM64" "$DERIVED_IOS_SIM_X64"

  # iOS (arm64) - device
  run_xcodebuild \
    -project "$PROJ" \
    -scheme "$SCHEME_IOS_LIB" \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED_IOS_DEV" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    IPHONEOS_DEPLOYMENT_TARGET=12.0 \
    build

  IOS_DEV_LIB="$DERIVED_IOS_DEV/Build/Products/${CONFIG}-iphoneos/libXADMaster.ios.a"
  [[ -f "$IOS_DEV_LIB" ]] || { echo "error: iOS device static library not found: $IOS_DEV_LIB" >&2; exit 1; }

  # iOS Simulator (arm64)
  run_xcodebuild \
    -project "$PROJ" \
    -scheme "$SCHEME_IOS_LIB" \
    -configuration "$CONFIG" \
    -sdk iphonesimulator \
    -derivedDataPath "$DERIVED_IOS_SIM_ARM64" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    IPHONEOS_DEPLOYMENT_TARGET=12.0 \
    build

  IOS_SIM_ARM64_LIB="$DERIVED_IOS_SIM_ARM64/Build/Products/${CONFIG}-iphonesimulator/libXADMaster.ios.a"
  [[ -f "$IOS_SIM_ARM64_LIB" ]] || { echo "error: iOS simulator arm64 static library not found: $IOS_SIM_ARM64_LIB" >&2; exit 1; }

  # iOS Simulator (x86_64) - optional, some hosts may miss cross toolchains; failure is non-fatal
  IOS_SIM_X64_LIB=""
  if xcodebuild -version >/dev/null 2>&1; then
    set +e
    run_xcodebuild \
      -project "$PROJ" \
      -scheme "$SCHEME_IOS_LIB" \
      -configuration "$CONFIG" \
      -sdk iphonesimulator \
      -derivedDataPath "$DERIVED_IOS_SIM_X64" \
      ARCHS=x86_64 \
      ONLY_ACTIVE_ARCH=NO \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      IPHONEOS_DEPLOYMENT_TARGET=12.0 \
      build
    if [ -f "$DERIVED_IOS_SIM_X64/Build/Products/${CONFIG}-iphonesimulator/libXADMaster.ios.a" ]; then
      IOS_SIM_X64_LIB="$DERIVED_IOS_SIM_X64/Build/Products/${CONFIG}-iphonesimulator/libXADMaster.ios.a"
    else
      echo "warn: iOS simulator x86_64 static library missing; continuing..."
    fi
    set -e
  fi

  # Reuse the shared headers directory (for iOS/Catalyst static libs)
  echo "==> Using shared headers directory: $HEADERS_DIR"

  # Lipo iOS simulator arm64 + x86_64 into one fat library to avoid 'equivalent library definitions'
  IOS_SIM_UNI_DIR="$OUT_DIR/Universal-ios-simulator"
  IOS_SIM_UNI_LIB="$IOS_SIM_UNI_DIR/libXADMaster.ios.a"
  rm -rf "$IOS_SIM_UNI_DIR" && mkdir -p "$IOS_SIM_UNI_DIR"
  if [[ -n "${IOS_SIM_X64_LIB}" ]]; then
    /usr/bin/lipo -create "$IOS_SIM_ARM64_LIB" "$IOS_SIM_X64_LIB" -output "$IOS_SIM_UNI_LIB"
  else
    cp "$IOS_SIM_ARM64_LIB" "$IOS_SIM_UNI_LIB"
  fi

  # Add iOS device + simulator fat library to create-xcframework command
  CMD_CREATE+=( -library "$IOS_DEV_LIB" -headers "$HEADERS_DIR" )
  CMD_CREATE+=( -library "$IOS_SIM_UNI_LIB" -headers "$HEADERS_DIR" )

  # Optionally build and include Mac Catalyst (disabled by default)
  if [[ "${INCLUDE_CATALYST:-0}" == "1" ]]; then
    echo "==> Building Mac Catalyst static library..."
    DERIVED_CAT="$OUT_DIR/DerivedData-maccatalyst"
    rm -rf "$DERIVED_CAT"
    run_xcodebuild \
      -project "$PROJ" \
      -scheme "$SCHEME_IOS_LIB" \
      -configuration "$CONFIG" \
      -destination 'generic/platform=macOS,variant=Mac Catalyst' \
      -derivedDataPath "$DERIVED_CAT" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      SUPPORTS_MACCATALYST=YES \
      IPHONEOS_DEPLOYMENT_TARGET=13.0 \
      build
    CAT_LIB="$DERIVED_CAT/Build/Products/Release-maccatalyst/libXADMaster.ios.a"
    if [[ -f "$CAT_LIB" ]]; then
      CMD_CREATE+=( -library "$CAT_LIB" -headers "$HEADERS_DIR" )
    else
      echo "warn: Mac Catalyst static library not found; skipping."
fi
  fi
fi

echo "==> Creating XADMaster.xcframework..."
"${CMD_CREATE[@]}" -output "$OUT_DIR/XADMaster.xcframework"

echo "Done: $OUT_DIR/XADMaster.xcframework"
