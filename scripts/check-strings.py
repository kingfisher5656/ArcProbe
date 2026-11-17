#!/usr/bin/env python3
"""Keeps the string catalog whole and reports what is not translated.

- Adds the strings worded inside the Swift packages (every `localized("…")` call under Packages/), which the
  compiler does not report for the app, and removes the ones that are gone.
- Lists every key without a Korean translation. Exits with 1 when there is one.
"""
from pathlib import Path
import json, re, sys

root = Path(__file__).resolve().parents[1]
path = root / 'ArcaeaOffline/Resources/Localizable.xcstrings'
catalog = json.loads(path.read_text())
strings = catalog['strings']

# localized("…") is how the packages word things for people (see Packages/ArcaeaCore/…/Domain/Localized.swift).
package_keys = set()
for source in sorted((root / 'Packages').glob('*/Sources/**/*.swift')):
    for literal in re.findall(r'localized\(("(?:[^"\\]|\\.)*")\)', source.read_text()):
        package_keys.add(json.loads(literal))
for key in list(strings):
    if strings[key].get('extractionState') == 'manual' and key not in package_keys: del strings[key]
for key in package_keys:
    strings.setdefault(key, {})['extractionState'] = 'manual'  # the sync step leaves manual keys alone

# A key the code no longer uses is marked stale by the sync step; drop it so the catalog does not collect leftovers.
for key in [k for k, v in strings.items() if v.get('extractionState') == 'stale']:
    del strings[key]

def translated(entry):
    ko = entry.get('localizations', {}).get('ko')
    if not ko: return False
    if 'stringUnit' in ko: return ko['stringUnit'].get('state') == 'translated'
    return 'variations' in ko

missing = sorted(k for k, v in strings.items() if not translated(v) and v.get('shouldTranslate', True))
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
print(f'{len(strings)} strings, {len(missing)} without Korean')
for key in missing: print('  ' + json.dumps(key, ensure_ascii=False))
sys.exit(1 if missing else 0)
