#!/usr/bin/env python3
import ctypes
import ctypes.util
import json
import os
import subprocess
import sys
import tempfile
import time

try:
    from PIL import Image
except Exception as exc:
    print(json.dumps({"ok": False, "error": f"Pillow import failed: {exc}"}))
    sys.exit(1)


def parse_int(name, default):
    raw = os.environ.get(name, "")
    if raw == "":
        return default
    return int(raw)


class CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]


def click_at(x, y):
    lib_path = ctypes.util.find_library("CoreGraphics")
    if not lib_path:
        return False
    cg = ctypes.cdll.LoadLibrary(lib_path)

    kCGEventLeftMouseDown = 1
    kCGEventLeftMouseUp = 2
    kCGHIDEventTap = 0

    cg.CGEventCreateMouseEvent.restype = ctypes.c_void_p
    cg.CGEventCreateMouseEvent.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, CGPoint, ctypes.c_uint32,
    ]
    cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    cg.CFRelease.argtypes = [ctypes.c_void_p]

    point = CGPoint(float(x), float(y))

    down = cg.CGEventCreateMouseEvent(None, kCGEventLeftMouseDown, point, 0)
    up = cg.CGEventCreateMouseEvent(None, kCGEventLeftMouseUp, point, 0)
    if not down or not up:
        return False

    cg.CGEventPost(kCGHIDEventTap, down)
    time.sleep(0.05)
    cg.CGEventPost(kCGHIDEventTap, up)

    cg.CFRelease(down)
    cg.CFRelease(up)
    return True


def is_blue(pixel):
    if len(pixel) >= 4 and pixel[3] == 0:
        return False
    r, g, b = pixel[:3]
    return b >= 170 and g >= 90 and r <= 80 and (b - r) >= 100 and b >= g


def get_window_bounds(app_name):
    script = f'''
        tell application "{app_name}"
            activate
        end tell
        delay 0.2
        tell application "System Events"
            tell process "{app_name}"
                set frontmost to true
                set p to position of window 1
                set s to size of window 1
                return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
            end tell
        end tell
    '''
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        return None
    parts = r.stdout.strip().split(",")
    if len(parts) != 4:
        return None
    try:
        return [int(v.strip()) for v in parts]
    except ValueError:
        return None


def main():
    app_name = os.environ.get("APP_NAME", "")
    capture_w = parse_int("CAPTURE_W", 420)
    capture_h = parse_int("CAPTURE_H", 180)

    if app_name:
        bounds = get_window_bounds(app_name)
        if not bounds:
            print(json.dumps({"ok": False, "error": f"Could not get window bounds for {app_name}"}))
            return
        win_x, win_y, win_w, win_h = bounds
        x = win_x + max(0, win_w - capture_w)
        y = win_y + max(0, win_h - capture_h)
        w = min(capture_w, win_w)
        h = min(capture_h, win_h)
    else:
        x = parse_int("CAPTURE_X", 0)
        y = parse_int("CAPTURE_Y", 0)
        w = parse_int("CAPTURE_W", 500)
        h = parse_int("CAPTURE_H", 220)

    min_pixels = parse_int("BLUE_MIN_PIXELS", 150)

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        image_path = tmp.name

    try:
        subprocess.run(
            ["screencapture", "-x", "-R", f"{x},{y},{w},{h}", image_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        image = Image.open(image_path).convert("RGBA")
        width, height = image.size
        pixels = image.load()

        # Detect Retina scale factor from actual vs requested capture size
        scale_x = width / w if w > 0 else 1
        scale_y = height / h if h > 0 else 1
        scale = max(scale_x, scale_y, 1)

        min_x = width
        min_y = height
        max_x = -1
        max_y = -1
        count = 0

        for py in range(height):
            for px in range(width):
                if is_blue(pixels[px, py]):
                    count += 1
                    if px < min_x:
                        min_x = px
                    if py < min_y:
                        min_y = py
                    if px > max_x:
                        max_x = px
                    if py > max_y:
                        max_y = py

        if count < min_pixels or max_x < min_x or max_y < min_y:
            print(json.dumps({
                "ok": False,
                "error": "Blue region not found",
                "capture": {"x": x, "y": y, "w": w, "h": h},
                "imageSize": {"w": width, "h": height},
                "scale": scale,
                "bluePixels": count,
            }))
            return

        # Convert image-pixel center back to logical screen coordinates
        center_x = x + int(((min_x + max_x) / 2) / scale)
        center_y = y + int(((min_y + max_y) / 2) / scale)

        clicked = False
        if os.environ.get("CLICK", "") == "1":
            clicked = click_at(center_x, center_y)

        print(json.dumps({
            "ok": True,
            "clickX": center_x,
            "clickY": center_y,
            "clicked": clicked,
            "bounds": {
                "left": x + int(min_x / scale),
                "top": y + int(min_y / scale),
                "right": x + int(max_x / scale),
                "bottom": y + int(max_y / scale),
            },
            "capture": {"x": x, "y": y, "w": w, "h": h},
            "imageSize": {"w": width, "h": height},
            "scale": scale,
            "bluePixels": count,
        }))
    finally:
        try:
            os.unlink(image_path)
        except OSError:
            pass


if __name__ == "__main__":
    main()
