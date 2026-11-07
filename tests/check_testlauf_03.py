"""Coverage checks specific to Testlauf 03."""
import json
from pathlib import Path

inputs=json.loads(Path('tests/testlauf-03-eingabe.json').read_text())
entries=json.loads(Path('tests/testlauf-03-ergebnisse.json').read_text())
previous=[]
for path in ('data/testlauf/testlauf-01-ergebnisse.json','data/testlauf/testlauf-02-ergebnisse.json'):
    previous.extend(json.loads(Path(path).read_text()))
key=lambda e:(e['lemma']['sprache'],e['lemma']['text'].casefold(),e['lemma']['wortart'])
used={key(e) for e in previous}
new={key(e) for e in entries}
errors=[]
if new & used: errors.append('Testlauf 03 repeats lemmas from Testlauf 01 or 02')
if len([e for e in entries if len(e['senses'])>1])<10: errors.append('fewer than 10 ambiguous lemmas')
if not any(e['lemma']['niveau'] in ('B1','B2','C1','C2') for e in entries): errors.append('no B1+ content')
for lang in ('de','en'):
    if not any(e['lemma']['sprache']==lang and e['lemma']['wortart']=='adverb' for e in entries): errors.append(f'missing {lang} adverb')
    if not any(e['lemma']['sprache']==lang and e['lemma']['wortart']=='praeposition' for e in entries): errors.append(f'missing {lang} preposition')
by_id={s['id']:s for e in entries for s in e['senses']}
erwerben=by_id.get('de-erwerben-verb-1')
expected={'en-acquire-verb-1','en-obtain-verb-1'}
if not erwerben or set(erwerben['uebersetzung']['verknuepfte_sense_ids'])!=expected: errors.append('the planned 1:n erwerben → acquire/obtain mapping is missing')
for target in expected:
    if target not in by_id or 'de-erwerben-verb-1' not in by_id[target]['uebersetzung']['verknuepfte_sense_ids']:
        errors.append(f'1:n reverse link missing for {target}')

by_lemma={e['lemma']['id']:e for e in entries}
kiefer=by_lemma.get('de-kiefer-nomen')
if not kiefer or kiefer['senses'][0].get('artikel')!='der': errors.append('jaw sense must use der Kiefer')
see=by_lemma.get('de-see-nomen')
if not see or see['senses'][1].get('plural') is not None: errors.append('die See (sea) must have plural=null')
band=by_lemma.get('en-band-nomen')
if not band or band['senses'][1]['uebersetzung']['text']!='Streifen' or 'Band' not in band['senses'][1]['uebersetzung']['alternativen']:
    errors.append('band (strip) translation must separate Streifen and Band into text/alternatives')
for lemma_id in ('de-band-nomen','de-leiter-nomen','de-see-nomen','de-kiefer-nomen','de-mutter-nomen','de-ziehen-verb','en-bark-nomen','en-crane-nomen','en-match-nomen','en-seal-nomen','en-band-nomen'):
    entry=by_lemma.get(lemma_id)
    if not entry or any(not ex.get('merkhilfe') for sense in entry['senses'] for ex in sense['explanations']):
        errors.append(f'{lemma_id}: ambiguous senses need a useful mnemonic in both explanation languages')
for lemma_id,plural in [('en-bark-nomen','barks'),('en-crane-nomen','cranes'),('en-match-nomen','matches'),('en-seal-nomen','seals'),('en-band-nomen','bands')]:
    entry=by_lemma.get(lemma_id)
    if not entry or entry['lemma'].get('plural')!=plural or any(sense.get('plural') is not None for sense in entry['senses']):
        errors.append(f'{lemma_id}: shared English plural must be stored once on the lemma')
obtain=by_lemma.get('en-obtain-verb')
acquire=by_lemma.get('en-acquire-verb')
if not obtain or obtain['senses'][0]['uebersetzung']['text']!='erhalten': errors.append('obtain translation must match its example translations')
for entry in (obtain, acquire):
    if entry and set(entry['senses'][0]['uebersetzung'].get('alternativen',[])) & {'get','obtain','acquire'}:
        errors.append(f"{entry['lemma']['text']}: English alternatives must not be placed in German translation alternatives")
for lemma_id in ('de-gegen-praeposition','en-against-praeposition'):
    entry=by_lemma.get(lemma_id)
    if not entry or len(entry['senses'])!=2: errors.append(f'{lemma_id}: contact and opposition meanings must be separate')
if len(entries)!=40 or len(inputs)!=40: errors.append('run must have exactly 40 lemmas')
if errors:
    print('FAIL'); print('\n'.join(errors)); raise SystemExit(1)
print(f'PASS Testlauf 03 coverage: {len(entries)} new lemmas, {sum(len(e["senses"])>1 for e in entries)} ambiguous lemmas, 1:n links, B1+, adverbs and prepositions')
