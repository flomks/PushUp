#!/usr/bin/env python3
"""
Generates PushUp app icon PNG files for all required iOS sizes.

The icon design:
  - Background: deep blue gradient (#007AFF -> #0055CC)
  - Foreground: white push-up figure silhouette (geometric shapes)
  - Rounded corners applied at the OS level (not baked in)

Run from the repo root:
  python3 generate_icons.py
"""

from PIL import Image, ImageDraw, ImageFont
import math
import os

ICON_DIR = "iosApp/iosApp/Assets.xcassets/AppIcon.appiconset"

# All sizes needed for the universal iOS icon set
SIZES = [
    1024,  # App Store / universal
    512,
    256,
    128,
    64,
    32,
    20,
    16,
]


def lerp_color(c1, c2, t):
    """Linear interpolation between two RGB tuples."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_icon(size: int) -> Image.Image:
    """Draw the PushUp app icon at the given pixel size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- Background gradient (top-left: bright blue -> bottom-right: deep blue) ---
    color_top = (0, 122, 255)      # #007AFF
    color_bot = (0, 64, 180)       # #0040B4

    for y in range(size):
        t = y / max(size - 1, 1)
        row_color = lerp_color(color_top, color_bot, t)
        draw.line([(0, y), (size - 1, y)], fill=row_color + (255,))

    # --- Push-up figure (white, geometric) ---
    # Scale all coordinates relative to the 1024-pt reference frame
    s = size / 1024.0

    def sc(v):
        """Scale a reference coordinate to the current size."""
        return int(round(v * s))

    # Body proportions (person in push-up / plank position, viewed from side)
    # The figure is centred horizontally and vertically in the icon.

    white = (255, 255, 255, 255)
    white_dim = (255, 255, 255, 200)

    # Head (circle)
    head_cx, head_cy = sc(720), sc(340)
    head_r = sc(72)
    draw.ellipse(
        [head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r],
        fill=white,
    )

    # Torso (thick line from shoulders to hips, slightly angled)
    torso_lw = max(1, sc(60))
    draw.line(
        [(sc(640), sc(430)), (sc(330), sc(560))],
        fill=white,
        width=torso_lw,
    )

    # Upper arm (from shoulder down to elbow)
    arm_lw = max(1, sc(50))
    draw.line(
        [(sc(640), sc(430)), (sc(580), sc(600))],
        fill=white,
        width=arm_lw,
    )

    # Forearm (from elbow to wrist / floor contact)
    draw.line(
        [(sc(580), sc(600)), (sc(480), sc(660))],
        fill=white,
        width=arm_lw,
    )

    # Legs (from hips to feet, straight)
    leg_lw = max(1, sc(55))
    draw.line(
        [(sc(330), sc(560)), (sc(200), sc(660))],
        fill=white,
        width=leg_lw,
    )

    # Feet (small circles)
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

    # --- Subtle "P" monogram in bottom-right corner (only for large sizes) ---
    if size >= 128:
        # Draw a small white "P" badge
        badge_r = sc(130)
        badge_cx, badge_cy = sc(820), sc(820)
        # Badge circle (semi-transparent white)
        draw.ellipse(
            [
                badge_cx - badge_r,
                badge_cy - badge_r,
                badge_cx + badge_r,
                badge_cy + badge_r,
            ],
            fill=(255, 255, 255, 40),
        )

    return img


def generate_all():
    os.makedirs(ICON_DIR, exist_ok=True)

    for size in SIZES:
        img = draw_icon(size)
        filename = f"AppIcon-{size}x{size}.png"
        path = os.path.join(ICON_DIR, filename)
        img.save(path, "PNG")
        print(f"  Generated {filename}")

    # Also generate the three variants for the Contents.json:
    # 1. Standard (already done as 1024)
    # 2. Dark variant (slightly different gradient)
    img_dark = draw_icon_dark(1024)
    img_dark.save(os.path.join(ICON_DIR, "AppIcon-1024x1024-dark.png"), "PNG")
    print("  Generated AppIcon-1024x1024-dark.png")

    # 3. Tinted variant (monochrome for tinted icon mode)
    img_tinted = draw_icon_tinted(1024)
    img_tinted.save(os.path.join(ICON_DIR, "AppIcon-1024x1024-tinted.png"), "PNG")
    print("  Generated AppIcon-1024x1024-tinted.png")

    print(f"\nAll icons written to {ICON_DIR}/")


def draw_icon_dark(size: int) -> Image.Image:
    """Dark variant: darker background, same figure."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    color_top = (10, 100, 220)
    color_bot = (5, 40, 120)

    for y in range(size):
        t = y / max(size - 1, 1)
        row_color = lerp_color(color_top, color_bot, t)
        draw.line([(0, y), (size - 1, y)], fill=row_color + (255,))

    # Reuse the same figure drawing logic
    _draw_figure(draw, size)
    return img


def draw_icon_tinted(size: int) -> Image.Image:
    """Tinted variant: black background with white figure (for iOS tinted icon)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)
    _draw_figure(draw, size)
    return img


def _draw_figure(draw: ImageDraw.ImageDraw, size: int):
    """Draw the push-up figure onto an existing draw context."""
    s = size / 1024.0

    def sc(v):
        return int(round(v * s))

    white = (255, 255, 255, 255)

    # Head
    head_cx, head_cy = sc(720), sc(340)
    head_r = sc(72)
    draw.ellipse(
        [head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r],
        fill=white,
    )

    # Torso
    torso_lw = max(1, sc(60))
    draw.line([(sc(640), sc(430)), (sc(330), sc(560))], fill=white, width=torso_lw)

    # Upper arm
    arm_lw = max(1, sc(50))
    draw.line([(sc(640), sc(430)), (sc(580), sc(600))], fill=white, width=arm_lw)

    # Forearm
    draw.line([(sc(580), sc(600)), (sc(480), sc(660))], fill=white, width=arm_lw)

    # Legs
    leg_lw = max(1, sc(55))
    draw.line([(sc(330), sc(560)), (sc(200), sc(660))], fill=white, width=leg_lw)

    # Feet
    foot_r = max(1, sc(30))
    draw.ellipse(
        [sc(170) - foot_r, sc(660) - foot_r, sc(170) + foot_r, sc(660) + foot_r],
        fill=white,
    )

    # Hand
    hand_r = max(1, sc(28))
    draw.ellipse(
        [sc(480) - hand_r, sc(660) - hand_r, sc(480) + hand_r, sc(660) + hand_r],
        fill=white,
    )


if __name__ == "__main__":
    generate_all()
