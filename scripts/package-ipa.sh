#!/bin/zsh
# Builds an unsigned release IPA for SideStore: artifacts/ArcProbe-<version>.ipa
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
python3 scripts/generate-project.py
VERSION="$(python3 -c "import re,pathlib;print(re.search(r\"MARKETING_VERSION = '([^']+)'\", pathlib.Path('scripts/generate-project.py').read_text()).group(1))")"
mkdir -p build/package artifacts
xcodebuild build \
  -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/ReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 \
  > build/package/release-build.log 2>&1 || { tail -40 build/package/release-build.log; exit 1; }
STAGE="$(mktemp -d "$ROOT/build/package/ipa.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
ditto "$ROOT/build/ReleaseDerivedData/Build/Products/Release-iphoneos/ArcaeaOffline.app" "$STAGE/Payload/ArcaeaOffline.app"
(cd "$STAGE" && zip -qry "ArcProbe-$VERSION.ipa" Payload)
mv "$STAGE/ArcProbe-$VERSION.ipa" "artifacts/ArcProbe-$VERSION.ipa"
shasum -a 256 "artifacts/ArcProbe-$VERSION.ipa" > "artifacts/ArcProbe-$VERSION.ipa.sha256"
print "Created artifacts/ArcProbe-$VERSION.ipa (unsigned; install through SideStore)."
