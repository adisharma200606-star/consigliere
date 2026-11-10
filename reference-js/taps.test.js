'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const taps = require('./taps.js');

/** Runs a script of steps and returns the events, each with the time it happened. */
function run(steps) {
  let state = taps.newState();
  const out = [];
  for (const s of steps) {
    let r;
    if (s.do === 'down') r = taps.down(state, s.key, s.side || 'left', s.t, s.alone !== false);
    else if (s.do === 'up') r = taps.up(state, s.key, s.t);
    else if (s.do === 'other') r = taps.other(state);
    else r = taps.tick(state, s.t);
    state = r.state;
    if (r.event) out.push({ t: s.t, event: r.event });
  }
  return out;
}

const D = (key, t, side, alone) => ({ do: 'down', key, t, side: side || 'left', alone: alone !== false });
const U = (key, t) => ({ do: 'up', key, t });
const O = (t) => ({ do: 'other', t });
const T = (t) => ({ do: 'tick', t });

const SCRIPTS = {
  doubleOption: [D('option', 0), U('option', 80), D('option', 200), U('option', 270)],
  doubleControl: [D('control', 0), U('control', 90), D('control', 250), U('control', 330)],
  singleTap: [D('option', 0), U('option', 80)],
  tooSlowBetween: [D('option', 0), U('option', 80), D('option', 500), U('option', 580)],
  pressTooLong: [D('option', 0), U('option', 400), D('option', 500), U('option', 560)],
  differentKeys: [D('option', 0), U('option', 80), D('control', 200), U('control', 260)],
  accentTyping: [D('option', 0), O(50), U('option', 120), D('option', 200), U('option', 260)],
  keyBetweenTaps: [D('option', 0), U('option', 80), O(120), D('option', 200), U('option', 260)],
  withAnotherModifier: [D('command', 0), D('option', 20, 'left', false), U('option', 60), U('command', 80)],
  tripleTapIsOneDouble: [D('option', 0), U('option', 60), D('option', 150), U('option', 210), D('option', 300), U('option', 360)],
  holdRightOption: [D('option', 0, 'right'), T(100), T(360), T(900), U('option', 1500)],
  holdLeftOptionDoesNothing: [D('option', 0, 'left'), T(400), U('option', 1500)],
  holdBrokenByKey: [D('option', 0, 'right'), O(100), T(400), U('option', 900)],
  doubleTapRightOptionStillOpens: [D('option', 0, 'right'), T(50), U('option', 80), D('option', 200, 'right'), T(250), U('option', 270)],
  keysDuringHoldDoNotEndIt: [D('option', 0, 'right'), T(360), O(500), T(600), U('option', 1200)],
  otherModifierUpDuringHold: [D('option', 0, 'right'), T(360), U('control', 500), U('option', 800)]
};

test('taps: tapping Option or Control twice quickly is a double-tap', () => {
  assert.deepStrictEqual(run(SCRIPTS.doubleOption), [{ t: 270, event: 'double:option' }]);
  assert.deepStrictEqual(run(SCRIPTS.doubleControl), [{ t: 330, event: 'double:control' }]);
});

test('taps: one tap, a slow second tap, a long press, or two different keys do nothing', () => {
  assert.deepStrictEqual(run(SCRIPTS.singleTap), []);
  assert.deepStrictEqual(run(SCRIPTS.tooSlowBetween), []);
  assert.deepStrictEqual(run(SCRIPTS.pressTooLong), []);
  assert.deepStrictEqual(run(SCRIPTS.differentKeys), []);
});

test('taps: using the key normally (an accent, a shortcut, with another modifier) is never a tap', () => {
  assert.deepStrictEqual(run(SCRIPTS.accentTyping), []);
  assert.deepStrictEqual(run(SCRIPTS.keyBetweenTaps), []);
  assert.deepStrictEqual(run(SCRIPTS.withAnotherModifier), []);
});

test('taps: three quick taps are one double-tap, not two', () => {
  assert.deepStrictEqual(run(SCRIPTS.tripleTapIsOneDouble), [{ t: 210, event: 'double:option' }]);
});

test('taps: holding right Option starts talking, letting go ends it', () => {
  assert.deepStrictEqual(run(SCRIPTS.holdRightOption), [{ t: 360, event: 'holdStart' }, { t: 1500, event: 'holdEnd' }]);
  assert.deepStrictEqual(run(SCRIPTS.holdLeftOptionDoesNothing), []);
  assert.deepStrictEqual(run(SCRIPTS.holdBrokenByKey), []);
  assert.deepStrictEqual(run(SCRIPTS.keysDuringHoldDoNotEndIt), [{ t: 360, event: 'holdStart' }, { t: 1200, event: 'holdEnd' }]);
  assert.deepStrictEqual(run(SCRIPTS.otherModifierUpDuringHold), [{ t: 360, event: 'holdStart' }, { t: 800, event: 'holdEnd' }]);
});

test('taps: right Option can still be double-tapped', () => {
  assert.deepStrictEqual(run(SCRIPTS.doubleTapRightOptionStillOpens), [{ t: 270, event: 'double:option' }]);
});

test('write taps fixtures', () => {
  const cases = Object.keys(SCRIPTS).map((name) => ({ name, steps: SCRIPTS[name], events: run(SCRIPTS[name]) }));
  fs.writeFileSync(path.join(__dirname, '..', 'fixtures', 'taps.json'),
    JSON.stringify({ tapMax: taps.TAP_MAX, gapMax: taps.GAP_MAX, holdAfter: taps.HOLD_AFTER, cases }, null, 2));
});
