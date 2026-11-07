"""Check cross-entry and project-specific rules for a test run."""
import json
import re
import sys
from pathlib import Path

FORMS = {
    'bank': {'bank', 'banks'}, 'schloss': {'schloss', 'schlösser'},
    'lampe': {'lampe', 'lampen'}, 'freund': {'freund', 'freunde'},
    'licht': {'licht', 'lichter'}, 'weg': {'weg', 'wege'},
    'ball': {'ball', 'bälle'}, 'blatt': {'blatt', 'blätter'},
    'zug': {'zug', 'züge'}, 'bahn': {'bahn', 'bahnen'},
    'laufen': {'laufen', 'laufe', 'läufst', 'läuft', 'lauft'},
    'fahren': {'fahren', 'fahre', 'fährst', 'fährt', 'fahrt'},
    'spielen': {'spielen', 'spiele', 'spielst', 'spielt'},
    'finden': {'finden', 'finde', 'findest', 'findet'},
    'nehmen': {'nehmen', 'nehme', 'nimmst', 'nimmt', 'nehmt', 'nimm'},
    'klar': {'klar', 'klare', 'klaren', 'klarem', 'klarer'},
    'frei': {'frei', 'freie', 'freien', 'freiem', 'freier'},
    'schwer': {'schwer', 'schwere', 'schweren', 'schwerem', 'schwerer'},
    'spät': {'spät', 'späte', 'späten', 'spätem', 'später'},
    'werden': {'werden', 'werde', 'wirst', 'wird', 'werdet'},
    'spring': {'spring', 'springs', 'springing', 'sprang'}, 'bat': {'bat', 'bats'},
    'light': {'light', 'lights'}, 'right': {'right', 'righter', 'rightest'},
    'kind': {'kind', 'kinder', 'kindest'}, 'run': {'run', 'runs', 'running', 'ran'},
    'get': {'get', 'gets', 'getting', 'got', 'gotten'},
    'take': {'take', 'takes', 'taking', 'took', 'taken'},
    'set': {'set', 'sets', 'setting'}, 'watch': {'watch', 'watches', 'watching', 'watched'},
    'book': {'book', 'books'}, 'close': {'close', 'closer', 'closest'},
    'mean': {'mean', 'means', 'meaning', 'meant'}, 'fast': {'fast', 'faster', 'fastest'},
    'hard': {'hard', 'harder', 'hardest'}, 'fair': {'fair', 'fairer', 'fairest'},
    'point': {'point', 'points'}, 'break': {'break', 'breaks', 'breaking', 'broke', 'broken'},
    'charge': {'charge', 'charges', 'charging', 'charged'},
}
LEVEL_LIMIT = {'A1': 8, 'A2': 12, 'B1': 16, 'B2': 20}


def normalize(text):
    return (text.casefold().replace('ä', 'ae').replace('ö', 'oe')
            .replace('ü', 'ue').replace('ß', 'ss').replace(' ', '-'))


def word_count(text):
    return len(re.findall(r"\b[\w’'-]+\b", text, flags=re.UNICODE))


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: check_testlauf.py INPUT.json OUTPUT.json')
    source = json.loads(Path(sys.argv[1]).read_text())
    entries = json.loads(Path(sys.argv[2]).read_text())
    errors = []
    input_keys = {(x['sprache'], x['text'].casefold(), x['wortart']) for x in source}
    output_keys = {(x['lemma']['sprache'], x['lemma']['text'].casefold(), x['lemma']['wortart']) for x in entries}
    if input_keys != output_keys: errors.append('input/output lemma sets differ')
    if len(entries) != len(source): errors.append('entry count differs from input')
    lemma_ids = [x['lemma']['id'] for x in entries]
    if len(set(lemma_ids)) != len(lemma_ids): errors.append('duplicate lemma ID')
    sense_ids = {s['id'] for e in entries for s in e['senses']}
    for entry in entries:
        lemma = entry['lemma']
        base = f"{lemma['sprache']}-{normalize(lemma['text'])}-{lemma['wortart']}"
        if lemma['id'] != base: errors.append(f"{lemma['id']}: lemma ID does not match convention")
        if not re.fullmatch(r'[a-z0-9-]+', lemma['id']): errors.append(f"{lemma['id']}: ID is not ASCII-safe")
        if lemma['sprache'] == 'de' and lemma['wortart'] == 'nomen':
            if not lemma.get('artikel'): errors.append(f"{lemma['id']}: missing German article")
            if not lemma.get('plural'): errors.append(f"{lemma['id']}: missing German plural")
        if not 1 <= len(entry['senses']) <= 4: errors.append(f"{lemma['id']}: sense count")
        for index, sense in enumerate(entry['senses'], 1):
            if sense['id'] != f'{base}-{index}': errors.append(f"{sense['id']}: sense ID/order")
            linked = sense['uebersetzung'].get('verknuepfter_sense_id')
            if linked is not None and linked not in sense_ids: errors.append(f"{sense['id']}: unresolved linked sense")
            expected_target = 'en' if lemma['sprache'] == 'de' else 'de'
            if sense['uebersetzung']['sprache'] != expected_target: errors.append(f"{sense['id']}: translation language")
            if len(sense['uebersetzung'].get('alternativen', [])) > 3: errors.append(f"{sense['id']}: too many translation alternatives")
            explanations = sense['explanations']
            if len(explanations) != 2 or {x['erklaersprache'] for x in explanations} != {'de', 'en'}:
                errors.append(f"{sense['id']}: requires one explanation per language")
            for explanation in explanations:
                if explanation['stufe'] != lemma['niveau']: errors.append(f"{sense['id']}: explanation level")
                if not 2 <= len(explanation['beispiele']) <= 3: errors.append(f"{sense['id']}: example count")
                limit = LEVEL_LIMIT.get(explanation['stufe'])
                texts = [explanation['definition']] + [b['satz'] for b in explanation['beispiele']]
                if limit:
                    for text in texts:
                        for sentence in re.split(r'(?<=[.!?])\s+', text):
                            if word_count(sentence) > limit:
                                errors.append(f"{sense['id']}: sentence exceeds {limit} words")
                allowed = FORMS.get(lemma['text'].casefold(), {lemma['text'].casefold()})
                for example in explanation['beispiele']:
                    tokens = {t.casefold() for t in re.findall(r'\w+', example['satz'], flags=re.UNICODE)}
                    if not tokens & allowed: errors.append(f"{sense['id']}: lemma form missing from example")
                    same_language = lemma['sprache'] == explanation['erklaersprache']
                    if same_language and example['uebersetzung'] is not None:
                        errors.append(f"{sense['id']}: same-language example must have null translation")
                    if not same_language and not example['uebersetzung']:
                        errors.append(f"{sense['id']}: cross-language example needs translation")
    if errors:
        print('FAIL')
        print('\n'.join(errors))
        raise SystemExit(1)
    print(f'PASS: {len(entries)} entries, input coverage, IDs, senses, explanations, examples and level limits')


if __name__ == '__main__':
    main()
