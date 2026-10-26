/*
 * Consigliere reference core.
 *
 * This file is the source of truth for HOW the brain behaves. The Swift
 * package ConsigliereCore is a port of this file and must reproduce the golden
 * fixtures in /fixtures exactly. Keep it dependency-free and deterministic:
 * time and randomness are always injected.
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- text ----

  /** Lowercase and strip everything except a-z and 0-9. "You Tube!" -> "youtube" */
  function normalize(s) {
    return String(s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  }

  /** Lowercase words split on anything that is not a-z / 0-9. */
  function words(s) {
    return String(s || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean);
  }

  /** Classic Levenshtein distance. */
  function editDistance(a, b) {
    if (a === b) return 0;
    if (!a.length) return b.length;
    if (!b.length) return a.length;
    var prev = [];
    for (var j = 0; j <= b.length; j++) prev.push(j);
    for (var i = 1; i <= a.length; i++) {
      var cur = [i];
      for (var k = 1; k <= b.length; k++) {
        var cost = a.charAt(i - 1) === b.charAt(k - 1) ? 0 : 1;
        cur.push(Math.min(prev[k] + 1, cur[k - 1] + 1, prev[k - 1] + cost));
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /**
   * Greedy earliest subsequence match. Returns the span (last index - first
   * index + 1) the query covers inside key, or -1 when q is not a subsequence.
   */
  function subsequenceSpan(q, key) {
    var first = -1, last = -1, qi = 0;
    for (var i = 0; i < key.length && qi < q.length; i++) {
      if (key.charAt(i) === q.charAt(qi)) {
        if (first < 0) first = i;
        last = i;
        qi++;
      }
    }
    return qi === q.length ? last - first + 1 : -1;
  }

  /** Percent-encode everything except RFC 3986 unreserved characters. */
  function encodeQuery(s) {
    var out = '';
    var bytes = utf8Bytes(String(s));
    for (var i = 0; i < bytes.length; i++) {
      var c = bytes[i];
      var unreserved =
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) ||
        c === 0x2d || c === 0x2e || c === 0x5f || c === 0x7e;
      out += unreserved ? String.fromCharCode(c) : '%' + (c < 16 ? '0' : '') + c.toString(16).toUpperCase();
    }
    return out;
  }

  function utf8Bytes(str) {
    var bytes = [];
    for (var i = 0; i < str.length; i++) {
      var cp = str.codePointAt(i);
      if (cp > 0xffff) i++;
      if (cp < 0x80) bytes.push(cp);
      else if (cp < 0x800) bytes.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
      else if (cp < 0x10000) bytes.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
      else bytes.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    }
    return bytes;
  }

  // ------------------------------------------------------------- matcher ----

  // Match quality bands, best first. "Strong" bands are safe to act on from
  // speech without confirmation; weak ones need an Enter / tap.
  var BAND = {
    exact: 7,        // "yt" == alias "yt"
    prefix: 6,       // "you" -> "youtube"
    wordPrefix: 5,   // "code" -> "vs code"
    acronym: 4,      // "vsc" -> "visual studio code"
    subsequence: 3,  // "ytb" -> "youtube" (same first letter required)
    prefixEdit: 2,   // "youto" -> "youtube" (speech mishearing)
    edit: 1          // "utube" -> "youtube"
  };
  var STRONG_FROM = BAND.acronym;

  function bandName(n) {
    for (var k in BAND) if (BAND[k] === n) return k;
    return 'none';
  }

  /** Score one normalized query against one raw key (a name or an alias). */
  function scoreKey(q, rawKey) {
    var key = normalize(rawKey);
    if (!q || !key) return null;
    if (q === key) return { band: BAND.exact, quality: 1 };
    if (key.indexOf(q) === 0) return { band: BAND.prefix, quality: q.length / key.length };

    var ws = words(rawKey);
    if (q.length >= 2 && ws.length >= 2) {
      for (var i = 1; i < ws.length; i++) {
        if (ws[i].indexOf(q) === 0) return { band: BAND.wordPrefix, quality: q.length / ws[i].length };
      }
      var acr = ws.map(function (w) { return w.charAt(0); }).join('');
      if (acr.indexOf(q) === 0) return { band: BAND.acronym, quality: q.length / acr.length };
    }

    if (q.length >= 2 && q.charAt(0) === key.charAt(0)) {
      var span = subsequenceSpan(q, key);
      if (span > 0) return { band: BAND.subsequence, quality: q.length / span };
    }

    if (q.length >= 4) {
      var head = key.slice(0, q.length);
      var pd = editDistance(q, head);
      var pdMax = q.length >= 6 ? 2 : 1;
      if (pd <= pdMax) return { band: BAND.prefixEdit, quality: -pd };

      var d = editDistance(q, key);
      var dMax = key.length <= 5 ? 1 : 2;
      if (d <= dMax) return { band: BAND.edit, quality: -d };
    }
    return null;
  }

  /** Best score for an entry across its name and aliases. */
  function scoreEntry(q, entry) {
    var keys = [entry.name].concat(entry.aliases || []);
    var best = null;
    for (var i = 0; i < keys.length; i++) {
      var s = scoreKey(q, keys[i]);
      if (s && (!best || s.band > best.band || (s.band === best.band && s.quality > best.quality))) best = s;
    }
    return best;
  }

  /**
   * Rank the catalog for a normalized query.
   * Order: band desc, usage desc, quality desc, name asc.
   * "Within the same match quality, the thing you open most wins."
   */
  function rank(q, catalog, usage) {
    usage = usage || {};
    var hits = [];
    for (var i = 0; i < catalog.length; i++) {
      var s = scoreEntry(q, catalog[i]);
      if (s) hits.push({ entry: catalog[i], band: s.band, quality: s.quality, usage: usage[catalog[i].name] || 0 });
    }
    hits.sort(function (a, b) {
      if (a.band !== b.band) return b.band - a.band;
      if (a.usage !== b.usage) return b.usage - a.usage;
      if (a.quality !== b.quality) return b.quality - a.quality;
      return a.entry.name < b.entry.name ? -1 : a.entry.name > b.entry.name ? 1 : 0;
    });
    return hits;
  }

  /** Every entry, most used first. Things never used keep the order they have in the catalog. */
  function mostUsed(catalog, usage) {
    usage = usage || {};
    return catalog
      .map(function (e, index) { return { entry: e, band: 0, quality: 0, usage: usage[e.name] || 0, index: index }; })
      .sort(function (a, b) { return a.usage !== b.usage ? b.usage - a.usage : a.index - b.index; })
      .map(function (h) { return { entry: h.entry, band: h.band, quality: h.quality, usage: h.usage }; });
  }

  // Entries that accept more words after their name: searchable sites ("yt berserk amv")
  // and tools that take an argument ("timer 10"). `toolsOnly` is used for the trailing form ("10 min timer").
  function exactEntryWithSearch(head, catalog, toolsOnly) {
    for (var i = 0; i < catalog.length; i++) {
      var e = catalog[i];
      var takes = toolsOnly ? (e.kind === 'tool' && e.takesWords === true) : (!!e.searchTemplate || e.takesWords === true);
      if (!takes) continue;
      var keys = [e.name].concat(e.aliases || []);
      for (var k = 0; k < keys.length; k++) if (normalize(keys[k]) === head) return e;
    }
    return null;
  }

  // Words people say (or type) around the name of a thing. They carry no
  // meaning here, so they are dropped before matching. This is what lets
  // "play me some youtube" and "open the downloads folder" work without
  // there being any command language to learn.
  var FILLER = ['open', 'launch', 'start', 'run', 'go', 'goto', 'to', 'play', 'me', 'some', 'the',
    'my', 'show', 'please', 'hey', 'yo', 'consigliere', 'up', 'a', 'set'];

  // Asking. The box works like a browser's address bar: a name opens the thing, anything that reads
  // like a question gets asked. There is still no command to learn.
  var QUESTION_WORDS = ['how', 'what', 'whats', 'why', 'who', 'whos', 'when', 'where', 'which', 'is', 'are', 'can', 'could',
    'does', 'do', 'did', 'should', 'would', 'explain', 'define', 'meaning', 'tell'];

  function askDecision(text, confident) {
    return { mode: 'ask', query: String(text).replace(/^[\s?]+/, '').trim(), results: [], confident: confident };
  }

  function stripLeadingFiller(tokens) {
    var i = 0;
    while (i < tokens.length && FILLER.indexOf(normalize(tokens[i])) >= 0) i++;
    return i === tokens.length ? tokens : tokens.slice(i);
  }

  /**
   * The one entry point. Raw text in (typed or spoken), decision out.
   *   mode "empty"  -> nothing typed; results = most used
   *   mode "open"   -> results ranked; results[0] is what Enter opens
   *   mode "search" -> first word(s) named a searchable site; query = the rest
   *   mode "ask"    -> it reads like a question; query = the question, results = []
   *   mode "none"   -> nothing matched
   * `confident` is true when it is safe to act without a confirming Enter/tap
   * (used for speech, where a wrong guess must never open the wrong thing).
   *
   * Steps, in order:
   *   1. drop leading filler words
   *   2. whole input is an exact name/alias            -> open
   *   3. first 2 or 1 words exactly name a searchable site or a tool that takes words -> search
   *  3b. last 2 or 1 words exactly name a tool that takes words ("10 min timer")       -> search
   *   4. whole input ranks strongly                    -> open
   *   5. a shorter run of leading words ranks strongly -> open ("gmail inbox")
   *   6. whole input ranks weakly                      -> open, not confident
   *   7. otherwise                                     -> none
   */
  function match(input, catalog, usage, limit) {
    limit = limit || 4;
    usage = usage || {};
    var rawTokens = String(input || '').trim().split(/\s+/).filter(Boolean);
    if (!normalize(input)) return { mode: 'empty', results: mostUsed(catalog, usage).slice(0, limit), confident: false };

    var trimmed = String(input).trim();
    if (trimmed.charAt(trimmed.length - 1) === '?' || trimmed.charAt(0) === '?') return askDecision(trimmed, true);

    var tokens = stripLeadingFiller(rawTokens);
    var whole = normalize(tokens.join(''));

    var ranked = rank(whole, catalog, usage);
    if (ranked.length && ranked[0].band === BAND.exact) {
      return { mode: 'open', results: ranked.slice(0, limit), confident: true };
    }

    if (tokens.length >= 2) {
      var maxHead = Math.min(2, tokens.length - 1);
      for (var k = maxHead; k >= 1; k--) {
        var head = normalize(tokens.slice(0, k).join(''));
        var e = exactEntryWithSearch(head, catalog);
        if (e) {
          return {
            mode: 'search',
            query: tokens.slice(k).join(' '),
            results: [{ entry: e, band: BAND.exact, quality: 1, usage: usage[e.name] || 0 }],
            confident: true
          };
        }
      }
    }

    // The same, the other way round, for tools only: "10 min timer".
    if (tokens.length >= 2) {
      var maxTail = Math.min(2, tokens.length - 1);
      for (var t = maxTail; t >= 1; t--) {
        var tail = normalize(tokens.slice(tokens.length - t).join(''));
        var tool = exactEntryWithSearch(tail, catalog, true);
        if (tool) {
          return {
            mode: 'search',
            query: tokens.slice(0, tokens.length - t).join(' '),
            results: [{ entry: tool, band: BAND.exact, quality: 1, usage: usage[tool.name] || 0 }],
            confident: true
          };
        }
      }
    }

    // "play beabadoobee": "play" is a filler word, so "play me some youtube" still opens YouTube. Only when what
    // follows is not strongly one of his things does it go to the music tool, before it could be read as a question.
    if (rawTokens.length >= 2 && normalize(rawTokens[0]) === 'play' && tokens.length < rawTokens.length) {
      var music = catalog.filter(function (e) { return e.kind === 'tool' && e.target === 'music' && e.takesWords === true; })[0];
      if (music && !(ranked.length && ranked[0].band >= STRONG_FROM)) {
        return {
          mode: 'search',
          query: tokens.join(' '),
          results: [{ entry: music, band: BAND.exact, quality: 1, usage: usage[music.name] || 0 }],
          confident: true
        };
      }
    }

    // It starts like a question and is more than one word: ask.
    if (tokens.length >= 2 && QUESTION_WORDS.indexOf(normalize(tokens[0])) >= 0) {
      return askDecision(tokens.join(' '), true);
    }

    if (ranked.length && ranked[0].band >= STRONG_FROM) {
      return { mode: 'open', results: ranked.slice(0, limit), confident: true };
    }

    for (var n = tokens.length - 1; n >= 1; n--) {
      var partial = rank(normalize(tokens.slice(0, n).join('')), catalog, usage);
      if (partial.length && partial[0].band >= STRONG_FROM) {
        return { mode: 'open', results: partial.slice(0, limit), confident: true };
      }
    }

    if (ranked.length) return { mode: 'open', results: ranked.slice(0, limit), confident: false };
    if (tokens.length >= 2) return askDecision(tokens.join(' '), false);
    return { mode: 'none', results: [], confident: false };
  }

  // ---------------------------------------------------------- action plan ----

  /** Turn a match decision into a plain description of what the shell should do. */
  function plan(decision) {
    if (decision && decision.mode === 'ask') return decision.query ? { type: 'ask', question: decision.query } : null;
    if (!decision || !decision.results.length || decision.mode === 'empty' || decision.mode === 'none') return null;
    var e = decision.results[0].entry;
    if (decision.mode === 'search' && e.kind === 'tool') {
      return { type: 'openTool', tool: e.target, argument: decision.query, entry: e.name };
    }
    if (decision.mode === 'search') {
      return {
        type: 'openURL',
        url: e.searchTemplate.replace('{q}', encodeQuery(decision.query)),
        profile: e.profile || 'personal',
        entry: e.name
      };
    }
    if (e.kind === 'site') return { type: 'openURL', url: e.target, profile: e.profile || 'personal', entry: e.name };
    if (e.kind === 'app') return { type: 'openApp', bundleID: e.target, entry: e.name };
    if (e.kind === 'path') return { type: 'openPath', path: e.target, entry: e.name };
    if (e.kind === 'tool') return { type: 'openTool', tool: e.target, entry: e.name };
    return null;
  }

  // --------------------------------------------------------------- stash ----

  var DAY_MS = 24 * 60 * 60 * 1000;
  var FRESH_DAYS = 14;
  var SKIP_LIMIT = 3;

  /**
   * Stash state is plain data so it can be saved as JSON as-is:
   *   { items: [...], lastBucket: "fresh" | "old" | null, currentID: string | null }
   * Item: { id, kind, payload, title, source, savedAt, servedAt, openedAt, skippedCount }
   * All times are milliseconds since epoch.
   */
  function newStash() { return { items: [], lastBucket: null, currentID: null }; }

  function addItem(stash, item, now) {
    var payload = String(item.payload || '').trim();
    if (!payload) return null;
    // Saving the same thing twice just refreshes it instead of duplicating.
    for (var i = 0; i < stash.items.length; i++) {
      var it = stash.items[i];
      if (it.payload === payload && it.kind === (item.kind || 'url')) {
        it.savedAt = now; it.openedAt = null; it.skippedCount = 0;
        return it;
      }
    }
    var created = {
      id: item.id || ('s' + now + '-' + stash.items.length),
      kind: item.kind || 'url',
      payload: payload,
      title: item.title || null,
      source: item.source || 'drop',
      savedAt: now,
      servedAt: null,
      openedAt: null,
      skippedCount: 0
    };
    stash.items.push(created);
    return created;
  }

  function byAgeThenID(a, b) {
    if (a.savedAt !== b.savedAt) return a.savedAt - b.savedAt;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  }

  /**
   * Serve one item. Consumes exactly ONE rng() value when it serves something,
   * zero when the stash has nothing to give.
   *  - never serves an opened item
   *  - items skipped SKIP_LIMIT+ times only come back when nothing else is left
   *  - alternates fresh (< 14 days) and old buckets, starting with fresh
   */
  function serve(stash, now, rng, excludeID) {
    var pool = stash.items.filter(function (it) { return !it.openedAt; });
    if (excludeID && pool.length > 1) pool = pool.filter(function (it) { return it.id !== excludeID; });
    if (!pool.length) { stash.currentID = null; return null; }

    var keen = pool.filter(function (it) { return it.skippedCount < SKIP_LIMIT; });
    if (keen.length) pool = keen;

    var fresh = pool.filter(function (it) { return now - it.savedAt < FRESH_DAYS * DAY_MS; }).sort(byAgeThenID);
    var old = pool.filter(function (it) { return now - it.savedAt >= FRESH_DAYS * DAY_MS; }).sort(byAgeThenID);

    var want = stash.lastBucket === 'fresh' ? 'old' : 'fresh';
    var bucket = want === 'fresh' ? fresh : old;
    if (!bucket.length) { want = want === 'fresh' ? 'old' : 'fresh'; bucket = want === 'fresh' ? fresh : old; }

    var r = rng();
    var idx = Math.min(bucket.length - 1, Math.floor(r * bucket.length));
    var item = bucket[idx];
    item.servedAt = now;
    item.openedAt = now;
    stash.lastBucket = want;
    stash.currentID = item.id;
    return item;
  }

  /** "Another": un-open the current item, count the skip, serve the next one. */
  function another(stash, now, rng) {
    var cur = null;
    for (var i = 0; i < stash.items.length; i++) if (stash.items[i].id === stash.currentID) cur = stash.items[i];
    if (cur) { cur.openedAt = null; cur.skippedCount += 1; }
    return serve(stash, now, rng, cur ? cur.id : null);
  }

  function remaining(stash) {
    return stash.items.filter(function (it) { return !it.openedAt; }).length;
  }

  // --------------------------------------------------------------- lines ----

  var HISTORY = 5;
  var TARGET_BIAS = 0.6;

  /**
   * bank:  { "open_site": [{id, text}], "target:youtube": [...], ... }
   * state: { history: { category: [ids] } }   (persisted between picks)
   *
   * Consumes rng() in a FIXED order so ports stay in lockstep:
   *   1. only when a target pool exists: one value to choose target vs generic
   *   2. one value to choose the line
   *   3. one value to decide whether it is spoken
   * Returns { id, text, speak } or null when the bank has nothing for it.
   */
  function pickLine(bank, state, category, target, frequency, rng) {
    var generic = bank[category] || [];
    var targeted = target ? (bank['target:' + target] || []) : [];
    var pool = generic, key = category;
    if (targeted.length) {
      var useTarget = rng() < TARGET_BIAS || !generic.length;
      if (useTarget) { pool = targeted; key = 'target:' + target; }
    }
    if (!pool.length) return null;

    state.history = state.history || {};
    var hist = state.history[key] || [];
    var open = pool.filter(function (l) { return hist.indexOf(l.id) < 0; });
    if (!open.length) { hist = []; open = pool.slice(); }

    var r = rng();
    var line = open[Math.min(open.length - 1, Math.floor(r * open.length))];
    // Remember the last few lines so he never hears the same one back to back.
    // Never remember so many that the pool runs dry.
    var keep = Math.max(0, Math.min(HISTORY, pool.length - 1));
    hist = hist.concat([line.id]);
    hist = keep === 0 ? [] : hist.slice(Math.max(0, hist.length - keep));
    state.history[key] = hist;

    var speak = rng() < frequency;
    return { id: line.id, text: line.text, speak: speak };
  }

  // ----------------------------------------------------------------- ask ----

  var ASK_RULES = [
    'You are answering inside a tiny panel at the top of a Mac screen.',
    'Reply in at most three short sentences of plain English. No preamble, no markdown, no lists.',
    'The reader is a self-taught builder who is new to coding, so avoid jargon or explain it in passing.',
    'If the best answer is a command or a line of code, give one sentence first, then put the command alone on the last line, starting with "$ ".',
    'If you are not sure, say so in one sentence. If it needs information from today and you cannot look it up, say that plainly instead of guessing.'
  ].join(' ');
  var MAX_CLIP = 6000;

  /** Does the question point at something he copied? "what does this mean", "explain this". */
  function wantsClipboard(question) {
    return words(question).some(function (w) { return w === 'this' || w === 'these'; });
  }

  /** The two texts sent to the model. `clip` is whatever he copied, used only when the question points at it. */
  function buildAsk(question, clip) {
    var q = String(question || '').trim();
    var user = q;
    if (clip && wantsClipboard(q)) {
      var c = String(clip);
      var cut = c.length > MAX_CLIP;
      user = q + '\n\nHere is what I copied' + (cut ? ' (cut short)' : '') + ':\n' + c.slice(0, MAX_CLIP);
    }
    return { system: ASK_RULES, user: user };
  }

  /** Split an answer into the part to read and, when the last line starts with "$ ", a command to copy. */
  function shapeAnswer(text) {
    var lines = String(text || '').replace(/\r/g, '').split('\n').map(function (l) { return l.trim(); }).filter(Boolean);
    var command = null;
    if (lines.length && lines[lines.length - 1].indexOf('$ ') === 0) command = lines.pop().slice(2).trim();
    return { text: lines.join(' '), command: command || null };
  }

  // ------------------------------------------------------------ feedback ----

  // What he hears and feels for each thing that happens. Sounds are files in Resources/sounds.
  // Haptics are the Mac trackpad's three kinds; they are only felt while a finger rests on the trackpad.
  var FEEDBACK = {
    open:          { sound: 'open',   haptic: 'alignment' },
    close:         { sound: 'close',  haptic: null },
    opened:        { sound: null,     haptic: null },          // the thing opening is its own feedback
    saved:         { sound: 'save',   haptic: 'levelChange' },
    captured:      { sound: 'save',   haptic: 'levelChange' },
    bookmarkMoved: { sound: 'save',   haptic: 'levelChange' },
    pulled:        { sound: 'pull',   haptic: null },
    another:       { sound: 'pull',   haptic: null },
    unknown:       { sound: 'nope',   haptic: 'generic' },
    answer:        { sound: 'answer', haptic: null },
    tunerLock:     { sound: 'lock',   haptic: 'alignment' },
    allInTune:     { sound: 'done',   haptic: 'generic' },
    timerDone:     { sound: 'done',   haptic: 'generic' }
  };

  // -------------------------------------------------------------- export ----

  var api = {
    normalize: normalize, words: words, editDistance: editDistance, subsequenceSpan: subsequenceSpan,
    encodeQuery: encodeQuery, BAND: BAND, bandName: bandName, scoreKey: scoreKey, rank: rank,
    match: match, plan: plan, FILLER: FILLER, QUESTION_WORDS: QUESTION_WORDS,
    newStash: newStash, addItem: addItem, serve: serve, another: another, remaining: remaining,
    FRESH_DAYS: FRESH_DAYS, SKIP_LIMIT: SKIP_LIMIT, DAY_MS: DAY_MS,
    pickLine: pickLine, FEEDBACK: FEEDBACK,
    ASK_RULES: ASK_RULES, wantsClipboard: wantsClipboard, buildAsk: buildAsk, shapeAnswer: shapeAnswer
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereCore = api;
})(typeof self !== 'undefined' ? self : this);
