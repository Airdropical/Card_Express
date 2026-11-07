"""Validate a content array against ContentFile and its referenced LemmaEntry schema."""
import json
import sys
from pathlib import Path
try:
    from jsonschema import Draft202012Validator, FormatChecker
    from referencing import Registry, Resource
except ImportError as exc:
    raise SystemExit('Install the standard validator first: python3 -m pip install -r requirements-dev.txt') from exc

if len(sys.argv) != 4:
    raise SystemExit('usage: validate_content_file.py CONTENT_SCHEMA.json ENTRY_SCHEMA.json CONTENT.json')
content_schema = json.loads(Path(sys.argv[1]).read_text())
entry_schema = json.loads(Path(sys.argv[2]).read_text())
data = json.loads(Path(sys.argv[3]).read_text())
Draft202012Validator.check_schema(content_schema)
Draft202012Validator.check_schema(entry_schema)
registry = Registry().with_resource(entry_schema['$id'], Resource.from_contents(entry_schema))
validator = Draft202012Validator(content_schema, registry=registry, format_checker=FormatChecker())
errors = list(validator.iter_errors(data))
if errors:
    print('INVALID')
    for error in errors:
        path = '.'.join(map(str, error.absolute_path)) or '$'
        print(f'{path}: {error.message}')
    raise SystemExit(1)
print(f'VALID Draft 2020-12 content array: {len(data)} entries')
