"""Puts a mafia fedora on the character: every frame of an animated GIF, following the top of his head.

    python3 scripts/hat.py in.gif out.gif

Used once to make ~/.consigliere/character/idle.gif (Gengar from Pokemon Showdown's gen5ani sprites, in a hat).
The hat is original pixel art and can live in the repo; the character it goes on stays in
~/.consigliere/character/ and is never committed. Needs Pillow (`pip3 install pillow`).

How it finds his head: in each frame, the topmost opaque row, and the middle of the opaque pixels in the
fourteen rows below it. The hat sits there, its brim a few pixels down so it rests on the head rather than
floating above the spikes. Tweak SINK and NUDGE_X if it sits wrong on a different character.
"""
import sys
from PIL import Image, ImageSequence

# The fedora, facing the viewer, cocked a little to the right. O outline, H hat, S shade, L light, W the white band.
HAT = [
    "..........OOOOO..OOOOO..........",
    ".........OHHHHHOOHHHHLO.........",
    "........OHHHHHHHHHHHHHLO........",
    "........OSHHHHHHHHHHHHLO........",
    "........OSHHHHHHHHHHHHHO........",
    "........OSSHHHHHHHHHHHHO........",
    "........OWWWWWWWWWWWWWWO........",
    "........OWWWWWWWWWWWWWWO........",
    "...OOOOOOSSSSSSSSSSSSSSOOOOOOO..",
    "..OHHHHHHHHHHHHHHHHHHHHHHHHHHLO.",
    ".OSSHHHHHHHHHHHHHHHHHHHHHHHHLLLO",
    "..OOOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
]
COLOURS = {
    "O": (8, 8, 10, 255),
    "H": (40, 40, 48, 255),
    "S": (26, 26, 32, 255),
    "L": (74, 74, 86, 255),
    "W": (232, 226, 208, 255),
}
SINK = 10       # how far below the top of his head the brim's bottom sits
NUDGE_X = 1     # a pixel to the right looks more natural on a front-facing sprite
PAD = len(HAT)  # room added above every frame, so the hat is never cut off


def head(frame):
    """(centre x, top y) of the head in an RGBA frame."""
    px = frame.load()
    w, h = frame.size
    rows = [y for y in range(h) if any(px[x, y][3] > 0 for x in range(w))]
    top = rows[0]
    band = [x for y in range(top, min(h, top + 14)) for x in range(w) if px[x, y][3] > 0]
    return round(sum(band) / len(band)), top


def main(src, dst):
    gif = Image.open(src)
    frames, durations = [], []
    for frame in ImageSequence.Iterator(gif):
        rgba = frame.convert("RGBA")
        canvas = Image.new("RGBA", (rgba.width, rgba.height + PAD), (0, 0, 0, 0))
        canvas.paste(rgba, (0, PAD))
        cx, top = head(rgba)
        left = cx - len(HAT[0]) // 2 + NUDGE_X
        brim_bottom = PAD + top + SINK
        px = canvas.load()
        for dy, row in enumerate(HAT):
            for dx, ch in enumerate(row):
                if ch != ".":
                    x, y = left + dx, brim_bottom - len(HAT) + 1 + dy
                    if 0 <= x < canvas.width and 0 <= y < canvas.height:
                        px[x, y] = COLOURS[ch]
        frames.append(canvas)
        durations.append(frame.info.get("duration", 80))
    frames[0].save(dst, save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2)
    print(f"put a hat on {len(frames)} frames -> {dst}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
