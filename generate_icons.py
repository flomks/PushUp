#!/usr/bin/env python3
"""
Generates PushUp app icon PNG files for the iOS Asset Catalog.

Design:
  - Background: blue gradient (#007AFF -> #0040B4)
  - Foreground: white push-up figure silhouette (geometric shapes)
  - Rounded corners are applied by iOS at runtime (not baked in)

iOS 18+ universal icons only need a single 1024x1024 image per variant.
Three variants are generated:
  1. Standard  -- blue gradient background
  2. Dark      -- deeper blue gradient background
  3. Tinted    -- black background (iOS applies the user's tint colour)

Run from the repo root:
  python3 generate_icons.py
"""

from PIL import Image, ImageDraw
import os

ICON_DIR = "iosApp/iosApp/Assets.xcassets/AppIcon.appiconset"

# Reference coordinate system: all figure coordinates are defined at 1024px
# and scaled proportionally for any output size.
_REF_SIZE = 1024


def _lerp_color(c1: tuple, c2: tuple, t: float) -> tuple:
    """Linear interpolation between two RGB tuples."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def _draw_figure(draw: ImageDraw.ImageDraw, size: int) -> None:
    """Draw the push-up figure silhouette onto an existing draw context.

    All coordinates are relative to a 1024-pt reference frame and scaled
    to the actual output size.
    """
    s = size / _REF_SIZE

    def sc(v: int) -> int:
        return int(round(v * s))

    white = (255, 255, 255, 255)

    # Head (circle)
    head_cx, head_cy, head_r = sc(720), sc(340), sc(72)
    draw.ellipse(
        [head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r],
        fill=white,
    )

    # Torso (thick line from shoulders to hips)
    draw.line(
        [(sc(640), sc(430)), (sc(330), sc(560))],
        fill=white, width=max(1, sc(60)),
    )

    # Upper arm (shoulder to elbow)
    arm_lw = max(1, sc(50))
    draw.line([(sc(640), sc(430)), (sc(580), sc(600))], fill=white, width=arm_lw)

    # Forearm (elbow to wrist / floor contact)
    draw.line([(sc(580), sc(600)), (sc(480), sc(660))], fill=white, width=arm_lw)

    # Legs (hips to feet)
    draw.line(
        [(sc(330), sc(560)), (sc(200), sc(660))],
        fill=white, width=max(1, sc(55)),
    )

    # Feet (small circle)
    foot_r = max(1, sc(30))
    draw.ellipse(
        [sc(170) - foot_r, sc(660) - foot_r, sc(170) + foot_r, sc(660) + foot_r],
        fill=white,
    )

    # Hand (small circle at floor contact)
    hand_r = max(1, sc(28))
    draw.ellipse(
        [sc(480) - hand_r, sc(660) - hand_r, sc(480) + hand_r, sc(660) + hand_r],
        fill=white,
    )


def _draw_gradient(draw: ImageDraw.ImageDraw, size: int,
                   color_top: tuple, color_bot: tuple) -> None:
    """Fill the canvas with a vertical linear gradient."""
    for y in range(size):
        t = y / max(size - 1, 1)
        row_color = _lerp_color(color_top, color_bot, t)
        draw.line([(0, y), (size - 1, y)], fill=row_color + (255,))


def draw_icon_standard(size: int = 1024) -> Image.Image:
    """Standard variant: blue gradient background + white figure."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    _draw_gradient(draw, size, color_top=(0, 122, 255), color_bot=(0, 64, 180))
    _draw_figure(draw, size)
    return img


def draw_icon_dark(size: int = 1024) -> Image.Image:
    """Dark variant: deeper blue gradient background + white figure."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    _draw_gradient(draw, size, color_top=(10, 100, 220), color_bot=(5, 40, 120))
    _draw_figure(draw, size)
    return img


def draw_icon_tinted(size: int = 1024) -> Image.Image:
    """Tinted variant: black background + white figure (iOS applies tint)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    _draw_figure(draw, size)
    return img


def generate_all() -> None:
    """Generate all three 1024x1024 icon variants into the asset catalog."""
    os.makedirs(ICON_DIR, exist_ok=True)

    variants = [
        ("AppIcon-1024x1024.png",        draw_icon_standard),
        ("AppIcon-1024x1024-dark.png",   draw_icon_dark),
        ("AppIcon-1024x1024-tinted.png", draw_icon_tinted),
    ]

    for filename, draw_fn in variants:
        img = draw_fn(1024)
        path = os.path.join(ICON_DIR, filename)
        img.save(path, "PNG")
        print(f"  Generated {filename}")

    print(f"\nAll icons written to {ICON_DIR}/")


if __name__ == "__main__":
    generate_all()
