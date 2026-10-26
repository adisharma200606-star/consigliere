"""Draws the little dragon that lives in the notch, as pixel art, into App/Consigliere/Resources/character/.

He is original art, made here, so he can ship in the repo. To use someone else (a Dragonite, say), drop your
own PNGs into ~/.consigliere/character/ (see docs/GUIDE.md, "The character"); those are never committed.

Four frames, all facing right (the app mirrors them when he flies left):
  dragon_idle_0, dragon_idle_1   sitting, bobbing one pixel
  dragon_fly_0, dragon_fly_1     wings up, wings down
No libraries needed: the PNGs are written by hand with zlib.
"""
import pathlib, struct, zlib

PALETTE = {
    '.': (0, 0, 0, 0),
    'K': (43, 33, 51, 255),      # outline
    'O': (242, 154, 58, 255),    # body
    'C': (247, 225, 176, 255),   # belly
    'W': (255, 255, 255, 255),   # the shine in his eye
    'G': (63, 163, 155, 255),    # wing
    'g': (46, 122, 116, 255),    # wing, darker
}

SIZE = 20

BODY = [
    "....................",
    "...........KKKK.....",
    "..........KOOOOK....",
    ".........KOOOOOOK...",
    ".........KOOOKWOK...",
    ".........KOOOKKOK...",
    ".........KOOOOOOOK..",
    "........KOOOCCCOK...",
    ".......KOOOCCCCK....",
    "......KOOOCCCCCK....",
    "......KOOCCCCCCK....",
    ".....KOOOCCCCCCK....",
    "....KOOOOCCCCCCK....",
    "...KOOOOOCCCCCOK....",
    "..KOKOOOOOCCCOOK....",
    ".KOK.KOOOOOOOOK.....",
    ".KK...KOOKKOOK......",
    ".......KKK.KKK......",
    "....................",
    "....................",
]

WING = [
    ".KK...",
    "KGGK..",
    "KGgGK.",
    ".KGgGK",
    "..KGGK",
]


def canvas():
    return [['.'] * SIZE for _ in range(SIZE)]


def stamp(grid, pattern, x, y):
    for dy, row in enumerate(pattern):
        for dx, ch in enumerate(row):
            if ch != '.' and 0 <= y + dy < SIZE and 0 <= x + dx < SIZE:
                grid[y + dy][x + dx] = ch


def frame(wing_y, shift=0):
    grid = canvas()
    stamp(grid, WING, 2, wing_y + shift)
    stamp(grid, [r.ljust(SIZE, '.') for r in BODY], 0, shift)
    return grid


def png(grid, path):
    raw = b''.join(b'\x00' + b''.join(bytes(PALETTE[ch]) for ch in row) for row in grid)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    path.write_bytes(data)


root = pathlib.Path(__file__).resolve().parent.parent
out = root / 'App' / 'Consigliere' / 'Resources' / 'character'
out.mkdir(parents=True, exist_ok=True)
frames = {
    'dragon_idle_0': frame(7),
    'dragon_idle_1': frame(7, shift=1),
    'dragon_fly_0': frame(4),
    'dragon_fly_1': frame(9),
}
for name, grid in frames.items():
    png(grid, out / f'{name}.png')
print('drew', len(frames), 'frames into', out.relative_to(root))
