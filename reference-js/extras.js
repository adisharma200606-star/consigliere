/*
 * Consigliere extras: reference implementation of the timer and of "living" bookmarks.
 * Pure logic. The Swift package ports this file.
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- timer ----

  var UNIT_SECONDS = {
    h: 3600, hr: 3600, hrs: 3600, hour: 3600, hours: 3600,
    m: 60, min: 60, mins: 60, minute: 60, minutes: 60,
    s: 1, sec: 1, secs: 1, second: 1, seconds: 1
  };
  var MAX_SECONDS = 24 * 3600;

  /**
   * How long did he mean? Returns whole seconds, or null when it cannot be read.
   *   "10"        10 minutes (a bare number means minutes)
   *   "1.5"       90 seconds
   *   "90s"       90 seconds          "10 min"     10 minutes        "1h" one hour
   *   "1h30"      90 minutes          "5m30"       5 min 30 s        "1 hour 30 minutes"
   *   "1:30"      1 min 30 s          "1:30:00"    90 minutes
   *   "for 10 minutes", "of about 5 min" -> the small words are ignored
   * Anything under one second or over 24 hours is refused.
   */
  function parseDuration(text) {
    var t = String(text || '').toLowerCase().replace(/\b(for|of|about|a|an|and)\b/g, ' ').replace(/,/g, ' ').trim();
    if (!t) return null;

    var clock = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(t);
    var total = 0;
    if (clock) {
      total = clock[3] === undefined
        ? parseInt(clock[1], 10) * 60 + parseInt(clock[2], 10)
        : parseInt(clock[1], 10) * 3600 + parseInt(clock[2], 10) * 60 + parseInt(clock[3], 10);
    } else {
      var re = /(\d+(?:\.\d+)?)\s*([a-z]+)?/g, m, consumed = '', lastUnit = null, any = false;
      while ((m = re.exec(t)) !== null) {
        var value = parseFloat(m[1]), unit = m[2];
        var per;
        if (unit === undefined) {
          // A bare number takes the next unit down: after hours it means minutes, after minutes seconds.
          per = lastUnit === 3600 ? 60 : lastUnit === 60 ? 1 : lastUnit === 1 ? null : 60;
        } else {
          per = UNIT_SECONDS[unit];
        }
        if (per === null || per === undefined) return null;
        total += value * per; lastUnit = per; any = true; consumed += m[0];
      }
      if (!any) return null;
      // Anything left over that is not a number or a unit means we did not understand it.
      if (t.replace(/(\d+(?:\.\d+)?)\s*([a-z]+)?/g, '').replace(/\s+/g, '') !== '') return null;
    }
    total = Math.round(total);
    if (total < 1 || total > MAX_SECONDS) return null;
    return total;
  }

  /** "9:41", "0:07", "1:02:03". Rounds up, so a timer shows 0:01 until it is really over. */
  function formatRemaining(ms) {
    var s = Math.max(0, Math.ceil(ms / 1000));
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    var two = function (n) { return (n < 10 ? '0' : '') + n; };
    return h > 0 ? h + ':' + two(m) + ':' + two(sec) : m + ':' + two(sec);
  }

  function startTimer(seconds, nowMs) { return { startedAt: nowMs, durationMs: seconds * 1000 }; }

  /** The same timer with more time on it. Adding to a finished timer counts from now. */
  function addTime(timer, seconds, nowMs) {
    var end = Math.max(timer.startedAt + timer.durationMs, nowMs) + seconds * 1000;
    return { startedAt: timer.startedAt, durationMs: end - timer.startedAt };
  }

  /** "timer stop", "stop timer", "cancel the timer": words that mean stop, not a length of time. */
  var STOP_WORDS = ['stop', 'cancel', 'off', 'end', 'kill', 'done', 'enough', 'reset', 'clear'];
  function isStopWord(text) {
    var words = String(text || '').toLowerCase().split(/\s+/).map(function (w) { return w.replace(/[^a-z0-9]/g, ''); }).filter(Boolean);
    return words.length > 0 && words.length <= 3 && words.some(function (w) { return STOP_WORDS.indexOf(w) >= 0; }) &&
      words.every(function (w) { return STOP_WORDS.indexOf(w) >= 0 || ['the', 'my', 'it', 'please', 'timer'].indexOf(w) >= 0; });
  }
  function timerStatus(timer, nowMs) {
    var left = Math.max(0, timer.startedAt + timer.durationMs - nowMs);
    return { remainingMs: left, fraction: timer.durationMs === 0 ? 0 : left / timer.durationMs, done: left === 0, text: formatRemaining(left) };
  }

  // ------------------------------------------------------- living bookmarks ----

  /** Split a URL into a comparable host and its path segments, without needing a URL library. */
  function urlParts(url) {
    var rest = String(url || '').trim().replace(/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//, '');
    var cut = rest.search(/[\/?#]/);
    var host = (cut < 0 ? rest : rest.slice(0, cut)).toLowerCase();
    var at = host.lastIndexOf('@'); if (at >= 0) host = host.slice(at + 1);
    if (host.indexOf('www.') === 0) host = host.slice(4);
    var path = cut < 0 ? '' : rest.slice(cut);
    var end = path.search(/[?#]/); if (end >= 0) path = path.slice(0, end);
    return { host: host, segments: path.split('/').filter(Boolean) };
  }

  function sharedLeadingSegments(a, b) {
    var n = 0;
    while (n < a.length && n < b.length && a[n] === b[n]) n++;
    return n;
  }

  /**
   * He pressed "remember where I am" on some page. Which entry should move?
   * Only entries marked `living` are ever touched, so "youtube" never gets overwritten by a video.
   *   { result: "update", entry }        exactly one sensible candidate
   *   { result: "ambiguous", entries }   several living entries fit equally well; the app asks
   *   { result: "none" }                 nothing living lives on this site
   */
  function findLivingEntry(currentURL, catalog) {
    var here = urlParts(currentURL);
    if (!here.host) return { result: 'none' };
    var same = catalog.filter(function (e) { return e.kind === 'site' && e.living === true && urlParts(e.target).host === here.host; });
    if (!same.length) return { result: 'none' };
    if (same.length === 1) return { result: 'update', entry: same[0] };

    var best = -1, tied = [];
    same.forEach(function (e) {
      var score = sharedLeadingSegments(here.segments, urlParts(e.target).segments);
      if (score > best) { best = score; tied = [e]; } else if (score === best) tied.push(e);
    });
    if (tied.length === 1) return { result: 'update', entry: tied[0] };
    tied.sort(function (a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0; });
    return { result: 'ambiguous', entries: tied };
  }

  /** The catalog with one entry pointed at a new page. Everything else about the entry is kept. */
  function moveEntry(catalog, entryName, newURL) {
    return catalog.map(function (e) {
      if (e.name !== entryName) return e;
      var copy = {}; for (var k in e) copy[k] = e[k];
      copy.target = newURL;
      return copy;
    });
  }


  // ---------------------------------------------------------------- iPhone ----
  //
  // The phone and the Mac never write to the same file, so iCloud can never make them clash:
  //   phone-inbox.txt    only the phone appends.  One save per line:   <ISO date> <link or text>
  //   phone-opened.txt   only the phone appends.  One open per line:   <ISO date> <link or text>
  //   for-phone.txt      only the Mac writes.     One unopened item per line, for the phone's "bored" shortcut.

  /** Read a phone file. Tolerant: blank lines are skipped, a missing or unreadable date means "now". */
  function parsePhoneLines(text, nowMs) {
    var out = [];
    String(text || '').split(/\r?\n/).forEach(function (raw) {
      var line = raw.trim();
      if (!line) return;
      var sp = line.indexOf(' ');
      var first = sp > 0 ? line.slice(0, sp) : '';
      var ms = /^\d{4}-\d{2}-\d{2}/.test(first) ? Date.parse(first) : NaN;
      var payload = isNaN(ms) ? line : line.slice(sp + 1).trim();
      if (!payload) return;
      out.push({ payload: payload, at: isNaN(ms) ? nowMs : ms, dated: !isNaN(ms) });
    });
    return out;
  }

  function kindOf(payload) { return /^https?:\/\//i.test(payload) ? 'url' : 'text'; }

  /**
   * Fold the phone's files into the stash. Safe to run again and again on the same files:
   * nothing is duplicated, and something he already opened is not brought back unless he saved it again later.
   */
  function ingestPhone(stash, inboxText, openedText, nowMs) {
    var counts = { added: 0, refreshed: 0, opened: 0 };
    parsePhoneLines(inboxText, nowMs).forEach(function (line) {
      var kind = kindOf(line.payload), existing = null;
      for (var i = 0; i < stash.items.length; i++) {
        if (stash.items[i].payload === line.payload && stash.items[i].kind === kind) existing = stash.items[i];
      }
      if (!existing) {
        stash.items.push({ id: 'p' + line.at + '-' + stash.items.length, kind: kind, payload: line.payload, title: null,
          source: 'phone', savedAt: line.at, servedAt: null, openedAt: null, skippedCount: 0 });
        counts.added++;
      } else if (line.dated && line.at > existing.savedAt + 1000) {
        // Only a line with a real date can count as "saved again". An undated line would look new on every run.
        existing.savedAt = line.at; existing.openedAt = null; existing.skippedCount = 0;
        counts.refreshed++;
      }
    });
    parsePhoneLines(openedText, nowMs).forEach(function (line) {
      stash.items.forEach(function (item) {
        if (!item.openedAt && item.payload === line.payload && line.dated && line.at >= item.savedAt) { item.openedAt = line.at; counts.opened++; }
      });
    });
    return counts;
  }

  /** What the Mac writes for the phone: every unopened link or note, oldest first, one per line. */
  function exportForPhone(stash) {
    return stash.items
      .filter(function (it) { return !it.openedAt && (it.kind === 'url' || it.kind === 'text') && it.payload.indexOf('\n') < 0; })
      .sort(function (a, b) { return a.savedAt !== b.savedAt ? a.savedAt - b.savedAt : (a.id < b.id ? -1 : a.id > b.id ? 1 : 0); })
      .map(function (it) { return it.payload; })
      .join('\n');
  }

  var api = {
    parsePhoneLines: parsePhoneLines, ingestPhone: ingestPhone, exportForPhone: exportForPhone,
    parseDuration: parseDuration, formatRemaining: formatRemaining, startTimer: startTimer, timerStatus: timerStatus,
    addTime: addTime, isStopWord: isStopWord, STOP_WORDS: STOP_WORDS,
    urlParts: urlParts, findLivingEntry: findLivingEntry, moveEntry: moveEntry
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereExtras = api;
})(typeof self !== 'undefined' ? self : this);
