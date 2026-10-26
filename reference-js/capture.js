/*
 * Consigliere capture: reading "remind me to call mom tomorrow at 5" into a title and a time.
 * Pure logic, no clock and no time zone of its own. The Swift package ports this file.
 *
 * Times are "wall-clock milliseconds": the number Date.UTC(y, m, d, h, min) would give for what the clock
 * on the wall says. The app converts to and from real dates; the parser never has to think about zones.
 */
(function (root) {
  'use strict';

  var MIN = 60000, HOUR = 3600000, DAY = 86400000;
  var WEEKDAYS = { sun: 0, sunday: 0, mon: 1, monday: 1, tue: 2, tues: 2, tuesday: 2, wed: 3, weds: 3, wednesday: 3,
    thu: 4, thur: 4, thurs: 4, thursday: 4, fri: 5, friday: 5, sat: 6, saturday: 6 };
  var UNITS = { m: MIN, min: MIN, mins: MIN, minute: MIN, minutes: MIN, h: HOUR, hr: HOUR, hrs: HOUR, hour: HOUR, hours: HOUR,
    d: DAY, day: DAY, days: DAY, w: 7 * DAY, week: 7 * DAY, weeks: 7 * DAY };
  var PARTS_OF_DAY = { morning: 9, afternoon: 15, evening: 19, night: 20, tonight: 20, noon: 12, midday: 12, midnight: 0 };
  var LEAD_IN = ['me', 'to', 'that', 'about'];
  var DANGLING = ['at', 'on', 'by', 'in', 'for', 'to', 'around', 'the', 'this', 'next', 'and'];

  function bare(token) { return token.toLowerCase().replace(/^[^a-z0-9:]+|[^a-z0-9:]+$/g, ''); }
  function isDigits(s) { return /^\d+$/.test(s); }

  /** "5", "5pm", "5:30", "5:30pm", "17:30" -> { hour, minute, meridiem } or null. */
  function readClock(word) {
    var m = /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/.exec(word);
    if (!m) return null;
    var hour = parseInt(m[1], 10), minute = m[2] === undefined ? 0 : parseInt(m[2], 10);
    if (hour > 23 || minute > 59) return null;
    if (m[3] && (hour < 1 || hour > 12)) return null;
    return { hour: hour, minute: minute, meridiem: m[3] || null, hasColon: m[2] !== undefined };
  }

  /**
   * text     what he typed after "remind" / "reminder" / "todo"
   * nowWall  the current wall-clock time in wall-clock milliseconds
   * Returns { title, dueWall } where dueWall is null when no time was mentioned.
   *
   * Understands: in 20 minutes, in an hour, in half an hour, in 2 days, today, tonight, tomorrow,
   * day after tomorrow, friday / on friday / next friday (the coming one), at 5, at 5pm, 5:30 pm, 17:30,
   * noon, midnight, morning, afternoon, evening. A day with no time means 9:00 (for "today" after 9:00, an hour
   * or two from now). A time that has already passed today means tomorrow. A bare hour from 1 to 6 means the afternoon.
   */
  function parseReminder(text, nowWall) {
    var tokens = String(text || '').trim().split(/\s+/).filter(Boolean);
    while (tokens.length > 1 && LEAD_IN.indexOf(bare(tokens[0])) >= 0) tokens.shift();
    var words = tokens.map(bare), used = tokens.map(function () { return false; });
    var relative = null, dayOffset = null, clock = null, partOfDay = null, i;

    function take(from, count) { for (var k = from; k < from + count; k++) used[k] = true; }

    for (i = 0; i < words.length; i++) {
      if (used[i]) continue;
      var w = words[i], next = words[i + 1], after = words[i + 2];

      // in 20 minutes / in 20min / in an hour / in half an hour
      if (w === 'in' && relative === null && next !== undefined) {
        if (next === 'half' && after === 'an' && words[i + 3] === 'hour') { relative = 30 * MIN; take(i, 4); continue; }
        if ((next === 'a' || next === 'an') && UNITS[after]) { relative = UNITS[after]; take(i, 3); continue; }
        if (isDigits(next) && UNITS[after]) { relative = parseInt(next, 10) * UNITS[after]; take(i, 3); continue; }
        var glued = /^(\d+)([a-z]+)$/.exec(next);
        if (glued && UNITS[glued[2]]) { relative = parseInt(glued[1], 10) * UNITS[glued[2]]; take(i, 2); continue; }
      }

      if (dayOffset === null) {
        if (w === 'day' && next === 'after' && (after === 'tomorrow' || after === 'tmrw')) { dayOffset = 2; take(i, 3); continue; }
        if (w === 'today') { dayOffset = 0; take(i, 1); continue; }
        if (w === 'tomorrow' || w === 'tmrw' || w === 'tmr') { dayOffset = 1; take(i, 1); continue; }
        if (w === 'tonight') { dayOffset = 0; partOfDay = 20; take(i, 1); continue; }
        if (WEEKDAYS[w] !== undefined) {
          var today = new Date(nowWall).getUTCDay();
          var ahead = (WEEKDAYS[w] - today + 7) % 7;
          dayOffset = ahead === 0 ? 7 : ahead;
          var lead = i > 0 && !used[i - 1] && (words[i - 1] === 'on' || words[i - 1] === 'next' || words[i - 1] === 'this') ? 1 : 0;
          take(i - lead, 1 + lead); continue;
        }
      }

      if (clock === null && partOfDay === null && PARTS_OF_DAY[w] !== undefined && w !== 'tonight') {
        partOfDay = PARTS_OF_DAY[w];
        var back = 0;
        if (i >= 2 && words[i - 2] === 'in' && words[i - 1] === 'the' && !used[i - 1] && !used[i - 2]) back = 2;
        else if (i >= 1 && !used[i - 1] && (words[i - 1] === 'this' || words[i - 1] === 'at' || words[i - 1] === 'the')) back = 1;
        take(i - back, 1 + back); continue;
      }

      if (clock === null) {
        var c = readClock(w), introduced = i > 0 && !used[i - 1] && (words[i - 1] === 'at' || words[i - 1] === 'by' || words[i - 1] === 'around');
        if (c) {
          var separateMeridiem = !c.meridiem && (next === 'am' || next === 'pm');
          if (c.meridiem || c.hasColon || separateMeridiem || introduced) {
            if (separateMeridiem) { c.meridiem = next; if (c.hour < 1 || c.hour > 12) c = null; }
            if (c) { clock = c; take(introduced ? i - 1 : i, (introduced ? 1 : 0) + 1 + (separateMeridiem ? 1 : 0)); continue; }
          }
        }
      }
    }

    // ---- put the time together
    var due = null;
    if (relative !== null && dayOffset === null && clock === null && partOfDay === null) {
      due = nowWall + relative;
    } else if (dayOffset !== null || clock !== null || partOfDay !== null) {
      var midnight = nowWall - (nowWall % DAY);
      var hour = 9, minute = 0, guessed = false;
      if (clock) {
        hour = clock.hour; minute = clock.minute;
        if (clock.meridiem === 'pm' && hour < 12) hour += 12;
        if (clock.meridiem === 'am' && hour === 12) hour = 0;
        if (!clock.meridiem && !clock.hasColon && hour >= 1 && hour <= 6) hour += 12;          // "at 5" means 17:00
        else if (!clock.meridiem && !clock.hasColon && hour >= 7 && hour <= 11) guessed = true;  // "at 9" could be either
      } else if (partOfDay !== null) {
        hour = partOfDay;
      }
      due = midnight + (dayOffset || 0) * DAY + hour * HOUR + minute * MIN + (relative || 0);
      if (dayOffset === null && due <= nowWall) {
        if (guessed && due + 12 * HOUR > nowWall) due += 12 * HOUR;   // 9 has passed, so he means 21:00
        else due += DAY;
      } else if (dayOffset === 0 && !clock && partOfDay === null && due <= nowWall) {
        // "today" with no time, and 9:00 has gone: the top of the next hour, plus one.
        due = nowWall - (nowWall % HOUR) + 2 * HOUR;
      }
    }

    // ---- what is left is the title
    var kept = [];
    for (i = 0; i < tokens.length; i++) if (!used[i]) kept.push(tokens[i]);
    // Removing "tomorrow at 5" can leave an "at" or "on" hanging off the end. Only tidy up when something was removed.
    if (kept.length < tokens.length) {
      while (kept.length > 1 && DANGLING.indexOf(bare(kept[kept.length - 1])) >= 0) kept.pop();
    }
    var title = kept.join(' ').replace(/[\s,;:.\-]+$/, '').trim();
    if (!title) title = tokens.join(' ');
    return { title: title, dueWall: due };
  }

  /** "Today 17:00", "Tomorrow 09:00", "Fri 26 Sep 09:00": how the notch confirms what it understood. */
  function describeDue(dueWall, nowWall) {
    if (dueWall === null || dueWall === undefined) return 'no time set';
    var d = new Date(dueWall), two = function (n) { return (n < 10 ? '0' : '') + n; };
    var time = two(d.getUTCHours()) + ':' + two(d.getUTCMinutes());
    var days = Math.floor(dueWall / DAY) - Math.floor(nowWall / DAY);
    if (days === 0) return 'Today ' + time;
    if (days === 1) return 'Tomorrow ' + time;
    var names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[d.getUTCDay()] + ' ' + d.getUTCDate() + ' ' + months[d.getUTCMonth()] + ' ' + time;
  }

  var api = { parseReminder: parseReminder, describeDue: describeDue };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereCapture = api;
})(typeof self !== 'undefined' ? self : this);
