'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const core = require('./core.js');
const catalog = require('../defaults/catalog.json');

// Scripted randomness: tests and fixtures hand the code an explicit list of
// numbers, so the JS reference and the Swift port consume identical values.
function scripted(values) {
  let i = 0;
  const fn = () => { if (i >= values.length) throw new Error('rng exhausted'); return values[i++]; };
  fn.used = () => i;
  return fn;
}

// ------------------------------------------------------------------ matcher

// [input, expected mode, expected top entry (or null), expected search query, usage, confident]
const MATCH_CASES = [
  // typed: exact names and aliases
  ['yt', 'open', 'youtube', null, {}, true],
  ['YT', 'open', 'youtube', null, {}, true],
  ['youtube', 'open', 'youtube', null, {}, true],
  ['you tube', 'open', 'youtube', null, {}, true],
  ['You-Tube!', 'open', 'youtube', null, {}, true],
  ['ytm', 'open', 'youtube music', null, {}, true],
  ['youtube music', 'open', 'youtube music', null, {}, true],
  ['g', 'open', 'google', null, {}, true],
  ['gmail', 'open', 'gmail', null, {}, true],
  ['mail', 'open', 'gmail', null, {}, true],
  ['gh', 'open', 'github', null, {}, true],
  ['li', 'open', 'linkedin', null, {}, true],
  ['claude', 'open', 'claude', null, {}, true],
  ['wa', 'open', 'whatsapp', null, {}, true],
  ['steam', 'open', 'steam', null, {}, true],
  ['code', 'open', 'vs code', null, {}, true],
  ['vs code', 'open', 'vs code', null, {}, true],
  ['vscode', 'open', 'vs code', null, {}, true],
  ['visual studio code', 'open', 'vs code', null, {}, true],
  ['dl', 'open', 'downloads', null, {}, true],
  ['desktop', 'open', 'desktop', null, {}, true],

  // typed: lazy prefixes
  ['y', 'open', 'youtube', null, {}, true],
  ['you', 'open', 'youtube', null, {}, true],
  ['gm', 'open', 'gmail', null, {}, true],
  ['git', 'open', 'github', null, {}, true],
  ['link', 'open', 'linkedin', null, {}, true],
  ['cl', 'open', 'claude', null, {}, true],
  ['whats', 'open', 'whatsapp', null, {}, true],
  ['spot', 'open', 'spotify', null, {}, true],
  ['vsc', 'open', 'vs code', null, {}, true],
  ['visual', 'open', 'vs code', null, {}, true],
  ['down', 'open', 'downloads', null, {}, true],
  ['desk', 'open', 'desktop', null, {}, true],
  ['d', 'open', 'downloads', null, {}, true],

  // typed: a later word, skipped letters
  ['lofi music', 'search', 'music', 'lofi', {}, true],
  ['studio', 'open', 'vs code', null, {}, true],
  ['stm', 'open', 'steam', null, {}, false],
  ['ytb', 'open', 'youtube', null, {}, false],
  ['linkdin', 'open', 'linkedin', null, {}, false],

  // the thing you open most wins inside the same match quality
  ['s', 'open', 'steam', null, { steam: 1 }, true],
  ['s', 'open', 'spotify', null, { spotify: 3 }, true],
  ['c', 'open', 'vs code', null, {}, true],
  ['c', 'open', 'claude', null, { claude: 5 }, true],
  ['g', 'open', 'google', null, { gmail: 99 }, true], // exact alias still beats a popular prefix

  // built-in tools are just more names in the catalog
  ['tune', 'open', 'tuner', null, {}, true],
  ['tuner', 'open', 'tuner', null, {}, true],
  ['guitar tuner', 'open', 'tuner', null, {}, true],
  ['uke', 'open', 'tuner', null, {}, true],
  ['open the tuner', 'open', 'tuner', null, {}, true],

  // a tool that takes words: the timer
  ['timer', 'open', 'timer', null, {}, true],
  ['timer 10', 'search', 'timer', '10', {}, true],
  ['countdown 1:30', 'search', 'timer', '1:30', {}, true],
  ['set a timer for 10 minutes', 'search', 'timer', 'for 10 minutes', {}, true],
  ['10 min timer', 'search', 'timer', '10 min', {}, true],
  ['ti', 'open', 'timer', null, {}, true],
  ['tu', 'open', 'tuner', null, {}, true],

  ['one eighty', 'open', 'flip', null, {}, true],
  ['180', 'open', 'flip', null, {}, true],
  ['flip', 'open', 'flip', null, {}, true],
  ['rotate', 'open', 'flip', null, {}, true],
  ['help', 'open', 'help', null, {}, true],
  ['tutorial', 'open', 'help', null, {}, true],
  ['bored', 'open', 'bored', null, {}, true],
  ["i'm bored", 'open', 'bored', null, {}, true],
  ['settings', 'open', 'settings', null, {}, true],
  ['preferences', 'open', 'settings', null, {}, true],

  // capturing: a note or a reminder is a tool that takes words
  ['note', 'open', 'note', null, {}, true],
  ['new note', 'open', 'note', null, {}, true],
  ['note buy new strings', 'search', 'note', 'buy new strings', {}, true],
  ['remind me to call mom tomorrow at 5', 'search', 'reminder', 'to call mom tomorrow at 5', {}, true],
  ['todo finish the report', 'search', 'reminder', 'finish the report', {}, true],
  ['reminder', 'open', 'reminder', null, {}, true],

  // jobs, the diary, and being left alone
  ['jobs', 'open', 'jobs', null, {}, true],
  ['jobs read 30 min, duolingo by 10pm', 'search', 'jobs', 'read 30 min, duolingo by 10pm', {}, true],
  ['today call dad', 'search', 'jobs', 'call dad', {}, true],
  ['done read', 'search', 'done', 'read', {}, true],
  ['diary long day, good one', 'search', 'diary', 'long day, good one', {}, true],
  ['hush', 'open', 'quiet', null, {}, true],
  ['read', 'open', 'books', null, {}, true],

  // music: "play" is still a filler word in front of his own things, and only goes to music otherwise
  ['play beabadoobee', 'search', 'music', 'beabadoobee', {}, true],
  ['play some arctic monkeys', 'search', 'music', 'arctic monkeys', {}, true],
  ['play what is love', 'search', 'music', 'what is love', {}, true],
  ['play spotify', 'open', 'spotify', null, {}, true],
  ['music beabadoobee', 'search', 'music', 'beabadoobee', {}, true],
  ['music', 'open', 'music', null, {}, true],
  ['pause', 'open', 'pause', null, {}, true],
  ['next', 'open', 'next song', null, {}, true],
  ['skip', 'open', 'next song', null, {}, true],
  ['volume up', 'open', 'louder', null, {}, true],
  ['volume 30', 'search', 'volume', '30', {}, true],

  // the dragon
  ['pet', 'open', 'pet', null, {}, true],
  ['dragonite', 'open', 'pet', null, {}, true],
  ['come here', 'open', 'pet', null, {}, true],
  ['go home', 'open', 'go home', null, {}, true],
  ['go back', 'open', 'go home', null, {}, true],
  ['scram', 'open', 'go home', null, {}, true],
  ['bye', 'open', 'go home', null, {}, true],

  // asking: a question mark, a question word, or several words that match nothing
  ['how do i undo a git commit?', 'ask', null, 'how do i undo a git commit?', {}, true],
  ['what is a closure', 'ask', null, 'what is a closure', {}, true],
  ['how to tune a guitar', 'ask', null, 'how to tune a guitar', {}, true],
  ['explain this', 'ask', null, 'explain this', {}, true],
  ["what's a pull request", 'ask', null, "what's a pull request", {}, true],
  ['why is my build failing', 'ask', null, 'why is my build failing', {}, true],
  ['hey tell me who won the 2022 world cup', 'ask', null, 'tell me who won the 2022 world cup', {}, true],
  ['youtube?', 'ask', null, 'youtube?', {}, true],
  ['? capital of italy', 'ask', null, 'capital of italy', {}, true],
  ['capital of italy', 'ask', null, 'capital of italy', {}, false],
  ['g how to tune a guitar', 'search', 'google', 'how to tune a guitar', {}, true], // naming a site still wins
  ["what's app", 'open', 'whatsapp', null, {}, true],                               // an exact name still wins

  // nothing
  ['', 'empty', null, null, {}, false],
  ['    ', 'empty', null, null, {}, false],
  ['!!!', 'empty', null, null, {}, false],
  ['zzz', 'none', null, null, {}, false],
  ['xbox', 'none', null, null, {}, false],
  ['clod', 'none', null, null, {}, false],

  // site name then what you want = search on that site
  ['yt berserk amv', 'search', 'youtube', 'berserk amv', {}, true],
  ['youtube lofi', 'search', 'youtube', 'lofi', {}, true],
  ['you tube lofi beats', 'search', 'youtube', 'lofi beats', {}, true],
  ['google weather bengaluru', 'search', 'google', 'weather bengaluru', {}, true],
  ['gh dynamicnotchkit', 'search', 'github', 'dynamicnotchkit', {}, true],
  ['open yt arctic monkeys 505', 'search', 'youtube', 'arctic monkeys 505', {}, true],

  // filler words and trailing noise, typed or spoken
  ['open youtube', 'open', 'youtube', null, {}, true],
  ['play me some youtube', 'open', 'youtube', null, {}, true],
  ['consigliere open steam', 'open', 'steam', null, {}, true],
  ['go to gmail', 'open', 'gmail', null, {}, true],
  ['gmail inbox', 'open', 'gmail', null, {}, true],
  ['downloads folder', 'open', 'downloads', null, {}, true],
  ['open the downloads folder', 'open', 'downloads', null, {}, true],
  ['open', 'none', null, null, {}, false], // only filler: nothing to open, but no crash

  // speech mishearings
  ['g mail', 'open', 'gmail', null, {}, true],
  ['linked in', 'open', 'linkedin', null, {}, true],
  ['you to', 'open', 'youtube', null, {}, true],
  ['youto', 'open', 'youtube', null, {}, false],
  ['youtwo', 'open', 'youtube', null, {}, false],
  ['utube', 'open', 'youtube', null, {}, false],
  ['spotifi', 'open', 'spotify', null, {}, false],
  ['get hub', 'open', 'github', null, {}, false],
  ['steem', 'open', 'steam', null, {}, false],
  ['cloud', 'open', 'claude', null, {}, false]
];

test('matcher: every hand-written case', () => {
  for (const [input, mode, top, query, usage, confident] of MATCH_CASES) {
    const m = core.match(input, catalog, usage);
    const label = JSON.stringify(input) + ' usage=' + JSON.stringify(usage);
    assert.strictEqual(m.mode, mode, 'mode for ' + label);
    if (mode === 'open' || mode === 'search') assert.strictEqual(m.results[0].entry.name, top, 'top for ' + label);
    if (mode === 'none') assert.strictEqual(m.results.length, 0, 'no results for ' + label);
    if (mode === 'search' || mode === 'ask') assert.strictEqual(m.query, query, 'query for ' + label);
    if (mode === 'ask') assert.strictEqual(m.results.length, 0, 'ask has no rows for ' + label);
    assert.strictEqual(m.confident, confident, 'confident for ' + label);
    assert.ok(m.results.length <= 4, 'at most 4 results for ' + label);
  }
  assert.ok(MATCH_CASES.length >= 60);
});

test('matcher: empty input lists the most used things', () => {
  const m = core.match('', catalog, { steam: 9, gmail: 4 });
  assert.deepStrictEqual(m.results.map(r => r.entry.name), ['steam', 'gmail', 'youtube', 'youtube music']);
});

test('plan: sites, apps, paths and searches', () => {
  assert.deepStrictEqual(core.plan(core.match('yt', catalog)), {
    type: 'openURL', url: 'https://www.youtube.com', profile: 'personal', entry: 'youtube' });
  assert.deepStrictEqual(core.plan(core.match('steam', catalog)), {
    type: 'openApp', bundleID: 'com.valvesoftware.steam', entry: 'steam' });
  assert.deepStrictEqual(core.plan(core.match('dl', catalog)), {
    type: 'openPath', path: '~/Downloads', entry: 'downloads' });
  assert.strictEqual(core.plan(core.match('yt berserk & guts: 1997 ost', catalog)).url,
    'https://www.youtube.com/results?search_query=berserk%20%26%20guts%3A%201997%20ost');
  assert.strictEqual(core.plan(core.match('g café ☕', catalog)).url,
    'https://www.google.com/search?q=caf%C3%A9%20%E2%98%95');
  assert.deepStrictEqual(core.plan(core.match('tune', catalog)), { type: 'openTool', tool: 'tuner', entry: 'tuner' });
  assert.deepStrictEqual(core.plan(core.match('timer 10', catalog)), { type: 'openTool', tool: 'timer', argument: '10', entry: 'timer' });
  assert.strictEqual(core.plan(core.match('zzz', catalog)), null);
  assert.strictEqual(core.plan(core.match('', catalog)), null);
});


test('ask: what gets sent, and how the answer is split', () => {
  assert.deepStrictEqual(core.plan(core.match('what is a closure', catalog)), { type: 'ask', question: 'what is a closure' });
  assert.strictEqual(core.plan(core.match('?', catalog)), null, 'a lone question mark asks nothing');
  assert.strictEqual(core.wantsClipboard('what does this mean'), true);
  assert.strictEqual(core.wantsClipboard('what is a thistle'), false);
  assert.strictEqual(core.buildAsk('what is a closure', 'IGNORED').user, 'what is a closure');
  const withClip = core.buildAsk('explain this', 'TypeError: x is not a function');
  assert.strictEqual(withClip.user, 'explain this\n\nHere is what I copied:\nTypeError: x is not a function');
  assert.ok(withClip.system.includes('three short sentences'));
  const long = core.buildAsk('explain this', 'a'.repeat(7000));
  assert.ok(long.user.includes('(cut short)'));
  assert.strictEqual(long.user.length, 'explain this\n\nHere is what I copied (cut short):\n'.length + 6000);
  assert.deepStrictEqual(core.shapeAnswer('It moves your last commit back to your working files.\n\n$ git reset --soft HEAD~1\n'),
    { text: 'It moves your last commit back to your working files.', command: 'git reset --soft HEAD~1' });
  assert.deepStrictEqual(core.shapeAnswer('Rome.'), { text: 'Rome.', command: null });
  assert.deepStrictEqual(core.shapeAnswer(''), { text: '', command: null });
});

// -------------------------------------------------------------------- stash

const T0 = Date.UTC(2026, 8, 19, 12, 0, 0);
const DAY = core.DAY_MS;

function seededStash() {
  const s = core.newStash();
  core.addItem(s, { id: 'old1', payload: 'https://example.com/old1' }, T0 - 120 * DAY);
  core.addItem(s, { id: 'old2', payload: 'https://example.com/old2' }, T0 - 40 * DAY);
  core.addItem(s, { id: 'new1', payload: 'https://example.com/new1' }, T0 - 3 * DAY);
  core.addItem(s, { id: 'new2', payload: 'https://example.com/new2' }, T0 - 1 * DAY);
  return s;
}

test('stash: alternates fresh and old, never repeats an opened item', () => {
  const s = seededStash();
  const rng = scripted([0, 0, 0, 0]);
  const order = [];
  for (let i = 0; i < 4; i++) order.push(core.serve(s, T0 + i, rng).id);
  assert.deepStrictEqual(order, ['new1', 'old1', 'new2', 'old2']);
  assert.strictEqual(core.serve(s, T0 + 10, rng), null);
  assert.strictEqual(rng.used(), 4, 'an empty serve must not consume randomness');
  assert.strictEqual(core.remaining(s), 0);
});

test('stash: rng picks inside the bucket', () => {
  const s = seededStash();
  assert.strictEqual(core.serve(s, T0, scripted([0.99])).id, 'new2');
});

test('stash: "another" un-opens, counts the skip, and moves on', () => {
  const s = seededStash();
  const rng = scripted([0, 0]);
  const first = core.serve(s, T0, rng);
  const second = core.another(s, T0 + 1, rng);
  assert.notStrictEqual(second.id, first.id);
  const firstAgain = s.items.find(i => i.id === first.id);
  assert.strictEqual(firstAgain.openedAt, null);
  assert.strictEqual(firstAgain.skippedCount, 1);
});

test('stash: "another" with a single item serves that item again rather than nothing', () => {
  const s = core.newStash();
  core.addItem(s, { id: 'only', payload: 'https://example.com/only' }, T0);
  const rng = scripted([0, 0]);
  core.serve(s, T0, rng);
  assert.strictEqual(core.another(s, T0 + 1, rng).id, 'only');
});

test('stash: things skipped three times go to the back', () => {
  const s = core.newStash();
  core.addItem(s, { id: 'meh', payload: 'https://example.com/meh' }, T0 - DAY);
  core.addItem(s, { id: 'good', payload: 'https://example.com/good' }, T0 - 2 * DAY);
  s.items[0].skippedCount = 3;
  assert.strictEqual(core.serve(s, T0, scripted([0.99])).id, 'good');
  assert.strictEqual(core.serve(s, T0 + 1, scripted([0])).id, 'meh');
});

test('stash: saving the same thing twice refreshes it', () => {
  const s = core.newStash();
  core.addItem(s, { id: 'a', payload: 'https://example.com/a' }, T0 - 50 * DAY);
  core.serve(s, T0 - 49 * DAY, scripted([0]));
  core.addItem(s, { payload: '  https://example.com/a ' }, T0);
  assert.strictEqual(s.items.length, 1);
  assert.strictEqual(s.items[0].openedAt, null);
  assert.strictEqual(s.items[0].savedAt, T0);
  assert.strictEqual(core.addItem(s, { payload: '   ' }, T0), null);
});

// -------------------------------------------------------------------- lines

const BANK = {
  open_site: [1, 2, 3, 4, 5, 6, 7, 8].map(n => ({ id: 'os' + n, text: 'generic ' + n })),
  'target:youtube': [1, 2, 3].map(n => ({ id: 'yt' + n, text: 'youtube ' + n })),
  saved: [{ id: 'sv1', text: 'only one' }]
};

test('lines: never repeats within the last five', () => {
  const state = {};
  const seen = [];
  for (let i = 0; i < 40; i++) {
    const l = core.pickLine(BANK, state, 'open_site', null, 1, scripted([0, 0]));
    const lastFive = seen.slice(-5);
    assert.ok(!lastFive.includes(l.id), 'repeat of ' + l.id + ' at ' + i);
    seen.push(l.id);
  }
});

test('lines: target lines win 60% of the time and rng order is fixed', () => {
  const a = core.pickLine(BANK, {}, 'open_site', 'youtube', 0.5, scripted([0.59, 0, 0.49]));
  assert.deepStrictEqual(a, { id: 'yt1', text: 'youtube 1', speak: true });
  const b = core.pickLine(BANK, {}, 'open_site', 'youtube', 0.5, scripted([0.6, 0, 0.5]));
  assert.deepStrictEqual(b, { id: 'os1', text: 'generic 1', speak: false });
  const rng = scripted([0, 0.3]);
  core.pickLine(BANK, {}, 'open_site', 'steam', 1, rng);
  assert.strictEqual(rng.used(), 2, 'no target pool means no target roll');
});

test('lines: a pool of one still works, an unknown category gives null', () => {
  const state = {};
  assert.strictEqual(core.pickLine(BANK, state, 'saved', null, 1, scripted([0, 0])).id, 'sv1');
  assert.strictEqual(core.pickLine(BANK, state, 'saved', null, 1, scripted([0, 0])).id, 'sv1');
  assert.strictEqual(core.pickLine(BANK, state, 'nope', null, 1, scripted([])), null);
});

test('lines: frequency 0 never speaks but still returns the text', () => {
  const l = core.pickLine(BANK, {}, 'open_site', null, 0, scripted([0.2, 0]));
  assert.strictEqual(l.speak, false);
  assert.ok(l.text);
});

// ------------------------------------------------------------ golden fixtures
// Written on every passing run. The Swift tests load these files and must
// produce identical output.

test('feedback: every sound it names exists as a file', () => {
  const sounds = path.join(__dirname, '..', 'App', 'Consigliere', 'Resources', 'sounds');
  for (const [event, spec] of Object.entries(core.FEEDBACK)) {
    if (spec.sound) assert.ok(fs.existsSync(path.join(sounds, spec.sound + '.wav')), event + ' -> ' + spec.sound + '.wav is missing');
    assert.ok([null, 'alignment', 'levelChange', 'generic'].includes(spec.haptic), event + ' haptic');
  }
});

test('write golden fixtures', () => {
  const dir = path.join(__dirname, '..', 'fixtures');
  fs.mkdirSync(dir, { recursive: true });

  const matcher = MATCH_CASES.map(([input, , , , usage]) => {
    const m = core.match(input, catalog, usage);
    return {
      input, usage,
      mode: m.mode,
      confident: m.confident,
      query: m.query || null,
      results: m.results.map(r => ({ name: r.entry.name, band: core.bandName(r.band) })),
      plan: core.plan(m)
    };
  });
  const ask = {
    rules: core.ASK_RULES,
    builds: [['what is a closure', 'IGNORED'], ['explain this', 'TypeError: x is not a function'], ['what are these', ''], ['explain this', 'a'.repeat(6500)]]
      .map(([question, clip]) => ({ question, clip, user: core.buildAsk(question, clip).user })),
    answers: ['It moves your last commit back.\n\n$ git reset --soft HEAD~1\n', 'Rome.', '', 'Line one.\r\nLine two.', '$ ls -la']
      .map(text => ({ text, shaped: core.shapeAnswer(text) }))
  };
  fs.writeFileSync(path.join(dir, 'feedback.json'), JSON.stringify(core.FEEDBACK, null, 2));
  fs.writeFileSync(path.join(dir, 'matcher.json'), JSON.stringify({ catalog, cases: matcher, ask }, null, 2));

  // A long scripted session against the stash.
  const s = seededStash();
  core.addItem(s, { id: 'new3', payload: 'https://example.com/new3' }, T0 - 5 * DAY);
  core.addItem(s, { id: 'old3', payload: 'https://example.com/old3' }, T0 - 15 * DAY);
  const initial = JSON.parse(JSON.stringify(s));
  const values = [0.5, 0.1, 0.9, 0.34, 0.0, 0.72, 0.5, 0.99, 0.2, 0.6, 0.45, 0.8];
  const rng = scripted(values);
  const ops = ['serve', 'another', 'another', 'serve', 'serve', 'another', 'serve', 'serve', 'serve', 'serve'];
  const steps = ops.map((op, i) => {
    const item = core[op](s, T0 + (i + 1) * 1000, rng);
    return { op, now: T0 + (i + 1) * 1000, served: item ? item.id : null, rngUsed: rng.used() };
  });
  fs.writeFileSync(path.join(dir, 'stash.json'),
    JSON.stringify({ initial, rngValues: values, steps, final: s }, null, 2));

  const lineValues = [0.1, 0.5, 0.2, 0.7, 0.9, 0.95, 0.3, 0.3, 0.3, 0.61, 0.0, 0.0, 0.2, 0.99, 0.4, 0.05, 0.5, 0.5];
  const lrng = scripted(lineValues);
  const lstate = {};
  const calls = [
    ['open_site', 'youtube', 0.6], ['open_site', 'youtube', 0.6], ['open_site', null, 0.6],
    ['open_site', 'youtube', 0.6], ['saved', null, 1], ['open_site', 'steam', 0.0], ['open_site', 'youtube', 0.6]
  ];
  const picks = calls.map(([category, target, frequency]) => {
    const l = core.pickLine(BANK, lstate, category, target, frequency, lrng);
    return { category, target, frequency, picked: l, rngUsed: lrng.used() };
  });
  fs.writeFileSync(path.join(dir, 'lines.json'),
    JSON.stringify({ bank: BANK, rngValues: lineValues, picks, finalState: lstate }, null, 2));
});
