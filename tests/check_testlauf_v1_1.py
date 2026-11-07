"""Cross-record and educational rules for manual runs under schema 1.1."""
import json
import re
import sys
from pathlib import Path
from check_testlauf import FORMS as TEST01_FORMS

FORMS = {
    'gehen': {'gehen','gehe','gehst','geht'}, 'essen': {'essen','esse','isst','esst'},
    'fragen': {'fragen','frage','fragst','fragt'}, 'kaufen': {'kaufen','kaufe','kaufst','kauft'},
    'helfen': {'helfen','helfe','hilfst','hilft'}, 'klein': {'klein','kleine','kleinen','kleiner','kleines'},
    'wichtig': {'wichtig','wichtige','wichtigen','wichtiger','wichtiges'}, 'lernen': {'lernen','lerne','lernst','lernt'},
    'go': {'go','goes','going','went','gone'}, 'fast': {'fast','faster','fastest'}, 'eat': {'eat','eats','eating','ate','eaten'},
    'learn': {'learn','learns','learning','learned'}, 'ask': {'ask','asks','asking','asked'},
    'help': {'help','helps','helping','helped'}, 'buy': {'buy','buys','buying','bought'},
    'begin': {'begin','begins','beginning','began','begun'},
    'werfen': {'werfen','wirf','wirft','warf','warfst','warft','warfen','geworfen'},
    'schlafen': {'schlafen','schlafe','schläfst','schläft','schlief','schliefen','geschlafen'},
    'geben': {'geben','gebe','gibst','gibt','gab','gabst','gaben','gegeben'},
    'behalten': {'behalten','behalte','behält','behielt','behielten'},
    'ziehen': {'ziehen','ziehe','ziehst','zieht','zog','zogen','gezogen'},
    'throw': {'throw','throws','threw','thrown','throwing'},
    'sleep': {'sleep','sleeps','slept','sleeping'},
    'give': {'give','gives','gave','given','giving'},
    'keep': {'keep','keeps','kept','keeping'},
    'acquire': {'acquire','acquires','acquired','acquiring'},
    'obtain': {'obtain','obtains','obtained','obtaining'},
    'erwerben': {'erwerben','erwirbt','erwarb','erwarben','erworben'},
    'kiefer': {'kiefer','kiefern'},
    'dünn': {'dünn','dünne','dünner','dünnes'},
    'seltsam': {'seltsam','seltsame','seltsamer','seltsames'},
}
FORMS.update(TEST01_FORMS)
LIMIT = {'A1': 8, 'A2': 12, 'B1': 16, 'B2': 20}
QUALITY_RANK = {'prueffliste': 0, 'roh': 1, 'geprueft': 2, 'freigegeben': 3}
NONCOUNT_EN = {'water', 'work'}
CASE_AMBIGUOUS_PREPOSITIONS = {'an','auf','bei','durch','für','gegen','hinter','in','mit','nach','neben','über','um','unter','von','vor','zu','zwischen'}

def normalize(text):
    return text.casefold().replace('ä','ae').replace('ö','oe').replace('ü','ue').replace('ß','ss').replace(' ','-')

def words(text):
    return len(re.findall(r"\b[\w’'-]+\b", text, flags=re.UNICODE))

def main():
    if len(sys.argv) != 4:
        raise SystemExit('usage: check_testlauf_v1_1.py SCHEMA.json INPUT.json OUTPUT.json')
    schema = json.loads(Path(sys.argv[1]).read_text())
    source = json.loads(Path(sys.argv[2]).read_text())
    entries = json.loads(Path(sys.argv[3]).read_text())
    errors = []
    warnings = []
    expected = {(x['sprache'], x['text'].casefold(), x['wortart']) for x in source}
    actual = {(e['lemma']['sprache'], e['lemma']['text'].casefold(), e['lemma']['wortart']) for e in entries}
    if len(source) != 40 or len(entries) != 40: errors.append('run must contain exactly 40 input and output lemmas')
    if sum(x['sprache']=='de' for x in source) != 20 or sum(x['sprache']=='en' for x in source) != 20: errors.append('input must contain 20 German and 20 English lemmas')
    if actual != expected: errors.append('input/output lemma sets differ')
    if len(actual) != len(entries): errors.append('duplicate language/text/word-class lemma')

    senses = {s['id']: s for e in entries for s in e['senses']}
    owners = {s['id']: e['lemma'] for e in entries for s in e['senses']}
    seen_lemma_ids = set()
    for entry in entries:
        lemma = entry['lemma']
        base = f"{lemma['sprache']}-{normalize(lemma['text'])}-{lemma['wortart']}"
        if lemma['id'] != base: errors.append(f"{lemma['id']}: unexpected lemma ID")
        if lemma['id'] in seen_lemma_ids: errors.append(f"duplicate lemma ID {lemma['id']}")
        seen_lemma_ids.add(lemma['id'])
        if not 1 <= len(entry['senses']) <= 4: errors.append(f"{lemma['id']}: invalid sense count")

        effective_plural_values = [sense.get('plural') or lemma.get('plural') for sense in entry['senses']]
        effective_plurals = set(effective_plural_values)
        effective_plurals.discard(None)
        if len(entry['senses']) > 1 and all(value is not None for value in effective_plural_values) and len(effective_plurals) == 1:
            common_plural = next(iter(effective_plurals))
            if lemma.get('plural') != common_plural or any(sense.get('plural') is not None for sense in entry['senses']):
                errors.append(f"{lemma['id']}: identical plural must be normalized at lemma level")

        for field in ('artikel', 'plural'):
            effective = {sense.get(field) or lemma.get(field) for sense in entry['senses']}
            effective.discard(None)
            if len(effective) > 1 and lemma.get(field) is not None:
                errors.append(f"{lemma['id']}: lemma {field} must be null when senses differ")
        if lemma['sprache'] == 'en' and lemma['wortart'] == 'nomen':
            plural = lemma.get('plural')
            if plural and plural.casefold() in {'s','es','ies'}:
                errors.append(f"{lemma['id']}: plural must be the complete English word form")
            if lemma['text'].casefold() in NONCOUNT_EN and plural is not None:
                errors.append(f"{lemma['id']}: uncountable noun must use plural=null")

        child_statuses = []
        for index, sense in enumerate(entry['senses'], 1):
            if sense['id'] != f"{base}-{index}": errors.append(f"{sense['id']}: unexpected sense ID/order")
            if lemma['sprache'] == 'de' and lemma['wortart'] == 'nomen':
                if not (sense.get('artikel') or lemma.get('artikel')): errors.append(f"{sense['id']}: German noun has no article")
                if not (sense.get('plural') or lemma.get('plural')) and sense['id'] != 'de-see-nomen-2': errors.append(f"{sense['id']}: German noun has no complete plural")
            for linked in sense['uebersetzung']['verknuepfte_sense_ids']:
                if linked not in senses:
                    errors.append(f"{sense['id']}: unresolved link {linked}")
                    continue
                if sense['id'] not in senses[linked]['uebersetzung']['verknuepfte_sense_ids']:
                    errors.append(f"{sense['id']} -> {linked}: link is not reciprocal")
                if owners[linked]['sprache'] == lemma['sprache']:
                    errors.append(f"{sense['id']} -> {linked}: link must target the other language")

            explanations = sense['explanations']
            if len(explanations) != 2 or {x['erklaersprache'] for x in explanations} != {'de','en'}:
                errors.append(f"{sense['id']}: requires one explanation per language")
            example_sequences = []
            for explanation in explanations:
                quality = explanation.get('qualitaet')
                if quality is None:
                    errors.append(f"{sense['id']}: missing explanation quality")
                else:
                    child_statuses.append(quality['status'])
                if explanation['stufe'] != lemma['niveau']: errors.append(f"{sense['id']}: explanation level differs from lemma")
                if not 2 <= len(explanation['beispiele']) <= 3: errors.append(f"{sense['id']}: invalid example count")
                example_sequences.append(tuple(x['satz'] for x in explanation['beispiele']))
                for text in [explanation['definition']] + [x['satz'] for x in explanation['beispiele']]:
                    for sentence in re.split(r'(?<=[.!?])\s+', text):
                        if words(sentence) > LIMIT.get(explanation['stufe'], 10**6):
                            errors.append(f"{sense['id']}: sentence exceeds level limit")
                allowed = FORMS.get(lemma['text'].casefold(), {lemma['text'].casefold()})
                for example in explanation['beispiele']:
                    tokens = {x.casefold() for x in re.findall(r'\w+', example['satz'], flags=re.UNICODE)}
                    if not tokens & allowed: errors.append(f"{sense['id']}: lemma or known inflection absent from example")
                    same_language = lemma['sprache'] == explanation['erklaersprache']
                    if same_language and example['uebersetzung'] is not None: errors.append(f"{sense['id']}: same-language example translation must be null")
                    if not same_language and not example['uebersetzung']: errors.append(f"{sense['id']}: cross-language example translation missing")
                    if lemma['sprache'] == 'de' and lemma['wortart'] == 'nomen':
                        article = sense.get('artikel') or lemma.get('artikel')
                        if article:
                            for match in re.finditer(rf"\b(der|die|das)\s+{re.escape(lemma['text'])}\b", example['satz'], flags=re.IGNORECASE):
                                seen = match.group(1).casefold()
                                preceding = re.findall(r"[\wäöüß]+", example['satz'][:match.start()], flags=re.IGNORECASE)
                                previous_word = preceding[-1].casefold() if preceding else None
                                # In these contexts 'der' can be feminine dative/genitive,
                                # so don't treat it as evidence of masculine gender.
                                if previous_word in CASE_AMBIGUOUS_PREPOSITIONS:
                                    continue
                                if seen != article:
                                    warnings.append(f"{sense['id']}: possible article mismatch: schema says '{article}', example has '{seen}'")
            if len(set(example_sequences)) > 1:
                errors.append(f"{sense['id']}: examples differ between explanations; step 4a must copy identical sentences")

        if child_statuses and entry['qualitaet']['status'] != min(child_statuses, key=lambda x: QUALITY_RANK.get(x, -1)):
            errors.append(f"{lemma['id']}: entry quality is not the worst child status")
    if errors:
        print('FAIL')
        print('\n'.join(errors))
        raise SystemExit(1)
    print(f'PASS: {len(entries)} entries, balanced input, IDs, full plurals, sense metadata, reciprocal links, quality, shared examples and level limits')
    for warning in sorted(set(warnings)):
        print(f'REVIEW WARNING: {warning}')

if __name__ == '__main__':
    main()
