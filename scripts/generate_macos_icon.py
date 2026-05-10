from __future__ import annotations

from pathlib import Path
import math
import struct
import sys
import zlib


RGBA = tuple[int, int, int, int]


ICON_FILES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def main() -> int:
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("AppIcon.iconset")
    output_dir.mkdir(parents=True, exist_ok=True)
    base = render_icon(1024)
    for name, size in ICON_FILES.items():
        image = base if size == 1024 else resize(base, 1024, size)
        write_png(output_dir / name, size, size, image)
    return 0


def render_icon(size: int) -> bytearray:
    pixels = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (size * 2)
            r = int(20 + 12 * t)
            g = int(23 + 18 * t)
            b = int(34 + 30 * t)
            set_pixel(pixels, size, x, y, (r, g, b, 255))

    rounded_rect(pixels, size, 52, 52, 920, 920, 210, (14, 17, 27, 255))
    rounded_rect(pixels, size, 86, 86, 852, 852, 180, (25, 30, 45, 255))
    rounded_rect(pixels, size, 150, 188, 724, 488, 118, (42, 51, 73, 255))
    triangle(pixels, size, [(354, 658), (460, 562), (532, 674)], (42, 51, 73, 255))

    glow_circle(pixels, size, 510, 420, 320, (77, 139, 255, 45))
    rounded_rect(pixels, size, 222, 265, 210, 70, 35, (40, 176, 136, 255))
    rounded_rect(pixels, size, 505, 265, 210, 70, 35, (94, 129, 255, 255))
    rounded_rect(pixels, size, 222, 410, 210, 70, 35, (206, 108, 255, 255))
    rounded_rect(pixels, size, 505, 410, 210, 70, 35, (41, 198, 218, 255))

    line(pixels, size, 432, 300, 505, 300, 22, (132, 145, 170, 255))
    line(pixels, size, 432, 445, 505, 445, 22, (132, 145, 170, 255))
    line(pixels, size, 327, 335, 327, 410, 22, (132, 145, 170, 255))
    line(pixels, size, 610, 335, 610, 410, 22, (132, 145, 170, 255))

    bolt = [(539, 325), (430, 527), (512, 527), (468, 710), (610, 465), (526, 465)]
    polygon(pixels, size, bolt, (255, 212, 95, 255))
    polygon(pixels, size, [(539, 325), (506, 465), (610, 465)], (255, 236, 146, 220))

    rounded_rect(pixels, size, 154, 190, 718, 486, 118, (255, 255, 255, 18), outline=True, outline_width=8)
    return pixels


def resize(source: bytearray, source_size: int, target_size: int) -> bytearray:
    scale = source_size / target_size
    target = bytearray(target_size * target_size * 4)
    for y in range(target_size):
        y0 = int(y * scale)
        y1 = max(y0 + 1, int((y + 1) * scale))
        for x in range(target_size):
            x0 = int(x * scale)
            x1 = max(x0 + 1, int((x + 1) * scale))
            acc = [0, 0, 0, 0]
            count = 0
            for sy in range(y0, min(y1, source_size)):
                for sx in range(x0, min(x1, source_size)):
                    i = (sy * source_size + sx) * 4
                    acc[0] += source[i]
                    acc[1] += source[i + 1]
                    acc[2] += source[i + 2]
                    acc[3] += source[i + 3]
                    count += 1
            set_pixel(target, target_size, x, y, tuple(v // count for v in acc))  # type: ignore[arg-type]
    return target


def rounded_rect(
    pixels: bytearray,
    size: int,
    x: int,
    y: int,
    w: int,
    h: int,
    r: int,
    color: RGBA,
    *,
    outline: bool = False,
    outline_width: int = 1,
) -> None:
    for py in range(max(0, y), min(size, y + h)):
        for px in range(max(0, x), min(size, x + w)):
            dx = max(x + r - px, 0, px - (x + w - r))
            dy = max(y + r - py, 0, py - (y + h - r))
            inside = dx * dx + dy * dy <= r * r
            if not inside:
                continue
            if outline:
                inner = rounded_contains(px, py, x + outline_width, y + outline_width, w - outline_width * 2, h - outline_width * 2, max(1, r - outline_width))
                if inner:
                    continue
            blend_pixel(pixels, size, px, py, color)


def rounded_contains(px: int, py: int, x: int, y: int, w: int, h: int, r: int) -> bool:
    dx = max(x + r - px, 0, px - (x + w - r))
    dy = max(y + r - py, 0, py - (y + h - r))
    return x <= px <= x + w and y <= py <= y + h and dx * dx + dy * dy <= r * r


def glow_circle(pixels: bytearray, size: int, cx: int, cy: int, radius: int, color: RGBA) -> None:
    for py in range(max(0, cy - radius), min(size, cy + radius)):
        for px in range(max(0, cx - radius), min(size, cx + radius)):
            distance = math.hypot(px - cx, py - cy)
            if distance > radius:
                continue
            alpha = int(color[3] * (1 - distance / radius) ** 2)
            blend_pixel(pixels, size, px, py, (color[0], color[1], color[2], alpha))


def line(pixels: bytearray, size: int, x1: int, y1: int, x2: int, y2: int, width: int, color: RGBA) -> None:
    min_x, max_x = sorted((x1, x2))
    min_y, max_y = sorted((y1, y2))
    radius = width / 2
    for py in range(max(0, min_y - width), min(size, max_y + width + 1)):
        for px in range(max(0, min_x - width), min(size, max_x + width + 1)):
            distance = point_line_distance(px, py, x1, y1, x2, y2)
            if distance <= radius:
                blend_pixel(pixels, size, px, py, color)


def triangle(pixels: bytearray, size: int, points: list[tuple[int, int]], color: RGBA) -> None:
    polygon(pixels, size, points, color)


def polygon(pixels: bytearray, size: int, points: list[tuple[int, int]], color: RGBA) -> None:
    min_x = max(0, min(x for x, _ in points))
    max_x = min(size - 1, max(x for x, _ in points))
    min_y = max(0, min(y for _, y in points))
    max_y = min(size - 1, max(y for _, y in points))
    for py in range(min_y, max_y + 1):
        for px in range(min_x, max_x + 1):
            if point_in_polygon(px, py, points):
                blend_pixel(pixels, size, px, py, color)


def point_in_polygon(x: int, y: int, points: list[tuple[int, int]]) -> bool:
    inside = False
    j = len(points) - 1
    for i, point in enumerate(points):
        xi, yi = point
        xj, yj = points[j]
        if (yi > y) != (yj > y):
            x_intersect = (xj - xi) * (y - yi) / ((yj - yi) or 1) + xi
            if x < x_intersect:
                inside = not inside
        j = i
    return inside


def point_line_distance(px: int, py: int, x1: int, y1: int, x2: int, y2: int) -> float:
    dx = x2 - x1
    dy = y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
    cx = x1 + t * dx
    cy = y1 + t * dy
    return math.hypot(px - cx, py - cy)


def set_pixel(pixels: bytearray, size: int, x: int, y: int, color: RGBA) -> None:
    index = (y * size + x) * 4
    pixels[index : index + 4] = bytes(color)


def blend_pixel(pixels: bytearray, size: int, x: int, y: int, color: RGBA) -> None:
    index = (y * size + x) * 4
    alpha = color[3] / 255
    inverse = 1 - alpha
    pixels[index] = int(color[0] * alpha + pixels[index] * inverse)
    pixels[index + 1] = int(color[1] * alpha + pixels[index + 1] * inverse)
    pixels[index + 2] = int(color[2] * alpha + pixels[index + 2] * inverse)
    pixels[index + 3] = min(255, int(color[3] + pixels[index + 3] * inverse))


def write_png(path: Path, width: int, height: int, pixels: bytearray) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride : (y + 1) * stride])
    data = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)),
            chunk(b"IEND", b""),
        ]
    )
    path.write_bytes(data)


def chunk(kind: bytes, data: bytes) -> bytes:
    payload = kind + data
    return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)


if __name__ == "__main__":
    raise SystemExit(main())
