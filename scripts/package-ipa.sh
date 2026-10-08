#!/bin/zsh
set -euo pipefail
TASK_PROJECT_ROOT="${0:A:h:h}"
cd "$TASK_PROJECT_ROOT"
python3 scripts/generate-project.py
mkdir -p build/package artifacts
xcodebuild build \
  -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/ReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 \
  > build/package/release-build.log 2>&1
TASK_APP_PATH="$TASK_PROJECT_ROOT/build/ReleaseDerivedData/Build/Products/Release-iphoneos/ArcaeaOffline.app"
TASK_PACKAGE_DIR="$(mktemp -d "$TASK_PROJECT_ROOT/build/package/ipa.XXXXXX")"
trap 'rm -rf "$TASK_PACKAGE_DIR"' EXIT
mkdir -p "$TASK_PACKAGE_DIR/Payload"
ditto "$TASK_APP_PATH" "$TASK_PACKAGE_DIR/Payload/ArcaeaOffline.app"
cd "$TASK_PACKAGE_DIR"
zip -qry "$TASK_PACKAGE_DIR/ArcProbe-0.2.2.ipa" Payload
mv "$TASK_PACKAGE_DIR/ArcProbe-0.2.2.ipa" "$TASK_PROJECT_ROOT/artifacts/ArcProbe-0.2.2.ipa"
cd "$TASK_PROJECT_ROOT"
shasum -a 256 artifacts/ArcProbe-0.2.2.ipa > artifacts/ArcProbe-0.2.2.ipa.sha256
print 'Created artifacts/ArcProbe-0.2.2.ipa. This unsigned device build requires SideStore re-signing; it is not device verified.'
