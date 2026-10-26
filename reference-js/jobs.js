/*
 * Consigliere jobs: the day's list, what starts each job, and when he comes out of the notch about one.
 * Pure logic, no clock of its own. The Swift package ports this file (Jobs.swift and Nudge.swift).
 *
 * Every time here is in "wall-clock milliseconds", the same idea as capture.js: the number Date.UTC would
 * give for what the clock on the wall says. The app converts; this file never thinks about time zones.
 *
 * The incentive is not guilt. It is removing the first step: every job gets a "starter", the thing that
 * opens when he presses "start it" (Books for "read", the saved course page for "swift course").
 */
(function (root) {
  'use strict';

  var core = typeof require === 'function' ? require('./core.js') : root.ConsigliereCore;
  var extras = typeof require === 'function' ? require('./extras.js') : root.ConsigliereExtras;
  var capture = typeof require === 'function' ? require('./capture.js') : root.ConsigliereCapture;

  var MIN = 60000, HOUR = 3600000, DAY = 86400000;
  /** A job day runs from 04:00 to 04:00, so a job typed at 1 a.m. still belongs to the evening before. */
  var ROLLOVER_HOUR = 4;
  var DURATION_UNITS = ['h', 'hr', 'hrs', 'hour', 'hours', 'm', 'min', 'mins', 'minute', 'minutes'];
  /** Words people put in front of a job that are not part of it: "i need to call dad" is the job "call dad". */
  var LEADING_PHRASES = [['i', 'need', 'to'], ['i', 'have', 'to'], ['i', 'gotta'], ['i', 'must'], ['i', 'should'],
    ['need', 'to'], ['have', 'to'], ['gotta'], ['must'], ['to']];

  var DEFAULT_SETTINGS = {
    dayStartMin: 9 * 60,      // he does not come out before this
    bedtimeMin: 30,           // 00:30; after this the only job left is sleep
    cooldownMin: 45,          // least time between two appearances about jobs with no time set
    dueGapMin: 10,            // least time between two appearances about jobs that are due
    sleepGapMin: 10,          // least time between two bedtime appearances
    laterMin: 30,             // what "later" puts a job off by
    maxLevel: 3,              // how bold he gets when ignored: 0 bobs under the notch, 3 loops the middle of the screen
    idleLimitSec: 300,        // nobody at the Mac for this long: stay home
    openAtMin: 10 * 60,       // the list opens by itself once a day, the first time he is at the Mac after this
    activeWithinSec: 120      // ...and only if he touched the Mac this recently, so it is seen
  };

  function bare(token) { return String(token).toLowerCase().replace(/^[^a-z0-9.:]+|[^a-z0-9.:]+$/g, ''); }

  /** "09:00" or "0:30" -> minutes after midnight, or null. */
  function clockMinutes(text) {
    var m = /^(\d{1,2}):(\d{2})$/.exec(String(text || '').trim());
    if (!m) return null;
    var h = parseInt(m[1], 10), mm = parseInt(m[2], 10);
    if (h > 23 || mm > 59) return null;
    return h * 60 + mm;
  }

  /** "2026-10-11": which job day a wall time belongs to. */
  function dayKey(wall) {
    var d = new Date(wall - ROLLOVER_HOUR * HOUR), two = function (n) { return (n < 10 ? '0' : '') + n; };
    return d.getUTCFullYear() + '-' + two(d.getUTCMonth() + 1) + '-' + two(d.getUTCDate());
  }

  /** Minutes since midnight, but the small hours count as the end of the day before (1:00 is 1500). */
  function shiftedMinutes(min) { return min < ROLLOVER_HOUR * 60 ? min + 1440 : min; }
  function wallMinutes(wall) { return Math.floor((((wall % DAY) + DAY) % DAY) / MIN); }

  // ------------------------------------------------------------ reading jobs ----

  /** Finds "30 min", "for 1h", "an hour", "half an hour" (but not "in 30 min", which is a time). Returns
   *  { minutes, rest } with the words removed, or { minutes: null, rest } when there is none. */
  function takeDuration(tokens) {
    var words = tokens.map(bare);
    for (var i = 0; i < words.length; i++) {
      if (i > 0 && words[i - 1] === 'in') continue;
      var seconds = null, count = 0;
      if (words[i] === 'half' && words[i + 1] === 'an' && words[i + 2] === 'hour') { seconds = 1800; count = 3; }
      else if ((words[i] === 'an' || words[i] === 'a') && words[i + 1] === 'hour') { seconds = 3600; count = 2; }
      else if (/^\d+(\.\d+)?$/.test(words[i]) && DURATION_UNITS.indexOf(words[i + 1]) >= 0) {
        seconds = extras.parseDuration(words[i] + ' ' + words[i + 1]); count = 2;
      } else {
        var glued = /^(\d+(?:\.\d+)?)([a-z]+)$/.exec(words[i]);
        if (glued && DURATION_UNITS.indexOf(glued[2]) >= 0) { seconds = extras.parseDuration(words[i]); count = 1; }
      }
      if (seconds === null || seconds === undefined) continue;
      var from = i;
      if (i > 0 && words[i - 1] === 'for') { from = i - 1; count += 1; }
      var rest = tokens.slice(0, from).concat(tokens.slice(from + count));
      return { minutes: Math.max(1, Math.round(seconds / 60)), rest: rest };
    }
    return { minutes: null, rest: tokens };
  }

  function dropLeadingPhrase(tokens) {
    var words = tokens.map(bare);
    for (var p = 0; p < LEADING_PHRASES.length; p++) {
      var phrase = LEADING_PHRASES[p];
      if (words.length <= phrase.length) continue;
      var same = phrase.every(function (w, k) { return words[k] === w; });
      if (same) return tokens.slice(phrase.length);
    }
    return tokens;
  }

  /**
   * Which catalog entry starts this job, or null. In order:
   *  1. a word he has bound before ("read" -> "books")
   *  2. the whole title matches confidently ("duolingo", "read a chapter" -> books through "read")
   *  3. the end of the title exactly names an entry ("finish the swift course" -> "swift course")
   * Tools never start a job: "timer" in a job title is not a reason to open the timer.
   */
  function bindStarter(title, catalog, bindings) {
    bindings = bindings || {};
    var tokens = String(title).split(/\s+/).filter(Boolean);
    var hasEntry = function (name) { return catalog.some(function (e) { return e.name === name && e.kind !== 'tool'; }); };
    for (var i = 0; i < tokens.length; i++) {
      var bound = bindings[core.normalize(tokens[i])];
      if (bound && hasEntry(bound)) return bound;
    }
    var d = core.match(title, catalog, {});
    if (d.mode === 'open' && d.confident && d.results.length && d.results[0].entry.kind !== 'tool') return d.results[0].entry.name;
    for (var start = 1; start < tokens.length; start++) {
      var ranked = core.rank(core.normalize(tokens.slice(start).join('')), catalog, {});
      if (ranked.length && ranked[0].band === core.BAND.exact && ranked[0].entry.kind !== 'tool') return ranked[0].entry.name;
    }
    return null;
  }

  /**
   * "read 30 min, swift course, duolingo by 10pm" -> three drafts.
   * Commas, semicolons and new lines separate jobs. "and" does not, so "call mom and dad" stays one job.
   * Each draft: { title, minutes, dueWall, starter }.
   */
  function parseJobs(text, nowWall, catalog, bindings) {
    var pieces = String(text || '').split(/[,;\n]+/);
    var drafts = [];
    pieces.forEach(function (piece) {
      var tokens = piece.trim().split(/\s+/).filter(Boolean);
      if (!tokens.length) return;
      tokens = dropLeadingPhrase(tokens);
      var d = takeDuration(tokens);
      if (!d.rest.length) return;
      var r = capture.parseReminder(d.rest.join(' '), nowWall);
      var title = r.title.trim();
      if (!title) return;
      drafts.push({ title: title, minutes: d.minutes, dueWall: r.dueWall, starter: bindStarter(title, catalog, bindings) });
    });
    return drafts;
  }

  // ------------------------------------------------------------ the day ----

  function newDay(key) {
    return { day: key, jobs: [], nextID: 1, lastAppearance: null, sleepSnoozedUntil: null, sleepIgnored: 0,
      closed: false, quietUntil: null, diaryNoteID: null, listOpened: false };
  }

  function newJob(id, draft, now) {
    return { id: id, title: draft.title, starter: draft.starter, minutes: draft.minutes, dueWall: draft.dueWall,
      status: 'open', addedAt: now, startedAt: null, doneAt: null, snoozedUntil: null, lastShownAt: null,
      ignored: 0, owedDays: 0 };
  }

  /** Adds drafts to the day. A draft with the same title as a job not yet finished updates it instead. */
  function addJobs(day, drafts, now) {
    var added = [];
    drafts.forEach(function (draft) {
      var same = day.jobs.filter(function (j) {
        return (j.status === 'open' || j.status === 'started') && core.normalize(j.title) === core.normalize(draft.title);
      })[0];
      if (same) {
        if (draft.minutes !== null) same.minutes = draft.minutes;
        if (draft.dueWall !== null) same.dueWall = draft.dueWall;
        if (draft.starter !== null) same.starter = draft.starter;
        added.push(same);
        return;
      }
      var job = newJob('j' + day.nextID, draft, now);
      day.nextID += 1;
      day.jobs.push(job);
      added.push(job);
    });
    return added;
  }

  /** A new day. Whatever was not finished comes along, owed one more day. Done and skipped jobs stay behind. */
  function rollover(day, key) {
    if (day && day.day === key) return day;
    var fresh = newDay(key);
    if (!day) return fresh;
    day.jobs.forEach(function (j) {
      if (j.status !== 'open' && j.status !== 'started') return;
      var carried = newJob('j' + fresh.nextID, j, j.addedAt);
      fresh.nextID += 1;
      carried.owedDays = j.owedDays + 1;
      // A time from yesterday is no longer a time; the job becomes one for whenever.
      carried.dueWall = null;
      fresh.jobs.push(carried);
    });
    return fresh;
  }

  function job(day, id) { return day.jobs.filter(function (j) { return j.id === id; })[0] || null; }

  /** "done read" -> the unfinished job whose title best fits "read". Exact, then start, then anywhere. */
  function findJob(day, text) {
    var q = core.normalize(text);
    if (!q) return null;
    var live = day.jobs.filter(function (j) { return j.status === 'open' || j.status === 'started'; });
    var tests = [
      function (t) { return t === q; },
      function (t) { return t.indexOf(q) === 0; },
      function (t) { return t.indexOf(q) >= 0; }
    ];
    for (var k = 0; k < tests.length; k++) {
      var hit = live.filter(function (j) { return tests[k](core.normalize(j.title)); })[0];
      if (hit) return hit;
    }
    return null;
  }

  function touch(j) { j.ignored = 0; j.snoozedUntil = null; }
  function start(day, id, now) { var j = job(day, id); if (!j) return null; j.status = 'started'; j.startedAt = now; touch(j); return j; }
  function finish(day, id, now) { var j = job(day, id); if (!j) return null; j.status = 'done'; j.doneAt = now; touch(j); return j; }
  function skip(day, id) { var j = job(day, id); if (!j) return null; j.status = 'skipped'; touch(j); return j; }
  function later(day, id, now, settings) {
    var j = job(day, id); if (!j) return null;
    touch(j);
    j.snoozedUntil = now + (settings || DEFAULT_SETTINGS).laterMin * MIN;
    return j;
  }
  function sleepLater(day, now, minutes) { day.sleepSnoozedUntil = now + (minutes || 10) * MIN; day.sleepIgnored = 0; }
  function closeBooks(day) { day.closed = true; }
  /** Ticked by mistake: back on the list. */
  function reopen(day, id) {
    var j = job(day, id); if (!j) return null;
    j.status = 'open'; j.doneAt = null; j.startedAt = null; touch(j);
    return j;
  }
  /** Gone from the list, not done and not skipped: it never goes into the ledger. */
  function remove(day, id) {
    var before = day.jobs.length;
    day.jobs = day.jobs.filter(function (j) { return j.id !== id; });
    return day.jobs.length < before;
  }

  /**
   * Should the list open by itself now, so he can plan the day? Once a day, the first time he is at the Mac
   * after openAtMin, never during quiet, never after bedtime. This is the one thing besides a due job that
   * shows without being asked, and it is silent: the list opens, nothing is said.
   */
  function shouldOpenList(day, now, settings, ctx) {
    settings = settings || DEFAULT_SETTINGS;
    ctx = ctx || {};
    if (day.listOpened || ctx.quiet) return false;
    if (day.quietUntil !== null && day.quietUntil !== undefined && now < day.quietUntil) return false;
    if ((ctx.idleSec || 0) > settings.activeWithinSec) return false;
    var nowS = shiftedMinutes(wallMinutes(now));
    return nowS >= shiftedMinutes(settings.openAtMin) && nowS < shiftedMinutes(settings.bedtimeMin);
  }
  function listOpened(day) { day.listOpened = true; }

  // ------------------------------------------------------------ when he comes out ----

  function snoozed(j, now) { return j.snoozedUntil !== null && now < j.snoozedUntil; }

  /**
   * Should he come out of the notch now, and about what? Returns null, or { kind, jobID, level }.
   *   kind 'job'    a job to start
   *   kind 'check'  a job that was started a while ago: done yet?
   *   kind 'sleep'  it is past bedtime
   * ctx: { quiet, idleSec }. quiet is a Focus mode with his filter on, or "shh".
   *
   * He never speaks when he comes out. The app only makes him fly; the voice waits for a click.
   */
  function nextNudge(day, now, settings, ctx) {
    settings = settings || DEFAULT_SETTINGS;
    ctx = ctx || {};
    if (ctx.quiet) return null;
    if (day.quietUntil !== null && day.quietUntil !== undefined && now < day.quietUntil) return null;
    if ((ctx.idleSec || 0) > settings.idleLimitSec) return null;

    var nowS = shiftedMinutes(wallMinutes(now));
    var gap = day.lastAppearance === null ? Infinity : now - day.lastAppearance;

    if (nowS >= shiftedMinutes(settings.bedtimeMin)) {
      if (day.closed) return null;
      if (day.sleepSnoozedUntil !== null && now < day.sleepSnoozedUntil) return null;
      if (gap < settings.sleepGapMin * MIN) return null;
      return { kind: 'sleep', jobID: null, level: Math.min(settings.maxLevel, day.sleepIgnored) };
    }
    if (nowS < shiftedMinutes(settings.dayStartMin)) return null;

    var level = function (j) { return Math.min(settings.maxLevel, j.ignored); };
    var byID = function (a, b) { return parseInt(a.id.slice(1), 10) - parseInt(b.id.slice(1), 10); };

    var due = day.jobs.filter(function (j) { return j.status === 'open' && !snoozed(j, now) && j.dueWall !== null && j.dueWall <= now; })
      .sort(function (a, b) { return a.dueWall !== b.dueWall ? a.dueWall - b.dueWall : byID(a, b); });
    if (due.length && gap >= settings.dueGapMin * MIN) return { kind: 'job', jobID: due[0].id, level: level(due[0]) };

    if (gap < settings.cooldownMin * MIN) return null;

    var checks = day.jobs.filter(function (j) {
      return j.status === 'started' && !snoozed(j, now) && j.startedAt !== null &&
        now - j.startedAt >= Math.max(j.minutes || 0, settings.cooldownMin) * MIN;
    }).sort(byID);
    if (checks.length) return { kind: 'check', jobID: checks[0].id, level: level(checks[0]) };

    var loose = day.jobs.filter(function (j) { return j.status === 'open' && !snoozed(j, now) && j.dueWall === null; })
      .sort(function (a, b) {
        if (a.owedDays !== b.owedDays) return b.owedDays - a.owedDays;
        var as = a.lastShownAt === null ? -1 : a.lastShownAt, bs = b.lastShownAt === null ? -1 : b.lastShownAt;
        if (as !== bs) return as - bs;
        return byID(a, b);
      });
    if (loose.length) return { kind: 'job', jobID: loose[0].id, level: level(loose[0]) };
    return null;
  }

  /** He came out. */
  function appeared(day, nudge, now) {
    day.lastAppearance = now;
    var j = nudge.jobID ? job(day, nudge.jobID) : null;
    if (j) j.lastShownAt = now;
  }

  /** He went home without anyone clicking him. Next time he is one step bolder. */
  function ignored(day, nudge) {
    if (nudge.kind === 'sleep') { day.sleepIgnored += 1; return; }
    var j = job(day, nudge.jobID);
    if (j) j.ignored += 1;
  }

  // ------------------------------------------------------------ saying it back ----

  function two(n) { return (n < 10 ? '0' : '') + n; }
  function clockText(wall) { var d = new Date(wall); return two(d.getUTCHours()) + ':' + two(d.getUTCMinutes()); }

  /** The small grey text beside a job in the list: "by 22:00 · 30 min · owed 2 days". */
  function describeJob(j) {
    var parts = [];
    if (j.status === 'done') parts.push('done');
    else if (j.status === 'skipped') parts.push('skipped');
    else if (j.status === 'started') parts.push('on it');
    if (j.dueWall !== null) parts.push('by ' + clockText(j.dueWall));
    if (j.minutes !== null) parts.push(j.minutes + ' min');
    if (j.owedDays === 1) parts.push('owed since yesterday');
    else if (j.owedDays > 1) parts.push('owed ' + j.owedDays + ' days');
    return parts.join(' · ');
  }

  /** The day's record, written into the diary when he closes the books. */
  function ledger(day) {
    var pick = function (status) { return day.jobs.filter(function (j) { return j.status === status; }); };
    var name = function (j) { return j.title + (j.minutes !== null ? ' (' + j.minutes + ' min)' : ''); };
    var lines = ['Jobs, ' + day.day];
    var done = pick('done'), skipped = pick('skipped');
    var owed = day.jobs.filter(function (j) { return j.status === 'open' || j.status === 'started'; });
    if (!day.jobs.length) lines.push('No jobs today.');
    if (done.length) lines.push('Done: ' + done.map(name).join(', '));
    if (skipped.length) lines.push('Skipped: ' + skipped.map(name).join(', '));
    if (owed.length) lines.push('Still owed: ' + owed.map(function (j) {
      return name(j) + (j.owedDays > 0 ? ' (' + (j.owedDays + 1) + ' days now)' : '');
    }).join(', '));
    return lines.join('\n');
  }

  var api = {
    DEFAULT_SETTINGS: DEFAULT_SETTINGS, ROLLOVER_HOUR: ROLLOVER_HOUR,
    clockMinutes: clockMinutes, dayKey: dayKey, takeDuration: takeDuration, bindStarter: bindStarter, parseJobs: parseJobs,
    newDay: newDay, addJobs: addJobs, rollover: rollover, findJob: findJob,
    start: start, finish: finish, skip: skip, later: later, sleepLater: sleepLater, closeBooks: closeBooks,
    reopen: reopen, remove: remove, shouldOpenList: shouldOpenList, listOpened: listOpened,
    nextNudge: nextNudge, appeared: appeared, ignored: ignored, describeJob: describeJob, ledger: ledger
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereJobs = api;
})(typeof self !== 'undefined' ? self : this);
