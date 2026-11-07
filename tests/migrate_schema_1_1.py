"""Migrate the initial manual test data from schema 1.0 to 1.1."""
import json
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit('usage: migrate_schema_1_1.py INPUT.json OUTPUT.json')
source = json.loads(Path(sys.argv[1]).read_text())
# Confirmed cross-language sense correspondences; all links are emitted symmetrically.
pairs = [
    ('de-bank-nomen-1', 'en-bank-nomen-1'),
    ('de-licht-nomen-1', 'en-light-nomen-1'),
    ('de-laufen-verb-1', 'en-run-verb-1'),
    ('de-nehmen-verb-1', 'en-take-verb-1'),
    ('de-schwer-adjektiv-2', 'en-hard-adjektiv-1'),
]
links = {}
for left, right in pairs:
    links.setdefault(left, []).append(right)
    links.setdefault(right, []).append(left)
for entry in source:
    for sense in entry['senses']:
        translation = sense['uebersetzung']
        old = translation.pop('verknuepfter_sense_id', None)
        ids = links.get(sense['id'], [old] if old else [])
        translation['verknuepfte_sense_ids'] = sorted(set(ids))
        sense['artikel'] = None
        sense['plural'] = None
        for explanation in sense['explanations']:
            explanation['qualitaet'] = json.loads(json.dumps(entry['qualitaet']))
    if entry['lemma']['id'] == 'de-bank-nomen':
        entry['lemma']['plural'] = None
        entry['senses'][0]['plural'] = 'Banken'
        entry['senses'][1]['plural'] = 'Bänke'
    entry['qualitaet']['modellversion'] = 'ChatGPT (manueller Test)'
Path(sys.argv[2]).write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n')
