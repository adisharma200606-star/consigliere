'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const jobs = require('./jobs.js');
const smart = require('./smart.js');
const defaults = require('../defaults/catalog.json');

const NOW = Date.UTC(2026, 10, 15, 10, 0);
const GROUPS = ['work', 'general'];
const CATALOG = defaults.concat([
  { name: 'gmail', aliases: [], kind: 'site', target: 'https://mail.google.com', profile: 'personal' },
  { name: 'GMAIL', aliases: [], kind: 'site', target: 'https://mail.google.com', profile: 'work' }  // a repeat
]);

/** Four jobs: one fully placed by the rules (read: books, typed into work), three that need help. */
function sampleDay() {
  const day = jobs.newDay('2026-11-15');
  jobs.addJobs(day, jobs.parseJobs('work: read 30 min, email the landlord, call dad, general: practice guitar', NOW, CATALOG, {}, GROUPS), NOW);
  return day;
}

// [reply text, expected suggestions]
const REPLY_CASES = [
  ['{"jobs":[{"id":"j2","opens":"Gmail","folder":"work"},{"id":"j3","opens":null,"folder":"general"}]}',
    [{ id: 'j2', starter: 'gmail', group: 'work' }, { id: 'j3', starter: null, group: 'general' }]],
  // a made-up app and a made-up folder are thrown away; a job not asked about is ignored; a repeat counts once
  ['{"jobs":[{"id":"j2","opens":"Outlook","folder":"errands"},{"id":"j1","opens":"youtube","folder":"work"},{"id":"j3","opens":"spotify","folder":null},{"id":"j3","opens":"gmail","folder":"work"}]}',
    [{ id: 'j3', starter: 'spotify', group: null }]],
  ['{"jobs":[{"id":"j4","opens":"timer","folder":"general"}]}', [{ id: 'j4', starter: null, group: 'general' }]],  // tools never start a job
  ['not json at all', []],
  ['{"answer":"j2 is gmail"}', []],
  ['{"jobs":[{"id":5,"opens":"gmail"}]}', []]
];

test('smart: only jobs that still need something are sent', () => {
  const day = sampleDay();
  assert.deepStrictEqual(smart.needingHelp(day, ['j1', 'j2', 'j3', 'j4'], GROUPS).map(j => j.id), ['j2', 'j3', 'j4']);
  assert.deepStrictEqual(smart.needingHelp(day, ['j1', 'j2', 'j3', 'j4'], []).map(j => j.id), ['j2', 'j3', 'j4'],
    'with no folders, a job with no starter still asks');
  jobs.finish(day, 'j2', NOW);
  assert.deepStrictEqual(smart.needingHelp(day, ['j2', 'j3'], GROUPS).map(j => j.id), ['j3'], 'done jobs are left alone');
  assert.deepStrictEqual(smart.needingHelp(day, ['j1'], GROUPS), [], 'read is placed already: nothing to send');
});

test('smart: the words sent', () => {
  const day = sampleDay();
  const prompt = smart.buildPrompt(smart.needingHelp(day, ['j2', 'j3'], GROUPS), CATALOG, GROUPS);
  assert.strictEqual(prompt.system, smart.RULES);
  const lines = prompt.user.split('\n');
  assert.strictEqual(lines[0], 'Things to open:');
  assert.ok(lines[1].includes('gmail') && !lines[1].includes('GMAIL'), 'each name once');
  assert.ok(!lines[1].split(', ').includes('timer'), 'no tools');
  assert.deepStrictEqual(lines.slice(2), ['', 'Folders:', 'work, general', '', 'Jobs:', 'j2: email the landlord', 'j3: call dad']);
  assert.ok(!prompt.user.includes('https://'), 'no addresses leave the Mac');
  assert.ok(smart.buildPrompt([], CATALOG, []).user.includes('(none, so folder is always null)'));
});

test('smart: reading the reply', () => {
  for (const [text, expected] of REPLY_CASES) {
    assert.deepStrictEqual(smart.readReply(text, ['j2', 'j3', 'j4'], CATALOG, GROUPS), expected, text);
  }
});

test('write smart fixtures', () => {
  const day = sampleDay();
  const asked = smart.needingHelp(day, ['j1', 'j2', 'j3', 'j4'], GROUPS);
  fs.writeFileSync(path.join(__dirname, '..', 'fixtures', 'smart.json'), JSON.stringify({
    rules: smart.RULES,
    schema: smart.SCHEMA,
    groups: GROUPS,
    catalog: CATALOG,
    day: day,
    askedIDs: asked.map(j => j.id),
    noGroupsAskedIDs: smart.needingHelp(day, ['j1', 'j2', 'j3', 'j4'], []).map(j => j.id),
    candidates: smart.candidates(CATALOG),
    prompt: smart.buildPrompt(asked, CATALOG, GROUPS),
    noGroupsPrompt: smart.buildPrompt(asked, CATALOG, []),
    replies: REPLY_CASES.map(([text]) => ({ text, suggestions: smart.readReply(text, ['j2', 'j3', 'j4'], CATALOG, GROUPS) }))
  }, null, 2));
});
