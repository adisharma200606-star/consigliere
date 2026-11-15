/*
 * Consigliere smart jobs: asking Claude what opens a job and which folder it belongs in, for the jobs the
 * plain rules in jobs.js could not place. This file holds everything that does not need the internet: who
 * needs help, the words sent, and how the reply is checked. The app does the network call.
 * The Swift package ports this file (Smart.swift); fixtures/smart.json keeps the two in step.
 *
 * Why it is careful:
 *  - Only jobs that still lack a starter or a folder are sent, so most jobs never leave the Mac and cost nothing.
 *  - Only the job titles, the names of things that can be opened, and the folder names are sent. Never
 *    addresses, notes, the clipboard or anything else.
 *  - The reply can only pick names that exist. Anything else is thrown away, so a made-up app never opens.
 */
(function (root) {
  'use strict';

  var core = typeof require === 'function' ? require('./core.js') : root.ConsigliereCore;

  /** The standing instructions. Short, because every word is paid for on every request. */
  var RULES = [
    'You sort the jobs on one person\'s to-do list for an app on his Mac.',
    'For each job, pick from "Things to open" the one thing he would open to do that job, or null when nothing clearly fits (a phone call, a chore away from the computer, a job too vague to tell).',
    'Then pick from "Folders" the folder the job belongs in, or null when none fits.',
    'Write every name exactly as it appears in the lists. Never invent one.'
  ].join(' ');

  /** The most jobs sent at once, and the most names of things to open. Keeps one request small and cheap. */
  var MAX_JOBS = 20;
  var MAX_CANDIDATES = 400;

  /** The shape the reply must have. Fixed, so the API can reuse it from one request to the next. */
  var SCHEMA = {
    type: 'object',
    properties: {
      jobs: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string' },
            opens: { anyOf: [{ type: 'string' }, { type: 'null' }] },
            folder: { anyOf: [{ type: 'string' }, { type: 'null' }] }
          },
          required: ['id', 'opens', 'folder'],
          additionalProperties: false
        }
      }
    },
    required: ['jobs'],
    additionalProperties: false
  };

  function live(j) { return j.status === 'open' || j.status === 'started'; }

  /** The jobs worth asking about: not finished, and missing a starter, or a folder when there are folders. */
  function needingHelp(day, ids, groups) {
    var hasGroups = !!(groups && groups.length);
    return day.jobs.filter(function (j) {
      return ids.indexOf(j.id) >= 0 && live(j) && (j.starter === null || (hasGroups && j.group === null));
    }).slice(0, MAX_JOBS);
  }

  /** Names that can be picked: every entry except tools (a job never starts the timer), each name once. */
  function candidates(catalog) {
    var seen = {}, out = [];
    catalog.forEach(function (e) {
      if (e.kind === 'tool') return;
      var key = core.normalize(e.name);
      if (!key || seen[key]) return;
      seen[key] = true;
      out.push(e.name);
    });
    return out.slice(0, MAX_CANDIDATES);
  }

  /** The words sent: { system, user }. Lists first, then the jobs, one per line with their id. */
  function buildPrompt(jobsToSort, catalog, groups) {
    var lines = ['Things to open:', candidates(catalog).join(', '), ''];
    lines.push('Folders:', groups && groups.length ? groups.join(', ') : '(none, so folder is always null)', '');
    lines.push('Jobs:');
    jobsToSort.forEach(function (j) { lines.push(j.id + ': ' + j.title); });
    return { system: RULES, user: lines.join('\n') };
  }

  /** The exact spelling from `names` that matches `value`, or null. Case and spacing do not matter. */
  function pick(value, names) {
    if (typeof value !== 'string') return null;
    var key = core.normalize(value);
    if (!key) return null;
    return names.filter(function (n) { return core.normalize(n) === key; })[0] || null;
  }

  /**
   * Reads the reply text into [{ id, starter, group }], only for jobs that were asked about, only with names
   * that exist. Text that is not the expected JSON gives an empty list: nothing changes.
   */
  function readReply(text, askedIDs, catalog, groups) {
    var parsed;
    try { parsed = JSON.parse(text); } catch (e) { return []; }
    if (!parsed || !Array.isArray(parsed.jobs)) return [];
    var names = candidates(catalog), seen = {};
    var out = [];
    parsed.jobs.forEach(function (item) {
      if (!item || typeof item.id !== 'string' || askedIDs.indexOf(item.id) < 0 || seen[item.id]) return;
      seen[item.id] = true;
      var starter = pick(item.opens, names), group = pick(item.folder, groups || []);
      if (starter === null && group === null) return;
      out.push({ id: item.id, starter: starter, group: group });
    });
    return out;
  }

  var api = { RULES: RULES, SCHEMA: SCHEMA, MAX_JOBS: MAX_JOBS, needingHelp: needingHelp, candidates: candidates,
    buildPrompt: buildPrompt, readReply: readReply };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereSmart = api;
})(typeof self !== 'undefined' ? self : this);
