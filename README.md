# XADMaster.xcframework Builder

A one‑click shell script to build a single distributable `XADMaster.xcframework` you can drop into any Xcode project.

Upstream projects:
- XADMaster: https://github.com/MacPaw/XADMaster
- UniversalDetector: https://github.com/MacPaw/universal-detector

Highlights:
- Defaults to macOS (arm64) and iOS (device + simulator).
- Optional macOS x86_64 and Mac Catalyst via flags.
- Generates a modulemap so Swift can `import XADMaster` (enabled by default).

## Requirements

- macOS with Xcode (Command Line Tools installed)
- git

## Quick Start

```bash
# Build with defaults (macOS arm64 + iOS device/simulator)
bash build_xadmaster_xcframework.sh

# Build with a specific revision
bash build_xadmaster_xcframework.sh v1.10.8

# Check the build location
ls -ld Build/XADMaster.xcframework
```

## Configuration (env vars)

- `CONFIGURATION`: Xcode configuration, default `Release`.
- `OUT_DIR`: output directory, default `./Build`.
- `INCLUDE_MACOS_X86_64`: add macOS x86_64 (lipo’d with arm64), default `0`.
- `INCLUDE_CATALYST`: add Mac Catalyst (arm64 + x86_64), default `0`.
- `GENERATE_MODULEMAP`: emit `module.modulemap` for Swift import, default `1`.
- `USE_XCPRETTY`: auto‑detected; set `0/1` to force off/on.
- Minimum platform versions (baked in; override if needed):
  - `MACOSX_DEPLOYMENT_TARGET=10.13`
  - `IPHONEOS_DEPLOYMENT_TARGET=12.0`
  - `IOS_SIMULATOR_DEPLOYMENT_TARGET=12.0`
  - `MAC_CATALYST_DEPLOYMENT_TARGET=13.0`

Examples:

```bash
# “Full‑platform” build (adds macOS x86_64 + Catalyst)
INCLUDE_MACOS_X86_64=1 INCLUDE_CATALYST=1 ./build_xadmaster_xcframework.sh

# Custom output dir and disable modulemap generation
OUT_DIR=./Artifacts GENERATE_MODULEMAP=0 ./build_xadmaster_xcframework.sh
```

## Output

- Artifact: `Build/XADMaster.xcframework`
- Default slices:
  - `macos-arm64`
  - `ios-arm64` (device)
  - `ios-arm64_x86_64-simulator` (simulator)
- Optional slices:
  - `macos-arm64_x86_64` (when `INCLUDE_MACOS_X86_64=1`)
  - `ios-arm64_x86_64-maccatalyst` (when `INCLUDE_CATALYST=1`)


## Integrate Into Your App/Framework

Mostly you only need to see [Releases](https://github.com/MrTreble/XADMaster/releases) for a pre-built version instead of build it by yourself.

And then, with the `XADMaster.xcframework.zip`, unzip it to get a `XADMaster.xcframework` folder.

1) Drag `XADMaster.xcframework` into your Xcode project (select the target).
2) Ensure Build Setting “Enable Modules (C and Objective‑C)” is `Yes`.
3) Swift: `import XADMaster`; Objective‑C: `#import <XADMaster/XAD.h>` and other headers.


