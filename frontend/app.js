const DATA_URL = '/api/v1/content';
const diagnostics = [];
const LANGUAGE_NAMES = { de: 'Deutsch', en: 'Englisch' };
const POS_NAMES = {
  nomen: 'Nomen', verb: 'Verb', adjektiv: 'Adjektiv', adverb: 'Adverb',
  praeposition: 'Präposition', konjunktion: 'Konjunktion', pronomen: 'Pronomen',
  interjektion: 'Interjektion', andere: 'Wortart'
};
const QUALITY_NAMES = { roh: 'Entwurf', geprueft: 'Geprüft', freigegeben: 'Freigegeben', prueffliste: 'Prüfliste' };

const state = {
  entries: [],
  visibleEntries: [],
  learningLanguage: 'en',
  explanationLanguage: 'de',
  level: 'all',
  query: '',
  entryIndex: 0,
  senseIndex: 0,
  toastTimer: null
};

const ui = {
  list: document.querySelector('#word-list'),
  listCount: document.querySelector('#list-count'),
  wordCount: document.querySelector('#word-count'),
  position: document.querySelector('#position-label'),
  progress: document.querySelector('#progress-fill'),
  card: document.querySelector('#word-card'),
  search: document.querySelector('#word-search'),
  empty: document.querySelector('#empty-list'),
  learning: document.querySelector('#learning-language'),
  explanation: document.querySelector('#explanation-language'),
  level: document.querySelector('#level-filter'),
  filterLabel: document.querySelector('#filter-label'),
  previous: document.querySelector('#previous-button'),
  next: document.querySelector('#next-button'),
  toast: document.querySelector('#toast')
};

function logDiagnostic(message, level = 'info') {
  const line = `${new Date().toLocaleTimeString()} ${message}`;
  diagnostics.push(line);
  console[level](`[Word Express Vorschau] ${message}`);
  const log = document.querySelector('#diagnostic-log');
  if (log) log.textContent = diagnostics.join('\n');
}

function escapeHtml(value = '') {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[char]);
}

function currentEntry() {
  return state.visibleEntries[state.entryIndex] || null;
}

function currentSense(entry = currentEntry()) {
  return entry?.senses[state.senseIndex] || entry?.senses[0] || null;
}

function currentExplanation(sense) {
  return sense?.explanations.find((item) => item.erklaersprache === state.explanationLanguage) || null;
}

function sortedEntries() {
  const query = state.query.trim().toLocaleLowerCase();
  return state.entries
    .filter((entry) => entry.lemma.sprache === state.learningLanguage)
    .filter((entry) => state.level === 'all' || entry.lemma.niveau === state.level)
    .filter((entry) => {
      if (!query) return true;
      const lemma = entry.lemma.text.toLocaleLowerCase();
      const translations = entry.senses.flatMap((sense) => [
        sense.uebersetzung.text,
        ...(sense.uebersetzung.alternativen || [])
      ]).join(' ').toLocaleLowerCase();
      return lemma.includes(query) || translations.includes(query);
    })
    .sort((a, b) => a.lemma.text.localeCompare(b.lemma.text, state.learningLanguage));
}

function renderWordList() {
  state.visibleEntries = sortedEntries();
  state.entryIndex = Math.min(state.entryIndex, Math.max(0, state.visibleEntries.length - 1));
  state.senseIndex = Math.min(state.senseIndex, Math.max(0, (currentEntry()?.senses.length || 1) - 1));
  ui.listCount.textContent = String(state.visibleEntries.length);
  ui.wordCount.textContent = `${state.visibleEntries.length} Wörter`;
  ui.filterLabel.textContent = state.level === 'all' ? 'Alle Niveaus' : `Niveau ${state.level}`;
  ui.empty.classList.toggle('hidden', state.visibleEntries.length > 0);
  ui.list.classList.toggle('hidden', state.visibleEntries.length === 0);
  ui.list.innerHTML = state.visibleEntries.map((entry, index) => {
    const lemma = entry.lemma;
    const active = index === state.entryIndex;
    return `<button class="word-item${active ? ' active' : ''}" type="button" data-entry-index="${index}" aria-current="${active ? 'true' : 'false'}">
      <span class="word-item-copy"><span class="word-item-article">${lemma.sprache === 'de' && lemma.artikel ? escapeHtml(lemma.artikel) : ''}</span><span class="word-item-text">${escapeHtml(lemma.text)}</span></span>
      <span class="word-item-level">${escapeHtml(lemma.niveau)}</span>
    </button>`;
  }).join('');
  ui.list.querySelectorAll('[data-entry-index]').forEach((button) => {
    button.addEventListener('click', () => {
      state.entryIndex = Number(button.dataset.entryIndex);
      state.senseIndex = 0;
      render();
    });
  });
  renderCard();
}

function renderCard() {
  const entry = currentEntry();
  if (!entry) {
    ui.card.innerHTML = `<div class="empty-state">Für diese Auswahl wurden keine Wörter gefunden.</div>`;
    ui.position.textContent = 'Keine Treffer';
    ui.progress.style.width = '0%';
    ui.previous.disabled = true;
    ui.next.disabled = true;
    return;
  }

  const lemma = entry.lemma;
  const sense = currentSense(entry);
  const explanation = currentExplanation(sense);
  const translation = sense.uebersetzung;
  const percent = ((state.entryIndex + 1) / state.visibleEntries.length) * 100;
  ui.position.textContent = `${state.entryIndex + 1} von ${state.visibleEntries.length} Wörtern`;
  ui.progress.style.width = `${percent}%`;
  ui.previous.disabled = state.entryIndex === 0;
  ui.next.disabled = state.entryIndex >= state.visibleEntries.length - 1;

  if (!explanation) {
    ui.card.innerHTML = `<div class="error-card"><h2>Erklärung fehlt</h2><p>Für ${escapeHtml(LANGUAGE_NAMES[state.explanationLanguage])} ist in diesem Eintrag keine Erklärung hinterlegt.</p></div>`;
    return;
  }

  const effectiveArticle = sense.artikel ?? lemma.artikel;
  const effectivePlural = sense.plural ?? lemma.plural;
  const article = lemma.sprache === 'de' && effectiveArticle
    ? `<span class="article">${escapeHtml(effectiveArticle)}</span>` : '';
  const plural = lemma.wortart === 'nomen' && effectivePlural
    ? `<p class="plural-line">Plural: ${escapeHtml(effectivePlural)}</p>` : '';
  const ipa = lemma.ipa ? `<span class="ipa">${escapeHtml(lemma.ipa)}</span>` : '';
  const meaningButtons = entry.senses.map((item, index) => `
    <button type="button" class="meaning-button${index === state.senseIndex ? ' active' : ''}" data-sense-index="${index}">${escapeHtml(item.bedeutung_kurz)}</button>
  `).join('');
  const translationBlock = `<div class="translation-box"><span class="translation-arrow" aria-hidden="true">↔</span><div><small class="translation-caption">Übersetzung · ${escapeHtml(LANGUAGE_NAMES[translation.sprache])}</small><div class="translation-value">${escapeHtml(translation.text)}</div>${translation.alternativen?.length ? `<small class="translation-alts">Auch: ${translation.alternativen.map(escapeHtml).join(', ')}</small>` : ''}</div></div>`;
  const hints = [
    explanation.merkhilfe ? `<span class="hint"><strong>Merkhilfe</strong> ${escapeHtml(explanation.merkhilfe)}</span>` : '',
    explanation.verwechslung ? `<span class="hint"><strong>Nicht verwechseln</strong> ${escapeHtml(explanation.verwechslung)}</span>` : ''
  ].filter(Boolean).join('');
  const examples = explanation.beispiele.map((example) => `
    <div class="example"><span class="example-sentence">${escapeHtml(example.satz)}</span>${example.uebersetzung ? `<span class="example-translation">${escapeHtml(example.uebersetzung)}</span>` : ''}</div>
  `).join('');
  const quality = explanation.qualitaet || entry.qualitaet;
  const qualityHints = quality?.hinweise || [];
  const qualityPanel = qualityHints.length ? `<details class="quality-details"><summary>Qualitätshinweise (${qualityHints.length})</summary>${qualityHints.map((hint) => `<p>${escapeHtml(hint)}</p>`).join('')}</details>` : '';

  ui.card.innerHTML = `<div class="card-content">
    <div class="card-overline"><div class="badge-row"><span class="chip level">${escapeHtml(lemma.niveau)}</span><span class="chip">${escapeHtml(POS_NAMES[lemma.wortart] || lemma.wortart)}</span><span class="chip quality">${escapeHtml(QUALITY_NAMES[quality?.status || entry.qualitaet?.status] || 'Entwurf')}</span></div><span class="sense-counter">Bedeutung ${state.senseIndex + 1} / ${entry.senses.length}</span></div>
    <div class="word-heading">${article}<h2>${escapeHtml(lemma.text)}</h2></div>
    ${plural}
    <div class="lemma-meta">${ipa ? `<span>${ipa}</span><span class="separator">·</span>` : ''}<span>${escapeHtml(LANGUAGE_NAMES[lemma.sprache])} lernen</span><span class="separator">·</span><span>Erklärung auf ${escapeHtml(LANGUAGE_NAMES[state.explanationLanguage])}</span></div>
    ${entry.senses.length > 1 ? `<div class="meaning-row"><span class="meaning-label">Bedeutung</span><div class="meaning-switcher">${meaningButtons}</div></div>` : `<div class="meaning-row"><span class="meaning-label">${escapeHtml(sense.bedeutung_kurz)}</span></div>`}
    ${translationBlock}
    <section class="explanation-section" aria-label="Erklärung">
      <div class="section-heading">Einfach erklärt · ${escapeHtml(explanation.stufe)}</div>
      <p class="definition">${escapeHtml(explanation.definition)}</p>
      ${hints ? `<div class="hint-row">${hints}</div>` : ''}
      <div class="section-heading">Beispiele</div>
      <div class="examples">${examples}</div>
      ${qualityPanel}
    </section>
  </div>`;

  ui.card.querySelectorAll('[data-sense-index]').forEach((button) => {
    button.addEventListener('click', () => {
      state.senseIndex = Number(button.dataset.senseIndex);
      renderCard();
    });
  });
}

function render() {
  renderWordList();
}

function moveEntry(delta) {
  const next = state.entryIndex + delta;
  if (next < 0 || next >= state.visibleEntries.length) return;
  state.entryIndex = next;
  state.senseIndex = 0;
  render();
}

function showToast(message) {
  ui.toast.textContent = message;
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => { ui.toast.textContent = ''; }, 2400);
}

ui.learning.addEventListener('change', () => {
  state.learningLanguage = ui.learning.value;
  state.entryIndex = 0;
  state.senseIndex = 0;
  render();
});
ui.explanation.addEventListener('change', () => {
  state.explanationLanguage = ui.explanation.value;
  renderCard();
});
ui.level.addEventListener('change', () => {
  state.level = ui.level.value;
  state.entryIndex = 0;
  state.senseIndex = 0;
  render();
});
ui.search.addEventListener('input', () => {
  state.query = ui.search.value;
  state.entryIndex = 0;
  state.senseIndex = 0;
  render();
});
ui.previous.addEventListener('click', () => moveEntry(-1));
ui.next.addEventListener('click', () => moveEntry(1));
document.addEventListener('keydown', (event) => {
  const target = event.target;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
    event.preventDefault();
    ui.search.focus();
    return;
  }
  if (target instanceof HTMLInputElement || target instanceof HTMLSelectElement || target instanceof HTMLTextAreaElement) return;
  if (event.key === 'ArrowLeft') moveEntry(-1);
  if (event.key === 'ArrowRight') moveEntry(1);
});

const resolvedDataUrl = new URL(DATA_URL, document.baseURI).href;
logDiagnostic(`Seite: ${window.location.href}`);
logDiagnostic(`Lade Datendatei: ${resolvedDataUrl}`);

fetch(resolvedDataUrl, { cache: 'no-store' })
  .then((response) => {
    const contentType = response.headers.get('content-type') || '(kein Content-Type)';
    logDiagnostic(`Antwort: HTTP ${response.status} ${response.statusText}; Content-Type: ${contentType}`, response.ok ? 'info' : 'error');
    if (!response.ok) throw new Error(`HTTP ${response.status} beim Laden von ${resolvedDataUrl}`);
    return response.text().then((body) => {
      logDiagnostic(`Antwortgröße: ${body.length} Zeichen`);
      try {
        return JSON.parse(body);
      } catch (error) {
        const preview = body.slice(0, 100).replace(/\s+/g, ' ');
        throw new Error(`Antwort ist kein gültiges JSON (${error.message}). Anfang der Antwort: ${preview}`);
      }
    });
  })
  .then((entries) => {
    if (!Array.isArray(entries)) throw new Error('Die Inhaltsdatei muss ein JSON-Array sein.');
    const deCount = entries.filter((entry) => entry?.lemma?.sprache === 'de').length;
    const enCount = entries.filter((entry) => entry?.lemma?.sprache === 'en').length;
    logDiagnostic(`JSON gelesen: ${entries.length} Einträge (de=${deCount}, en=${enCount})`);
    state.entries = entries;
    render();
    logDiagnostic('Oberfläche mit Testdaten aufgebaut.');
  })
  .catch((error) => {
    logDiagnostic(`FEHLER: ${error.message}`, 'error');
    const panel = document.querySelector('#diagnostic-panel');
    if (panel) panel.open = true;
    ui.card.innerHTML = `<div class="error-card"><h2>Testdaten konnten nicht geladen werden</h2><p>Prüfe die Verbindung zur Word Express API unter <code>/api/v1/content</code>.</p><p><code>${escapeHtml(error.message)}</code></p></div>`;
    ui.position.textContent = 'Testdaten nicht geladen';
    ui.wordCount.textContent = '—';
  });
