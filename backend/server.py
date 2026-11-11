#!/usr/bin/env python3
"""Private-pilot Gemini API with invite-only authentication and hard usage limits."""
import base64, hashlib, hmac, json, os, re, secrets, sqlite3, threading, time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from ai_prompts.planning import build_agent_plan_prompt

ROOT = os.path.dirname(os.path.abspath(__file__))
def load_dotenv():
    path = os.path.join(ROOT, '.env')
    if os.path.exists(path):
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1); os.environ.setdefault(key.strip(), value.strip().strip('"\''))
load_dotenv()
os.umask(0o077)
APP_ENV = os.environ.get('APP_ENV', 'development').strip().lower()
LOCAL_AUTH_DISABLED = APP_ENV == 'development' and os.environ.get('LOCAL_AUTH_DISABLED', '1') == '1'
DATA_DIR = os.environ.get('DATA_DIR', os.path.join(ROOT, 'data'))
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.environ.get('DATABASE_PATH', os.path.join(DATA_DIR, 'pilot.sqlite3'))
MAX_BODY = 8 * 1024 * 1024
MODEL = os.environ.get('GEMINI_MODEL', 'gemini-3.5-flash-lite')
FALLBACK_MODEL = os.environ.get('GEMINI_FALLBACK_MODEL', 'gemini-3.1-flash-lite')
PILOT_DAILY_LIMIT = int(os.environ.get('PILOT_DAILY_REQUEST_LIMIT', '40'))
PILOT_TOTAL_LIMIT = int(os.environ.get('PILOT_TOTAL_REQUEST_LIMIT', '400'))
PILOT_BUDGET_USD = float(os.environ.get('PILOT_BUDGET_USD', '5'))
RATE_PER_MINUTE = int(os.environ.get('RATE_LIMIT_PER_MINUTE', '8'))
TOKEN_TTL = int(os.environ.get('SESSION_TTL_SECONDS', str(14 * 86400)))
DB_LOCK = threading.Lock()

def db():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    try: os.chmod(DB_PATH, 0o600)
    except OSError: pass
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('''CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, expires INTEGER NOT NULL)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS attempts(ip TEXT, stamp INTEGER)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS traffic(ip TEXT, stamp INTEGER)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS usage(id INTEGER PRIMARY KEY, stamp INTEGER, input_tokens INTEGER, output_tokens INTEGER, cost REAL)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''')
    return conn

def password_ok(candidate):
    # Store scrypt hash as salt_hex:hash_hex. Plaintext env is supported for simple one-user setup.
    configured = os.environ.get('PILOT_PASSWORD_HASH', '')
    if configured:
        try:
            salt_hex, expected = configured.split(':', 1)
            derived = hashlib.scrypt(candidate.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1).hex()
            return hmac.compare_digest(derived.encode('ascii'), expected.encode('ascii'))
        except Exception:
            return False
    return bool(os.environ.get('PILOT_PASSWORD')) and hmac.compare_digest(candidate.encode('utf-8'), os.environ['PILOT_PASSWORD'].encode('utf-8'))

def error(status, message):
    exc = RuntimeError(message); exc.status = status; return exc

def estimate_cost(model, inp, out):
    # USD per million tokens; conservative published standard-tier rates for the configured models.
    rates = {'gemini-3.5-flash-lite': (.30, 2.50), 'gemini-3.1-flash-lite': (.25, 1.50)}
    ir, orate = rates.get(model, (.50, 3.00))
    return inp * ir / 1_000_000 + out * orate / 1_000_000

def reserve_usage():
    with DB_LOCK, db() as conn:
        now = int(time.time()); day = now - 86400
        count_day = conn.execute('SELECT count(*) FROM usage WHERE stamp>=?', (day,)).fetchone()[0]
        count_minute = conn.execute('SELECT count(*) FROM usage WHERE stamp>=?', (now-60,)).fetchone()[0]
        count_total = conn.execute('SELECT count(*) FROM usage').fetchone()[0]
        spent = conn.execute('SELECT coalesce(sum(cost),0) FROM usage').fetchone()[0]
        # Reserve a deliberately high 100k input / 2k output token ceiling per call.
        reserve = max(estimate_cost(MODEL, 100000, 2048), estimate_cost(FALLBACK_MODEL, 100000, 2048))
        configured_end = int(os.environ.get('PILOT_END_UNIX', '0') or 0)
        if configured_end:
            pilot_end = configured_end
        else:
            row = conn.execute('SELECT value FROM settings WHERE key=?', ('pilot_start',)).fetchone()
            if row is None:
                conn.execute('INSERT INTO settings VALUES(?,?)', ('pilot_start', str(now)))
                pilot_end = now + 14 * 86400
            else:
                pilot_end = int(row[0]) + 14 * 86400
        if now > pilot_end: raise error(403, 'Der 14-Tage-Privatpilot ist abgelaufen.')
        if count_minute >= RATE_PER_MINUTE: raise error(429, 'Zu viele KI-Anfragen. Bitte kurz warten.')
        if count_day >= PILOT_DAILY_LIMIT or count_total >= PILOT_TOTAL_LIMIT: raise error(429, 'Das KI-Kontingent des Privatpiloten ist ausgeschöpft.')
        if spent + reserve > PILOT_BUDGET_USD: raise error(429, 'Das Kostenlimit des Privatpiloten ist erreicht.')
        cur = conn.execute('INSERT INTO usage(stamp,input_tokens,output_tokens,cost) VALUES(?,0,0,?)', (now, reserve))
        return cur.lastrowid

def settle_usage(rowid, model, result):
    usage = result.get('usageMetadata', {})
    inp = int(usage.get('promptTokenCount', 0)); out = int(usage.get('candidatesTokenCount', 0))
    with DB_LOCK, db() as conn:
        # Keep the worst-case reservation if the upstream omits token metadata.
        if inp or out:
            conn.execute('UPDATE usage SET input_tokens=?,output_tokens=?,cost=? WHERE id=?', (inp, out, estimate_cost(model, inp, out), rowid))

def request_gemini(parts, schema):
    key = os.environ.get('GEMINI_API_KEY')
    if not key: raise error(503, 'Das KI-Backend ist noch nicht konfiguriert.')
    import urllib.parse
    payload = {'contents':[{'role':'user','parts':parts}], 'generationConfig':{'responseMimeType':'application/json','responseSchema':schema,'maxOutputTokens':2048}}
    def one_model(model, attempts=2):
        url = 'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent?' + urllib.parse.urlencode({'key':key})
        request = Request(url, data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'}, method='POST')
        for attempt in range(attempts):
            try:
                with urlopen(request, timeout=25) as response: return json.loads(response.read()), model
            except HTTPError as exc:
                detail = exc.read().decode(errors='replace')
                if exc.code == 503 and attempt + 1 < attempts: time.sleep(.8); continue
                if exc.code in (429, 500, 502, 503, 504): raise error(503 if exc.code == 503 else exc.code, 'Der KI-Dienst ist vorübergehend nicht verfügbar. Bitte später erneut versuchen.')
                raise error(502, 'Der KI-Dienst hat die Anfrage abgelehnt.')
            except URLError:
                if attempt + 1 < attempts: time.sleep(.8); continue
                raise error(502, 'Der KI-Dienst ist nicht erreichbar.')
    try: result, model = one_model(MODEL)
    except RuntimeError as exc:
        if getattr(exc, 'status', None) != 503 or not FALLBACK_MODEL or FALLBACK_MODEL == MODEL: raise
        result, model = one_model(FALLBACK_MODEL, attempts=1)
    return result, model

def detect_deck_tree_request(message):
    """Extract a combined new-deck/subdeck/card request for deterministic sequencing."""
    if not re.search(r'\bdeck\b.*\bunterdeck\b', message, re.IGNORECASE | re.DOTALL): return None
    def name_after(pattern):
        match=re.search(pattern+r'\s+mit\s+dem\s+namen\s*["“„]?([^"”„\n.]+)',message,re.IGNORECASE)
        if not match: return None
        return match.group(1).strip().strip('"\'“”„ ').strip()
    main=name_after(r'\bdeck')
    child=name_after(r'\bunterdeck')
    if not main or not child: return None
    count_match=re.search(r'\b(\d{1,2})\s+(?:lern)?karten\b',message,re.IGNORECASE)
    count=min(max(int(count_match.group(1)),1),20) if count_match else 10
    return {'deckName':main,'subdeckName':child,'cardCount':count}

def detect_existing_deck_cards_request(message, decks):
    """Route explicit requests for cards in an existing deck to card generation."""
    match=re.search(r'\b(?:im|in\s+dem|in|für\s+(?:das|den))\s+(?:unterdeck|deck)\s+["“„]?([^"”„,\n.!?;:]+?)["”„]?\s*(?:,\s*|\s+)(?=(?:lern)?karten\b)',message,re.IGNORECASE)
    if not match: return None
    requested=match.group(1).strip().strip('"\'“”„ ')
    def key(value):
        folded=unicodedata.normalize('NFKD',value).encode('ascii','ignore').decode().casefold()
        return re.sub(r'[^a-z0-9]','',folded)
    matches=[str(name).strip() for name in decks if key(str(name).strip())==key(requested)]
    if len(matches)!=1: return None
    count_match=re.search(r'\b(\d{1,2})\s+(?:lern)?karten\b',message,re.IGNORECASE)
    count=min(max(int(count_match.group(1)),1),20) if count_match else 5
    return {'deckName':matches[0],'cardCount':count}

def sanitize_agent_plan(plan):
    """Drop malformed/duplicate operations and cap action fan-out before showing approval UI."""
    actions=plan.get('actions',[])
    if not isinstance(actions,list): actions=[]
    kept=[]; seen=set(); dropped=0
    for action in actions:
        if not isinstance(action,dict): dropped+=1; continue
        kind=action.get('type')
        if kind=='create_deck_tree' and (not str(action.get('deckName','')).strip() or not str(action.get('subdeckName','')).strip()): dropped+=1; continue
        if kind=='create_subdeck' and (not str(action.get('deckName','')).strip() or not str(action.get('parentDeck','')).strip()): dropped+=1; continue
        if kind=='create_deck' and not str(action.get('deckName','')).strip(): dropped+=1; continue
        if kind=='create_cards' and (not str(action.get('deckName','')).strip() or not action.get('cards')): dropped+=1; continue
        if kind in ('create_vocabulary_folder','add_vocabulary') and (not str(action.get('folderName','')).strip() or not action.get('vocabularyEntries')): dropped+=1; continue
        if kind=='create_calendar_entry' and (not str(action.get('title','')).strip() or not str(action.get('dateISO','')).strip()): dropped+=1; continue
        signature=(kind,str(action.get('deckName','')).casefold(),str(action.get('subdeckName','')).casefold(),str(action.get('parentDeck','')).casefold(),str(action.get('folderName','')).casefold(),str(action.get('title','')).casefold())
        if signature in seen: dropped+=1; continue
        seen.add(signature); kept.append(action)
        if len(kept)>=6:
            dropped += max(len(actions)-len(kept)-dropped,0)
            break
    if dropped: print('Agent plan sanitized: received=%d kept=%d dropped=%d.'%(len(actions),len(kept),dropped),flush=True)
    plan['actions']=kept
    return plan

CARD_SCHEMA={'type':'OBJECT','properties':{'cards':{'type':'ARRAY','items':{'type':'OBJECT','properties':{'question':{'type':'STRING'},'answer':{'type':'STRING'}},'required':['question','answer']}}},'required':['cards']}
EVALUATION_SCHEMA={'type':'OBJECT','properties':{'rating':{'type':'STRING','enum':['easy','good','hard','wrong']},'feedback':{'type':'STRING'}},'required':['rating','feedback']}
REPLY_SCHEMA={'type':'OBJECT','properties':{'reply':{'type':'STRING'}},'required':['reply']}
SUMMARY_SCHEMA={'type':'OBJECT','properties':{'summary':{'type':'STRING'}},'required':['summary']}
VOCABULARY_DRAFT_SCHEMA={'type':'OBJECT','properties':{'term':{'type':'STRING'},'translation':{'type':'STRING'},'pronunciation':{'type':'STRING'},'example':{'type':'STRING'},'synonyms':{'type':'ARRAY','items':{'type':'STRING'}},'difficulty':{'type':'INTEGER'}},'required':['term','translation','pronunciation']}
AGENT_PLAN_SCHEMA={'type':'OBJECT','properties':{'reply':{'type':'STRING'},'actions':{'type':'ARRAY','items':{'type':'OBJECT','properties':{'type':{'type':'STRING','enum':['create_deck','create_deck_tree','create_subdeck','create_cards','create_calendar_entry','create_vocabulary_folder','add_vocabulary']},'parentDeck':{'type':'STRING'},'createParentDeck':{'type':'BOOLEAN'},'deckName':{'type':'STRING'},'subdeckName':{'type':'STRING'},'folderName':{'type':'STRING'},'title':{'type':'STRING'},'dateISO':{'type':'STRING'},'kind':{'type':'STRING','enum':['exam','test','assignment','other']},'note':{'type':'STRING'},'cards':{'type':'ARRAY','items':{'type':'OBJECT','properties':{'question':{'type':'STRING'},'answer':{'type':'STRING'}},'required':['question','answer']}},'vocabularyEntries':{'type':'ARRAY','items':VOCABULARY_DRAFT_SCHEMA}},'required':['type']}}},'required':['reply','actions']}

class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        data=json.dumps(body,ensure_ascii=False).encode()
        self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('X-Content-Type-Options','nosniff'); self.send_header('Content-Length',str(len(data))); self.end_headers()
        try: self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError): pass
    def read_body(self):
        try: size=int(self.headers.get('Content-Length','-1'))
        except ValueError: raise error(400,'Ungültige Anfrage.')
        if size < 0 or size > MAX_BODY: raise error(413,'Die Anfrage ist zu groß (maximal 8 MB).')
        try: return json.loads(self.rfile.read(size) or b'{}')
        except (json.JSONDecodeError, UnicodeDecodeError): raise error(400,'Ungültiges JSON.')
    def client_ip(self): return self.client_address[0]
    def rate_limit_login(self):
        now=int(time.time())
        with DB_LOCK, db() as conn:
            conn.execute('DELETE FROM attempts WHERE stamp<?',(now-900,))
            attempts=conn.execute('SELECT count(*) FROM attempts WHERE ip=? AND stamp>?',(self.client_ip(),now-900)).fetchone()[0]
            if attempts >= 10: raise error(429,'Zu viele Anmeldeversuche. Bitte 15 Minuten warten.')
    def record_login_failure(self):
        with DB_LOCK, db() as conn: conn.execute('INSERT INTO attempts VALUES(?,?)',(self.client_ip(),int(time.time())))
    def rate_limit_http(self):
        now=int(time.time())
        with DB_LOCK, db() as conn:
            conn.execute('DELETE FROM traffic WHERE stamp<?',(now-60,))
            conn.execute('DELETE FROM attempts WHERE stamp<?',(now-900,))
            count=conn.execute('SELECT count(*) FROM traffic WHERE ip=? AND stamp>?',(self.client_ip(),now-60)).fetchone()[0]
            if count >= 120: raise error(429,'Zu viele Anfragen von diesem Anschluss. Bitte kurz warten.')
            conn.execute('INSERT INTO traffic VALUES(?,?)',(self.client_ip(),now))
    def authenticate(self):
        if LOCAL_AUTH_DISABLED: return 'local-development'
        token=self.headers.get('Authorization','')
        if not token.startswith('Bearer '): raise error(401,'Bitte melde dich für den Privatpilot an.')
        digest=hashlib.sha256(token[7:].encode()).hexdigest(); now=int(time.time())
        with DB_LOCK, db() as conn:
            row=conn.execute('SELECT expires FROM sessions WHERE token_hash=?',(digest,)).fetchone()
            if not row or row[0] < now:
                conn.execute('DELETE FROM sessions WHERE token_hash=?',(digest,)); raise error(401,'Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.')
        return digest
    def do_GET(self):
        if self.path == '/api/health': self.send_json(200,{'ok':True}); return
        self.send_json(404,{'error':'Route nicht gefunden.'})
    def do_POST(self):
        try:
            self.rate_limit_http()
            body=self.read_body()
            if self.path == '/api/login':
                self.rate_limit_login()
                email=str(body.get('email','')).strip().lower(); password=str(body.get('password',''))
                expected=os.environ.get('PILOT_EMAIL','').strip().lower()
                if not expected or not os.environ.get('PILOT_PASSWORD_HASH') and not os.environ.get('PILOT_PASSWORD'): raise error(503,'Privatpilot-Anmeldung ist nicht konfiguriert.')
                if not hmac.compare_digest(email.encode('utf-8'),expected.encode('utf-8')) or not password_ok(password):
                    self.record_login_failure()
                    raise error(401,'E-Mail oder Passwort ist falsch.')
                raw=secrets.token_urlsafe(32); digest=hashlib.sha256(raw.encode()).hexdigest(); expiry=int(time.time())+TOKEN_TTL
                with DB_LOCK, db() as conn:
                    conn.execute('DELETE FROM attempts WHERE ip=?',(self.client_ip(),))
                    conn.execute('INSERT INTO sessions VALUES(?,?)',(digest,expiry))
                self.send_json(200,{'token':raw,'expiresAt':expiry}); return
            if self.path == '/api/logout':
                digest=self.authenticate()
                with DB_LOCK, db() as conn: conn.execute('DELETE FROM sessions WHERE token_hash=?',(digest,))
                self.send_json(200,{'ok':True}); return
            self.authenticate()
            if self.path not in ('/api/generate-cards','/api/evaluate','/api/tutor','/api/summary','/api/agent-plan'):
                self.send_json(404,{'error':'Route nicht gefunden.'}); return
            if not os.environ.get('GEMINI_API_KEY'): raise error(503,'Das KI-Backend ist noch nicht konfiguriert.')
            rowid=reserve_usage()
            try:
                result=self.handle_ai(self.path,body)
                # Handle returns (payload, selected model, raw usage metadata).
                response, model, raw = result
                if self.path=='/api/agent-plan':
                    actions=response.get('actions',[]) if isinstance(response,dict) else []
                    print('Tutor agent plan completed: actions=%d model=%s.'%(len(actions) if isinstance(actions,list) else 0,model),flush=True)
                settle_usage(rowid,model,raw); self.send_json(200,response)
            except Exception as exc:
                # Validation failures release the reservation; upstream failures stay reserved conservatively.
                if getattr(exc,'status',500) < 500:
                    with DB_LOCK, db() as conn: conn.execute('UPDATE usage SET cost=0 WHERE id=?',(rowid,))
                raise
        except Exception as exc:
            status=getattr(exc,'status',500)
            if status >= 500: print('Request %s failed (%s).'%(self.path,status),flush=True)
            message = str(exc) if status < 500 else 'Der Dienst ist vorübergehend nicht verfügbar. Bitte später erneut versuchen.'
            self.send_json(status,{'error':message})
    def handle_ai(self,path,body):
        tree_request=None
        cards_request=None
        def textval(name,limit,required=False):
            value=str(body.get(name,'') or '')
            if len(value)>limit: raise error(413,'Ein Textfeld ist zu lang.')
            if required and not value.strip(): raise error(400,'Bitte fülle die erforderlichen Felder aus.')
            return value
        if path=='/api/generate-cards':
            source=textval('text',18000); instruction=textval('instructions',1000)
            image=body.get('imageBase64'); parts=[]
            if source: parts.append({'text':'Material:\n'+source})
            if image:
                if len(image)>7_000_000: raise error(413,'Das Bild ist zu groß.')
                mime=body.get('mimeType','image/jpeg')
                if mime not in ('image/jpeg','image/png','image/webp'): raise error(400,'Dieses Bildformat wird nicht unterstützt.')
                try: base64.b64decode(image,validate=True)
                except Exception: raise error(400,'Das Bild ist ungültig.')
                parts.append({'inlineData':{'mimeType':mime,'data':image}})
            if not parts: raise error(400,'Bitte füge Text oder ein Bild hinzu.')
            lang='English' if body.get('language') in ('English','Englisch') else 'German'
            prompt='Create 5 to 12 accurate flashcards in '+lang+'. Cover key facts without duplicates or invention. '+instruction+' Reply only with requested JSON.'
            result,model=request_gemini([{'text':prompt}]+parts,CARD_SCHEMA)
        elif path=='/api/evaluate':
            q=textval('question',1500,True); expected=textval('expected',3000,True); answer=textval('answer',3000)
            response_language=textval('language',60) or 'German'
            language_aliases={'de':'German','deutsch':'German','german':'German','en':'English','englisch':'English','english':'English','fr':'French','französisch':'French','es':'Spanish','spanisch':'Spanish','it':'Italian','italienisch':'Italian','pt':'Portuguese','ja':'Japanese','zh':'Chinese','nl':'Dutch'}
            response_language=language_aliases.get(response_language.casefold(),response_language)
            prompt='Evaluate this study answer. Accept accurate paraphrases and synonyms. easy=complete and correct; good=core right with minor omission; hard=materially incomplete; wrong=incorrect, contradictory, or empty. Provide concise, specific feedback. REQUIRED OUTPUT LANGUAGE: '+response_language+'. Write the rating feedback entirely in this language. Do not copy or switch to the learner response language if it differs from the card language. Keep this same language for every evaluation.\nQuestion: '+q+'\nExpected answer: '+expected+'\nLearner response: '+answer
            result,model=request_gemini([{'text':prompt}],EVALUATION_SCHEMA)
        elif path=='/api/tutor':
            history=body.get('history') or []
            if not isinstance(history,list) or len(history)>10: raise error(400,'Der Chatverlauf ist ungültig.')
            transcript='\n'.join(('Tutor' if m.get('role')=='assistant' else 'Lernende Person')+': '+str(m.get('text',''))[:1000] for m in history if isinstance(m,dict))
            prompt='You are a concise, friendly study tutor. Use context accurately; state uncertainty.\nContext: '+textval('answer',4000)+'\nHistory:\n'+transcript+'\nQuestion: '+textval('message',1500,True)
            result,model=request_gemini([{'text':prompt}],REPLY_SCHEMA)
        elif path=='/api/agent-plan':
            decks=body.get('decks') or []
            if not isinstance(decks,list) or len(decks)>100: raise error(400,'Die Deckliste ist ungültig.')
            deck_lines='\n'.join(str(d)[:120] for d in decks)
            folders=body.get('vocabularyFolders') or []
            if not isinstance(folders,list) or len(folders)>100: raise error(400,'Die Vokabelliste ist ungültig.')
            folder_lines='\n'.join(str(folder)[:120] for folder in folders)
            source=textval('sourceLanguage',80,True); target=textval('targetLanguage',80,True)
            mode=textval('mode',40) or 'automatic'
            lang='English' if body.get('language') in ('English','Englisch') else 'German'
            message=textval('message',1500,True)
            tree_request=detect_deck_tree_request(message)
            cards_request=detect_existing_deck_cards_request(message,decks) if not tree_request else None
            if tree_request:
                prompt=('Create exactly '+str(tree_request['cardCount'])+' flashcards in German for the requested subdeck. Main deck: '+tree_request['deckName']+'. Subdeck: '+tree_request['subdeckName']+'. Follow the full user instruction and its exact learning objective. The FRONT of every card must be a distinct complex sentence and a task to identify its sentence constituents. The BACK must give the same sentence segmented and clearly label each constituent (subject, predicate, objects, adverbials as applicable). Never make cards that merely translate the subdeck title or explain what sentence constituents are. No duplicates. Return only the required JSON. User instruction: '+message)
                result,model=request_gemini([{'text':prompt}],CARD_SCHEMA)
            elif cards_request:
                prompt=('Create exactly '+str(cards_request['cardCount'])+' accurate, non-duplicate flashcards in '+lang+' for the existing deck or subdeck named "'+cards_request['deckName']+'". Treat the user\'s full instruction as the learning objective. Turn each requested topic into a useful question and a precise answer. Do not claim the cards are already saved. Return only the required JSON. User instruction: '+message)
                result,model=request_gemini([{'text':prompt}],CARD_SCHEMA)
            else:
                prompt=build_agent_plan_prompt(
                    language=lang,
                    mode=mode,
                    source_language=source,
                    target_language=target,
                    deck_lines=deck_lines,
                    folder_lines=folder_lines,
                    message=message,
                )
                result,model=request_gemini([{'text':prompt}],AGENT_PLAN_SCHEMA)
        else:
            cards=body.get('cards') or []
            if not isinstance(cards,list) or len(cards)>100: raise error(400,'Das Deck darf höchstens 100 Karten enthalten.')
            material='\n'.join('Q: '+str(c.get('question',''))[:300]+'\nA: '+str(c.get('answer',''))[:500] for c in cards if isinstance(c,dict))
            if not material: raise error(400,'Dieses Deck enthält noch keine Karten.')
            result,model=request_gemini([{'text':'Summarize these study cards concisely, group related ideas, do not invent facts.\n'+material}],SUMMARY_SCHEMA)
        candidates=result.get('candidates',[])
        raw={'usageMetadata':result.get('usageMetadata',{})}
        output=''.join(p.get('text','') for p in candidates[0].get('content',{}).get('parts',[])) if candidates else ''
        if not output: raise error(502,'Die KI hat keine auswertbare Antwort geliefert.')
        try:
            payload=json.loads(output)
            if path=='/api/agent-plan':
                if tree_request:
                    cards=payload.get('cards',[]) if isinstance(payload,dict) else []
                    valid=[c for c in cards if isinstance(c,dict) and str(c.get('question','')).strip() and str(c.get('answer','')).strip()]
                    if len(valid)<tree_request['cardCount']: raise error(502,'Die KI hat nicht alle angeforderten Karten erstellt. Bitte erneut versuchen.')
                    payload={'reply':'Vorschau für '+tree_request['deckName']+' › '+tree_request['subdeckName']+' mit '+str(tree_request['cardCount'])+' Karten.','actions':[{'type':'create_deck_tree','deckName':tree_request['deckName'],'subdeckName':tree_request['subdeckName'],'cards':valid[:tree_request['cardCount']]}]}
                elif cards_request:
                    cards=payload.get('cards',[]) if isinstance(payload,dict) else []
                    valid=[c for c in cards if isinstance(c,dict) and str(c.get('question','')).strip() and str(c.get('answer','')).strip()]
                    if len(valid)<cards_request['cardCount']: raise error(502,'Die KI hat nicht alle angeforderten Karten erstellt. Bitte erneut versuchen.')
                    payload={'reply':'Vorschlag für '+cards_request['deckName']+' mit '+str(cards_request['cardCount'])+' Karten.','actions':[{'type':'create_cards','deckName':cards_request['deckName'],'cards':valid[:cards_request['cardCount']]}]}
                else:
                    payload=sanitize_agent_plan(payload if isinstance(payload,dict) else {})
            return payload,model,raw
        except json.JSONDecodeError: raise error(502,'Die KI-Antwort war nicht im erwarteten Format.')
    def log_message(self,fmt,*args):
        # Avoid logging source IPs, paths, query strings, request bodies, tokens, and prompts.
        print('HTTP %s'%fmt.split(' ')[0],flush=True)

class PilotHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16
    _slots = threading.BoundedSemaphore(16)
    def process_request(self, request, client_address):
        self._slots.acquire()
        try: super().process_request(request, client_address)
        except Exception:
            self._slots.release()
            raise
    def process_request_thread(self, request, client_address):
        try: super().process_request_thread(request, client_address)
        finally: self._slots.release()

if __name__=='__main__':
    if APP_ENV == 'production' and LOCAL_AUTH_DISABLED:
        raise SystemExit('Authentifizierung kann in Produktion nicht deaktiviert sein.')
    if not LOCAL_AUTH_DISABLED and (not os.environ.get('PILOT_EMAIL') or not (os.environ.get('PILOT_PASSWORD_HASH') or os.environ.get('PILOT_PASSWORD'))):
        raise SystemExit('Setze PILOT_EMAIL und PILOT_PASSWORD_HASH (oder PILOT_PASSWORD) für den Privatpilot.')
    if APP_ENV=='production' and os.environ.get('TRUST_PROXY_HTTPS')!='1':
        raise SystemExit('Produktion nur hinter HTTPS-Proxy bereitstellen (TRUST_PROXY_HTTPS=1 nach aktivem TLS setzen).')
    if APP_ENV=='production' and not os.environ.get('PILOT_PASSWORD_HASH'):
        raise SystemExit('Produktion erfordert PILOT_PASSWORD_HASH; Klartextpasswörter sind nur für lokale Entwicklung erlaubt.')
    if LOCAL_AUTH_DISABLED:
        print('Lokaler Lernkarten-Server ohne Anmeldung; nur auf 127.0.0.1 erreichbar.',flush=True)
    else:
        print('Lernkarten Privatpilot API bereit; Modell %s; Limits %s/Tag, %s gesamt, $%.2f.'%(MODEL,PILOT_DAILY_LIMIT,PILOT_TOTAL_LIMIT,PILOT_BUDGET_USD),flush=True)
    bind_host = '127.0.0.1' if LOCAL_AUTH_DISABLED else '0.0.0.0'
    PilotHTTPServer((bind_host,int(os.environ.get('PORT','8787'))),Handler).serve_forever()
