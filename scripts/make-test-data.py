#!/usr/bin/env python3
"""Generates the performance-test data under TestData/ (TESTDATA-001). Deterministic: a fixed seed, so a re-run writes the same bytes.

  TestData/backgrounds/solid/solid-001-deep-blue.png ...      100 solid colours, 1920x1080, sRGB
  TestData/backgrounds/gradient/gradient-001-blue-to-violet.png ...   100 gradients (linear at many angles, some radial)
  TestData/songs/Test Song 001 - Morning Light.txt            100 synthetic songs in the import sheet's own text format
  TestData/songs/Test Song 005 - ....vi.txt                    the second-language (Vietnamese) text of the bilingual ones

Every word of every song is generated here from word lists. No line or title comes from a real song or hymn.
Needs Python 3 with Pillow (checked by scripts/make-test-data.sh). TestData/ is git-ignored.
"""
import colorsys
import math
import os
import random
import sys

from PIL import Image, ImageOps

try:
    from PIL import ImageCms
    SRGB_ICC = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
except Exception:                       # no little-cms in this Pillow: untagged PNG is read as sRGB by macOS
    SRGB_ICC = None

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "TestData")
W, H = 1920, 1080
COUNT = 100
SEED = 20260601

# ----------------------------------------------------------------------------------------- colours

HUE_NAMES = [(12, "red"), (40, "orange"), (62, "amber"), (75, "yellow"), (100, "lime"), (150, "green"), (195, "teal"),
             (215, "cyan"), (245, "blue"), (262, "indigo"), (285, "violet"), (305, "purple"), (335, "magenta"),
             (350, "rose"), (361, "red")]


def colour_name(h, s, l):
    base = next(name for limit, name in HUE_NAMES if h % 360 < limit)
    if s < 0.32:
        base = "muted-" + base
    if l < 0.2:
        return "deep-" + base
    if l < 0.3:
        return "dark-" + base
    if l > 0.8:
        return "pale-" + base
    if l > 0.62:
        return "light-" + base
    return base


def rgb(h, s, l):
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360.0, l, s)
    return (round(r * 255), round(g * 255), round(b * 255))


# Mostly dark and mid (white lyrics read on them), a minority light.
LIGHTNESS = [0.12, 0.17, 0.22, 0.27, 0.32, 0.38, 0.44, 0.52, 0.74, 0.86]
SATURATION = [0.55, 0.70, 0.85, 0.45, 0.65, 0.80, 0.30, 0.90]


def save(image, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    extra = {"icc_profile": SRGB_ICC} if SRGB_ICC else {}
    image.save(path, format="PNG", optimize=True, **extra)


def make_solids():
    folder = os.path.join(ROOT, "backgrounds", "solid")
    neutrals = [("near-black", 0.05), ("charcoal", 0.17), ("grey", 0.40), ("silver", 0.74), ("off-white", 0.94)]
    for i in range(1, COUNT + 1):
        if i > COUNT - len(neutrals):
            name, l = neutrals[i - (COUNT - len(neutrals)) - 1]
            colour = rgb(0, 0, l)
        else:
            h = (i * 137.508) % 360
            l = LIGHTNESS[(i * 3) % len(LIGHTNESS)]
            s = SATURATION[i % len(SATURATION)]
            name = colour_name(h, s, l)
            colour = rgb(h, s, l)
        save(Image.new("RGB", (W, H), colour), os.path.join(folder, "solid-%03d-%s.png" % (i, name)))


def gradient_image(c1, c2, angle=None, radial=None, mid=None):
    """Linear: `angle` in degrees, 0 = left to right, 90 = top to bottom. Radial: (cx, cy) as fractions, c1 at the centre.
    Built from Pillow's 256-step gradient strips with an affine resample, then coloured; no per-pixel Python."""
    if radial is not None:
        cx, cy = radial[0] * W, radial[1] * H
        far = max(math.hypot(x - cx, y - cy) for x in (0, W) for y in (0, H))
        k = 128.0 / far
        base = Image.radial_gradient("L")
        grey = base.transform((W, H), Image.AFFINE, (k, 0, 128 - k * cx, 0, k, 128 - k * cy), resample=Image.BILINEAR, fillcolor=255)
    else:
        th = math.radians(angle)
        dx, dy = math.cos(th), math.sin(th)
        proj = [x * dx + y * dy for x in (0, W) for y in (0, H)]
        lo, hi = min(proj), max(proj)
        k = 255.0 / (hi - lo)
        base = Image.linear_gradient("L")
        grey = base.transform((W, H), Image.AFFINE, (0, 0, 128, dx * k, dy * k, -lo * k), resample=Image.BILINEAR, fillcolor=0)
    return ImageOps.colorize(grey, black=c1, white=c2, mid=mid) if mid else ImageOps.colorize(grey, black=c1, white=c2)


ANGLES = [0, 90, 45, 135, 180, 270, 30, 60, 120, 150, 210, 315, 20, 70, 110, 160]


def make_gradients():
    folder = os.path.join(ROOT, "backgrounds", "gradient")
    rng = random.Random(SEED)
    offsets = [30, 60, 90, 120, 150, 180, -40, -80, -120, -160]
    for i in range(1, COUNT + 1):
        h1 = (i * 137.508 + 60) % 360
        h2 = (h1 + offsets[i % len(offsets)]) % 360
        light = i % 7 == 0                                  # 14 light gradients, for dark text
        if light:
            l1, l2 = rng.choice([0.72, 0.80, 0.88]), rng.choice([0.62, 0.70, 0.84])
        else:
            l1, l2 = rng.choice([0.14, 0.20, 0.26, 0.32, 0.40, 0.46]), rng.choice([0.10, 0.16, 0.24, 0.30, 0.38, 0.50])
        s1, s2 = rng.choice(SATURATION), rng.choice(SATURATION)
        n1, n2 = colour_name(h1, s1, l1), colour_name(h2, s2, l2)
        c1, c2 = rgb(h1, s1, l1), rgb(h2, s2, l2)
        if i % 7 == 3:                                      # 14 radial
            centre = rng.choice([(0.5, 0.5), (0.5, 0.5), (0.3, 0.4), (0.7, 0.45), (0.5, 0.2)])
            image = gradient_image(c1, c2, radial=centre)
            name = "gradient-%03d-radial-%s-to-%s" % (i, n1, n2)
        else:
            image = gradient_image(c1, c2, angle=ANGLES[i % len(ANGLES)])
            name = "gradient-%03d-%s-to-%s" % (i, n1, n2)
        save(image, os.path.join(folder, name + ".png"))


# ----------------------------------------------------------------------------------------- songs
# Concrete things and gifts, each as (English, Vietnamese). The Vietnamese is written to be correct, with its diacritics.

CONCRETE = [("river", "dòng sông"), ("mountain", "ngọn núi"), ("ocean", "đại dương"), ("valley", "thung lũng"),
            ("garden", "khu vườn"), ("wind", "cơn gió"), ("rain", "cơn mưa"), ("fire", "ngọn lửa"),
            ("sunrise", "bình minh"), ("field", "cánh đồng")]
GIFTS = [("light", "ánh sáng"), ("mercy", "lòng thương xót"), ("grace", "ân điển"), ("peace", "bình an"),
         ("hope", "hy vọng"), ("joy", "niềm vui"), ("love", "tình yêu"), ("strength", "sức mạnh"),
         ("truth", "lẽ thật"), ("promise", "lời hứa")]
ADJECTIVES = ["quiet", "golden", "endless", "gentle", "burning", "faithful", "ancient", "steady", "tender", "shining",
              "patient", "boundless"]

# (English, Vietnamese): {C1} {C2} are concrete, {G1} {G2} are gifts. A capital letter is added when a slot starts the line.
PAIRED = [
    ("{G1} rises over the {C1}", "{G1} trỗi dậy trên {C1}"),
    ("We will sing of your {G1} all our days", "Chúng con sẽ hát về {G1} của Chúa suốt đời"),
    ("You are the {G1} that never fades", "Chúa là {G1} không bao giờ phai"),
    ("Lead us through the {C1} to the {C2}", "Xin dẫn chúng con qua {C1} đến {C2}"),
    ("Let {G1} fill this quiet room", "Xin để {G1} tràn đầy căn phòng yên tĩnh này"),
    ("Every {C1} bows before your {G1}", "Mọi {C1} cúi mình trước {G1} của Chúa"),
    ("Your {G1} walks with us through the {C1}", "{G1} của Chúa đồng hành cùng chúng con qua {C1}"),
    ("Hold us when the {C1} grows dark", "Xin giữ chúng con khi {C1} trở nên tối tăm"),
    ("We found {G1} beside the {C1}", "Chúng con tìm thấy {G1} bên {C1}"),
    ("Your {G1} is deeper than the {C1}", "{G1} của Chúa sâu hơn {C1}"),
    ("Sing, my soul, of {G1} and {G2}", "Hãy hát lên, linh hồn con, về {G1} và {G2}"),
    ("Morning by morning we receive your {G1}", "Mỗi buổi sáng chúng con nhận lãnh {G1} của Chúa"),
]
# English only: more variety, with adjectives.
ENGLISH_ONLY = [
    "Beneath the {A1} sky we lift our voices",
    "Your {A1} {C1} carries us home",
    "Every {A1} {G1} is a gift from your hand",
    "We will wait by the {C1} until the dawn",
    "Rain on the {C1}, {G1} on the heart",
    "Hold fast, my soul, to {A1} {G1}",
    "The {A1} {C1} remembers your name",
    "Teach our hands to carry {G1} to the {C1}",
]
LONG_TAILS = [
    "until every tired heart in this wide room is held in the quiet of your care",
    "so that all who gather here, from the youngest to the oldest, may know your faithfulness in every season",
    "as the whole earth, from the lowest valley to the farthest shore, learns to sing together",
    "and nothing that we carry through the long night is too heavy for the hands that made the morning",
    "while the people of every street and every village lift one steady song above the noise of the day",
]
TITLE_A = ["Morning", "Lantern", "Harbor", "Silver", "Quiet", "Open", "Golden", "Distant", "River", "Mountain", "Evening",
           "Gentle", "Wide", "Faithful", "Hidden", "Rising", "Patient", "Shining"]
TITLE_B = ["Light", "Valley", "Shore", "Door", "Garden", "Dawn", "Field", "Table", "Road", "Bridge", "Window", "Lamp",
           "Harvest", "Fountain", "Hillside", "Shelter"]


def cap(text):
    return text[0].upper() + text[1:]


def fill(template, picks, language):
    """language 0 = English, 1 = Vietnamese. Slots at the start of the line get a capital."""
    out = template
    for key, pair in picks.items():
        word = pair[language] if isinstance(pair, tuple) else pair
        out = out.replace("{" + key + "}", word)
    return cap(out)


def pick_slots(rng):
    c = rng.sample(CONCRETE, 2)
    g = rng.sample(GIFTS, 2)
    return {"C1": c[0], "C2": c[1], "G1": g[0], "G2": g[1], "A1": rng.choice(ADJECTIVES)}


def section_lines(rng, bilingual, long_lines):
    """Four lines of one section: (english lines, vietnamese lines or None)."""
    english, vietnamese = [], []
    for _ in range(4):
        picks = pick_slots(rng)
        if bilingual:
            en_t, vi_t = rng.choice(PAIRED)
            english.append(fill(en_t, picks, 0))
            vietnamese.append(fill(vi_t, picks, 1))
        elif long_lines:
            first = fill(rng.choice(PAIRED + [(t, t) for t in ENGLISH_ONLY])[0], picks, 0)
            second = fill(rng.choice(ENGLISH_ONLY), pick_slots(rng), 0)
            english.append("%s, and %s, %s" % (first, second[0].lower() + second[1:], rng.choice(LONG_TAILS)))
        else:
            template = rng.choice([p[0] for p in PAIRED] + ENGLISH_ONLY)
            english.append(fill(template, picks, 0))
    return english, (vietnamese if bilingual else None)


def make_song(index):
    rng = random.Random(SEED * 1000 + index)
    bilingual = index % 5 == 0                      # 20 songs
    long_lines = index % 10 == 3                    # 10 songs, none of them bilingual
    verses = 2 + (index * 7) % 3                    # 2, 3 or 4
    has_bridge = index % 3 != 1
    plan = ["Verse 1", "Chorus", "Verse 2"] + ["Verse %d" % n for n in range(3, verses + 1)] + (["Bridge"] if has_bridge else [])
    vi_label = {"Chorus": "Điệp khúc", "Bridge": "Đoạn"}
    english_blocks, vietnamese_blocks = [], []
    for label in plan:
        en, vi = section_lines(rng, bilingual, long_lines)
        english_blocks.append(label + "\n" + "\n".join(en))
        if vi:
            vi_name = vi_label.get(label) or "Câu " + label.split()[1]
            vietnamese_blocks.append(vi_name + "\n" + "\n".join(vi))
    title = "Test Song %03d - %s %s" % (index, rng.choice(TITLE_A), rng.choice(TITLE_B))
    return title, "\n\n".join(english_blocks) + "\n", ("\n\n".join(vietnamese_blocks) + "\n") if bilingual else None


def make_songs():
    folder = os.path.join(ROOT, "songs")
    os.makedirs(folder, exist_ok=True)
    for index in range(1, COUNT + 1):
        title, english, vietnamese = make_song(index)
        with open(os.path.join(folder, title + ".txt"), "w", encoding="utf-8") as f:
            f.write(english)
        if vietnamese:
            with open(os.path.join(folder, title + ".vi.txt"), "w", encoding="utf-8") as f:
                f.write(vietnamese)


if __name__ == "__main__":
    what = sys.argv[1:] or ["solid", "gradient", "songs"]
    if "solid" in what:
        make_solids()
    if "gradient" in what:
        make_gradients()
    if "songs" in what:
        make_songs()
    print("TestData written under", os.path.normpath(ROOT))
