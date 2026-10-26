/*
 * Consigliere tuner: reference implementation.
 *
 * Pure maths, no microphone. The Swift package ports this file. It has three layers:
 *   1. notes      note names <-> MIDI numbers <-> frequencies
 *   2. detect     YIN pitch detection on a buffer of samples
 *   3. session    turns a jumpy stream of readings into a steady display
 */
(function (root) {
  'use strict';

  // ---------------------------------------------------------------- notes ----

  var NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  var BASE = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

  /** "E2", "F#3", "Bb3" -> MIDI note number. Returns null when it cannot be read. */
  function parseNote(name) {
    var m = /^([A-Ga-g])([#b]?)(-?\d+)$/.exec(String(name || '').trim());
    if (!m) return null;
    var semitone = BASE[m[1].toUpperCase()] + (m[2] === '#' ? 1 : m[2] === 'b' ? -1 : 0);
    return (parseInt(m[3], 10) + 1) * 12 + semitone;
  }

  function midiToFrequency(midi, a4) { return (a4 || 440) * Math.pow(2, (midi - 69) / 12); }
  function frequencyToMidi(freq, a4) { return 69 + 12 * (Math.log(freq / (a4 || 440)) / Math.LN2); }
  function centsBetween(freq, target) { return 1200 * (Math.log(freq / target) / Math.LN2); }

  /** Nearest note to a frequency, and how many cents sharp (+) or flat (-) it is. */
  function describe(freq, a4) {
    var exact = frequencyToMidi(freq, a4);
    var nearest = Math.round(exact);
    var pitchClass = ((nearest % 12) + 12) % 12;
    return { midi: nearest, name: NAMES[pitchClass], octave: Math.floor(nearest / 12) - 1, cents: (exact - nearest) * 100 };
  }

  /** Expand a tuning's note names into MIDI numbers and target frequencies. */
  function resolveTuning(tuning, a4) {
    return {
      id: tuning.id, instrument: tuning.instrument, name: tuning.name,
      strings: tuning.strings.map(function (note) {
        var midi = parseNote(note);
        return { note: note, midi: midi, frequency: midiToFrequency(midi, a4) };
      })
    };
  }

  // --------------------------------------------------------------- detect ----

  var DEFAULTS = { minFrequency: 45, maxFrequency: 1200, threshold: 0.12, giveUpAbove: 0.35 };

  /**
   * YIN pitch detection (de Cheveigne and Kawahara, 2002).
   * samples: array of numbers in -1...1. 4096 samples at 44.1 or 48 kHz reaches down to about 45 Hz,
   * which covers Drop A (55 Hz).
   * Returns { frequency, clarity, rms } or null when the sound has no clear pitch.
   *   clarity: 0...1, how confident the match is. rms: loudness, for a noise gate.
   */
  function detectPitch(samples, sampleRate, options) {
    var o = options || {};
    var minF = o.minFrequency || DEFAULTS.minFrequency, maxF = o.maxFrequency || DEFAULTS.maxFrequency;
    var threshold = o.threshold || DEFAULTS.threshold, giveUpAbove = o.giveUpAbove || DEFAULTS.giveUpAbove;
    var n = samples.length;
    if (n < 64) return null;

    var tauMax = Math.min(Math.floor(sampleRate / minF), Math.floor(n / 2));
    var tauMin = Math.max(2, Math.floor(sampleRate / maxF));
    if (tauMax <= tauMin + 2) return null;
    var windowLength = n - tauMax;

    // Remove any constant offset, and measure loudness.
    var mean = 0, i;
    for (i = 0; i < n; i++) mean += samples[i];
    mean /= n;
    var x = new Array(n), energy = 0;
    for (i = 0; i < n; i++) { x[i] = samples[i] - mean; energy += x[i] * x[i]; }
    var rms = Math.sqrt(energy / n);
    if (rms === 0) return null;

    // Step 1 and 2: the difference function.
    var diff = new Array(tauMax + 1);
    diff[0] = 0;
    for (var tau = 1; tau <= tauMax; tau++) {
      var sum = 0;
      for (var j = 0; j < windowLength; j++) { var delta = x[j] - x[j + tau]; sum += delta * delta; }
      diff[tau] = sum;
    }

    // Step 3: cumulative mean normalised difference.
    var cmnd = new Array(tauMax + 1);
    cmnd[0] = 1;
    var running = 0;
    for (tau = 1; tau <= tauMax; tau++) {
      running += diff[tau];
      cmnd[tau] = running === 0 ? 1 : diff[tau] * tau / running;
    }

    // Step 4: the first dip under the threshold, followed down to its lowest point.
    var found = -1;
    for (tau = tauMin; tau <= tauMax; tau++) {
      if (cmnd[tau] < threshold) {
        while (tau + 1 <= tauMax && cmnd[tau + 1] < cmnd[tau]) tau++;
        found = tau;
        break;
      }
    }
    if (found < 0) {
      // Nothing clearly periodic. Take the best dip if it is at least plausible.
      var best = tauMin;
      for (tau = tauMin + 1; tau <= tauMax; tau++) if (cmnd[tau] < cmnd[best]) best = tau;
      if (cmnd[best] > giveUpAbove) return null;
      found = best;
    }

    // Step 5: parabolic interpolation on the raw difference function for a sub-sample period.
    var period = found;
    if (found > 1 && found < tauMax) {
      var s0 = diff[found - 1], s1 = diff[found], s2 = diff[found + 1];
      var denominator = s0 + s2 - 2 * s1;
      if (denominator !== 0) {
        var shift = (s0 - s2) / (2 * denominator);
        if (shift > -1 && shift < 1) period = found + shift;
      }
    }

    return { frequency: sampleRate / period, clarity: Math.max(0, Math.min(1, 1 - cmnd[found])), rms: rms };
  }

  // -------------------------------------------------------------- strings ----

  /**
   * Which string of the tuning is this closest to, and how far off is it?
   *
   * Deliberately simple: nearest string, nothing clever. An earlier version tried to "fold" readings
   * that were an octave out onto the right string, but that makes a slack new string passing through
   * 55 Hz read as "A2, in tune". Stray octave slips are handled in the session instead, by ignoring a
   * change of string until two readings in a row agree.
   */
  function matchString(freq, resolved) {
    var bestIndex = 0, bestCents = Infinity;
    for (var i = 0; i < resolved.strings.length; i++) {
      var c = centsBetween(freq, resolved.strings[i].frequency);
      if (Math.abs(c) < Math.abs(bestCents)) { bestCents = c; bestIndex = i; }
    }
    var s = resolved.strings[bestIndex];
    return { index: bestIndex, note: s.note, targetFrequency: s.frequency, cents: bestCents };
  }

  // -------------------------------------------------------------- session ----

  var SESSION = { minClarity: 0.85, minRms: 0.01, toleranceCents: 5, lockAfterMs: 350, holdMs: 1200, windowMs: 600, keep: 7, switchAfter: 2 };

  function newSession(options) {
    var o = {}, k;
    for (k in SESSION) o[k] = SESSION[k];
    for (k in (options || {})) o[k] = options[k];
    return { options: o, key: null, pendingKey: null, pendingCount: 0, readings: [], inTuneSince: null, lastValidAt: null, last: null,
      lockedStrings: [], celebrated: false };
  }

  function median(values) {
    var s = values.slice().sort(function (a, b) { return a - b; });
    var mid = Math.floor(s.length / 2);
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  /**
   * Feed one detector reading (or null for "no pitch") and get back what the notch should show.
   * resolved: a resolved tuning, or null for chromatic mode (nearest note of any kind).
   *
   * state: "idle"      nothing heard for a while; show "pluck a string"
   *        "listening" a fresh reading; cents is the smoothed value
   *        "holding"   the note has just stopped ringing; keep the last display briefly
   */
  function feed(session, reading, nowMs, resolved, a4) {
    var o = session.options;
    var valid = !!reading && reading.clarity >= o.minClarity && reading.rms >= o.minRms && reading.frequency > 0;

    if (!valid) {
      if (session.last && session.lastValidAt !== null && nowMs - session.lastValidAt <= o.holdMs) {
        var held = {}; for (var k in session.last) held[k] = session.last[k];
        held.state = 'holding'; held.allInTuneNow = false;
        return held;
      }
      session.key = null; session.pendingKey = null; session.pendingCount = 0;
      session.readings = []; session.inTuneSince = null; session.last = null;
      return { state: 'idle', label: null, octave: null, stringIndex: null, cents: 0, inTune: false, frequency: null, allInTuneNow: false };
    }

    var key, label, octave, stringIndex, cents;
    if (resolved) {
      var m = matchString(reading.frequency, resolved);
      key = 's' + m.index; label = m.note; octave = null; stringIndex = m.index; cents = m.cents;
    } else {
      var d = describe(reading.frequency, a4);
      key = 'm' + d.midi; label = d.name; octave = d.octave; stringIndex = null; cents = d.cents;
    }

    // A different string or note only takes over once `switchAfter` readings in a row agree on it.
    // One stray reading (an octave slip, a knock on the desk) changes nothing.
    if (key !== session.key && session.key !== null) {
      if (key === session.pendingKey) session.pendingCount += 1;
      else { session.pendingKey = key; session.pendingCount = 1; }
      if (session.pendingCount < o.switchAfter) {
        session.lastValidAt = nowMs;
        var kept = {}; for (var p in session.last) kept[p] = session.last[p];
        kept.allInTuneNow = false;
        return kept;
      }
    }
    if (key !== session.key) { session.key = key; session.readings = []; session.inTuneSince = null; }
    session.pendingKey = null; session.pendingCount = 0;
    session.readings.push({ cents: cents, at: nowMs });
    session.readings = session.readings.filter(function (r) { return nowMs - r.at <= o.windowMs; });
    if (session.readings.length > o.keep) session.readings = session.readings.slice(session.readings.length - o.keep);

    var smoothed = median(session.readings.map(function (r) { return r.cents; }));
    if (Math.abs(smoothed) <= o.toleranceCents) {
      if (session.inTuneSince === null) session.inTuneSince = nowMs;
    } else {
      session.inTuneSince = null;
    }
    var locked = session.inTuneSince !== null && nowMs - session.inTuneSince >= o.lockAfterMs;

    // The one moment worth a line from the voice: every string of the tuning has locked at least once.
    var allInTuneNow = false;
    if (locked && resolved && stringIndex !== null && session.lockedStrings.indexOf(stringIndex) < 0) {
      session.lockedStrings.push(stringIndex);
      if (!session.celebrated && session.lockedStrings.length === resolved.strings.length) {
        session.celebrated = true; allInTuneNow = true;
      }
    }

    session.lastValidAt = nowMs;
    session.last = { state: 'listening', label: label, octave: octave, stringIndex: stringIndex, cents: smoothed, inTune: locked, frequency: reading.frequency };
    var shown = {}; for (var f in session.last) shown[f] = session.last[f];
    shown.allInTuneNow = allInTuneNow;
    return shown;
  }

  // ------------------------------------------------------- test signals ----

  /**
   * A plucked-string-like test tone: a stack of harmonics that die away, with a deliberately weak
   * fundamental when `weakFundamental` is set, which is what a laptop microphone does to low strings.
   * `noise` adds deterministic pseudo-random hiss (Park-Miller, which stays exact in a double, so every port makes the same numbers).
   */
  function synthString(frequency, sampleRate, length, options) {
    var o = options || {};
    var amps = o.weakFundamental ? [0.08, 1.0, 0.7, 0.45, 0.3, 0.2] : [1.0, 0.6, 0.4, 0.25, 0.15, 0.1];
    var noise = o.noise || 0, seed = 12345, out = new Array(length), peak = 0, i, h;
    for (i = 0; i < length; i++) {
      var t = i / sampleRate, v = 0;
      for (h = 0; h < amps.length; h++) {
        var f = frequency * (h + 1);
        if (f < sampleRate / 2) v += amps[h] * Math.sin(2 * Math.PI * f * t + h * 0.7) * Math.exp(-t * (1.5 + h));
      }
      if (noise) { seed = (seed * 48271) % 2147483647; v += noise * (seed / 2147483647 * 2 - 1); }
      out[i] = v; if (Math.abs(v) > peak) peak = Math.abs(v);
    }
    for (i = 0; i < length; i++) out[i] = out[i] / (peak || 1) * 0.5;
    return out;
  }

  var api = {
    NAMES: NAMES, parseNote: parseNote, midiToFrequency: midiToFrequency, frequencyToMidi: frequencyToMidi,
    centsBetween: centsBetween, describe: describe, resolveTuning: resolveTuning,
    detectPitch: detectPitch, matchString: matchString,
    newSession: newSession, feed: feed, median: median, synthString: synthString, SESSION: SESSION
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.ConsigliereTuner = api;
})(typeof self !== 'undefined' ? self : this);
