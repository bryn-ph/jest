"""Generate the wheel's slice art: Jest/Media/wedge_<N>.tga and wedge_<N>_glow.tga for N = 2..12.

Each texture is one ring segment (annulus wedge) pointing straight up, centred in a square
canvas, white with alpha. The addon tints it with SetVertexColor and rotates it into place
with Texture:SetRotation, so a single texture per slice count covers every slice.

Geometry, as fractions of the canvas half-size (keep in sync with UI/Skin.lua):
    OUTER = 0.98  outer edge of the segment
    INNER = 0.34  inner edge (leaves a hole for the centre icon/label and dead zone)
    GAP   = constant-width gap between neighbouring segments, in output pixels
    GLOW_SCALE = the glow's segment is drawn this much smaller inside its own canvas so the blur
                 has room and never touches the edge (rotation would clip it); the addon draws
                 the glow texture 1 / GLOW_SCALE times larger so the two line up

Usage:
    .venv\\Scripts\\pip install -r tools\\requirements.txt
    .venv\\Scripts\\python tools\\gen_wedges.py [--preview out.png]
"""
import argparse
import math
import pathlib

import numpy as np
from PIL import Image, ImageFilter

SIZE = 256          # fill texture size (power of two, required by the client)
GLOW_SIZE = 128     # glow is blurry, so half resolution is plenty
SUPERSAMPLE = 4     # render at 4x then downscale for anti-aliasing
OUTER = 0.98
INNER = 0.34
GAP_PX = 3.0        # gap between segments at output resolution
GLOW_SCALE = 0.84
COUNTS = range(2, 13)

OUT_DIR = pathlib.Path(__file__).resolve().parents[1] / "Jest" / "Media"


def wedge_alpha(n: int, size: int, scale: float = 1.0) -> np.ndarray:
    """Float alpha mask (0..1) of an upward-pointing ring segment for an n-slice wheel.

    `scale` shrinks the segment within the canvas (used for the glow).
    """
    s = size * SUPERSAMPLE
    centre = s / 2
    half = centre * scale  # radius that OUTER/INNER are fractions of
    # Pixel centres, y pointing up, origin at canvas centre.
    coords = np.arange(s) + 0.5 - centre
    x, y = np.meshgrid(coords, -coords)
    r = np.hypot(x, y)
    theta = np.abs(np.arctan2(x, y))          # angle from straight up, 0..pi
    half_angle = math.pi / n

    inside = (r >= INNER * half) & (r <= OUTER * half) & (theta <= half_angle)
    if n > 1:
        # Perpendicular distance to the nearer edge ray; keep GAP/2 clear on each side.
        edge_dist = r * np.sin(np.clip(half_angle - theta, 0, None))
        inside &= edge_dist >= (GAP_PX * SUPERSAMPLE * scale * size / SIZE) / 2

    # Slightly brighter towards the rim for a bit of depth.
    radial = np.clip((r / half - INNER) / (OUTER - INNER), 0, 1)
    alpha = np.where(inside, 0.78 + 0.22 * radial, 0.0)
    return alpha


def to_image(alpha: np.ndarray, size: int) -> Image.Image:
    a = Image.fromarray((alpha * 255).astype(np.uint8), mode="L")
    a = a.resize((size, size), Image.Resampling.LANCZOS)
    img = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    img.putalpha(a)
    return img


def glow_image(alpha: np.ndarray) -> Image.Image:
    base = to_image((alpha > 0).astype(np.float32), GLOW_SIZE)
    a = base.getchannel("A").filter(ImageFilter.GaussianBlur(GLOW_SIZE / 40))
    img = Image.new("RGBA", (GLOW_SIZE, GLOW_SIZE), (255, 255, 255, 0))
    img.putalpha(a)
    return img


def save_tga(img: Image.Image, path: pathlib.Path) -> None:
    # Uncompressed 32-bit, bottom-left origin: the most widely supported TGA flavour.
    img.save(path, format="TGA", rle=False)


def preview(n: int, out: pathlib.Path) -> None:
    """Composite a full n-slice wheel (dark wedges + gold highlight on slice 2) for eyeballing."""
    # Work on a canvas big enough for the enlarged glow, as the addon draws it (1 / GLOW_SCALE).
    big = round(SIZE / GLOW_SCALE)
    pad = (big - SIZE) // 2

    def centred(img: Image.Image) -> Image.Image:
        layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        layer.paste(img, ((big - img.width) // 2, (big - img.height) // 2))
        return layer

    fill = centred(to_image(wedge_alpha(n, SIZE), SIZE))
    glow = glow_image(wedge_alpha(n, GLOW_SIZE, GLOW_SCALE)).resize((big, big), Image.Resampling.BILINEAR)
    canvas = Image.new("RGBA", (big, big), (60, 70, 60, 255))

    def tinted(alpha: Image.Image, rgb, strength: float) -> Image.Image:
        layer = Image.new("RGBA", (big, big), (*rgb, 0))
        layer.putalpha(alpha.point(lambda v: int(v * strength)))
        return layer

    # PIL rotates counter-clockwise for positive angles; slice i sits (i-1)*360/n clockwise.
    for i in range(n):
        canvas.alpha_composite(tinted(fill.getchannel("A"), (15, 15, 20), 0.6).rotate(-(i * 360 / n)))
    canvas.alpha_composite(tinted(glow.getchannel("A"), (255, 209, 51), 1.0).rotate(-(360 / n)))
    canvas.alpha_composite(tinted(fill.getchannel("A"), (255, 209, 51), 0.35).rotate(-(360 / n)))
    canvas = canvas.crop((pad, pad, pad + SIZE, pad + SIZE))
    canvas.resize((SIZE * 2, SIZE * 2), Image.Resampling.LANCZOS).save(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=pathlib.Path, help="also write an 8-slice composite PNG here")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for n in COUNTS:
        save_tga(to_image(wedge_alpha(n, SIZE), SIZE), OUT_DIR / f"wedge_{n}.tga")
        save_tga(glow_image(wedge_alpha(n, GLOW_SIZE, GLOW_SCALE)), OUT_DIR / f"wedge_{n}_glow.tga")
    print(f"wrote {len(COUNTS) * 2} textures to {OUT_DIR}")
    if args.preview:
        preview(8, args.preview)
        print(f"preview: {args.preview}")


if __name__ == "__main__":
    main()
