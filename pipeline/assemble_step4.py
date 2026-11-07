"""Assemble locked Step 4a examples and Step 4b explanations into schema 1.1."""
import json
import sys
from pathlib import Path

QUALITY_RANK={'prueffliste':0,'roh':1,'geprueft':2,'freigegeben':3}
if len(sys.argv)!=5:
    raise SystemExit('usage: assemble_step4.py BASE.json EXAMPLES_4A.json EXPLANATIONS_4B.json OUTPUT.json')
basis=json.loads(Path(sys.argv[1]).read_text())
examples=json.loads(Path(sys.argv[2]).read_text())
explanations=json.loads(Path(sys.argv[3]).read_text())
examples_by_id={item['sense_id']:item for item in examples}
explanations_by_id={}
for item in explanations:
    explanations_by_id.setdefault(item['sense_id'],{})[item['erklaersprache']]=item
if len(examples_by_id)!=len(examples): raise SystemExit('4a contains duplicate sense_id')
output=[]
for entry in basis:
    statuses=[]
    for sense in entry['senses']:
        sense_id=sense['id']
        staged=examples_by_id.get(sense_id)
        langs=explanations_by_id.get(sense_id,{})
        if not staged: raise SystemExit(f'missing 4a examples for {sense_id}')
        if staged['lernsprache']!=entry['lemma']['sprache']: raise SystemExit(f'4a learning language mismatch: {sense_id}')
        if set(langs)!={'de','en'}: raise SystemExit(f'4b must include de and en for {sense_id}')
        sense['explanations']=[]
        for lang in ('de','en'):
            item=langs[lang]
            if item['stufe']!=entry['lemma']['niveau']: raise SystemExit(f'4b level mismatch: {sense_id}/{lang}')
            examples_out=[]
            for example in staged['beispiele']:
                same=entry['lemma']['sprache']==lang
                examples_out.append({'satz':example['satz'],'uebersetzung':None if same else example['uebersetzung_andere_sprache'],'quelle':example['quelle'],'quelle_id':example['quelle_id']})
            explanation={'erklaersprache':lang,'stufe':item['stufe'],'definition':item['definition'],'merkhilfe':item['merkhilfe'],'verwechslung':item['verwechslung'],'beispiele':examples_out,'qualitaet':item['qualitaet']}
            sense['explanations'].append(explanation)
            statuses.append(item['qualitaet']['status'])
    if statuses:
        entry['qualitaet']['status']=min(statuses,key=lambda value:QUALITY_RANK[value])
    output.append(entry)
Path(sys.argv[4]).write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n')
print(f'Assembled {len(output)} entries; 4a examples copied into each explanation.')
