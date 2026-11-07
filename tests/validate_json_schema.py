"""Validate a JSON object or each entry in a JSON array using Draft 2020-12."""
import json
import sys
from pathlib import Path
try:
    from jsonschema import Draft202012Validator, FormatChecker
except ImportError as exc:
    raise SystemExit('Install the standard validator first: python3 -m pip install -r requirements-dev.txt') from exc

if len(sys.argv) != 3:
    raise SystemExit('usage: validate_json_schema.py SCHEMA.json DATA.json')
schema = json.loads(Path(sys.argv[1]).read_text())
data = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
items = data if isinstance(data, list) else [data]
errors = []
for index, item in enumerate(items):
    errors.extend((index, error) for error in validator.iter_errors(item))
if errors:
    print('INVALID')
    for index, error in sorted(errors, key=lambda pair: (pair[0], list(pair[1].absolute_path))):
        path = '.'.join(map(str, error.absolute_path)) or '$'
        print(f'$[{index}].{path}: {error.message}')
    raise SystemExit(1)
print(f'VALID Draft 2020-12: {len(items)} entries')
