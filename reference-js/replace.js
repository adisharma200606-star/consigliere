/*
 * Consigliere text replacement: the macOS "Text Replacements" list (omw -> On my way!) for apps that ignore it.
 *
 * Why this exists: Safari and Apple's own apps run macOS's text system, which does the replacing. Brave (like
 * every Chromium browser) handles typing in web pages itself and skips it, so the list Adi keeps in
 * System Settings does nothing there. Consigliere watches the keys typed in Brave, and when a shortcut is
 * followed by a space or punctuation, it deletes the shortcut and types the phrase.
 *
 * This file is only the deciding part, with no keyboard in it: feed it one typed character at a time and it
 * says when to replace, how many characters to delete, and what to type instead. It keeps the last few
 * characters typed and nothing else; nothing is saved anywhere.
 *
 * The rules, chosen to feel like macOS's own:
 *   - A replacement happens when a delimiter (space . , ! ? ; : ) ) is typed right after a shortcut.
 *   - The shortcut must start a word: at the start of what has been typed, or after a non-letter/digit
 *     (so "now" does not fire inside "known").
 *   - Shortcuts match regardless of case ("OMW" works for "omw"); the phrase is typed exactly as written.
 *   - The longest matching shortcut wins; if two are equally long, the first in the list.
 *   - The delimiter is kept: "omw " becomes "On my way! ".
 *   - After a replacement the remembered text starts empty, so a shortcut typed straight after works too.
 */
(function (root) {
  'use strict';

  var DELIMITERS = [' ', '.', ',', '!', '?', ';', ':', ')'];
  /** How many typed characters are remembered. Longer than any sensible shortcut. */
  var MEMORY = 64;

  function chars(s) { return Array.from(String(s)); }
  function isWordChar(ch) { return /[\p{L}\p{N}]/u.test(ch); }

  /** Shortcuts that can never work are dropped: empty, containing spaces, or the same as their phrase. */
  function usable(list) {
    return (list || []).filter(function (r) {
      var s = String(r.shortcut || '');
      var p = String(r.phrase || '');
      return s.length > 0 && p.length > 0 && !/\s/.test(s) && s !== p;
    });
  }

  function newBuffer() { return { text: [] }; }

  /**
   * One character typed. Returns { buffer, expansion }, where expansion is null or
   * { deleteCount, insert }: press backspace deleteCount times, then type insert.
   */
  function type(buffer, ch, list) {
    var text = buffer.text.slice();
    if (DELIMITERS.indexOf(ch) !== -1) {
      var best = null;
      usable(list).forEach(function (r) {
        var s = chars(r.shortcut);
        if (s.length > text.length) return;
        // Compared character by character (not by string length), so emoji and accents count as one each.
        if (text.slice(text.length - s.length).join('').toLowerCase() !== s.join('').toLowerCase()) return;
        var before = text.length - s.length - 1;
        if (before >= 0 && isWordChar(text[before])) return;
        if (!best || s.length > chars(best.shortcut).length) best = r;
      });
      if (best) {
        return { buffer: newBuffer(), expansion: { deleteCount: chars(best.shortcut).length + 1, insert: best.phrase + ch } };
      }
    }
    text.push(ch);
    if (text.length > MEMORY) text = text.slice(text.length - MEMORY);
    return { buffer: { text: text }, expansion: null };
  }

  function backspace(buffer) { return { text: buffer.text.slice(0, -1) }; }

  var api = { DELIMITERS: DELIMITERS, MEMORY: MEMORY, usable: usable, newBuffer: newBuffer, type: type, backspace: backspace };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereReplace = api;
})(typeof self !== 'undefined' ? self : this);
