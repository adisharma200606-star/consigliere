"""Builds the self-contained phone prototype: inlines the reference core,
the default catalog and the seed lines into template.html."""
import json, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
html = (root / 'prototype' / 'template.html').read_text()
core = (root / 'reference-js' / 'core.js').read_text()
catalog = json.loads((root / 'defaults' / 'catalog.json').read_text())
lines_path = root / 'defaults' / 'lines.json'  # built by scripts/build_lines.py
if not lines_path.exists():
    lines_path = root / 'defaults' / 'lines.seed.json'
lines = json.loads(lines_path.read_text())
assert '</script' not in core
html = html.replace('/*__CORE__*/', core)
tuner = (root / 'reference-js' / 'tuner.js').read_text()
assert '</script' not in tuner
html = html.replace('/*__TUNER__*/', tuner)
html = html.replace('/*__EXTRAS__*/', (root / 'reference-js' / 'extras.js').read_text())
html = html.replace('/*__CAPTURE__*/', (root / 'reference-js' / 'capture.js').read_text())
import base64
sounds = {f.stem: base64.b64encode(f.read_bytes()).decode() for f in sorted((root / 'App' / 'Consigliere' / 'Resources' / 'sounds').glob('*.wav'))}
html = html.replace('/*__SOUNDS__*/{}', json.dumps(sounds))
html = html.replace('/*__TUNINGS__*/[]', json.dumps(json.loads((root / 'defaults' / 'tunings.json').read_text())))
html = html.replace('/*__CATALOG__*/[]', json.dumps(catalog))
html = html.replace('/*__LINES__*/{}', json.dumps(lines))
out = root / 'prototype' / 'index.html'
out.write_text(html)
print('built', out, len(html), 'bytes')
