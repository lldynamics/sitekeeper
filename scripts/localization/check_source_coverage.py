#!/usr/bin/env python3
"""Check literal localization requests against both app and widget resources."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re

QUOTED = r'"((?:[^"\\]|\\.)*)"'
ENTRY = re.compile(QUOTED + r'\s*=\s*' + QUOTED + r'\s*;', re.DOTALL)
REQUEST = re.compile(r'\bString\(\s*localized:\s*' + QUOTED)
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+#0 ]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|h|l|q|z|t|j)?([@diuoxXfFeEgGaAcCsSp])')


def decode_literal(value):
    def decode(match):
        escape = match.group(1)
        if escape.startswith('u{'):
            return chr(int(escape[2:-1], 16))
        if escape.startswith('U') and len(escape) == 5:
            return chr(int(escape[1:], 16))
        return {'n': '\n', 'r': '\r', 't': '\t', '"': '"', '\\': '\\', '0': '\0'}.get(escape, '\\' + escape)
    return re.sub(r'\\(u\{[0-9a-fA-F]+\}|U[0-9a-fA-F]{4}|.)', decode, value)


def without_comments(source):
    # Keep strings and line positions intact; Swift block comments may nest.
    result = list(source)
    index = 0
    while index < len(source):
        if source[index] == '"':
            index += 1
            while index < len(source):
                if source[index] == '\\':
                    index += 2
                elif source[index] == '"':
                    index += 1
                    break
                else:
                    index += 1
        elif source.startswith('//', index):
            end = source.find('\n', index)
            end = len(source) if end < 0 else end
            result[index:end] = ' ' * (end - index)
            index = end
        elif source.startswith('/*', index):
            depth = 1
            end = index + 2
            while end < len(source) and depth:
                if source.startswith('/*', end):
                    depth += 1
                    end += 2
                elif source.startswith('*/', end):
                    depth -= 1
                    end += 2
                else:
                    end += 1
            result[index:end] = ['\n' if c == '\n' else ' ' for c in source[index:end]]
            index = end
        else:
            index += 1
    return ''.join(result)


def requested_keys(source):
    clean = without_comments(source)
    for match in REQUEST.finditer(clean):
        raw = match.group(1)
        if '\\(' not in raw:  # Interpolated keys use a different extraction contract.
            yield decode_literal(raw), source.count('\n', 0, match.start()) + 1


def resource_values(source):
    values = {}
    for match in ENTRY.finditer(without_comments(source)):
        key, value = map(decode_literal, match.groups())
        if key in values:
            raise ValueError('duplicate localized key: ' + key)
        values[key] = value
    return values


def placeholders(value):
    arguments = Counter()
    next_argument = 1
    for match in FORMAT.finditer(value.replace('%%', '')):
        position, length, kind = match.groups()
        for _ in range(match.group(0).count('*')):
            arguments[(next_argument, 'd')] += 1
            next_argument += 1
        argument = int(position) if position else next_argument
        arguments[(argument, (length or '') + kind)] += 1
        if not position:
            next_argument += 1
    return arguments


def inspect(root):
    issues, missing = [], {}
    for scope, resources in [('Sources', 'Sources/Resources'), ('Widget', 'Widget')]:
        tables = {}
        for language in ('zh-Hans', 'en'):
            path = root / resources / (language + '.lproj') / 'Localizable.strings'
            tables[language] = resource_values(path.read_text(encoding='utf-8'))
        for path in sorted((root / scope).rglob('*.swift')):
            for key, line in requested_keys(path.read_text(encoding='utf-8')):
                absent = [language for language, values in tables.items() if key not in values]
                if absent:
                    location = str(path.relative_to(root)) + ':' + str(line)
                    issues.append(f'{location}: missing {",".join(absent)} key {key!r}')
                    missing.setdefault(scope, {}).setdefault(key, []).append(location)
        for key in tables['zh-Hans'].keys() & tables['en'].keys():
            if placeholders(tables['zh-Hans'][key]) != placeholders(tables['en'][key]):
                issues.append(f'{resources}: format placeholders differ for {key!r}')
    return issues, missing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--dump-missing', type=Path)
    args = parser.parse_args()
    try:
        issues, missing = inspect(args.root)
    except (OSError, ValueError) as error:
        raise SystemExit('[localization-source] FAIL: ' + str(error))
    if args.dump_missing:
        args.dump_missing.write_text(json.dumps(missing, ensure_ascii=False, indent=2), encoding='utf-8')
    if issues:
        for issue in issues[:30]:
            print(issue)
        raise SystemExit(f'[localization-source] FAIL: {len(issues)} missing references or format mismatches')
    print('[localization-source] PASS: literal source keys and format placeholders are covered')


if __name__ == '__main__':
    main()
