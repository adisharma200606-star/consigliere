'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const r = require('./replace.js');

const LIST = [
  { shortcut: 'omw', phrase: 'On my way!' },
  { shortcut: 'brb', phrase: 'be right back' },
  { shortcut: ';sig', phrase: 'Adi Sharma' },
  { shortcut: 'addr', phrase: 'Bengaluru' },
  { shortcut: 'addrw', phrase: 'Christ University, Bengaluru' },
  { shortcut: 'now', phrase: 'right now' },
  { shortcut: '', phrase: 'never' },
  { shortcut: 'two words', phrase: 'never' },
  { shortcut: 'same', phrase: 'same' }
];

/** Types a script of steps and returns every expansion, in order, with the step it came from. */
function run(steps, list) {
  let buffer = r.newBuffer();
  const out = [];
  steps.forEach((step, stepIndex) => {
    if (step.key === 'backspace') { buffer = r.backspace(buffer); return; }
    if (step.key === 'reset') { buffer = r.newBuffer(); return; }
    Array.from(step.text).forEach((ch) => {
      const result = r.type(buffer, ch, list);
      buffer = result.buffer;
      if (result.expansion) out.push({ step: stepIndex, ...result.expansion });
    });
  });
  return { expansions: out, remembered: buffer.text.join('') };
}

test('replace: a shortcut then a space becomes the phrase, keeping the space', () => {
  assert.deepStrictEqual(run([{ text: 'omw ' }], LIST).expansions, [{ step: 0, deleteCount: 4, insert: 'On my way! ' }]);
});

test('replace: punctuation also triggers, and is kept', () => {
  assert.deepStrictEqual(run([{ text: 'brb.' }], LIST).expansions, [{ step: 0, deleteCount: 4, insert: 'be right back.' }]);
});

test('replace: only at the start of a word', () => {
  assert.deepStrictEqual(run([{ text: 'known ' }], LIST).expansions, [], '"now" inside "known" never fires');
  assert.deepStrictEqual(run([{ text: 'see you (now) ' }], LIST).expansions, [{ step: 0, deleteCount: 4, insert: 'right now)' }],
    'after a bracket counts as the start of a word');
});

test('replace: case does not matter for the shortcut', () => {
  assert.deepStrictEqual(run([{ text: 'OMW ' }], LIST).expansions, [{ step: 0, deleteCount: 4, insert: 'On my way! ' }]);
});

test('replace: shortcuts that start with punctuation work', () => {
  assert.deepStrictEqual(run([{ text: 'thanks ;sig ' }], LIST).expansions, [{ step: 0, deleteCount: 5, insert: 'Adi Sharma ' }]);
});

test('replace: the longest shortcut wins', () => {
  assert.deepStrictEqual(run([{ text: 'addrw ' }], LIST).expansions, [{ step: 0, deleteCount: 6, insert: 'Christ University, Bengaluru ' }]);
  assert.deepStrictEqual(run([{ text: 'addr ' }], LIST).expansions, [{ step: 0, deleteCount: 5, insert: 'Bengaluru ' }]);
});

test('replace: backspace is followed, so a corrected word still fires and a broken one does not', () => {
  assert.deepStrictEqual(run([{ text: 'omx' }, { key: 'backspace' }, { text: 'w ' }], LIST).expansions,
    [{ step: 2, deleteCount: 4, insert: 'On my way! ' }]);
  assert.deepStrictEqual(run([{ text: 'omw' }, { key: 'backspace' }, { text: ' ' }], LIST).expansions, []);
});

test('replace: a reset (a click, an arrow key, another app) forgets what came before', () => {
  assert.deepStrictEqual(run([{ text: 'om' }, { key: 'reset' }, { text: 'w ' }], LIST).expansions, []);
});

test('replace: right after a replacement, another shortcut works straight away', () => {
  assert.deepStrictEqual(run([{ text: 'omw brb ' }], LIST).expansions,
    [{ step: 0, deleteCount: 4, insert: 'On my way! ' }, { step: 0, deleteCount: 4, insert: 'be right back ' }]);
});

test('replace: unusable shortcuts are ignored, and memory stays short', () => {
  assert.deepStrictEqual(r.usable(LIST).map(x => x.shortcut), ['omw', 'brb', ';sig', 'addr', 'addrw', 'now']);
  assert.deepStrictEqual(run([{ text: 'same ' }], LIST).expansions, []);
  assert.strictEqual(run([{ text: 'x'.repeat(100) }], LIST).remembered.length, r.MEMORY);
});

test('write replace fixtures', () => {
  const scripts = [
    [{ text: 'omw ' }],
    [{ text: 'brb.' }],
    [{ text: 'known ' }],
    [{ text: 'see you (now) ' }],
    [{ text: 'OMW ' }],
    [{ text: 'thanks ;sig ' }],
    [{ text: 'addrw ' }],
    [{ text: 'addr, ok' }],
    [{ text: 'omx' }, { key: 'backspace' }, { text: 'w ' }],
    [{ text: 'omw' }, { key: 'backspace' }, { text: ' ' }],
    [{ text: 'om' }, { key: 'reset' }, { text: 'w ' }],
    [{ text: 'omw brb ' }],
    [{ text: 'same ' }],
    [{ text: 'x'.repeat(100) + ' omw!' }],
    [{ text: 'é omw?' }]
  ];
  const cases = scripts.map((steps) => ({ steps, ...run(steps, LIST) }));
  const dir = path.join(__dirname, '..', 'fixtures');
  fs.writeFileSync(path.join(dir, 'replace.json'),
    JSON.stringify({ list: LIST, usable: r.usable(LIST).map(x => x.shortcut), memory: r.MEMORY, cases }, null, 2));
});
