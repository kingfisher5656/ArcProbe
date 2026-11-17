#!/bin/zsh
# Brings ArcaeaOffline/Resources/Localizable.xcstrings up to date with the code, then lists what still
# needs a Korean translation.
#
#   zsh scripts/sync-strings.sh             build for the simulator, then sync
#   zsh scripts/sync-strings.sh --no-build  sync from the last build in build/DerivedData
#
# The compiler writes every localisable string it sees to .stringsdata files; `xcstringstool sync` adds new
# keys to the catalog and drops the ones that are gone. Strings worded in the Swift packages are not seen by
# that step: scripts/check-strings.py collects them from the packages' localized("…") calls.
set -e
cd "$(dirname "$0")/.."
catalog=ArcaeaOffline/Resources/Localizable.xcstrings
derived=${DERIVED_DATA:-build/DerivedData}
if [[ "$1" != "--no-build" ]]; then
  xcodebuild build -project ArcaeaOffline.xcodeproj -scheme ArcaeaOffline \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived" ${=XCODEBUILD_EXTRA} 2>&1 | grep -E "error:|BUILD" | sort -u
fi
data=("$derived"/Build/Intermediates.noindex/ArcaeaOffline.build/*-iphonesimulator/ArcaeaOffline.build/Objects-normal/*/*.stringsdata(N))
[[ ${#data} -gt 0 ]] || { echo "No .stringsdata found under $derived. Build first."; exit 1 }
args=(); for file in $data; do args+=(--stringsdata "$file"); done
xcrun xcstringstool sync "$catalog" $args
python3 scripts/check-strings.py
