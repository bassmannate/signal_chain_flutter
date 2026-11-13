#!/usr/bin/env python3
"""
Deterministic Android launcher & Fastlane icon generator for Signal Chain.

Zero external pub.dev dependencies. Uses `rsvg-convert` / `inkscape` / `magick` /
`Pillow` if available, or falls back cleanly to pure-Python 3 stdlib (`zlib` +
`struct`) rendering of the official Signal Chain dark studio pedalboard icon.

Generates:
  - android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
  - android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_round.png
  - fastlane/metadata/android/en-US/images/icon.png (512x512)
"""

from __future__ import annotations

import math
import os
import shutil
import struct
import subprocess
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SVG_PATH = ROOT / "linux" / "packaging" / "signal-chain.svg"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"
FASTLANE_ICON_PATH = (
    ROOT / "fastlane" / "metadata" / "android" / "en-US" / "images" / "icon.png"
)

DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    """Encodes raw RGBA bytes into a deterministic PNG file using stdlib zlib."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return (
            struct.pack(">I", len(data))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    stride = width * 4
    raw = bytearray((stride + 1) * height)
    for y in range(height):
        row_start = y * (stride + 1)
        raw[row_start] = 0  # Filter type None
        src_start = y * stride
        raw[row_start + 1 : row_start + 1 + stride] = rgba[
            src_start : src_start + stride
        ]
    idat = zlib.compress(bytes(raw), level=9)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", idat)
        + chunk(b"IEND", b"")
    )


def decode_png_rgba(data: bytes) -> tuple[int, int, bytearray]:
    """Minimal pure-Python PNG decoder for 8-bit RGBA PNGs."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Not a valid PNG")
    pos = 8
    width = height = 0
    idat_parts: list[bytes] = []
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        tag = data[pos + 4 : pos + 8]
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, bit_depth, color_type = struct.unpack(
                ">IIBB", payload[:10]
            )
            if bit_depth != 8 or color_type != 6:
                raise ValueError("Unsupported PNG format")
        elif tag == b"IDAT":
            idat_parts.append(payload)
        elif tag == b"IEND":
            break

    raw = zlib.decompress(b"".join(idat_parts))
    stride = width * 4
    out = bytearray(width * height * 4)
    for y in range(height):
        in_row = y * (stride + 1)
        ftype = raw[in_row]
        row = bytearray(raw[in_row + 1 : in_row + 1 + stride])
        prev_row_start = (y - 1) * stride
        for i in range(stride):
            a = row[i - 4] if i >= 4 else 0
            b = out[prev_row_start + i] if y > 0 else 0
            c = out[prev_row_start + i - 4] if (y > 0 and i >= 4) else 0
            if ftype == 1:
                row[i] = (row[i] + a) & 0xFF
            elif ftype == 2:
                row[i] = (row[i] + b) & 0xFF
            elif ftype == 3:
                row[i] = (row[i] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 0xFF
        out[y * stride : (y + 1) * stride] = row
    return width, height, out


def apply_round_mask(rgba: bytearray, size: int) -> bytearray:
    """Applies an anti-aliased circular alpha mask for ic_launcher_round.png."""
    masked = bytearray(rgba)
    cx = cy = (size - 1) / 2.0
    radius = size * 0.465
    for y in range(size):
        for x in range(size):
            dist = math.hypot(x - cx, y - cy)
            idx = (y * size + x) * 4
            if dist >= radius + 0.75:
                masked[idx + 3] = 0
            elif dist > radius - 0.75:
                cov = max(0.0, min(1.0, (radius + 0.75 - dist) / 1.5))
                masked[idx + 3] = int(masked[idx + 3] * cov)
    return masked


def downsample_rgba(src: bytearray, src_size: int, dst_size: int) -> bytearray:
    """Bilinear downsample from src_size x src_size RGBA to dst_size x dst_size."""
    dst = bytearray(dst_size * dst_size * 4)
    scale = src_size / dst_size
    for dy in range(dst_size):
        sy = (dy + 0.5) * scale - 0.5
        y0 = max(0, min(src_size - 1, int(math.floor(sy))))
        y1 = max(0, min(src_size - 1, y0 + 1))
        fy = max(0.0, min(1.0, sy - y0))
        for dx in range(dst_size):
            sx = (dx + 0.5) * scale - 0.5
            x0 = max(0, min(src_size - 1, int(math.floor(sx))))
            x1 = max(0, min(src_size - 1, x0 + 1))
            fx = max(0.0, min(1.0, sx - x0))
            i00 = (y0 * src_size + x0) * 4
            i10 = (y0 * src_size + x1) * 4
            i01 = (y1 * src_size + x0) * 4
            i11 = (y1 * src_size + x1) * 4
            di = (dy * dst_size + dx) * 4
            for c in range(4):
                v = (
                    src[i00 + c] * (1 - fx) * (1 - fy)
                    + src[i10 + c] * fx * (1 - fy)
                    + src[i01 + c] * (1 - fx) * fy
                    + src[i11 + c] * fx * fy
                )
                dst[di + c] = int(round(v))
    return dst


def render_svg_512() -> bytearray:
    """Renders signal-chain.svg to 512x512 RGBA using system tools or stdlib fallback."""
    tmp_png = ROOT / ".dart_tool" / "tmp_icon_512.png"
    tmp_png.parent.mkdir(parents=True, exist_ok=True)
    try:
        rsvg = shutil.which("rsvg-convert")
        if rsvg and SVG_PATH.exists():
            subprocess.run(
                [rsvg, "-w", "512", "-h", "512", str(SVG_PATH), "-o", str(tmp_png)],
                check=True,
            )
            w, h, rgba = decode_png_rgba(tmp_png.read_bytes())
            if w == 512 and h == 512:
                return rgba
        magick = shutil.which("magick") or shutil.which("convert")
        if magick and SVG_PATH.exists():
            subprocess.run(
                [
                    magick,
                    "-background",
                    "none",
                    "-resize",
                    "512x512",
                    str(SVG_PATH),
                    f"PNG32:{tmp_png}",
                ],
                check=True,
            )
            w, h, rgba = decode_png_rgba(tmp_png.read_bytes())
            if w == 512 and h == 512:
                return rgba
    except Exception:
        pass
    finally:
        if tmp_png.exists():
            tmp_png.unlink()

    return _render_pure_python_512()


def _blend(
    buf: bytearray, size: int, x: int, y: int, r: int, g: int, b: int, a: float
) -> None:
    if x < 0 or y < 0 or x >= size or y >= size or a <= 0.0:
        return
    idx = (y * size + x) * 4
    inv = 1.0 - a
    buf[idx] = int(round(buf[idx] * inv + r * a))
    buf[idx + 1] = int(round(buf[idx + 1] * inv + g * a))
    buf[idx + 2] = int(round(buf[idx + 2] * inv + b * a))
    buf[idx + 3] = min(255, int(round(buf[idx + 3] + 255 * a * (1 - buf[idx + 3] / 255.0))))


def _fill_rounded_rect(
    buf: bytearray,
    size: int,
    x0: float,
    y0: float,
    w: float,
    h: float,
    rad: float,
    fill: tuple[int, int, int],
    stroke: tuple[int, int, int] | None = None,
    stroke_w: float = 0.0,
) -> None:
    x1, y1 = x0 + w, y0 + h
    cx0, cy0 = x0 + rad, y0 + rad
    cx1, cy1 = x1 - rad, y1 - rad
    ix0, iy0 = max(0, int(math.floor(x0 - stroke_w - 2))), max(
        0, int(math.floor(y0 - stroke_w - 2))
    )
    ix1, iy1 = min(size, int(math.ceil(x1 + stroke_w + 2))), min(
        size, int(math.ceil(y1 + stroke_w + 2))
    )
    for y in range(iy0, iy1):
        for x in range(ix0, ix1):
            px = min(max(x + 0.5, cx0), cx1)
            py = min(max(y + 0.5, cy0), cy1)
            dx = (x + 0.5) - px
            dy = (y + 0.5) - py
            dist = math.hypot(dx, dy) - rad
            if stroke is not None and stroke_w > 0:
                outer = dist - stroke_w * 0.5
                inner = dist + stroke_w * 0.5
                if outer <= 0.75 and inner >= -0.75:
                    cov = min(1.0, max(0.0, 0.75 - outer)) * min(
                        1.0, max(0.0, inner + 0.75)
                    )
                    _blend(buf, size, x, y, stroke[0], stroke[1], stroke[2], cov)
            if dist <= 0.75:
                cov = min(1.0, max(0.0, 0.75 - dist))
                if stroke is not None and stroke_w > 0:
                    cov = min(cov, min(1.0, max(0.0, 0.75 - (dist + stroke_w * 0.5))))
                _blend(buf, size, x, y, fill[0], fill[1], fill[2], cov)


def _fill_circle(
    buf: bytearray,
    size: int,
    cx: float,
    cy: float,
    rad: float,
    fill: tuple[int, int, int],
    alpha: float = 1.0,
    stroke: tuple[int, int, int] | None = None,
    stroke_w: float = 0.0,
) -> None:
    ix0, iy0 = max(0, int(math.floor(cx - rad - stroke_w - 2))), max(
        0, int(math.floor(cy - rad - stroke_w - 2))
    )
    ix1, iy1 = min(size, int(math.ceil(cx + rad + stroke_w + 2))), min(
        size, int(math.ceil(cy + rad + stroke_w + 2))
    )
    for y in range(iy0, iy1):
        for x in range(ix0, ix1):
            dist = math.hypot((x + 0.5) - cx, (y + 0.5) - cy) - rad
            if stroke is not None and stroke_w > 0:
                outer = dist - stroke_w * 0.5
                inner = dist + stroke_w * 0.5
                if outer <= 0.75 and inner >= -0.75:
                    cov = min(1.0, max(0.0, 0.75 - outer)) * min(
                        1.0, max(0.0, inner + 0.75)
                    )
                    _blend(buf, size, x, y, stroke[0], stroke[1], stroke[2], cov * alpha)
            if dist <= 0.75:
                cov = min(1.0, max(0.0, 0.75 - dist))
                _blend(buf, size, x, y, fill[0], fill[1], fill[2], cov * alpha)


def _render_pure_python_512() -> bytearray:
    """Pure-Python 512x512 fallback matching linux/packaging/signal-chain.svg."""
    size = 512
    buf = bytearray(size * size * 4)

    # Outer dark studio rounded square
    _fill_rounded_rect(
        buf, size, 24, 24, 464, 464, 100, (18, 19, 24), (45, 49, 57), 8
    )

    # Subtle grid lines inside bezel
    for pos in (160, 256, 352):
        for p in range(40, 472):
            if (p // 6) % 2 == 0:
                _blend(buf, size, p, pos, 37, 40, 51, 0.4)
                _blend(buf, size, pos, p, 37, 40, 51, 0.4)

    # Three stompboxes (RTL: Output Cyan <- Drive Amber <- Input Green)
    _fill_rounded_rect(buf, size, 92, 206, 90, 100, 18, (30, 34, 43), (0, 229, 255), 5)
    _fill_circle(buf, size, 137, 232, 7, (0, 229, 255))
    _fill_circle(buf, size, 117, 272, 8, (55, 65, 81), 1.0, (75, 85, 99), 2)
    _fill_circle(buf, size, 157, 272, 8, (55, 65, 81), 1.0, (75, 85, 99), 2)

    _fill_rounded_rect(buf, size, 211, 196, 90, 120, 18, (30, 34, 43), (255, 145, 0), 5)
    _fill_circle(buf, size, 256, 226, 7, (255, 145, 0))
    _fill_circle(buf, size, 236, 268, 9, (55, 65, 81), 1.0, (255, 145, 0), 2)
    _fill_circle(buf, size, 276, 268, 9, (55, 65, 81), 1.0, (75, 85, 99), 2)
    _fill_rounded_rect(buf, size, 236, 292, 40, 10, 3, (17, 19, 23))

    _fill_rounded_rect(buf, size, 330, 206, 90, 100, 18, (30, 34, 43), (0, 230, 118), 5)
    _fill_circle(buf, size, 375, 232, 7, (0, 230, 118))
    _fill_circle(buf, size, 355, 272, 8, (55, 65, 81), 1.0, (75, 85, 99), 2)
    _fill_circle(buf, size, 395, 272, 8, (55, 65, 81), 1.0, (75, 85, 99), 2)

    # RTL flow cables + IN/OUT dots
    for x in range(186, 212):
        for dy in (-2, -1, 0, 1):
            _blend(buf, size, x, 256 + dy, 0, 229, 255, 0.9)
    for x in range(305, 331):
        for dy in (-2, -1, 0, 1):
            _blend(buf, size, x, 256 + dy, 0, 229, 255, 0.9)
    _fill_circle(buf, size, 445, 256, 10, (0, 230, 118), 0.85)
    _fill_circle(buf, size, 67, 256, 10, (0, 229, 255), 0.85)

    # 5-pin DIN MIDI badge
    _fill_circle(buf, size, 256, 400, 32, (22, 24, 31), 1.0, (55, 65, 81), 4)
    for px, py in ((240, 402), (245, 388), (256, 384), (267, 388), (272, 402)):
        _fill_circle(buf, size, px, py, 3.5, (156, 163, 175))
    return buf


def main() -> None:
    master_rgba = render_svg_512()

    FASTLANE_ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
    FASTLANE_ICON_PATH.write_bytes(encode_png(512, 512, bytes(master_rgba)))
    print(f"Wrote {FASTLANE_ICON_PATH.relative_to(ROOT)} (512x512)")

    for density, px in DENSITIES.items():
        mipmap_dir = RES_DIR / f"mipmap-{density}"
        mipmap_dir.mkdir(parents=True, exist_ok=True)
        resized = downsample_rgba(master_rgba, 512, px)

        launcher_path = mipmap_dir / "ic_launcher.png"
        launcher_path.write_bytes(encode_png(px, px, bytes(resized)))

        round_rgba = apply_round_mask(resized, px)
        round_path = mipmap_dir / "ic_launcher_round.png"
        round_path.write_bytes(encode_png(px, px, bytes(round_rgba)))
        print(f"Wrote {density} icons ({px}x{px}) -> {mipmap_dir.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

