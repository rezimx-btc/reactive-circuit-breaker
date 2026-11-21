#!/usr/bin/env python3
"""Render the recorded Reactive demo typescript to an .mp4 video.

Input: docs/demo-recorded.typescript + docs/demo-recorded.timing (from `script -T`),
a faithful capture of a REAL live run of `bash docs/demo.sh` (run #2,
2026-11-21): normal withdrawal -> legitimate burst (3 known senders,
0.002 ETH x3) -> reactive callback pauses the vault -> 4th withdrawal
reverts -> Groq AI agent classifies LEGITIMATE -> verdict on-chain ->
vault unpauses -> withdrawals resume.

Long idle gaps (75s window wait, 25s burst spacing) are time-compressed
(cap 12 s each); the terminal text itself is reproduced verbatim, in
recorded order. Nothing is staged: every line on screen is real output
of that run.

Usage: python3 docs/render-demo-video.py
Output: video/reactive-circuit-breaker-demo.mp4 (1280x720, 10 fps, H.264)
Requires: PIL, numpy, ffmpeg on PATH, DejaVu Sans Mono.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPESCRIPT = ROOT / "docs" / "demo-recorded.typescript"
TIMING = ROOT / "docs" / "demo-recorded.timing"
OUT = ROOT / "video" / "reactive-circuit-breaker-demo.mp4"

W, H = 1280, 720
COLS, ROWS = 118, 34
FONT_SIZE = 16
FPS = 10
GAP_CAP = 12.0  # seconds; idle waits longer than this are shortened
TITLE_S, END_S = 3.0, 4.0

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
BG = (12, 12, 12)
FG = (204, 204, 204)
COLORS = {
    30: (110, 110, 110), 31: (224, 108, 117), 32: (78, 201, 78),
    33: (229, 192, 123), 34: (97, 175, 239), 35: (198, 120, 221),
    36: (86, 182, 194), 37: (204, 204, 204), 90: (130, 130, 130),
    91: (224, 108, 117), 92: (98, 209, 98), 93: (229, 192, 123),
    94: (97, 175, 239), 95: (198, 120, 221), 96: (86, 182, 194),
    97: (255, 255, 255),
}


class Screen:
    def __init__(self):
        self.lines = [[(" ", FG, False)] * COLS]  # rows of (char, fg, bold)
        self.r = 0
        self.c = 0
        self.fg = FG
        self.bold = False

    def _ensure_row(self, r):
        while len(self.lines) <= r:
            self.lines.append([(" ", FG, False)] * COLS)

    def put(self, ch):
        if self.c >= COLS:
            self.c = 0
            self.r += 1
        self._ensure_row(self.r)
        self.lines[self.r][self.c] = (ch, self.fg, self.bold)
        self.c += 1

    def newline(self):
        self.r += 1
        self.c = 0
        self._ensure_row(self.r)

    def clear_eol(self):
        self._ensure_row(self.r)
        for i in range(self.c, COLS):
            self.lines[self.r][i] = (" ", FG, False)

    def snapshot(self):
        return [row[:] for row in self.lines]


def feed(screen, data: bytes):
    """Apply one timing chunk to the screen (minimal ANSI handling)."""
    text = data.decode("utf-8", errors="replace")
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "\x1b" and i + 1 < n and text[i + 1] == "[":
            m = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", text[i:])
            if m:
                params, cmd = m.group(1), m.group(2)
                i += m.end()
                if cmd == "m":
                    for p in (params.split(";") if params else ["0"]):
                        try:
                            code = int(p)
                        except ValueError:
                            continue
                        if code == 0:
                            screen.fg, screen.bold = FG, False
                        elif code == 1:
                            screen.bold = True
                        elif code in COLORS:
                            screen.fg = COLORS[code]
                elif cmd == "K":
                    screen.clear_eol()
                elif cmd == "J":
                    screen.lines = [[(" ", FG, False)] * COLS]
                    screen.r = screen.c = 0
                elif cmd == "H":
                    screen.r = screen.c = 0
                continue
            i += 1
            continue
        if ch == "\r":
            screen.c = 0
        elif ch == "\n":
            screen.newline()
        elif ch == "\b":
            screen.c = max(0, screen.c - 1)
        elif ch == "\t":
            screen.c = min(COLS - 1, (screen.c // 8 + 1) * 8)
        elif ord(ch) >= 32:
            screen.put(ch)
        i += 1


def render_text_frame(draw_lines, title=None, subtitle=None, tagline=None):
    """Render one 1280x720 frame. draw_lines: list of (text, fg, bold)."""
    from PIL import Image, ImageDraw, ImageFont

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.truetype(FONT, FONT_SIZE)
        fb = ImageFont.truetype(FONT_BOLD, FONT_SIZE)
    except OSError:
        f = fb = ImageFont.load_default()
    lh = FONT_SIZE + 4
    if title is not None:
        tf = ImageFont.truetype(FONT_BOLD, 44)
        sf = ImageFont.truetype(FONT, 22)
        d.text((W // 2, 250), title, font=tf, fill=(255, 255, 255), anchor="mm")
        if subtitle:
            d.text((W // 2, 320), subtitle, font=sf, fill=(180, 180, 180), anchor="mm")
        if tagline:
            d.text((W // 2, 380), tagline, font=sf, fill=(120, 200, 120), anchor="mm")
        return img
    y = 24
    for text, fg, bold in draw_lines:
        d.text((24, y), text, font=fb if bold else f, fill=fg)
        y += lh
    return img


def screen_to_draw_lines(snapshot):
    vis = snapshot[-ROWS:]
    out = []
    for row in vis:
        out.append(("".join(ch for ch, _, _ in row).rstrip(), FG, False))
    return out


def main():
    raw = TYPESCRIPT.read_bytes()
    # drop `script` header/footer lines
    lines = raw.split(b"\n")
    body = [ln for ln in lines
            if not ln.startswith(b"Script started on")
            and not ln.startswith(b"Script done on")]
    data = b"\n".join(body)
    timing = []
    for ln in TIMING.read_text().splitlines():
        p = ln.split()
        if len(p) == 2:
            timing.append((float(p[0]), int(p[1])))
    total_raw = sum(d for d, _ in timing)
    total_comp = sum(min(d, GAP_CAP) for d, _ in timing)
    print(f"chunks={len(timing)} raw={total_raw:.1f}s compressed={total_comp:.1f}s "
          f"(cap {GAP_CAP}s) + title {TITLE_S}s + end {END_S}s")

    screen = Screen()
    segments = []  # (snapshot, hold_seconds)
    pos = 0
    for delay, nbytes in timing:
        chunk = data[pos:pos + nbytes]
        pos += nbytes
        feed(screen, chunk)
        segments.append((screen.snapshot(), min(delay, GAP_CAP)))
    print(f"total frames ~ {(total_comp + TITLE_S + END_S) * FPS:.0f} "
          f"-> duration ~ {total_comp + TITLE_S + END_S:.0f}s")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    ff = subprocess.Popen([
        "ffmpeg", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-movflags", "+faststart", str(OUT),
    ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import numpy as np

    def emit(img, seconds):
        frames = max(1, round(seconds * FPS))
        arr = np.asarray(img, dtype="uint8").tobytes()
        for _ in range(frames):
            ff.stdin.write(arr)

    # title card
    title_img = render_text_frame(
        [], title="Reactive Circuit-Breaker + AI verdict",
        subtitle="Live testnet demo — burst trips the breaker, AI unpauses it",
        tagline="Reactive Omni Buildathon  ·  Reactive Meets AI")
    emit(title_img, TITLE_S)
    for snap, hold in segments:
        emit(render_text_frame(screen_to_draw_lines(snap)), hold)
    # end card
    end_img = render_text_frame(
        [], title="Demo complete — vault unpaused",
        subtitle="burst #2 LEGITIMATE (Groq gpt-oss-20b)  ·  withdrawals resumed",
        tagline="Vault 0x736749e20AB19A2E84299FA4794f883D6Af7BBF5")
    emit(end_img, END_S)
    ff.stdin.close()
    rc = ff.wait()
    if rc != 0:
        print("ffmpeg failed", rc)
        sys.exit(1)
    print("wrote", OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
