/*
 * Consigliere key gestures: double-tap a modifier key, or hold one, instead of a typed-out hotkey.
 *
 *   double-tap Option   -> open the box
 *   double-tap Control  -> save the page in front
 *   hold right Option   -> talk; let go to run
 *
 * Why: hotkeys written as text ("ctrl+opt+s") break on one typo, and opt+space sits confusingly next to
 * the Mac's own cmd+space. A modifier key types nothing, so tapping it twice is safe in any app.
 *
 * This file is only the deciding part. The app tells it when a modifier goes down or up, when any other key
 * or mouse button is pressed, and what time it is; it answers with what happened. Times are milliseconds.
 *
 * The rules:
 *   - A tap is a modifier pressed alone and let go within TAP_MAX, with nothing else pressed meanwhile.
 *   - A double-tap is two taps of the same key, the second starting within GAP_MAX of the first ending.
 *     (So Option+E for an accent, or Control+C, is never a tap: another key was pressed.)
 *   - A hold is right Option kept down alone for HOLD_AFTER. It ends when the key is let go. A hold is
 *     never also a tap.
 */
(function (root) {
  'use strict';

  var TAP_MAX = 300;
  var GAP_MAX = 350;
  var HOLD_AFTER = 350;

  function newState() {
    return { downKey: null, downSide: null, downAt: 0, clean: false, lastTapKey: null, lastTapUpAt: 0, holding: false };
  }

  function copy(s) { return Object.assign({}, s); }

  /** A modifier went down. `alone` is false when another modifier was already held. */
  function down(state, key, side, t, alone) {
    var s = copy(state);
    if (s.holding) return { state: s, event: null };
    if (!alone) { return { state: newState(), event: null }; }
    s.downKey = key; s.downSide = side; s.downAt = t; s.clean = true;
    return { state: s, event: null };
  }

  /** A modifier was let go. */
  function up(state, key, t) {
    var s = copy(state);
    if (s.holding) {
      if (key !== s.downKey) return { state: s, event: null };
      return { state: newState(), event: 'holdEnd' };
    }
    var wasTap = s.downKey === key && s.clean && (t - s.downAt) <= TAP_MAX;
    var event = null;
    if (wasTap) {
      if (s.lastTapKey === key && (s.downAt - s.lastTapUpAt) <= GAP_MAX) {
        event = 'double:' + key;
        s.lastTapKey = null;
      } else {
        s.lastTapKey = key; s.lastTapUpAt = t;
      }
    } else {
      s.lastTapKey = null;
    }
    s.downKey = null; s.downSide = null; s.clean = false;
    return { state: s, event: event };
  }

  /** Any normal key or a mouse button: whatever was going on is not a tap. A hold in progress carries on. */
  function other(state) {
    var s = copy(state);
    s.clean = false; s.lastTapKey = null;
    return { state: s, event: null };
  }

  /** Time passing: has right Option been held alone long enough to start talking? */
  function tick(state, t) {
    var s = copy(state);
    if (!s.holding && s.downKey === 'option' && s.downSide === 'right' && s.clean && (t - s.downAt) >= HOLD_AFTER) {
      s.holding = true;
      return { state: s, event: 'holdStart' };
    }
    return { state: s, event: null };
  }

  var api = { TAP_MAX: TAP_MAX, GAP_MAX: GAP_MAX, HOLD_AFTER: HOLD_AFTER, newState: newState, down: down, up: up, other: other, tick: tick };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereTaps = api;
})(typeof self !== 'undefined' ? self : this);
