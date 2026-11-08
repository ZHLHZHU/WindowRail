#!/usr/bin/env python3
"""Validate bundled translations before compiling; uses macOS plutil only."""
import collections
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / 'Sources/WindowRail/Resources'
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|[hlLqztj])?([@diuoxXfFeEgGaAcCsSp])')


def placeholders(value):
    result = []
    offset = 0
    argument = 1
    while offset < len(value):
        if value[offset] != '%':
            offset += 1
            continue
        if value.startswith('%%', offset):
            offset += 2
            continue
        match = FORMAT.match(value, offset)
        if not match:
            raise ValueError('Invalid format placeholder: ' + value[offset:])
        result.append((int(match[1]) if match[1] else argument, (match[2] or '') + match[3]))
        if not match[1]:
            argument += 1
        offset = match.end()
    return sorted(result)


def validate(resource_root=RESOURCES, info_path=ROOT / 'Resources/Info.plist', key_path=ROOT / 'Sources/WindowRail/Services/L10n.swift'):
    tables = {}
    for path in sorted(resource_root.glob('*.lproj/Localizable.strings')):
        language = path.parent.stem
        source = path.read_text()
        keys = re.findall(r'^\s*"([^"\\]+)"\s*=', source, re.MULTILINE)
        duplicates = [key for key, count in collections.Counter(keys).items() if count > 1]
        if duplicates:
            raise ValueError(f'{language}: duplicate keys {duplicates}')
        parsed = subprocess.run(['/usr/bin/plutil', '-convert', 'json', '-o', '-', str(path)], capture_output=True, text=True)
        if parsed.returncode:
            raise ValueError(f'{language}: invalid strings file: {parsed.stderr.strip() or parsed.stdout.strip()}')
        tables[language] = json.loads(parsed.stdout)
        if set(keys) != set(tables[language]):
            raise ValueError(f'{language}: use one quoted localization key per line')
    if 'en' not in tables:
        raise ValueError('An English fallback table is required')
    baseline = tables['en']
    typed_keys = re.findall(r'^\s*case \w+ = "([^"]+)"', key_path.read_text(), re.MULTILINE)
    if len(set(typed_keys)) != len(typed_keys) or set(typed_keys) != set(baseline):
        raise ValueError('L10n.Key and English resource keys must match exactly')
    metadata = plistlib.loads(info_path.read_bytes())
    if set(metadata['CFBundleLocalizations']) != set(tables) or metadata['CFBundleDevelopmentRegion'] != 'en':
        raise ValueError('Info.plist localizations must match the bundled languages, with English as development language')
    for language, table in tables.items():
        if set(table) != set(baseline):
            raise ValueError(f'{language}: missing={sorted(set(baseline) - set(table))}, extra={sorted(set(table) - set(baseline))}')
        for key, value in table.items():
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f'{language}: empty or non-string translation for {key}')
            if placeholders(value) != placeholders(baseline[key]):
                raise ValueError(f'{language}: placeholder mismatch for {key}')
    print(f'PASS: {len(baseline)} typed localization keys across {len(tables)} languages; formats and metadata match')


if __name__ == '__main__':
    try:
        validate()
    except (ValueError, OSError, KeyError) as error:
        print(f'Localization validation failed: {error}', file=sys.stderr)
        sys.exit(1)
