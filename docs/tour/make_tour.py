"""Renders the Screenshot Shelf feature tour as frames (SVG -> PNG) for a looping GIF."""
import math, os, sys
import cairosvg

W, H = 800, 500
FPS = 12
FONT = "Helvetica"
ACCENT = "#0a84ff"
DESK = "#2e3b35"
PANEL = "#1c1c1e"

# ---------------------------------------------------------------- helpers

def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))

def lerp(a, b, t):
    return a + (b - a) * t

def ease_out(t):
    t = clamp(t)
    return 1 - (1 - t) ** 3

def ease_in_out(t):
    t = clamp(t)
    return 4 * t * t * t if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2

def prog(t, start, end):
    """0..1 progress of t across [start, end]."""
    if end <= start:
        return 1.0 if t >= end else 0.0
    return clamp((t - start) / (end - start))

def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def sym(kind, x, y, size, color="#fff", op=1.0):
    """Draws a Mac key symbol as shapes (fonts often lack these glyphs). (x, y) = left, baseline."""
    w = size * 0.72
    cy = y - size * 0.36
    sw = max(1.0, size * 0.085)
    st = f'fill="none" stroke="{color}" stroke-opacity="{op:.3f}" stroke-width="{sw:.2f}" stroke-linecap="round" stroke-linejoin="round"'
    cx = x + w / 2
    if kind == "cmd":
        a = size * 0.15  # half side of the centre square
        r = size * 0.12
        d = (f"M{cx-a:.1f} {cy-a-2*r:.1f} v{4*r+2*a:.1f} M{cx+a:.1f} {cy-a-2*r:.1f} v{4*r+2*a:.1f} "
             f"M{cx-a-2*r:.1f} {cy-a:.1f} h{4*r+2*a:.1f} M{cx-a-2*r:.1f} {cy+a:.1f} h{4*r+2*a:.1f}")
        loops = ""
        for sx in (-1, 1):
            for sy in (-1, 1):
                loops += f'<circle cx="{cx+sx*(a+r):.1f}" cy="{cy+sy*(a+r):.1f}" r="{r:.1f}" {st}/>'
        return f'<path d="M{cx-a:.1f} {cy-a:.1f} h{2*a:.1f} v{2*a:.1f} h{-2*a:.1f} z" {st}/>' + loops
    if kind == "shift":
        h = size * 0.7
        top = cy - h / 2
        d = (f"M{cx:.1f} {top:.1f} L{cx+w/2:.1f} {top+h*0.48:.1f} L{cx+w*0.22:.1f} {top+h*0.48:.1f} "
             f"L{cx+w*0.22:.1f} {top+h:.1f} L{cx-w*0.22:.1f} {top+h:.1f} L{cx-w*0.22:.1f} {top+h*0.48:.1f} "
             f"L{cx-w/2:.1f} {top+h*0.48:.1f} Z")
        return f'<path d="{d}" {st}/>'
    if kind == "ctrl":
        d = f"M{cx-w*0.36:.1f} {cy+size*0.08:.1f} L{cx:.1f} {cy-size*0.26:.1f} L{cx+w*0.36:.1f} {cy+size*0.08:.1f}"
        return f'<path d="{d}" {st}/>'
    return ""

def _str_w(t, size):
    return sum(size * (0.28 if ch == " " else 0.53) for ch in t)

def rich_width(items, size):
    w = 0.0
    for it in items:
        w += size * 0.82 if isinstance(it, tuple) else _str_w(it, size)
    return w

def rich(x, y, items, size=12, fill="#fff", weight=400, anchor="start", opacity=1.0):
    """Text with key symbols mixed in: items are strings or ("s", "cmd"|"shift"|"ctrl")."""
    total = rich_width(items, size)
    if anchor == "middle":
        x -= total / 2
    out = ""
    for it in items:
        if isinstance(it, tuple):
            out += sym(it[1], x, y, size, fill, opacity)
            x += size * 0.82
        else:
            out += text(x, y, it, size, fill, weight, "start", opacity)
            x += _str_w(it, size)
    return out

def text(x, y, s, size=12, fill="#fff", weight=400, anchor="start", opacity=1.0, family=FONT):
    return (f'<text xml:space="preserve" x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size}" '
            f'font-weight="{weight}" fill="{fill}" fill-opacity="{opacity:.3f}" '
            f'text-anchor="{anchor}">{esc(s)}</text>')

def rect(x, y, w, h, rx=0, fill="#fff", opacity=1.0, stroke=None, sw=1, sop=1.0, dash=None):
    st = ""
    if stroke:
        st = f' stroke="{stroke}" stroke-width="{sw}" stroke-opacity="{sop:.3f}"'
        if dash:
            st += f' stroke-dasharray="{dash}"'
    return (f'<rect x="{x:.1f}" y="{y:.1f}" width="{max(w,0):.1f}" height="{max(h,0):.1f}" rx="{rx}" '
            f'fill="{fill}" fill-opacity="{opacity:.3f}"{st}/>')

def group(content, opacity=1.0, transform=""):
    tr = f' transform="{transform}"' if transform else ""
    return f'<g opacity="{opacity:.3f}"{tr}>{content}</g>'

_clip_id = [0]
def clipped(x, y, w, h, rx, content):
    _clip_id[0] += 1
    cid = f"c{_clip_id[0]}"
    return (f'<clipPath id="{cid}"><rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}"/></clipPath>'
            f'<g clip-path="url(#{cid})">{content}</g>')

# ---------------------------------------------------------------- building blocks

def desktop():
    return rect(0, 0, W, H, 0, DESK)

def menubar(icon_active=False):
    s = rect(0, 0, W, 24, 0, "#f6f6f8", 0.92)
    s += f'<circle cx="18" cy="12" r="5" fill="none" stroke="#1d1d1f" stroke-width="1.5"/>'
    s += text(34, 16.5, "Finder", 12, "#1d1d1f", 700)
    x = 86
    for m in ["File", "Edit", "View", "Go", "Window"]:
        s += text(x, 16.5, m, 12, "#1d1d1f")
        x += len(m) * 7 + 18
    # shelf icon
    ix = 604
    if icon_active:
        s += rect(ix - 6, 3, 28, 18, 5, "#000", 0.16)
    s += rect(ix, 8, 10, 8, 1.5, "none", 1, "#1d1d1f", 1.3)
    s += f'<path d="M{ix+3} 6 h9.5 v7" fill="none" stroke="#1d1d1f" stroke-width="1.3" stroke-linecap="round"/>'
    # wifi + battery
    s += f'<path d="M640 10a9 9 0 0 1 13 0M642.5 12.5a5.5 5.5 0 0 1 8 0M645 15a2 2 0 0 1 3 0" fill="none" stroke="#1d1d1f" stroke-width="1.4" stroke-linecap="round"/>'
    s += rect(664, 7, 20, 10, 2.5, "none", 1, "#1d1d1f", 1.1) + rect(666, 9, 12, 6, 1.2, "#1d1d1f")
    s += text(788, 16.5, "Mon 9:41 AM", 12, "#1d1d1f", 400, "end")
    return s

def chart_content(x, y, w, h):
    """A simple page with a bar chart: what gets screenshotted."""
    s = rect(x, y, w, h, 0, "#ffffff")
    s += rect(x + w * 0.06, y + h * 0.10, w * 0.35, h * 0.07, 2, "#1d1d1f")
    s += rect(x + w * 0.06, y + h * 0.22, w * 0.55, h * 0.04, 2, "#c7c7cc")
    bars = [0.45, 0.62, 0.38, 0.8, 0.66, 0.92]
    colors = ["#9ec5f8", "#9ec5f8", "#9ec5f8", ACCENT, "#9ec5f8", "#9ec5f8"]
    base = y + h * 0.90
    bw = w * 0.09
    for i, b in enumerate(bars):
        bx = x + w * 0.08 + i * w * 0.145
        bh = h * 0.55 * b
        s += rect(bx, base - bh, bw, bh, 2, colors[i])
    s += rect(x + w * 0.06, base, w * 0.88, max(1, h * 0.008), 0, "#d1d1d6")
    return s

def doc_window(x=60, y=60, w=420, h=330, opacity=1.0):
    s = rect(x, y, w, h, 10, "#ffffff", 1, "#000", 0.5, 0.25)
    s += rect(x, y, w, 30, 10, "#ececef") + rect(x, y + 20, w, 10, 0, "#ececef")
    for i, c in enumerate(["#ec6a5e", "#f4bf4f", "#61c554"]):
        s += f'<circle cx="{x+16+i*16}" cy="{y+15}" r="5" fill="{c}"/>'
    s += rect(x + w / 2 - 90, y + 8, 180, 14, 7, "#ffffff")
    s += text(x + w / 2, y + 19, "analytics.example.com", 9, "#6e6e73", 400, "middle")
    s += text(x + 36, y + 66, "Weekly sign-ups", 16, "#1d1d1f", 700)
    s += rect(x + 36, y + 76, 200, 6, 3, "#c7c7cc")
    # the region that gets captured
    s += chart_content(96, 170, 240, 122)
    s += rect(x + 36, y + 252, 300, 6, 3, "#e5e5ea")
    s += rect(x + 36, y + 266, 240, 6, 3, "#e5e5ea")
    s += rect(x + 36, y + 280, 270, 6, 3, "#e5e5ea")
    return group(s, opacity)

def cursor(x, y, pressed=False):
    sc = 0.9 if pressed else 1.0
    return (f'<g transform="translate({x:.1f},{y:.1f}) scale({sc})">'
            f'<path d="M0 0 L0 17 L4.5 13 L7.5 20 L10.5 18.6 L7.6 12 L13 12 Z" fill="#fff" stroke="#000" stroke-width="1.1" stroke-linejoin="round"/></g>')

def crosshair(x, y):
    return (f'<path d="M{x-9} {y} H{x+9} M{x} {y-9} V{y+9}" stroke="#fff" stroke-width="1.5"/>'
            f'<path d="M{x-9} {y} H{x+9} M{x} {y-9} V{y+9}" stroke="#000" stroke-width="0.5"/>')

def caption(s, opacity=1.0, y=468):
    items = s if isinstance(s, list) else [s]
    w = rich_width(items, 15) + 44
    c = rect(W / 2 - w / 2, y - 21, w, 32, 16, "#000000", 0.62)
    c += rich(W / 2, y, items, 15, "#ffffff", 600, "middle")
    return group(c, opacity)

def phone_icon(x, y, color="#ffffff", op=0.6):
    return (f'<rect x="{x}" y="{y}" width="7" height="12" rx="1.6" fill="none" stroke="{color}" stroke-opacity="{op}" stroke-width="1.2"/>'
            f'<rect x="{x+2.5}" y="{y+9.4}" width="2" height="1" rx="0.5" fill="{color}" fill-opacity="{op}"/>')

def pin_icon(x, y, color="#fff", filled=False):
    f = color if filled else "none"
    return f'<path d="M{x+1.5} {y} h5 l-0.8 4.5 l2.6 2.6 h-8.6 l2.6 -2.6 z M{x+4} {y+7} v5" fill="{f}" stroke="{color}" stroke-width="1.2" stroke-linejoin="round" stroke-linecap="round"/>'

# ---------------------------------------------------------------- the shelf

SHELF_W = 284

def shelf_header(px, py, tab):
    s = rect(px + 12, py + 12, 222, 32, 9, "#ffffff", 0.07)
    selx = px + 14 if tab == "shots" else px + 124
    s += rect(selx, py + 14, 108, 28, 7, "#ffffff", 0.18)
    s += text(px + 68, py + 32.5, "Screenshots", 12, "#fff", 600, "middle", 1 if tab == "shots" else 0.65)
    s += text(px + 178, py + 32.5, "Clipboard", 12, "#fff", 600, "middle", 1 if tab == "clips" else 0.65)
    s += f'<circle cx="{px+257}" cy="{py+28}" r="15" fill="#fff" fill-opacity="0.14"/>'
    s += f'<path d="M{px+252} {py+23} L{px+262} {py+33} M{px+262} {py+23} L{px+252} {py+33}" stroke="#fff" stroke-width="2" stroke-linecap="round"/>'
    return s

def toast_view(x, y, msg, op):
    s = rect(x, y, 260, 28, 8, "#ffffff", 0.10)
    s += f'<circle cx="{x+16}" cy="{y+14}" r="7" fill="#30d158"/>'
    s += f'<path d="M{x+12.5} {y+14} l2.4 2.4 l4.4 -4.8" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>'
    s += text(x + 30, y + 18.5, msg, 11, "#fff", 600)
    return group(s, op)

def shot_card(x, y, hover=0.0, pressed=None, meta_left="Just now", meta_right="Deletes in 7 days"):
    s = rect(x, y, 260, 172, 12, "#ffffff", 0.06 + 0.04 * hover)
    tx, ty = x + 8, y + 8
    inner = chart_content(tx, ty, 244, 124)
    if hover > 0:
        bar = rect(tx, ty + 86, 244, 38, 0, "#000", 0.75)
        bx = tx + 6
        bar += rect(bx, ty + 92, 81, 26, 6, ACCENT, 0.75 if pressed == "copy" else 1)
        bar += text(bx + 40.5, ty + 109, "Copy", 11, "#fff", 600, "middle")
        bar += rect(bx + 87, ty + 92, 81, 26, 6, "#ffffff", 0.34 if pressed == "text" else 0.18)
        bar += text(bx + 127.5, ty + 109, "Copy text", 11, "#fff", 600, "middle")
        bar += rect(bx + 174, ty + 92, 26, 26, 6, "#ffffff", 0.18) + pin_icon(bx + 182.5, ty + 98)
        bar += rect(bx + 206, ty + 92, 26, 26, 6, "#ffffff", 0.18)
        bar += f'<path d="M{bx+213.5} {ty+100} h11 M{bx+217} {ty+100} v-1.5 h4 v1.5 M{bx+215} {ty+100} l0.8 9.5 h6.4 l0.8 -9.5" fill="none" stroke="#fff" stroke-width="1.3" stroke-linejoin="round" stroke-linecap="round"/>'
        inner += group(bar, hover)
    s += clipped(tx, ty, 244, 124, 8, inner)
    s += text(x + 10, y + 156, meta_left, 11, "#fff", 400, "start", 0.55)
    s += text(x + 250, y + 156, meta_right, 11, "#fff", 400, "end", 0.55)
    return s

def shelf_shots(px, py, hover=0.0, pressed=None, toast=None, toast_op=0.0, toast_shift=0.0):
    content_h = 56 + 172 + 12 + toast_shift
    s = rect(px, py, SHELF_W, content_h, 16, PANEL, 0.96, "#ffffff", 0.5, 0.14)
    s += shelf_header(px, py, "shots")
    if toast:
        s += toast_view(px + 12, py + 56, toast, toast_op)
    s += shot_card(px + 12, py + 56 + toast_shift, hover, pressed)
    return s

def clip_rows(px, y, rows):
    s = ""
    for r in rows:
        h = 52 if r.get("image") else 38
        s += rect(px + 12, y, 260, h, 8, "#ffffff", 0.06)
        if r.get("image"):
            s += clipped(px + 20, y + 7, 60, 38, 5, chart_content(px + 20, y + 7, 60, 38))
            s += phone_icon(px + 90, y + 20)
            s += text(px + 104, y + 30, "Image from iPhone · 1 min ago", 11, "#fff", 400, "start", 0.55)
        else:
            tx = px + 22
            if r.get("phone"):
                s += phone_icon(px + 22, y + 13)
                tx = px + 36
            s += text(tx, y + 23.5, r["text"], 12, "#fff")
            if r.get("pinned"):
                s += pin_icon(px + 252, y + 13, "#ff9f0a", True)
        y += h + 6
    return s, y

def shelf_clips(px, py, query="", caret=True, rows=None, height=None):
    rows = rows or []
    filtered = [r for r in rows if query.lower() in r.get("text", "").lower()] if query else rows
    body, end_y = clip_rows(px, py + 94, filtered)
    total_h = height or (end_y - py + 30)
    s = rect(px, py, SHELF_W, total_h, 16, PANEL, 0.96, "#ffffff", 0.5, 0.14)
    s += shelf_header(px, py, "clips")
    s += rect(px + 12, py + 56, 260, 28, 6, "#ffffff", 0.08, ACCENT, 2)
    if query:
        s += text(px + 22, py + 74.5, query, 12, "#fff")
        cx = px + 22 + len(query) * 6.9 + 1
    else:
        s += text(px + 22, py + 74.5, "Search clipboard", 12, "#fff", 400, "start", 0.45)
        cx = px + 21
    if caret:
        s += rect(cx, py + 63, 1.5, 14, 0, "#fff")
    s += body
    s += rich(px + 14, py + total_h - 12, [("s", "ctrl"), ("s", "cmd"), "V opens this · Return copies the top one"], 10, "#fff", 400, "start", 0.5)
    return s

CLIP_ROWS = [
    {"text": "Meeting moved to 4:30", "phone": True},
    {"text": 'git commit -m "Fix shelf"'},
    {"image": True, "text": ""},
    {"text": "Flat 4B, Green Park Apts", "pinned": True},
    {"text": "npm run build -- --watch"},
]

# ---------------------------------------------------------------- scenes

def app_icon(cx, cy, size):
    s = size / 100
    g = rect(cx - 50 * s, cy - 50 * s, 100 * s, 100 * s, 24 * s, PANEL, 1, "#ffffff", 1, 0.15)
    g += rect(cx - 26 * s, cy - 14 * s, 44 * s, 34 * s, 6 * s, "#ffffff", 0.18)
    g += rect(cx - 18 * s, cy - 24 * s, 44 * s, 34 * s, 6 * s, ACCENT)
    g += rect(cx - 12 * s, cy - 6 * s, 10 * s, 12 * s, 1.5 * s, "#fff", 0.9)
    g += rect(cx + 1 * s, cy - 12 * s, 10 * s, 18 * s, 1.5 * s, "#fff", 0.9)
    g += rect(cx + 14 * s, cy - 2 * s, 8 * s, 8 * s, 1.5 * s, "#fff", 0.9)
    return g

def scene_title(t, d):
    s = rect(0, 0, W, H, 0, "#18201c")
    a = ease_out(prog(t, 0.0, 0.7))
    b = ease_out(prog(t, 0.3, 1.0))
    s += group(app_icon(W / 2, 190 - 10 * (1 - a), 96), a)
    s += group(text(W / 2, 290, "Screenshot Shelf", 40, "#fff", 700, "middle"), b,
               f"translate(0,{12*(1-b):.1f})")
    c = ease_out(prog(t, 0.6, 1.3))
    s += group(text(W / 2, 326, "Your screenshots and clipboard, tidy and searchable.", 17, "#fff", 400, "middle", 0.75), c)
    return s

DOC = None

def scene_capture(t, d):
    s = desktop() + menubar() + doc_window()
    # selection drag
    sel = ease_in_out(prog(t, 0.5, 1.6))
    if 0.4 <= t < 1.75:
        x0, y0 = 96, 170
        x1, y1 = lerp(x0, 336, sel), lerp(y0, 292, sel)
        s += rect(0, 0, W, H, 0, "#000", 0.18)
        s += rect(x0, y0, x1 - x0, y1 - y0, 0, "#ffffff", 0.12, "#ffffff", 1.2)
        s += crosshair(x1, y1)
    # flash
    fl = prog(t, 1.6, 1.75) if t < 1.75 else 1 - prog(t, 1.75, 2.0)
    # shelf slides in
    px = lerp(W + 10, 500, ease_out(prog(t, 1.9, 2.5)))
    if t >= 1.9:
        s += shelf_shots(px, 34)
    # thumbnail flies (drawn over the shelf card until it lands)
    if 1.75 <= t < 2.75:
        f = ease_in_out(prog(t, 1.8, 2.7))
        fx, fy = lerp(96, 520, f), lerp(170, 98, f)
        fw, fh = lerp(240, 244, f), lerp(122, 124, f)
        lift = math.sin(f * math.pi) * 18
        sh = rect(fx + 4, fy + 8 - lift, fw, fh, 8, "#000", 0.25 * math.sin(f * math.pi))
        s += sh + clipped(fx, fy - lift, fw, fh, 8, chart_content(fx, fy - lift, fw, fh))
    if fl > 0:
        s += rect(0, 0, W, H, 0, "#ffffff", 0.85 * fl)
    if t < 2.4:
        s += caption(["Take a screenshot  ", ("s", "shift"), ("s", "cmd"), "4"], 1 - prog(t, 2.2, 2.4))
    else:
        s += caption("It lands on the shelf, not your Desktop", prog(t, 2.4, 2.6))
    return s

def scene_copytext(t, d):
    s = desktop() + menubar() + doc_window()
    cx = lerp(360, 600, ease_in_out(prog(t, 0.0, 0.8)))
    cy = lerp(330, 160, ease_in_out(prog(t, 0.0, 0.8)))
    hover = ease_out(prog(t, 0.6, 0.9))
    # move to "Copy text"
    m2 = ease_in_out(prog(t, 0.9, 1.4))
    cx, cy = lerp(cx, 650, m2), lerp(cy, 202, m2)
    pressed = "text" if 1.45 <= t < 1.7 else None
    toast_p = ease_out(prog(t, 1.65, 1.95))
    s += shelf_shots(500, 34, hover, pressed, "Copied 3 lines of text", toast_p, 36 * toast_p)
    s += cursor(cx, cy + 36 * toast_p * (1 if t > 1.65 else 0), pressed is not None)
    s += caption("Copy the image, or the text inside it", prog(t, 0.0, 0.25))
    return s

def chat_window(drop_hint=0.0, sent=0.0):
    x, y, w, h = 40, 44, 400, 386
    s = rect(x, y, w, h, 12, "#ffffff", 1, "#000", 0.5, 0.25)
    s += rect(x, y, w, 44, 12, "#ffffff") + rect(x, y + 43, w, 1, 0, "#000", 0.1)
    for i, c in enumerate(["#ec6a5e", "#f4bf4f", "#61c554"]):
        s += f'<circle cx="{x+18+i*16}" cy="{y+22}" r="5" fill="{c}"/>'
    s += text(x + 80, y + 27, "Riya", 13, "#1d1d1f", 600)
    s += rect(x, y + 44, w, h - 44 - 46, 0, "#f6f6f8")
    s += rect(x + 16, y + 60, 210, 30, 15, "#ffffff", 1, "#000", 0.5, 0.1)
    s += text(x + 30, y + 80, "can you send me the chart?", 12, "#1d1d1f")
    s += rect(x + w - 16 - 100, y + 100, 100, 30, 15, ACCENT)
    s += text(x + w - 66, y + 120, "one sec", 12, "#fff", 400, "middle")
    if sent > 0:
        iy = y + 142 + 10 * (1 - sent)
        s += group(rect(x + w - 16 - 180, iy, 180, 92, 14, "#000", 0.08)
                   + clipped(x + w - 16 - 180, iy, 180, 92, 14, chart_content(x + w - 16 - 180, iy, 180, 92)), sent)
    if drop_hint > 0:
        s += group(rect(x + 16, y + 150, w - 32, 130, 12, ACCENT, 0.08, ACCENT, 2, 1, "6 5")
                   + text(x + w / 2, y + 222, "Drop to send", 13, "#0a4fa8", 600, "middle"), drop_hint)
    s += rect(x + 14, y + h - 38, w - 28, 28, 14, "#f0f0f3")
    s += text(x + 30, y + h - 19, "Message", 12, "#8e8e93")
    return s

def scene_drag(t, d):
    s = desktop() + menubar()
    dragging = 0.5 <= t < 2.4
    drop_hint = ease_out(prog(t, 0.6, 0.9)) * (1 - prog(t, 2.3, 2.5))
    sent = ease_out(prog(t, 2.45, 2.8))
    s += chat_window(drop_hint, sent)
    s += shelf_shots(500, 34)
    # cursor path: card -> chat
    start = (640, 150)
    end = (250, 250)
    f = ease_in_out(prog(t, 0.5, 2.2))
    cx, cy = lerp(start[0], end[0], f), lerp(start[1], end[1], f)
    if t < 0.5:
        cx, cy = lerp(700, 640, ease_out(prog(t, 0, 0.4))), lerp(300, 150, ease_out(prog(t, 0, 0.4)))
    if dragging:
        g = clipped(cx - 70, cy - 30, 140, 72, 8, chart_content(cx - 70, cy - 30, 140, 72))
        s += group(rect(cx - 66, cy - 22, 140, 72, 8, "#000", 0.25) + g, 0.92,
                   f"rotate(-4 {cx:.1f} {cy:.1f})")
    s += cursor(cx, cy, dragging)
    s += caption("Drag it straight into any app", prog(t, 0.0, 0.25))
    return s

def keycaps(cx, cy, scale, op):
    keys = [("s", "ctrl"), ("s", "cmd"), "V"]
    g = ""
    for i, k in enumerate(keys):
        x = cx - 105 + i * 75
        g += rect(x, cy - 32, 60, 60, 12, "#ffffff", 1, "#000", 1, 0.15)
        g += rect(x, cy + 22, 60, 6, 3, "#000", 0.12)
        if isinstance(k, tuple):
            g += sym(k[1], x + 30 - 28 * 0.36, cy + 10, 28, "#1d1d1f")
        else:
            g += text(x + 30, cy + 9, k, 28, "#1d1d1f", 600, "middle")
    return group(g, op, f"translate({cx:.1f},{cy:.1f}) scale({scale:.3f}) translate({-cx:.1f},{-cy:.1f})")

def scene_clipboard(t, d):
    s = desktop() + menubar() + doc_window(opacity=1.0)
    pop = ease_out(prog(t, 0.0, 0.35))
    kop = pop * (1 - prog(t, 1.0, 1.3))
    if kop > 0:
        s += rect(0, 0, W, H, 0, "#000", 0.25 * kop)
        s += keycaps(W / 2, H / 2 - 10, 0.85 + 0.15 * pop, kop)
    if t >= 0.9:
        px = lerp(W + 10, 500, ease_out(prog(t, 0.9, 1.4)))
        q = "meet"
        n = int(clamp((t - 2.0) / 0.25, 0, len(q)))
        query = q[:n]
        caret = int(t * 2.5) % 2 == 0 or n < len(q)
        s += shelf_clips(px, 34, query, caret, CLIP_ROWS,
                         height=None if not query else None)
    s += caption([("s", "ctrl"), ("s", "cmd"), "V: everything you copied, even on your iPhone"], prog(t, 0.2, 0.45))
    return s

def library_window(x, y, query, typed_done, op):
    w, h = 440, 400
    s = rect(x, y, w, h, 12, "#fbfbfd", 1, "#000", 0.5, 0.2)
    s += rect(x + 14, y + 14, w - 28, 24, 6, "#e8e8ed")
    s += rect(x + 16, y + 16, (w - 32) / 2, 20, 5, "#ffffff", 1, "#000", 0.5, 0.08)
    s += text(x + 14 + (w - 28) / 4, y + 30.5, "Screenshots", 12, "#1d1d1f", 600, "middle")
    s += text(x + 14 + 3 * (w - 28) / 4, y + 30.5, "Clipboard", 12, "#1d1d1f", 400, "middle")
    s += rect(x + 14, y + 48, w - 28, 26, 6, "#ffffff", 1, "#000", 1, 0.18)
    if query:
        s += text(x + 24, y + 65.5, query, 12, "#1d1d1f")
    else:
        s += text(x + 24, y + 65.5, "Search text inside screenshots", 12, "#8e8e93")
    if not typed_done:
        s += text(x + 16, y + 100, "PINNED · KEPT FOREVER", 10, "#6e6e73", 700)
        for i in range(3):
            tx = x + 16 + i * 140
            s += rect(tx, y + 108, 128, 72, 7, ["#dfe8dc", "#ffffff", "#1e1f22"][i], 1, "#000", 0.5, 0.12)
        s += text(x + 16, y + 206, "RECENT", 10, "#6e6e73", 700)
        s += clipped(x + 16, y + 214, 200, 100, 7, chart_content(x + 16, y + 214, 200, 100))
        s += rect(x + 16, y + 214, 200, 100, 7, "none", 1, "#000", 0.5, 0.12)
        s += rect(x + 224, y + 214, 200, 100, 7, "#e4ecf7", 1, "#000", 0.5, 0.12)
        s += text(x + 16, y + 328, "Just now", 10, "#6e6e73")
        s += text(x + 216, y + 328, "Deletes in 7 days", 10, "#6e6e73", 400, "end")
        s += text(x + 224, y + 328, "5 days ago", 10, "#6e6e73")
        s += text(x + 424, y + 328, "Deletes tomorrow", 10, "#c2410c", 400, "end")
    else:
        s += text(x + 16, y + 100, "RESULTS", 10, "#6e6e73", 700)
        rx, ry = x + 16, y + 108
        g = rect(rx, ry, 200, 120, 7, "#ffffff", 1, ACCENT, 2)
        g += text(rx + 14, ry + 22, "INVOICE #2041", 10, "#6e6e73", 700)
        g += text(rx + 14, ry + 48, "Total 12,400", 18, "#1d1d1f", 700)
        g += rect(rx + 14, ry + 62, 150, 5, 2, "#c7c7cc") + rect(rx + 14, ry + 74, 120, 5, 2, "#c7c7cc")
        g += rect(rx + 14, ry + 92, 60, 16, 4, "#2f7a46")
        s += g
        s += text(rx, ry + 136, "2 days ago", 10, "#6e6e73")
        s += text(rx + 200, ry + 136, "Deletes in 5 days", 10, "#6e6e73", 400, "end")
    s += rect(x + 14, y + h - 62, w - 28, 1, 0, "#000", 0.12)
    s += text(x + 16, y + h - 38, "Auto-delete unpinned after", 12, "#1d1d1f", 600)
    s += rect(x + w - 110, y + h - 52, 96, 22, 5, "#ffffff", 1, "#000", 1, 0.18)
    s += text(x + w - 100, y + h - 36.5, "7 days", 12, "#1d1d1f")
    s += f'<path d="M{x+w-32} {y+h-44} l3.5 3.5 l3.5 -3.5" fill="none" stroke="#1d1d1f" stroke-width="1.4" stroke-linecap="round"/>'
    s += text(x + 16, y + h - 18, "Show shelf   ·   Open folder", 11, "#6e6e73")
    return group(s, op)

def scene_library(t, d):
    s = desktop() + menubar(icon_active=t > 0.35) + doc_window()
    cx = lerp(560, 610, ease_in_out(prog(t, 0.0, 0.35)))
    cy = lerp(200, 12, ease_in_out(prog(t, 0.0, 0.35)))
    op = ease_out(prog(t, 0.4, 0.7))
    q = "invoice"
    n = int(clamp((t - 1.0) / 0.13, 0, len(q)))
    done = n == len(q) and t > 2.0
    if op > 0:
        s += group(library_window(330, 30 - 8 * (1 - op), q[:n], done, 1), op)
    s += cursor(cx, cy, 0.3 < t < 0.45)
    s += caption("Search the text inside every screenshot", prog(t, 0.0, 0.25))
    return s

def feature_row(x, y, icon, title, sub, op, dx):
    g = f'<circle cx="{x+22}" cy="{y+22}" r="22" fill="#ffffff" fill-opacity="0.08"/>' + icon(x + 22, y + 22)
    g += text(x + 60, y + 18, title, 17, "#fff", 700)
    g += text(x + 60, y + 40, sub, 13, "#fff", 400, "start", 0.65)
    return group(g, op, f"translate({dx:.1f},0)")

def ic_moon(cx, cy):
    return f'<path d="M{cx+5} {cy-9} a9.5 9.5 0 1 0 5 13 a7.5 7.5 0 0 1 -5 -13z" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round"/>'

def ic_text(cx, cy):
    return f'<path d="M{cx-9} {cy-7} h18 M{cx-9} {cy} h18 M{cx-9} {cy+7} h11" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/>'

def ic_trash(cx, cy):
    return f'<path d="M{cx-9} {cy-6} h18 M{cx-3} {cy-6} v-3 h6 v3 M{cx-6} {cy-6} l1 15 h10 l1 -15" fill="none" stroke="#fff" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>'

def ic_lock(cx, cy):
    return (f'<rect x="{cx-8}" y="{cy-2}" width="16" height="12" rx="2.5" fill="none" stroke="#fff" stroke-width="1.8"/>'
            f'<path d="M{cx-5} {cy-2} v-4 a5 5 0 0 1 10 0 v4" fill="none" stroke="#fff" stroke-width="1.8"/>')

def scene_light(t, d):
    s = rect(0, 0, W, H, 0, "#18201c")
    a = ease_out(prog(t, 0.0, 0.5))
    s += group(text(110, 92, "Light on your Mac", 30, "#fff", 700), a)
    rows = [
        (ic_moon, "Sleeps until you take a screenshot", "macOS wakes it only when your screenshot folder changes"),
        (ic_text, "Reads text only when you ask", "in a small helper that quits a few seconds later"),
        (ic_trash, "Tidies itself up", "unpinned items go to the Trash after 7 days"),
        (ic_lock, "Nothing leaves your Mac", "no network access, no system changes"),
    ]
    for i, (ic, ti, sub) in enumerate(rows):
        p = ease_out(prog(t, 0.35 + i * 0.35, 0.8 + i * 0.35))
        s += feature_row(110, 130 + i * 78, ic, ti, sub, p, 24 * (1 - p))
    return s

def scene_end(t, d):
    s = rect(0, 0, W, H, 0, "#18201c")
    a = ease_out(prog(t, 0.0, 0.6))
    s += group(app_icon(W / 2, 180, 84), a)
    s += group(text(W / 2, 268, "Screenshot Shelf", 34, "#fff", 700, "middle"), a)
    b = ease_out(prog(t, 0.3, 0.9))
    s += group(rich(W / 2, 312, [("s", "shift"), ("s", "cmd"), "4 to capture   ·   ", ("s", "ctrl"), ("s", "cmd"), "V for your clipboard"], 16, "#fff", 500, "middle", 0.8), b)
    return s

SCENES = [
    (scene_title, 2.4),
    (scene_capture, 4.0),
    (scene_copytext, 3.4),
    (scene_drag, 3.8),
    (scene_clipboard, 4.4),
    (scene_library, 4.0),
    (scene_light, 3.8),
    (scene_end, 2.4),
]

FADE = 0.22

def frame_svg(t_global):
    acc = 0.0
    for fn, d in SCENES:
        if t_global < acc + d:
            lt = t_global - acc
            body = fn(lt, d)
            edge = min(lt, d - lt)
            dark = 1 - clamp(edge / FADE)
            if dark > 0:
                body += rect(0, 0, W, H, 0, "#000", dark * 0.85)
            break
        acc += d
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
            f'{body}</svg>')

def total_duration():
    return sum(d for _, d in SCENES)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "frames"
    only = [float(x) for x in sys.argv[2:]]
    os.makedirs(out, exist_ok=True)
    if only:
        for tt in only:
            cairosvg.svg2png(bytestring=frame_svg(tt).encode(), write_to=f"{out}/t{tt:05.2f}.png")
    else:
        n = int(total_duration() * FPS)
        for i in range(n):
            _clip_id[0] = 0
            cairosvg.svg2png(bytestring=frame_svg(i / FPS).encode(), write_to=f"{out}/f{i:04d}.png")
        print(n, "frames")
