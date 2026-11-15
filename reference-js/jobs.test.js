'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const jobs = require('./jobs.js');
const defaults = require('../defaults/catalog.json');

// Saturday 11 October 2026, 10:00 on the wall clock.
const at = (h, m, day) => Date.UTC(2026, 9, day || 11, h, m || 0);
const NOW = at(10, 0);
const CATALOG = defaults.concat([
  { name: 'swift course', aliases: [], kind: 'site', target: 'https://learn.example.org/swift/lesson/4', profile: 'personal', living: true }
]);

// [text, bindings, expected drafts as [title, minutes, dueWall, starter]]
const PARSE_CASES = [
  ['read 30 min, swift course, duolingo by 10pm', {}, [
    ['read', 30, null, 'books'], ['swift course', null, null, 'swift course'], ['duolingo', null, at(22, 0), 'duolingo']]],
  ['i need to call dad at 6', {}, [['call dad', null, at(18, 0), null]]],
  ['finish the swift course for an hour', {}, [['finish the swift course', 60, null, 'swift course']]],
  ['read in 20 minutes', {}, [['read', null, at(10, 20), 'books']]],
  ['read 1.5h', {}, [['read', 90, null, 'books']]],
  ['practice guitar half an hour', {}, [['practice guitar', 30, null, null]]],
  ['call mom and dad', {}, [['call mom and dad', null, null, null]]],
  ['gym 45m', { gym: 'youtube' }, [['gym', 45, null, 'youtube']]],
  ['timer stuff', {}, [['timer stuff', null, null, null]]],          // a tool never starts a job
  ['gotta read a chapter\nduolingo', {}, [['read a chapter', null, null, 'books'], ['duolingo', null, null, 'duolingo']]],
  [' , ;  ', {}, []]
];

test('jobs: reading what he typed', () => {
  for (const [text, bindings, expected] of PARSE_CASES) {
    const got = jobs.parseJobs(text, NOW, CATALOG, bindings).map(d => [d.title, d.minutes, d.dueWall, d.starter]);
    assert.deepStrictEqual(got, expected, JSON.stringify(text));
  }
});

test('jobs: clock settings and job days', () => {
  assert.strictEqual(jobs.clockMinutes('09:00'), 540);
  assert.strictEqual(jobs.clockMinutes('0:30'), 30);
  assert.strictEqual(jobs.clockMinutes('24:00'), null);
  assert.strictEqual(jobs.clockMinutes('nine'), null);
  assert.strictEqual(jobs.dayKey(at(10, 0)), '2026-10-11');
  assert.strictEqual(jobs.dayKey(at(1, 30, 12)), '2026-10-11', 'half past one at night is still the day before');
  assert.strictEqual(jobs.dayKey(at(4, 0, 12)), '2026-10-12');
});

test('jobs: the same job twice is one job, and done read finds it', () => {
  const day = jobs.newDay('2026-10-11');
  jobs.addJobs(day, jobs.parseJobs('read 30 min, call dad', NOW, CATALOG), NOW);
  jobs.addJobs(day, jobs.parseJobs('Read 45 min', NOW, CATALOG), NOW);
  assert.strictEqual(day.jobs.length, 2);
  assert.strictEqual(day.jobs[0].minutes, 45);
  assert.strictEqual(jobs.findJob(day, 'read').id, 'j1');
  assert.strictEqual(jobs.findJob(day, 'dad').id, 'j2');
  assert.strictEqual(jobs.findJob(day, 'gym'), null);
  assert.strictEqual(jobs.findJob(day, ''), null);
});

/** Plays a list of steps against one day and records what each step returned. */
function play(steps) {
  const day = jobs.newDay('2026-10-11');
  let last = null, shown = null;   // the last answer, and the last time he actually came out
  const results = [];
  for (const s of steps) {
    let r = null;
    switch (s.op) {
      case 'add': r = jobs.addJobs(day, jobs.parseJobs(s.text, s.at, CATALOG), s.at).map(j => j.id); break;
      case 'nudge': last = jobs.nextNudge(day, s.at, jobs.DEFAULT_SETTINGS, { quiet: !!s.quiet, idleSec: s.idle || 0 }); r = last; break;
      case 'appeared': shown = last; jobs.appeared(day, shown, s.at); break;
      case 'ignored': jobs.ignored(day, shown); break;
      case 'start': jobs.start(day, s.id, s.at); break;
      case 'finish': jobs.finish(day, s.id, s.at); break;
      case 'skip': jobs.skip(day, s.id); break;
      case 'later': jobs.later(day, s.id, s.at, jobs.DEFAULT_SETTINGS); break;
      case 'sleepLater': jobs.sleepLater(day, s.at, 10); break;
      case 'closeBooks': jobs.closeBooks(day); break;
      default: throw new Error('unknown step ' + s.op);
    }
    results.push(r);
  }
  return { day, results };
}

const STEPS = [
  { op: 'add', text: 'read 30 min, swift course, duolingo by 10pm', at: at(10, 0) },
  { op: 'nudge', at: at(8, 30) },
  { op: 'nudge', at: at(10, 0) }, { op: 'appeared', at: at(10, 0) },
  { op: 'nudge', at: at(10, 20) },
  { op: 'ignored' },
  { op: 'nudge', at: at(10, 45) }, { op: 'appeared', at: at(10, 45) },
  { op: 'nudge', at: at(11, 30) }, { op: 'appeared', at: at(11, 30) },
  { op: 'start', id: 'j1', at: at(11, 31) },
  { op: 'nudge', at: at(12, 20) }, { op: 'appeared', at: at(12, 20) },
  { op: 'finish', id: 'j1', at: at(12, 21) },
  { op: 'later', id: 'j2', at: at(12, 22) },
  { op: 'nudge', at: at(13, 10) }, { op: 'appeared', at: at(13, 10) },
  { op: 'nudge', at: at(14, 0), quiet: true },
  { op: 'nudge', at: at(14, 0), idle: 600 },
  { op: 'nudge', at: at(22, 0) }, { op: 'appeared', at: at(22, 0) },
  { op: 'nudge', at: at(22, 5) },
  { op: 'ignored' },
  { op: 'nudge', at: at(22, 11) }, { op: 'appeared', at: at(22, 11) },
  { op: 'skip', id: 'j3', at: at(22, 12) },
  { op: 'nudge', at: at(0, 40, 12) }, { op: 'appeared', at: at(0, 40, 12) },
  { op: 'nudge', at: at(0, 45, 12) },
  { op: 'ignored' },
  { op: 'nudge', at: at(0, 51, 12) }, { op: 'appeared', at: at(0, 51, 12) },
  { op: 'sleepLater', at: at(0, 52, 12) },
  { op: 'nudge', at: at(1, 0, 12) },
  { op: 'nudge', at: at(1, 3, 12) }, { op: 'appeared', at: at(1, 3, 12) },
  { op: 'closeBooks' },
  { op: 'nudge', at: at(1, 30, 12) }
];

test('jobs: when he comes out, and how bold he is', () => {
  const { day, results } = play(STEPS);
  const nudges = STEPS.map((s, i) => [s, results[i]]).filter(([s]) => s.op === 'nudge').map(([, r]) => r);
  assert.deepStrictEqual(nudges, [
    null,                                            // 08:30, before the day starts
    { kind: 'job', jobID: 'j1', level: 0 },          // 10:00, the first job
    null,                                            // 10:20, too soon after
    { kind: 'job', jobID: 'j2', level: 0 },          // 10:45, the one not yet shown
    { kind: 'job', jobID: 'j1', level: 1 },          // 11:30, back to read, bolder: he was ignored
    { kind: 'check', jobID: 'j1', level: 0 },        // 12:20, started 49 minutes ago: done yet?
    { kind: 'job', jobID: 'j2', level: 0 },          // 13:10, "later" is over
    null,                                            // a Focus mode with his filter on
    null,                                            // nobody at the Mac
    { kind: 'job', jobID: 'j3', level: 0 },          // 22:00, duolingo is due
    null,                                            // 22:05, too soon even for something due
    { kind: 'job', jobID: 'j3', level: 1 },          // 22:11, ignored once
    { kind: 'sleep', jobID: null, level: 0 },        // 00:40, past bedtime
    null,                                            // 00:45, too soon
    { kind: 'sleep', jobID: null, level: 1 },        // 00:51, ignored once
    null,                                            // 01:00, "10 more" is not over
    { kind: 'sleep', jobID: null, level: 0 },        // 01:03, it is
    null                                             // the books are closed
  ]);
  assert.strictEqual(jobs.ledger(day), 'Jobs, 2026-10-11\nDone: read (30 min)\nSkipped: duolingo\nStill owed: swift course');
  assert.deepStrictEqual(day.jobs.map(jobs.describeJob), ['done · 30 min', '', 'skipped · by 22:00']);

  const next = jobs.rollover(day, '2026-10-12');
  assert.deepStrictEqual(next.jobs.map(j => [j.id, j.title, j.owedDays, j.status, j.dueWall]), [['j1', 'swift course', 1, 'open', null]]);
  assert.strictEqual(jobs.describeJob(next.jobs[0]), 'owed since yesterday');
  assert.strictEqual(jobs.rollover(next, '2026-10-12'), next, 'the same day is left alone');
  const third = jobs.rollover(next, '2026-10-13');
  assert.strictEqual(third.jobs[0].owedDays, 2);
  assert.strictEqual(jobs.ledger(third), 'Jobs, 2026-10-13\nStill owed: swift course (3 days now)');
  assert.strictEqual(jobs.ledger(jobs.newDay('2026-10-14')), 'Jobs, 2026-10-14\nNo jobs today.');
});

// [hh, mm, day of October, quiet, idle seconds, already opened today, expected]
const OPEN_CASES = [
  [9, 59, 11, false, 0, false, false],     // before 10:00
  [10, 0, 11, false, 0, false, true],
  [15, 30, 11, false, 30, false, true],    // later in the day still counts: the first time he is around
  [15, 30, 11, false, 600, false, false],  // nobody at the Mac
  [15, 30, 11, true, 0, false, false],     // a Focus mode keeps it shut
  [15, 30, 11, false, 0, true, false],     // once a day
  [0, 45, 12, false, 0, false, false],     // after bedtime
  [3, 0, 12, false, 0, false, false]       // the small hours belong to the night before
];

test('jobs: the list opens by itself once a day', () => {
  for (const [h, m, d, quiet, idle, opened, expected] of OPEN_CASES) {
    const day = jobs.newDay('2026-10-11');
    if (opened) jobs.listOpened(day);
    assert.strictEqual(jobs.shouldOpenList(day, at(h, m, d), jobs.DEFAULT_SETTINGS, { quiet, idleSec: idle }), expected, `${h}:${m} quiet=${quiet} idle=${idle} opened=${opened}`);
  }
  const day = jobs.newDay('2026-10-11');
  day.quietUntil = at(4, 0, 12);
  assert.strictEqual(jobs.shouldOpenList(day, at(11, 0), jobs.DEFAULT_SETTINGS, {}), false, '"quiet" keeps it shut too');
});

test('jobs: unticking and deleting', () => {
  const day = jobs.newDay('2026-10-11');
  jobs.addJobs(day, jobs.parseJobs('read 30 min, call dad, gym', NOW, CATALOG), NOW);
  jobs.finish(day, 'j1', NOW);
  assert.strictEqual(jobs.reopen(day, 'j1').status, 'open');
  assert.strictEqual(day.jobs[0].doneAt, null);
  assert.strictEqual(jobs.remove(day, 'j2'), true);
  assert.strictEqual(jobs.remove(day, 'j2'), false);
  assert.deepStrictEqual(day.jobs.map(j => j.id), ['j1', 'j3']);
  jobs.addJobs(day, jobs.parseJobs('stretch', NOW, CATALOG), NOW);
  assert.strictEqual(day.jobs[2].id, 'j4', 'ids are never reused');
  assert.strictEqual(jobs.ledger(day), 'Jobs, 2026-10-11\nStill owed: read (30 min), gym, stretch');
});

const GROUPS = ['work', 'General', 'side project'];

// [text, expected drafts as [title, group, starter]]
const GROUP_CASES = [
  ['work: email the landlord', [['email the landlord', 'work', null]]],
  ['WORK:read 30 min, general: call dad', [['read', 'work', 'books'], ['call dad', 'General', null]]],
  ['side project: duolingo by 10pm', [['duolingo', 'side project', 'duolingo']]],
  ['call dad at 6:30', [['call dad', null, null]]],                  // a time is not a folder
  ['gym: legs', [['gym: legs', null, null]]],                        // no folder called gym: left as typed
  ['work:', []]
];

test('jobs: folders', () => {
  for (const [text, expected] of GROUP_CASES) {
    const got = jobs.parseJobs(text, NOW, CATALOG, {}, GROUPS).map(d => [d.title, d.group, d.starter]);
    assert.deepStrictEqual(got, expected, JSON.stringify(text));
  }
  assert.strictEqual(jobs.parseJobs('work: email', NOW, CATALOG, {})[0].group, null, 'no folders set up: nothing is read as one');

  const day = foldersDay();
  assert.deepStrictEqual(jobs.sections(day, GROUPS, at(13, 0)), [
    { group: 'work', ids: ['j1', 'j3'], left: 1, due: 1 },
    { group: 'General', ids: ['j2'], left: 1, due: 0 },
    { group: null, ids: ['j4', 'j5'], left: 2, due: 0 }
  ]);
  assert.deepStrictEqual(jobs.sections(day, [], at(13, 0)), [{ group: null, ids: ['j1', 'j2', 'j3', 'j4', 'j5'], left: 4, due: 1 }]);
  assert.deepStrictEqual(jobs.sections(jobs.newDay('2026-10-11'), GROUPS, NOW), []);

  // A suggestion fills only what is empty; what he typed wins.
  jobs.fillIn(day, 'j1', { starter: 'gmail', group: 'General' });
  assert.deepStrictEqual([day.jobs[0].starter, day.jobs[0].group], ['gmail', 'work']);
  jobs.fillIn(day, 'j4', { starter: null, group: 'General' });
  assert.strictEqual(day.jobs[3].group, 'General');
  assert.strictEqual(jobs.fillIn(day, 'j99', { starter: 'x', group: 'y' }), null);

  jobs.setGroup(day, 'j4', null);
  assert.strictEqual(day.jobs[3].group, null);
  assert.strictEqual(jobs.rollover(day, '2026-10-12').jobs.find(j => j.title === 'call dad').group, 'General', 'a carried job keeps its folder');
});

/** Five jobs in three folders: work (one due by noon, one done), general, and two in no folder (one in a folder
 *  that is not in the settings any more). */
function foldersDay() {
  const day = jobs.newDay('2026-10-11');
  jobs.addJobs(day, jobs.parseJobs('work: email the landlord by 12, general: call dad, work: standup notes, stretch, old: x', NOW, CATALOG, {}, GROUPS), NOW);
  day.jobs[4].group = 'old';
  jobs.finish(day, 'j3', NOW);
  return day;
}

test('write jobs fixtures', () => {
  const dir = path.join(__dirname, '..', 'fixtures');
  const { day, results } = play(STEPS);
  const next = jobs.rollover(JSON.parse(JSON.stringify(day)), '2026-10-12');
  fs.writeFileSync(path.join(dir, 'jobs.json'), JSON.stringify({
    now: NOW,
    catalog: CATALOG,
    parses: PARSE_CASES.map(([text, bindings]) => ({ text, bindings, drafts: jobs.parseJobs(text, NOW, CATALOG, bindings) })),
    dayKeys: [at(10, 0), at(1, 30, 12), at(4, 0, 12), at(3, 59, 1)].map(wall => ({ wall, key: jobs.dayKey(wall) })),
    steps: STEPS.map((s, i) => Object.assign({}, s, { result: results[i] })),
    finalDay: day,
    ledger: jobs.ledger(day),
    described: day.jobs.map(jobs.describeJob),
    rolled: next,
    rolledLedger: jobs.ledger(jobs.rollover(JSON.parse(JSON.stringify(next)), '2026-10-13')),
    groups: GROUPS,
    groupParses: GROUP_CASES.map(([text]) => ({ text, drafts: jobs.parseJobs(text, NOW, CATALOG, {}, GROUPS) })),
    foldersDay: foldersDay(),
    sections: jobs.sections(foldersDay(), GROUPS, at(13, 0)),
    sectionsAt: at(13, 0),
    opens: OPEN_CASES.map(([h, m, d, quiet, idle, opened]) => {
      const day = jobs.newDay('2026-10-11');
      if (opened) jobs.listOpened(day);
      return { wall: at(h, m, d), quiet, idle, opened, open: jobs.shouldOpenList(day, at(h, m, d), jobs.DEFAULT_SETTINGS, { quiet, idleSec: idle }) };
    })
  }, null, 2));
});
