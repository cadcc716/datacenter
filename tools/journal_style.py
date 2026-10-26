"""Journal figure style for the English figures (Applied Energy manuscript).

The English figures follow the look of the target journal: Times-like serif type with STIX mathematics,
white panels with dark frames and outward ticks, bold panel titles, light grid lines and framed legends.
The categorical colours are a muted version of the reference palette (same hue order and roles, so every
entity keeps its colour), validated with the data-viz palette checks on a white surface:
lightness band, chroma floor, CVD separation of adjacent slots (>= 8), normal-vision floor.

Usage (both plotting scripts, English mode only):
    import journal_style as js
    js.apply_rc()            # before any figure is created
    js.restyle(fig)          # just before saving: recolours every artist and styles the axes
    js.save_both(fig, path)  # PNG (for the Markdown drafts) + vector PDF (for the LaTeX manuscript)
"""
import os
import re
import numpy as np
import matplotlib.pyplot as plt
from matplotlib import colors as mcolors
from matplotlib import font_manager
from matplotlib.lines import Line2D
from matplotlib.patches import Patch
from matplotlib.collections import Collection
from matplotlib.text import Text
from matplotlib.legend import Legend

# reference palette (light mode) -> muted journal palette; neutrals -> plain greys on white
CMAP = {
    "#2a78d6": "#3b6fb0",   # slot 1 blue   (JR-D / proposed)
    "#eb6834": "#df7a35",   # slot 2 orange (IR-O*)
    "#1baf7a": "#1f9f78",   # slot 3 aqua   (IR-P)
    "#eda100": "#d39b12",   # slot 4 yellow (JR-S)
    "#e87ba4": "#cf6a95",   # slot 5 magenta (JR-M)
    "#008300": "#3f8a2a",   # slot 6 green  (IR-O)
    "#6250d6": "#6a5bc2",   # slot 7 violet (IR-R)
    "#e34948": "#c4433a",   # slot 8 red    (perfect information / limits)
    "#86b6ef": "#93b5dc",   # blue ramp (ordinal)
    "#9ec5f0": "#b1cbe8",
    "#3987e5": "#4a7fc0",
    "#1c5cab": "#2c5a94",
    "#123e70": "#1e3b63",
    "#fcfcfb": "#ffffff",   # surface
    "#f0efec": "#f2f2f2",   # diverging midpoint
    "#e1e0d9": "#e4e4e4",   # grid
    "#c3c2b7": "#9a9a9a",   # light rule
    "#898781": "#7a7a7a",   # muted ink
    "#52514e": "#3c3c3c",   # secondary ink
    "#0b0b0b": "#111111",   # primary ink
}
_RGB = {tuple(np.round(mcolors.to_rgb(k), 4)): mcolors.to_rgb(v) for k, v in CMAP.items()}
FRAME = "#3c3c3c"


def serif_fonts():
    have = {f.name for f in font_manager.fontManager.ttflist}
    return [f for f in ["Times New Roman", "Liberation Serif", "TeX Gyre Termes", "Nimbus Roman", "DejaVu Serif"] if f in have]


def apply_rc():
    plt.rcParams.update({
        "font.family": serif_fonts() + ["DejaVu Serif"], "font.serif": serif_fonts() + ["DejaVu Serif"],
        "mathtext.fontset": "stix",                                   # family list = glyph fallback (e.g. superscripts)
        "font.size": 9.5, "axes.titlesize": 10, "axes.titleweight": "bold", "axes.labelsize": 9.5,
        "xtick.labelsize": 8.8, "ytick.labelsize": 8.8, "legend.fontsize": 8.4,
        "axes.edgecolor": FRAME, "axes.linewidth": 0.8, "axes.labelcolor": "#111111", "text.color": "#111111",
        "xtick.color": FRAME, "ytick.color": FRAME, "xtick.direction": "out", "ytick.direction": "out",
        "axes.grid": True, "grid.color": "#e4e4e4", "grid.linewidth": 0.6, "grid.linestyle": "-",
        "legend.frameon": True, "legend.edgecolor": "#b5b5b5", "legend.framealpha": 0.92, "legend.fancybox": False,
        "figure.facecolor": "#ffffff", "axes.facecolor": "#ffffff", "savefig.facecolor": "#ffffff",
        "savefig.dpi": 300, "pdf.fonttype": 42, "ps.fonttype": 42, "axes.axisbelow": True,
    })


def _map(c):
    """recolour one RGBA colour if its RGB part is a palette colour (alpha kept)"""
    if c is None:
        return c
    try:
        r = mcolors.to_rgba(c)
    except (ValueError, TypeError):
        return c
    key = tuple(np.round(r[:3], 4))
    if key in _RGB:
        return (*_RGB[key], r[3])
    return r


def _map_arr(a):
    a = np.asarray(a, dtype=float)
    if a.ndim != 2 or a.shape[0] == 0:
        return a
    out = a.copy()
    for i in range(a.shape[0]):
        out[i] = _map(a[i])
    return out


# plain-text notation of the drawing code -> mathtext (applied outside existing $...$ segments, in order)
MATH = [
    (r"Γ_B/Γ_B⁰", r"$\Gamma_B/\Gamma_B^0$"), (r"Γ_B⁰", r"$\Gamma_B^0$"), (r"Γ_B", r"$\Gamma_B$"),
    (r"\bc_rb\b", r"$c^{\mathrm{rb}}$"), (r"MWh_th", r"MWh$_{\mathrm{th}}$"), (r"MW_th", r"MW$_{\mathrm{th}}$"),
    (r"\bG_k\b", r"$G_k$"), (r"\bC_k\b", r"$C_k$"), (r"\bC_([0-9])\b", r"$C_\1$"), (r"\bh_123\b", r"$h_{123}$"),
    (r"P\^G", r"$P^{\mathrm{G}}$"), (r"η_e", r"$\eta_e$"), (r"B_c ≤ B̄_c", r"$B_c \leq \bar{B}_c$"),
    (r"Σ\(P̄−P\^b\)⁺Δt", r"$\Sigma(\bar{P}-P^{\mathrm{b}})^{+}\Delta t$"), (r"P̄ = γP̂", r"$\bar{P}=\gamma\hat{P}$"),
    (r"εΣB", r"$\varepsilon\Sigma B$"), (r"θ\*", r"$\theta^*$"), (r"α\*", r"$\alpha^*$"),
]
GREEK = {"τ": "tau", "γ": "gamma", "ρ": "rho", "λ": "lambda", "δ": "delta", "α": "alpha", "θ": "theta",
         "ν": "nu", "μ": "mu", "ε": "varepsilon", "η": "eta", "φ": "varphi", "κ": "kappa", "β": "beta"}


def _outside_math(text, fn):
    parts = text.split("$")
    return "$".join(fn(p) if i % 2 == 0 else p for i, p in enumerate(parts))


def mathify(text):
    """typeset the variables of a label as mathematics (journal convention: italic symbols)"""
    if not text or text.count("$") % 2:
        return text
    for pat, rep in MATH:                         # replacement taken literally; "\\1" -> first group
        text = _outside_math(text, lambda p: re.sub(pat, lambda m: rep.replace("\\1", m.group(1) if m.groups() else ""), p))
    return _outside_math(text, lambda p: re.sub(r"(?<![A-Za-z\\])([%s])(?![A-Za-z])" % "".join(GREEK),
                                                   lambda m: "$\\" + GREEK[m.group(1)] + "$", p))


def restyle(fig):
    fig.set_facecolor("#ffffff")
    for ax in fig.axes:
        ax.set_facecolor(_map(ax.get_facecolor()))
        for s in ax.spines.values():
            if s.get_visible():
                s.set_edgecolor(FRAME)
        ax.title.set_fontweight("bold")
    for o in fig.findobj():
        if isinstance(o, Line2D):
            o.set_color(_map(o.get_color()))
            o.set_markerfacecolor(_map(o.get_markerfacecolor()))
            o.set_markeredgecolor(_map(o.get_markeredgecolor()))
        elif isinstance(o, Patch):
            o.set_facecolor(_map(o.get_facecolor()))
            o.set_edgecolor(_map(o.get_edgecolor()))
        elif isinstance(o, Collection):
            if getattr(o, "get_array", None) is not None and o.get_array() is not None:
                continue                                  # colour-mapped (scatter with c=, mesh): keep the colormap
            fc, ec = o.get_facecolor(), o.get_edgecolor()
            if len(fc):
                o.set_facecolor(_map_arr(fc))
            if len(ec):
                o.set_edgecolor(_map_arr(ec))
        elif isinstance(o, Text):
            o.set_color(_map(o.get_color()))
            t = o.get_text()
            if t:
                m = mathify(t)
                if m != t:
                    o.set_text(m)
            bb = o.get_bbox_patch()
            if bb is not None:
                bb.set_facecolor(_map(bb.get_facecolor()))
                bb.set_edgecolor(_map(bb.get_edgecolor()))
    for lg in fig.findobj(Legend):
        fr = lg.get_frame()
        if fr.get_visible() and lg.get_frame_on():
            fr.set_edgecolor("#b5b5b5")
            fr.set_linewidth(0.6)


def save_both(fig, path, dpi=200):
    """PNG (Markdown drafts) and vector PDF (LaTeX manuscript) with the same name"""
    fig.savefig(path, dpi=dpi)
    root, _ = os.path.splitext(path)
    fig.savefig(root + ".pdf")
