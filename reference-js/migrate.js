/*
 * Consigliere catalog migration: keeping an existing config.json in step with new built-in commands.
 *
 * The bug this exists to fix: config.json is only written with DefaultCatalog.entries the very first time
 * Consigliere ever runs. Every catalog entry added in a later update (like "flip" or "settings") would
 * otherwise never appear for someone who already has a config.json, no matter how many times they update,
 * because loading a config that already HAS a "catalog" array just uses that array as-is.
 *
 * The fix runs once at every launch: add any built-in entry that is missing and has never been offered
 * before. An entry that WAS offered before and is missing now was deleted on purpose, and stays deleted.
 */
(function (root) {
  'use strict';

  /**
   * existing:       the catalog currently on disk (his own entries, and whichever built-ins his config
   *                  happened to have when it was first written)
   * defaults:        the full, current built-in catalog (DefaultCatalog.entries)
   * alreadyOffered:  names of built-ins ever added by a previous run of this function (array)
   * Returns { catalog, offered }. `offered` is sorted, for stable, comparable output.
   */
  function mergeBuiltinCatalog(existing, defaults, alreadyOffered) {
    var existingNames = {};
    existing.forEach(function (e) { existingNames[e.name] = true; });
    var offeredSet = {};
    (alreadyOffered || []).forEach(function (n) { offeredSet[n] = true; });
    var merged = existing.slice();

    defaults.forEach(function (d) {
      if (existingNames[d.name]) {
        offeredSet[d.name] = true;   // present already: remember it, so a later deletion sticks
        return;
      }
      if (offeredSet[d.name]) return; // offered before, missing now: removed on purpose, leave it removed
      merged.push(d);                 // new since this install was set up, never offered: add it once
      existingNames[d.name] = true;
      offeredSet[d.name] = true;
    });

    return { catalog: merged, offered: Object.keys(offeredSet).sort() };
  }

  var api = { mergeBuiltinCatalog: mergeBuiltinCatalog };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereMigrate = api;
})(typeof self !== 'undefined' ? self : this);
