#!/usr/bin/env python3
"""Render the paper figures from matlab/results/*.csv (revised version).

Usage: python3 tools/plot_results.py [results_dir] [figure_dir] [--en]
  --en  English labels (written to <figure_dir>_en); figures are drawn once and every text is translated
        from the phrase table ZH2EN before saving, so both versions always show the same data.
Colour follows the entity (fixed categorical order of the reference palette); line/scatter charts show at
most three strategies (JR-D, IR-O*, IR-P = slots 1-3, validated all-pairs); charts with more strategies
put the strategy names on the category axis so that identity never relies on colour alone.
"""
import os, sys
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

HERE = os.path.dirname(os.path.abspath(__file__))
EN = "--en" in sys.argv
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
RES = ARGS[0] if len(ARGS) > 0 else os.path.join(HERE, "..", "matlab", "results")
FIG = ARGS[1] if len(ARGS) > 1 else os.path.join(HERE, "..", "matlab", "figures")
if EN: FIG = FIG.rstrip("/\\") + "_en"
os.makedirs(FIG, exist_ok=True)

for f in ([] if EN else ["Noto Sans CJK SC", "WenQuanYi Micro Hei", "SimHei", "Microsoft YaHei"]):
    if any(f in x.name for x in font_manager.fontManager.ttflist):
        plt.rcParams["font.sans-serif"] = [f, "DejaVu Sans"]
        break
INK, INK2, MUTED, GRID, AXIS = "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"
plt.rcParams.update({"axes.unicode_minus": False, "font.size": 9, "axes.titlesize": 10,
                     "axes.edgecolor": AXIS, "axes.linewidth": 0.8, "axes.grid": True,
                     "grid.color": GRID, "grid.linewidth": 0.6, "grid.linestyle": "-",
                     "xtick.color": INK2, "ytick.color": INK2, "axes.labelcolor": INK, "text.color": INK,
                     "legend.frameon": False, "figure.dpi": 150, "savefig.bbox": "tight", "axes.axisbelow": True,
                     "figure.facecolor": "#fcfcfb", "axes.facecolor": "#fcfcfb", "savefig.facecolor": "#fcfcfb"})

# entity -> fixed categorical slot (reference palette, light mode)
C = {"JR-D": "#2a78d6", "IR-O*": "#eb6834", "IR-P": "#1baf7a", "JR-S": "#eda100", "JR-M": "#e87ba4",
     "IR-O": "#008300", "IR-R": "#6250d6", "JR-oracle": "#e34948", "JR": "#2a78d6", "IR-O*(hindsight)": "#eb6834",
     "IR": "#eb6834", "IRJ": "#1baf7a", "bound": MUTED, "base": INK2, "cap": "#e34948", "NoDR": MUTED}
NAME = {"IR-R": "独立恢复-规则 IR-R", "IR-O": "独立恢复-固定分摊 IR-O", "IR-O*": "独立恢复-日前调优分摊 IR-O*",
        "IR-P": "独立恢复-影子价格协调 IR-P", "JR-M": "联合恢复-逐事件 JR-M", "JR-D": "联合恢复-确定性MPC JR-D（本文）",
        "JR-S": "联合恢复-场景MPC JR-S（本文）", "JR-oracle": "联合恢复-完美信息", "NoDR": "不参与DR",
        "IR-O*(hindsight)": "独立恢复-事后最优分摊 IR-O*", "JR": "联合恢复 JR（本文）"}
MK = {"JR-D": "o", "JR": "o", "IR-O*": "s", "IR-O*(hindsight)": "s", "IR-P": "^", "JR-S": "D", "JR-M": "v", "IR-O": "P", "IR-R": "X"}
EV = [(17, 18), (19, 20), (21, 22)]
FILE = {"IR-R": "IRR", "IR-O": "IRO", "IR-O*": "IROs", "IR-P": "IRP", "JR-M": "JRM", "JR-D": "JRD", "JR-S": "JRS",
        "JR-oracle": "JRoracle", "NoDR": "NoDR"}


def rd(name):
    p = os.path.join(RES, name)
    return pd.read_csv(p) if os.path.exists(p) else None


def shade(ax, ev=EV):
    for a, b in ev:
        ax.axvspan(a, b, color="#2a78d6", alpha=0.07, lw=0)


def save(fig, name):
    if EN: translate_fig(fig)
    fig.savefig(os.path.join(FIG, name)); plt.close(fig); print("wrote", name)


# Chinese -> English phrase table (longest phrases are replaced first; generic fragments last)
ZH2EN = {
    "独立恢复-规则 IR-R": "IR-R: independent, rule-based", "独立恢复-固定分摊 IR-O": "IR-O: independent, fixed split",
    "独立恢复-日前调优分摊 IR-O*": "IR-O*: independent, tuned split", "独立恢复-影子价格协调 IR-P": "IR-P: independent, price-coordinated",
    "联合恢复-逐事件 JR-M": "JR-M: joint, event-by-event", "联合恢复-确定性MPC JR-D（本文）": "JR-D: joint, deterministic MPC (proposed)",
    "联合恢复-场景MPC JR-S（本文）": "JR-S: joint, scenario MPC (proposed)", "联合恢复-完美信息": "JR: perfect information",
    "不参与DR": "No DR", "独立恢复-事后最优分摊 IR-O*": "IR-O*: independent, best split in hindsight",
    "联合恢复 JR（本文）": "JR: joint recovery (proposed)",
    "DR基线（前5个典型工作日均值）": "DR baseline (mean of 5 prior workdays)", "DR日不响应时的并网功率": "Grid import on the DR day without response",
    "并网容量上限": "Connection limit", "并网功率 / MW": "Grid import / MW", "(a) 并网功率基线": "(a) Grid import and baseline",
    "在线推理 (Flex0)": "Online inference (Flex 0)", "不可延迟训练 (Flex0)": "Non-deferrable training (Flex 0)",
    "C1 短作业 (L=0.5h)": "C1 short jobs (L = 0.5 h)", "C2 中作业 (L=1.5h)": "C2 medium jobs (L = 1.5 h)",
    "C3 长训练 (L=3h)": "C3 long training (L = 3 h)", "忙碌GPU / 千卡": "Busy GPUs / thousand",
    "(b) GPU负载构成（PAI/Azure 轨迹）": "(b) GPU load composition (PAI / Azure traces)", "分时电价 / (元/kWh)": "TOU price / (CNY/kWh)",
    "时刻 / h": "Time / h", "(c) 江苏工商业分时电价（夏季）": "(c) Jiangsu commercial TOU tariff (summer)", "光伏出力 / MW": "PV output / MW",
    "冷机系统COP": "Chiller-plant COP", "(d) 光伏出力与冷机COP（苏州吴江 2024-08-05）": "(d) PV output and chiller COP (Suzhou-Wujiang, 2024-08-05)",
    "前序 6 MW×2 h，后续 1 h": "Event A 6 MW × 2 h, event B 1 h", "前序 6 MW×1 h，后续 2 h": "Event A 6 MW × 1 h, event B 2 h",
    "联合响应+联合恢复 JR": "JR: joint response + joint recovery", "独立恢复 IR": "IR: independent recovery",
    "IR后状态+联合恢复": "IR post-event state + joint recovery", "命题1 上界": "Proposition 1 bound", "事件间隔 τ / h": "Interval τ / h",
    "后续事件可交付能力 Γ_B/Γ_B⁰": "Deliverable capability of event B, Γ_B/Γ_B⁰", "并网容量裕度 γ": "Connection margin γ",
    "（前序 6 MW×2 h）": " (event A 6 MW × 2 h)", "可交付能力比": "Capability ratio", "DR基线": "DR baseline", "并网容量": "Connection limit",
    "(a) 并网功率与基线（阴影为DR事件）": "(a) Grid import and baseline (shaded: DR events)", "电储能电量 / MWh": "Battery energy / MWh",
    "(b) 储能状态（储侧恢复状态）": "(b) Storage state (storage-side recovery state)", "积压任务 / 千GPU·h": "Backlog / 10³ GPU·h",
    "(c) 任务积压（算侧恢复状态）": "(c) Backlog (computing-side recovery state)", "积压 / 千GPU·h": "Backlog / 10³ GPU·h",
    "(a) 分类别积压：联合恢复跨事件“携带”长时限任务（实线 JR-D，点线 IR-O*）":
        "(a) Backlog by class: joint recovery carries long-lag jobs across events (solid JR-D, dotted IR-O*)",
    "BESS 放电(+)/充电(-)": "BESS discharge (+) / charge (−)", "蓄冷 放冷(+)/蓄冷(-)（电当量）": "TES discharge (+) / charge (−), electric equivalent",
    "燃气内燃机出力": "Gas engine output", "功率 / MW": "Power / MW", "(b) JR-D 综合能源设备出力": "(b) JR-D dispatch of the IES devices",
    "事件持续时间 / h": "Event duration / h", "事件间隔 / h": "Event interval / h", "响应承诺 / MW": "Commitment / MW",
    "连续响应兑现率 / %": "Fulfilment over consecutive events / %", "综合成本（期末状态折算）/ 万元": "Total cost incl. terminal-state value / 10⁴ CNY",
    "JR 相对最强独立基准的综合成本降幅": "Cost reduction of JR vs the strongest independent benchmark",
    "JR-D 相对最强独立基准的综合成本降幅": "Cost reduction of JR-D vs the strongest independent benchmark",
    "事件确定 · c_rb=3 元/kW": "events certain · c_rb = 3 CNY/kW", "事件确定 · c_rb=0": "events certain · c_rb = 0",
    "E3 不确定（p=0.6，提前1 h确认）": "E3 uncertain (p = 0.6, confirmed 1 h ahead)", "兑现率 / %": "Fulfilment / %",
    "综合成本 / 万元": "Total cost / 10⁴ CNY", "（数字为均值）": " (numbers: means)", "分时电价": "TOU price",
    "恢复通道价格 λ（γ=1.10，c_rb=3 元/kW）": "Channel price λ (γ = 1.10, c_rb = 3 CNY/kW)", "λ（γ=1.10，c_rb=0）": "λ (γ = 1.10, c_rb = 0)",
    "λ（γ=1.00，c_rb=0）": "λ (γ = 1.00, c_rb = 0)", "(a) 设施用电的边际价值（电平衡对偶）": "(a) Marginal value of facility power (dual of the power balance)",
    "电储能电量 ν": "Battery energy ν", "蓄冷量": "Chilled-water storage", "(b) 储侧状态的边际价值": "(b) Marginal value of the storage states",
    "(c) 算侧积压状态的边际成本 μ": "(c) Marginal cost of the backlog states μ", "全有效": "all valid ",
    "蒙特卡洛平均综合成本 / 万元": "Monte-Carlo mean total cost / 10⁴ CNY", "承诺—运行配对": "Commitment–operation pairing",
    "恢复期最大反弹（相对基线）/ MW": "Max rebound after events (vs baseline) / MW",
    "规则口径综合成本（不含反弹考核）/ 万元": "Total cost excl. rebound charge / 10⁴ CNY",
    "(a) 反弹—成本权衡（点旁数字为 c_rb，元/kW）": "(a) Rebound–cost trade-off (labels: c_rb, CNY/kW)",
    "反弹考核价格 c_rb / (元/kW·次)": "Rebound charge c_rb / (CNY/kW per event)", "(b) 兑现率": "(b) Fulfilment", "95% 可靠性": "95% reliability",
    "三次事件全部有效的天数占比 / %": "Days with all three events valid / %", "平均兑现率 / %": "Mean fulfilment / %",
    "平均综合成本 / 万元": "Mean total cost / 10⁴ CNY", "(a) 可靠性": "(a) Reliability", "(c) 综合成本（越低越好）": "(c) Total cost (lower is better)",
    "每次事件的统一承诺 C / MW": "Uniform commitment per event C / MW", "JR 闭式解": "JR closed form", "IR 闭式解": "IR closed form",
    "JR 线性规划": "JR LP", "IR 线性规划": "IR LP", "滞后上界 L = ": "Lag bound L = ", "事件 B 可交付削减 / MW": "Deliverable reduction in event B / MW",
    "需求响应补贴单价 / (元/kWh)": "DR payment rate / (CNY/kWh)", "偏差考核系数 κ": "Shortfall coefficient κ", "基准": "Base", "液冷": "Liquid cooling",
    "IT爬坡≤2MW/15min": "IT ramp ≤ 2 MW/15 min", "IT爬坡≤1MW/15min": "IT ramp ≤ 1 MW/15 min", "事件前抬升考核": "Pre-event load-up charge",
    "(b) 模型设定稳健性（统一 6 MW 承诺）": "(b) Robustness to model settings (uniform 6 MW)",
    "电储能能量容量 E / MWh（功率 6 MW）": "Battery energy capacity E / MWh (power 6 MW)",
    "并网裕度 γ（并网上限 = γ × 典型日峰值）": "Connection margin γ (limit = γ × typical-day peak)",
    "JR 在 ": "JR at ", " 时可靠容量 ": ": reliable capacity ", "独立恢复需 ": "independent recovery needs ",
    "独立恢复在扫描范围内达不到": "independent recovery does not reach it in the sweep",
    "≥99% 兑现且三次全有效的最大承诺 / MW": "Max commitment with ≥99% fulfilment, all valid / MW", "可靠可交付容量": "Reliably deliverable capacity",
    "物理储能能量（电池）": "Physical storage energy (battery)", "联合恢复调用的算力虚拟储能（E2 前积压）": "Virtual computing storage used by JR (backlog before E2)",
    "电储能能量容量 E / MWh": "Battery energy capacity E / MWh", "MWh（下方为虚拟储能）": "MWh (below zero: virtual storage)",
    "(c) 物理—虚拟储能镜像（JR，可靠容量处）": "(c) Physical vs virtual storage (JR at its reliable capacity)",
    "帕累托前沿（JR-D 运行）": "Pareto front (operated by JR-D)", "膝点：": "Knee: ", "样本外平均综合成本 / 万元": "Out-of-sample mean total cost / 10⁴ CNY",
    "样本外最差 10% 日平均成本（CVaR$_{0.9}$）/ 万元": "Out-of-sample mean of worst 10% days (CVaR$_{0.9}$) / 10⁴ CNY",
    "(a) 风险—期望权衡（52 个运行日）": "(a) Risk–expectation trade-off (52 operating days)",
    "模糊集半径 δ（0 = 随机规划，2 = 场景鲁棒）": "Ambiguity radius δ (0 = SP, 2 = scenario-robust)", "日前承诺 / MW": "Day-ahead commitment / MW",
    "(b) 承诺随保守度的变化": "(b) Commitments vs conservativeness", "能量（购电+燃气+退化）": "Energy (grid + gas + degradation)",
    "需求响应补贴": "DR payment", "短缺考核": "Shortfall penalty", "反弹考核": "Rebound charge", "任务延迟": "Job delay", "期末状态折算": "Terminal-state value",
    "事件确定，c_rb=3": "events certain, c_rb = 3", "事件确定，c_rb=0": "events certain, c_rb = 0", "E3 不确定": "E3 uncertain",
    "（对 ": " (vs ", "，合计 ": ", total ", " 万元/日）": " 10⁴ CNY/day)",
    "JR-D 相对较强调优基准的日均节省 / 万元（>0 有利于 JR-D）": "Daily saving of JR-D vs the stronger tuned benchmark / 10⁴ CNY (>0 favours JR-D)",
    "(a) 收益来源拆解（蒙特卡洛均值）": "(a) Sources of the saving (Monte-Carlo means)", "规则独立恢复": "Rule-based\nindependent",
    "+各侧优化": "+ each side\noptimised", "+日前调优分摊": "+ tuned split", "+通道价格协调": "+ channel-price\ncoordination",
    "+联合分配通道\n（逐事件）": "+ joint channel\nallocation (myopic)", "+跨事件远见\n（本文）": "+ cross-event\nforesight (proposed)",
    "+场景对冲\n（E3 不确定时）": "+ scenario hedging\n(E3 uncertain)",
    "(b) 机理贡献瀑布（蓝：降低成本，红：增加成本）": "(b) Mechanism waterfall (blue: cost down, red: cost up)",
    "规则独立恢复\n(IR-R)": "Rule-based\nindependent\n(IR-R)", "+各侧优化\n(IR-O)": "+ each side\noptimised\n(IR-O)",
    "+日前调优\n分摊 (IR-O*)": "+ tuned\nsplit\n(IR-O*)", "+通道价格\n协调 (IR-P)": "+ channel\nprice\n(IR-P)",
    "+联合分配\n通道 (JR-M)": "+ joint\nallocation\n(JR-M)", "+跨事件远见\n(JR-D)": "+ cross-event\nforesight\n(JR-D)",
    "+场景对冲\n(JR-S，E3 不确定)": "+ scenario\nhedging\n(JR-S)", "合计": "Total",
    "相对 IR-R 的日均成本变化 / 万元": "Change of daily mean cost vs IR-R / 10⁴ CNY",
    "可靠容量处": "at reliable capacity", "独立恢复": "Independent recovery", "联合恢复": "Joint recovery",
    # generic fragments
    "万元": "10⁴ CNY", "元/MWh": "CNY/MWh", "元/(GPU·h)": "CNY/(GPU·h)", "元/kWh": "CNY/kWh", "元/kW": "CNY/kW", "本文": "proposed",
    "积压": "backlog", "承诺": "commitment", "（": " (", "）": ")", "，": ", ", "：": ": ", "；": "; ",
}
_ZH_KEYS = sorted(ZH2EN, key=len, reverse=True)


def tr(text):
    for k in _ZH_KEYS:
        if k in text: text = text.replace(k, ZH2EN[k])
    return text


def translate_fig(fig):
    import functools
    from matplotlib.text import Text
    from matplotlib.ticker import FixedFormatter, FuncFormatter
    for t in fig.findobj(match=Text):
        if t.get_text(): t.set_text(tr(t.get_text()))
    for ax in fig.axes:                           # fixed tick labels are regenerated from the formatter at draw time
        for axis in (ax.xaxis, ax.yaxis):
            fm = axis.get_major_formatter()
            if isinstance(fm, FixedFormatter):
                axis.set_major_formatter(FixedFormatter([tr(str(x)) for x in fm.seq]))
            elif isinstance(fm, FuncFormatter) and isinstance(getattr(fm, "func", None), functools.partial) \
                    and fm.func.args and isinstance(fm.func.args[0], dict):
                d = {k: tr(str(v)) for k, v in fm.func.args[0].items()}
                axis.set_major_formatter(FuncFormatter(functools.partial(fm.func.func, d)))
    left = {t.get_text() for t in fig.findobj(match=Text) if any("\u4e00" <= ch <= "\u9fff" for ch in t.get_text())}
    if left: print("  untranslated:", sorted(left))


def end_label(ax, x, y, text, color):
    ax.annotate(text, (x, y), xytext=(4, 0), textcoords="offset points", va="center", fontsize=7, color=INK2)


# ---------------------------------------------------------------- fig01 case data
def fig_case():
    d = rd("case_profiles.csv")
    if d is None: return
    h = d.hour
    fig, ax = plt.subplots(2, 2, figsize=(9, 5.4), sharex=True)
    a = ax[0, 0]; shade(a)
    a.plot(h, d.baseline, color=C["base"], lw=2, label="DR基线（前5个典型工作日均值）")
    a.plot(h, d.pg_noDR, color=C["JR-D"], lw=1.5, label="DR日不响应时的并网功率")
    t = rd("ts_uniform6_JRD.csv")
    if t is not None: a.axhline(t.Pcap.iloc[0], color=C["cap"], lw=1, label="并网容量上限")
    a.set_ylabel("并网功率 / MW"); a.set_title("(a) 并网功率基线"); a.legend(fontsize=7, loc="lower left")
    a = ax[0, 1]
    st = [d.gpu_inf, d.gpu_flex0, d.gpu_c1, d.gpu_c2, d.gpu_c3]
    lab = ["在线推理 (Flex0)", "不可延迟训练 (Flex0)", "C1 短作业 (L=0.5h)", "C2 中作业 (L=1.5h)", "C3 长训练 (L=3h)"]
    col = ["#898781", "#c3c2b7", "#1baf7a", "#eb6834", "#2a78d6"]
    a.stackplot(h, *[s / 1000 for s in st], labels=lab, colors=col, lw=0.4, edgecolor="#fcfcfb")
    a.set_ylabel("忙碌GPU / 千卡"); a.set_title("(b) GPU负载构成（PAI/Azure 轨迹）"); a.legend(fontsize=6.5, loc="upper left", ncol=2)
    a = ax[1, 0]
    a.step(h, d.price / 1000, where="post", color=C["base"], lw=2)
    a.set_ylabel("分时电价 / (元/kWh)"); a.set_xlabel("时刻 / h"); a.set_title("(c) 江苏工商业分时电价（夏季）"); shade(a)
    a = ax[1, 1]
    a.plot(h, d.pv, color=C["JR-S"], lw=2, label="光伏出力 / MW")
    a.plot(h, d.cop, color=C["IR-O*"], lw=2, label="冷机系统COP")
    a.set_xlabel("时刻 / h"); a.set_title("(d) 光伏出力与冷机COP（苏州吴江 2024-08-05）"); a.legend(fontsize=7)
    for x in ax.flat: x.set_xlim(0, 30); x.set_xticks(range(0, 31, 3))
    save(fig, "fig01_case_profiles.png")


# ---------------------------------------------------------------- fig02 mechanism
def fig_mechanism():
    files = [("exp1_mechanism_CA6_DA2.csv", "前序 6 MW×2 h，后续 1 h"), ("exp1_mechanism_CA6_DA1_DB2.csv", "前序 6 MW×1 h，后续 2 h")]
    data = [(rd(f), t) for f, t in files]
    if any(x is None for x, _ in data): return
    fig, ax = plt.subplots(2, 2, figsize=(9.5, 7.4)); fig.subplots_adjust(hspace=0.42, wspace=0.32)
    for j, (d, t) in enumerate(data):
        a = ax[0, j]; g = d[np.isclose(d.gamma, 1.10)]
        for key, col, lab in [("G_JR", C["JR"], "联合响应+联合恢复 JR"), ("G_IR", C["IR"], "独立恢复 IR"), ("G_IRJ", C["IRJ"], "IR后状态+联合恢复")]:
            a.plot(g.tau_h, g[key] / g.G0, color=col, lw=2, marker="o", ms=4, label=lab)
        a.plot(g.tau_h, g.G_bound / g.G0, color=C["bound"], lw=1.2, ls="--", label="命题1 上界")
        a.set_ylim(0, 1.08); a.set_xlabel("事件间隔 τ / h"); a.set_ylabel("后续事件可交付能力 Γ_B/Γ_B⁰")
        a.set_title(f"({'ab'[j]}) {t}，γ=1.10"); a.legend(fontsize=7, loc="lower right")
    d = data[0][0]
    taus = sorted(d.tau_h.unique()); gams = sorted(d.gamma.unique())
    for j, (key, lab) in enumerate([("G_IR", "独立恢复"), ("G_JR", "联合恢复")]):
        Z = np.array([[float((d[(d.gamma == g) & (d.tau_h == t)][key] / d[(d.gamma == g) & (d.tau_h == t)].G0).iloc[0]) for t in taus] for g in gams])
        a = ax[1, j]; im = a.imshow(Z, origin="lower", aspect="auto", cmap="Blues", vmin=0.2, vmax=1.0)
        a.set_xticks(range(len(taus))); a.set_xticklabels([f"{t:g}" for t in taus]); a.set_yticks(range(len(gams))); a.set_yticklabels([f"{g:.2f}" for g in gams])
        for i in range(len(gams)):
            for k in range(len(taus)):
                a.text(k, i, f"{Z[i,k]:.2f}", ha="center", va="center", fontsize=6.5, color="white" if Z[i, k] > 0.65 else INK)
        a.set_xlabel("事件间隔 τ / h"); a.set_ylabel("并网容量裕度 γ"); a.set_title(f"({'cd'[j]}) {lab}：Γ_B/Γ_B⁰（前序 6 MW×2 h）"); a.grid(False)
    fig.colorbar(im, ax=ax[1, :], shrink=0.8, label="可交付能力比")
    save(fig, "fig02_mechanism.png")


# ---------------------------------------------------------------- fig03/04 time series
def fig_timeseries(case="DAcommit", tag=""):
    S = ["IR-O*", "IR-P", "JR-D"]
    D = {s: rd(f"ts_{case}_{FILE[s]}{tag}.csv") for s in S}
    if any(v is None for v in D.values()): return
    fig, ax = plt.subplots(3, 1, figsize=(8.5, 7.2), sharex=True)
    a = ax[0]; shade(a); b = D["JR-D"]
    a.plot(b.hour, b.base, color=C["base"], lw=1.5, ls="--", label="DR基线")
    a.axhline(b.Pcap.iloc[0], color=C["cap"], lw=1, label="并网容量")
    for s in S: a.plot(D[s].hour, D[s].pg, color=C[s], lw=1.8, label=NAME[s])
    a.set_ylabel("并网功率 / MW"); a.legend(fontsize=7, ncol=2, loc="lower left"); a.set_title("(a) 并网功率与基线（阴影为DR事件）")
    a = ax[1]; shade(a)
    for s in S: a.plot(D[s].hour, D[s].E, color=C[s], lw=1.8, label=NAME[s])
    a.set_ylabel("电储能电量 / MWh"); a.set_title("(b) 储能状态（储侧恢复状态）")
    a = ax[2]; shade(a)
    for s in S: a.plot(D[s].hour, (D[s].B1 + D[s].B2 + D[s].B3) / 1000, color=C[s], lw=1.8, label=NAME[s])
    a.set_ylabel("积压任务 / 千GPU·h"); a.set_xlabel("时刻 / h"); a.set_title("(c) 任务积压（算侧恢复状态）")
    for x in ax: x.set_xlim(12, 30); x.set_xticks(range(12, 31, 2))
    save(fig, f"fig03_timeseries_{case}{tag}.png")
    fig, ax = plt.subplots(2, 1, figsize=(8.5, 5), sharex=True)
    j = D["JR-D"]; o = D["IR-O*"]
    a = ax[0]; shade(a)
    for k, col in zip([1, 2, 3], ["#1baf7a", "#eb6834", "#2a78d6"]):
        a.plot(j.hour, j[f"B{k}"] / 1000, color=col, lw=2, label=f"JR-D C{k}")
        a.plot(o.hour, o[f"B{k}"] / 1000, color=col, lw=1, alpha=0.7, ls=":", label=f"IR-O* C{k}")
    a.set_ylabel("积压 / 千GPU·h"); a.legend(fontsize=7, ncol=3); a.set_title("(a) 分类别积压：联合恢复跨事件“携带”长时限任务（实线 JR-D，点线 IR-O*）")
    a = ax[1]; shade(a)
    a.plot(j.hour, j.pdis - j.pch, color=C["JR-D"], lw=2, label="BESS 放电(+)/充电(-)")
    a.plot(j.hour, (j.qtd - j.qtc) / 4.5, color=C["IR-P"], lw=2, label="蓄冷 放冷(+)/蓄冷(-)（电当量）")
    a.plot(j.hour, j.pgt, color=C["JR-S"], lw=2, label="燃气内燃机出力")
    a.set_ylabel("功率 / MW"); a.set_xlabel("时刻 / h"); a.legend(fontsize=7, ncol=3); a.set_title("(b) JR-D 综合能源设备出力")
    for x in ax: x.set_xlim(12, 30); x.set_xticks(range(12, 31, 2))
    save(fig, f"fig04_backlog_ies_{case}{tag}.png")


# ---------------------------------------------------------------- fig05/06 sensitivity
SENS = {3: "IR-O*(hindsight)", 4: "IR-P", 5: "JR"}


def fig_sensitivity(tag=""):
    files = [(f"exp3_duration{tag}.csv", "事件持续时间 / h"), (f"exp3_interval{tag}.csv", "事件间隔 / h"),
             (f"exp3_gamma{tag}.csv", "并网容量裕度 γ"), (f"exp3_commitment{tag}.csv", "响应承诺 / MW")]
    data = [(rd(f), l) for f, l in files]
    if any(d is None for d, _ in data): return
    fig, ax = plt.subplots(2, 4, figsize=(12, 5.2)); fig.subplots_adjust(wspace=0.3, hspace=0.3)
    for j, (d, lab) in enumerate(data):
        for i, s in SENS.items():
            q = d[d.strategy == i]
            ax[0, j].plot(q.x, q.fulfil_rate_pct, color=C[s], lw=2, marker=MK[s], ms=5, mec="#fcfcfb", mew=0.8, label=NAME[s])
            ax[1, j].plot(q.x, q.net_cost_adj / 1e4, color=C[s], lw=2, marker=MK[s], ms=5, mec="#fcfcfb", mew=0.8, label=NAME[s])
        ax[0, j].set_ylim(40, 103); ax[0, j].set_title(f"({'abcd'[j]}) {lab}")
        ax[1, j].set_xlabel(lab)
    ax[0, 0].set_ylabel("连续响应兑现率 / %"); ax[1, 0].set_ylabel("综合成本（期末状态折算）/ 万元")
    ax[0, 0].legend(fontsize=7, loc="lower left")
    save(fig, f"fig05_sensitivity{tag}.png")


def fig_map():
    out = []
    for tag, lab in [("", "c_rb=3 元/kW"), ("_crb0", "c_rb=0")]:
        d = rd(f"exp3_map{tag}.csv")
        if d is not None: out.append((d, lab))
    if not out: return
    fig, ax = plt.subplots(1, len(out), figsize=(5.4 * len(out), 3.6), squeeze=False); fig.subplots_adjust(wspace=0.45)
    for j, (d, lab) in enumerate(out):
        taus = sorted(d.x.unique()); gams = sorted(d.gamma.unique())
        def get(g, t, s):
            return float(d[(d.gamma == g) & (d.x == t) & (d.strategy == s)].net_cost_adj.iloc[0])
        Z = np.array([[100 * (min(get(g, t, 3), get(g, t, 4)) - get(g, t, 5)) / min(get(g, t, 3), get(g, t, 4)) for t in taus] for g in gams])
        a = ax[0, j]; im = a.imshow(np.maximum(Z, 0), origin="lower", aspect="auto", cmap="Blues", vmin=0, vmax=max(Z.max(), 1))
        a.set_xticks(range(len(taus))); a.set_xticklabels([f"{t:g}" for t in taus]); a.set_yticks(range(len(gams))); a.set_yticklabels([f"{g:.2f}" for g in gams])
        for i in range(len(gams)):
            for k in range(len(taus)):
                a.text(k, i, f"{Z[i,k]:.1f}", ha="center", va="center", fontsize=7, color="white" if Z[i, k] > 0.6 * Z.max() else INK)
        a.set_xlabel("事件间隔 τ / h"); a.set_ylabel("并网容量裕度 γ"); a.grid(False)
        a.set_title(f"({'ab'[j]}) JR 相对最强独立基准的综合成本降幅，{lab}")
        fig.colorbar(im, ax=a, label="%")
    save(fig, "fig06_interval_capacity_map.png")


# ---------------------------------------------------------------- fig07 Monte Carlo
def fig_mc():
    sets = [("_certain", "事件确定 · c_rb=3 元/kW"), ("_certain_crb0", "事件确定 · c_rb=0"), ("_e3uncertain", "E3 不确定（p=0.6，提前1 h确认）")]
    rows = [(rd(f"exp4{t}.csv"), rd(f"exp4{t}_strategies.csv"), lab) for t, lab in sets]
    rows = [r for r in rows if r[0] is not None and r[1] is not None]
    if not rows: return
    fig, ax = plt.subplots(len(rows), 2, figsize=(11, 3.2 * len(rows)), squeeze=False); fig.subplots_adjust(hspace=0.5, wspace=0.2)
    for i, (d, s, lab) in enumerate(rows):
        names = list(s["label"])
        for j, (col, ylab, sc) in enumerate([("fulfil_rate_pct", "兑现率 / %", 1), ("net_cost_adj", "综合成本 / 万元", 1e4)]):
            a = ax[i, j]
            vals = [d[d.strategy == k + 1][col].values / sc for k in range(len(names))]
            bp = a.boxplot(vals, widths=0.5, patch_artist=True, showfliers=False)
            for k, b in enumerate(bp["boxes"]):
                b.set_facecolor(C[names[k]] + "33"); b.set_edgecolor(C[names[k]])
            for k, m in enumerate(bp["medians"]): m.set_color(C[names[k]]); m.set_linewidth(2)
            for k, v in enumerate(vals):
                a.scatter(np.full(len(v), k + 1) + np.linspace(-0.15, 0.15, len(v)), v, s=8, color=C[names[k]], zorder=3, edgecolor="#fcfcfb", linewidth=0.5)
                a.text(k + 1, np.nanmax(v), f"{np.nanmean(v):.1f}", ha="center", va="bottom", fontsize=7, color=INK2)
            a.set_xticks(range(1, len(names) + 1)); a.set_xticklabels(names)
            a.set_title(f"({'abcdef'[2 * i + j]}) {lab}（数字为均值）"); a.set_ylabel(ylab)
    save(fig, "fig07_montecarlo.png")


# ---------------------------------------------------------------- fig08 shadow prices
def fig_shadow():
    d = rd("exp5_shadow.csv"); z = rd("exp5_shadow_crb0.csv"); g = rd("exp5_shadow_gamma100_crb0.csv")
    if d is None: return
    fig, ax = plt.subplots(3, 1, figsize=(8.5, 6.8), sharex=True)
    for a in ax: shade(a)
    ax[0].step(d.hour, d.price, where="post", color=C["base"], lw=1, ls="--", label="分时电价")
    ax[0].plot(d.hour, d.lambda_el, color=C["JR-D"], lw=2, label="恢复通道价格 λ（γ=1.10，c_rb=3 元/kW）")
    if z is not None: ax[0].plot(z.hour, z.lambda_el, color=C["IR-O*"], lw=1.5, label="λ（γ=1.10，c_rb=0）")
    if g is not None: ax[0].plot(g.hour, g.lambda_el, color=C["IR-P"], lw=1.5, label="λ（γ=1.00，c_rb=0）")
    ax[0].set_ylabel("元/MWh"); ax[0].legend(fontsize=7, loc="upper left"); ax[0].set_title("(a) 设施用电的边际价值（电平衡对偶）")
    ax[0].set_ylim(0, max(2500, float(np.nanpercentile(d.lambda_el, 97)) * 1.1))
    ax[1].plot(d.hour, d.value_E, color=C["JR-D"], lw=2, label="电储能电量 ν")
    ax[1].plot(d.hour, d.value_S, color=C["IR-P"], lw=2, label="蓄冷量")
    ax[1].set_ylabel("元/MWh"); ax[1].legend(fontsize=7); ax[1].set_title("(b) 储侧状态的边际价值")
    for k, col in zip([1, 2, 3], ["#1baf7a", "#eb6834", "#2a78d6"]):
        ax[2].plot(d.hour, d[f"cost_B{k}"], color=col, lw=2, label=f"C{k} 积压（L={[0.5,1.5,3][k-1]} h）")
    ax[2].set_ylabel("元/(GPU·h)"); ax[2].set_xlabel("时刻 / h"); ax[2].legend(fontsize=7); ax[2].set_title("(c) 算侧积压状态的边际成本 μ")
    for a in ax: a.set_xlim(12, 30); a.set_xticks(range(12, 31, 2))
    save(fig, "fig08_shadow_prices.png")


# ---------------------------------------------------------------- fig09 commitment pairing
def fig_commit():
    out = [(rd(f"exp6_commitment{t}.csv"), lab) for t, lab in [("", "c_rb=3 元/kW"), ("_crb0", "c_rb=0")]]
    out = [o for o in out if o[0] is not None]
    if not out: return
    fig, ax = plt.subplots(1, len(out), figsize=(5.6 * len(out), 3.6), squeeze=False); fig.subplots_adjust(wspace=0.3)
    for j, (d, lab) in enumerate(out):
        a = ax[0, j]
        packs = list(dict.fromkeys(l.split("|")[0] for l in d.label))
        ops = ["IR-O*", "JR-D"]; w = 0.36; x = np.arange(len(packs))
        for i, op in enumerate(ops):
            v = [float(d[d.label == f"{p}|{op}"].mc_net_cost_adj.iloc[0]) / 1e4 for p in packs]
            sh = [float(d[d.label == f"{p}|{op}"].mc_share_all_valid.iloc[0]) for p in packs]
            bars = a.bar(x + (i - 0.5) * (w + 0.02), v, w, color=C[op], label=NAME[op], edgecolor="#fcfcfb", linewidth=2)
            for xx, vv, ss in zip(x + (i - 0.5) * (w + 0.02), v, sh):
                a.text(xx, vv + 0.2, f"{vv:.1f}\n全有效{100*ss:.0f}%", ha="center", va="bottom", fontsize=6.5, color=INK2)
        tick = []
        for p in packs:
            r = d[d.label == f"{p}|JR-D"].iloc[0]
            tick.append(f"{p}\n[{r.C1:.1f}/{r.C2:.1f}/{r.C3:.1f}] MW")
        a.set_xticks(x); a.set_xticklabels(tick, fontsize=7); a.set_ylabel("蒙特卡洛平均综合成本 / 万元")
        a.set_ylim(0, a.get_ylim()[1] * 1.15); a.set_title(f"({'ab'[j]}) 承诺—运行配对，{lab}"); a.legend(fontsize=7, loc="lower right")
    save(fig, "fig09_commitment.png")


# ---------------------------------------------------------------- fig10 rebound policy
def fig_pareto():
    d = rd("exp8_rebound.csv"); s = rd("exp8_strategies.csv")
    if d is None or s is None: return
    names = dict(zip(s["index"], s["label"])); d["name"] = d.strategy.map(names)
    fig, ax = plt.subplots(1, 2, figsize=(10.5, 3.8)); fig.subplots_adjust(wspace=0.3)
    for nm in ["IR-O*", "IR-P", "JR-D"]:
        q = d[d.name == nm].sort_values("c_rb")
        ax[0].plot(q.max_rebound_MW, q.net_cost_excl_rb / 1e4, color=C[nm], lw=1.5, marker=MK[nm], ms=6, mec="#fcfcfb", mew=0.8, label=NAME[nm])
        for _, r in q.iterrows():
            if r.c_rb in (0, 3000, 6000):
                ax[0].annotate(f"{r.c_rb/1000:g}", (r.max_rebound_MW, r.net_cost_excl_rb / 1e4), xytext=(4, 3), textcoords="offset points", fontsize=7, color=INK2)
        ax[1].plot(q.c_rb / 1000, q.fulfil_rate_pct, color=C[nm], lw=2, marker=MK[nm], ms=6, mec="#fcfcfb", mew=0.8, label=NAME[nm])
    ax[0].set_xlabel("恢复期最大反弹（相对基线）/ MW"); ax[0].set_ylabel("规则口径综合成本（不含反弹考核）/ 万元")
    ax[0].set_title("(a) 反弹—成本权衡（点旁数字为 c_rb，元/kW）"); ax[0].legend(fontsize=7)
    ax[1].set_xlabel("反弹考核价格 c_rb / (元/kW·次)"); ax[1].set_ylabel("连续响应兑现率 / %"); ax[1].set_title("(b) 兑现率"); ax[1].set_ylim(80, 101.5); ax[1].legend(fontsize=7, loc="lower right")
    save(fig, "fig10_rebound_pareto.png")


# ---------------------------------------------------------------- fig11 capacity
def fig_capacity():
    d = rd("exp12_capacity_crb0.csv"); s = rd("exp12_strategies_crb0.csv")
    if d is None or s is None: return
    names = dict(zip(s["index"], s["label"])); d["name"] = d.strategy.map(names)
    g = d.groupby(["C", "name"]).agg(av=("all_valid", "mean"), f=("fulfil_rate_pct", "mean"), net=("net_cost_adj", "mean")).reset_index()
    fig, ax = plt.subplots(1, 3, figsize=(12, 3.6)); fig.subplots_adjust(wspace=0.3)
    for nm in s["label"]:
        q = g[g.name == nm]
        kw = dict(color=C[nm], lw=2, marker=MK[nm], ms=6, mec="#fcfcfb", mew=0.8, label=NAME[nm])
        ax[0].plot(q.C, 100 * q.av, **kw); ax[1].plot(q.C, q.f, **kw); ax[2].plot(q.C, q.net / 1e4, **kw)
    ax[0].axhline(95, color=MUTED, lw=1, ls="--"); ax[0].text(ax[0].get_xlim()[0], 96, "95% 可靠性", fontsize=7, color=INK2)
    ax[0].set_ylabel("三次事件全部有效的天数占比 / %"); ax[1].set_ylabel("平均兑现率 / %"); ax[2].set_ylabel("平均综合成本 / 万元")
    for a, t in zip(ax, ["(a) 可靠性", "(b) 兑现率", "(c) 综合成本（越低越好）"]):
        a.set_xlabel("每次事件的统一承诺 C / MW"); a.set_title(t)
    ax[0].legend(fontsize=7, loc="lower left")
    save(fig, "fig11_capacity.png")


# ---------------------------------------------------------------- fig12 stylised theorem
def fig_stylized():
    d = rd("exp11_stylized.csv")
    if d is None: return
    Ls = sorted(d.L_h.unique())
    fig, ax = plt.subplots(1, len(Ls), figsize=(3.0 * len(Ls), 3.0), sharey=True); fig.subplots_adjust(wspace=0.08)
    for a, L in zip(np.atleast_1d(ax), Ls):
        q = d[d.L_h == L]
        a.plot(q.tau_h, q.G_JR_closed, color=C["JR"], lw=2, label="JR 闭式解")
        a.plot(q.tau_h, q.G_IR_closed, color=C["IR"], lw=2, label="IR 闭式解")
        a.scatter(q.tau_h, q.G_JR_lp, s=14, color=C["JR"], marker="o", edgecolor="#fcfcfb", linewidth=0.6, zorder=3, label="JR 线性规划")
        a.scatter(q.tau_h, q.G_IR_lp, s=14, color=C["IR"], marker="s", edgecolor="#fcfcfb", linewidth=0.6, zorder=3, label="IR 线性规划")
        a.set_title(f"滞后上界 L = {L:g} h"); a.set_xlabel("事件间隔 τ / h")
    np.atleast_1d(ax)[0].set_ylabel("事件 B 可交付削减 / MW"); np.atleast_1d(ax)[0].legend(fontsize=7, loc="lower right")
    save(fig, "fig12_stylized_theorem.png")


# ---------------------------------------------------------------- fig13 robustness
def fig_robust():
    d = rd("exp9_price.csv"); s = rd("exp9_strategies.csv"); r = rd("exp10_realism.csv")
    if d is None or s is None: return
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"])))
    fig, ax = plt.subplots(1, 2, figsize=(11, 3.8)); fig.subplots_adjust(wspace=0.35)
    prices = sorted(d.price.unique()); kap = sorted(d.kappa.unique())
    Z = np.zeros((len(kap), len(prices)))
    for i, k in enumerate(kap):
        for j, p in enumerate(prices):
            q = d[(d.price == p) & (d.kappa == k)].set_index("name").net_cost_adj
            best = min(q.get("IR-O*", np.inf), q.get("IR-P", np.inf))
            Z[i, j] = 100 * (q["JR-D"] - best) / abs(best)
    a = ax[0]; im = a.imshow(-Z, origin="lower", aspect="auto", cmap="Blues", vmin=0)
    for i in range(len(kap)):
        for j in range(len(prices)):
            a.text(j, i, f"{-Z[i,j]:.1f}%", ha="center", va="center", fontsize=8, color="white" if -Z[i, j] > 0.6 * (-Z).max() else INK)
    a.set_xticks(range(len(prices))); a.set_xticklabels([f"{p/1000:g}" for p in prices]); a.set_yticks(range(len(kap))); a.set_yticklabels([f"{k:g}" for k in kap])
    a.set_xlabel("需求响应补贴单价 / (元/kWh)"); a.set_ylabel("偏差考核系数 κ"); a.grid(False)
    a.set_title("(a) JR-D 相对最强独立基准的综合成本降幅"); fig.colorbar(im, ax=a, label="%")
    if r is not None:
        r["cfg"] = r.label.str.split("|").str[0]; r["nm"] = r.label.str.split("|").str[1]
        cfgs = list(dict.fromkeys(r.cfg)); x = np.arange(len(cfgs)); w = 0.26
        lab = {"base": "基准", "liquid_cooling": "液冷", "it_ramp_2MW": "IT爬坡≤2MW/15min", "it_ramp_1MW": "IT爬坡≤1MW/15min", "preload_charge": "事件前抬升考核"}
        for i, nm in enumerate(["IR-O*", "IR-P", "JR-D"]):
            v = [float(r[(r.cfg == c) & (r.nm == nm)].net_cost_adj.iloc[0]) / 1e4 for c in cfgs]
            ax[1].bar(x + (i - 1) * (w + 0.02), v, w, color=C[nm], label=NAME[nm], edgecolor="#fcfcfb", linewidth=2)
        ax[1].set_xticks(x); ax[1].set_xticklabels([lab.get(c, c) for c in cfgs], fontsize=7)
        ax[1].set_ylabel("综合成本 / 万元"); ax[1].set_title("(b) 模型设定稳健性（统一 6 MW 承诺）"); ax[1].legend(fontsize=7, loc="lower right")
    save(fig, "fig13_robustness.png")


# ---------------------------------------------------------------- fig14 virtual-physical substitution
def rel_cap(q, thr=99.0):
    """largest uniform commitment delivered at >= thr % with all three events valid"""
    ok = q[(q.fulfil_rate_pct >= thr - 1e-6) & (q.n_valid == 3)]
    return float(ok.C.max()) if len(ok) else np.nan


def fig_substitution():
    d = rd("exp13_substitution.csv"); s = rd("exp13_strategies.csv")
    if d is None or s is None: return
    names = dict(zip(s["index"], s["label"])); d["name"] = d.strategy.map(names)
    order = ["JR", "IR-O*", "IR-P"]
    fig, ax = plt.subplots(1, 3, figsize=(13, 3.8)); fig.subplots_adjust(wspace=0.32)
    for j, (sw, xl) in enumerate([(1, "电储能能量容量 E / MWh（功率 6 MW）"), (2, "并网裕度 γ（并网上限 = γ × 典型日峰值）")]):
        a = ax[j]; q = d[d.sweep == sw]; vals = sorted(q.value.unique())
        caps = {}
        for nm in order:
            caps[nm] = [rel_cap(q[(q.value == v) & (q.name == nm)]) for v in vals]
            nmk = "IR-O*(hindsight)" if nm == "IR-O*" else nm
            a.plot(vals, caps[nm], color=C[nm], lw=2, marker=MK[nm], ms=6, mec="#fcfcfb", mew=0.8, label=NAME[nmk])
        # substitution: physical capacity the best independent strategy needs to match JR at the base case
        base = 12 if sw == 1 else 1.10
        if base in vals:
            target = caps["JR"][vals.index(base)]
            best = [max(a_, b_) for a_, b_ in zip(caps["IR-O*"], caps["IR-P"])]
            need = next((v for v, b_ in zip(vals, best) if b_ >= target - 1e-9), None)
            a.axhline(target, color=MUTED, lw=1, ls="--")
            txt = (f"JR 在 {base:g}{' MWh' if sw == 1 else ''} 时可靠容量 {target:g} MW；"
                   + (f"独立恢复需 {need:g}{' MWh' if sw == 1 else ''}" if need is not None else "独立恢复在扫描范围内达不到"))
            a.text(0.02, 0.97, txt, transform=a.transAxes, fontsize=7, color=INK2, va="top")
        a.set_xlabel(xl); a.set_ylabel("≥99% 兑现且三次全有效的最大承诺 / MW")
        a.set_title(f"({'ab'[j]}) 可靠可交付容量"); a.legend(fontsize=7, loc="lower right")
    # (c) mirror: physical battery energy above, virtual storage (backlog energy carried into E2) below
    a = ax[2]; q = d[(d.sweep == 1) & (d.name == "JR")]; vals = sorted(q.value.unique())
    virt = []
    for v in vals:
        cap = rel_cap(q[q.value == v]); r = q[(q.value == v) & (q.C == cap)]
        virt.append(float(r.virtual_E2_MWh.iloc[0]) if len(r) else np.nan)
    x = np.arange(len(vals))
    a.bar(x, vals, 0.6, color="#86b6ef", edgecolor="#fcfcfb", linewidth=2, label="物理储能能量（电池）")
    a.bar(x, -np.array(virt), 0.6, color=C["JR-D"], edgecolor="#fcfcfb", linewidth=2, label="联合恢复调用的算力虚拟储能（E2 前积压）")
    for xx, v, w in zip(x, vals, virt):
        a.text(xx, v + 0.3, f"{v:g}", ha="center", va="bottom", fontsize=7, color=INK2)
        if np.isfinite(w): a.text(xx, -w - 0.3, f"{w:.1f}", ha="center", va="top", fontsize=7, color=INK2)
    a.axhline(0, color=AXIS, lw=0.8); a.set_xticks(x); a.set_xticklabels([f"{v:g}" for v in vals])
    a.set_xlabel("电储能能量容量 E / MWh"); a.set_ylabel("MWh（下方为虚拟储能）")
    lim = max(max(vals), np.nanmax(virt) if len(virt) else 0) * 1.25; a.set_ylim(-lim, lim)
    a.set_title("(c) 物理—虚拟储能镜像（JR，可靠容量处）"); a.legend(fontsize=7, loc="upper left")
    save(fig, "fig14_substitution.png")


# ---------------------------------------------------------------- fig15 risk-averse commitment (Pareto)
def fig_risk():
    c = rd("exp15_commit.csv"); s = rd("exp15_settings.csv"); o = rd("exp15_oos.csv")
    if c is None or s is None or o is None: return
    lab = dict(zip(s["index"], s["label"]))
    g = o.groupby("setting").net_cost_adj
    mean = g.mean(); cvar = g.apply(lambda v: np.sort(v.values)[::-1][:max(1, int(round(0.1 * len(v))))].mean())
    allv = o.groupby("setting").all_valid.mean()
    pts = pd.DataFrame({"mean": mean / 1e4, "cvar": cvar / 1e4, "allv": 100 * allv}).reset_index()
    pts["label"] = pts.setting.map(lab)
    fig, ax = plt.subplots(1, 2, figsize=(11, 3.9)); fig.subplots_adjust(wspace=0.3)
    a = ax[0]
    # Pareto set (minimise both) and knee = point closest to the utopia point after normalisation
    P = pts.sort_values("mean"); front = []; best = np.inf
    for _, r in P.iterrows():
        if r.cvar < best - 1e-9: front.append(r); best = r.cvar
    F = pd.DataFrame(front)
    a.scatter(pts["mean"], pts["cvar"], s=40, color=AXIS, edgecolor="#fcfcfb", linewidth=1, zorder=2)
    a.plot(F["mean"], F["cvar"], color=C["JR-D"], lw=2, marker="o", ms=7, mec="#fcfcfb", mew=1, zorder=3, label="帕累托前沿（JR-D 运行）")
    if len(F) >= 2:
        nx = (F["mean"] - F["mean"].min()) / max(F["mean"].max() - F["mean"].min(), 1e-9)
        ny = (F["cvar"] - F["cvar"].min()) / max(F["cvar"].max() - F["cvar"].min(), 1e-9)
        k = (nx ** 2 + ny ** 2).idxmin(); r = F.loc[k]
        a.scatter([r["mean"]], [r["cvar"]], s=140, facecolor="none", edgecolor=INK, linewidth=1.2, zorder=4)
        a.annotate(f"膝点：{r.label}", (r["mean"], r["cvar"]), xytext=(10, 10), textcoords="offset points", fontsize=7.5, color=INK)
    for _, r in pts.iterrows():
        a.annotate(r.label, (r["mean"], r["cvar"]), xytext=(4, -10), textcoords="offset points", fontsize=6.5, color=INK2)
    a.set_xlabel("样本外平均综合成本 / 万元"); a.set_ylabel("样本外最差 10% 日平均成本（CVaR$_{0.9}$）/ 万元")
    a.set_title("(a) 风险—期望权衡（52 个运行日）"); a.legend(fontsize=7, loc="upper right")
    b = ax[1]
    dro = c[c.kind.isin([0, 1])].copy(); dro["delta"] = np.where(dro.kind == 0, 0.0, dro.p1); dro = dro.sort_values("delta")
    for k, col in zip([1, 2, 3], ["#86b6ef", "#3987e5", "#1c5cab"]):
        b.plot(dro.delta, dro[f"C{k}"], color=col, lw=2, marker="o", ms=6, mec="#fcfcfb", mew=0.8, label=f"E{k} 承诺")
    b.set_xlabel("模糊集半径 δ（0 = 随机规划，2 = 场景鲁棒）"); b.set_ylabel("日前承诺 / MW")
    b.set_title("(b) 承诺随保守度的变化"); b.legend(fontsize=7, loc="upper right")
    save(fig, "fig15_risk_pareto.png")


# ---------------------------------------------------------------- fig16 benefit sources and mechanism waterfall
COMP = [("能量（购电+燃气+退化）", ["cost_energy", "cost_gas", "cost_deg"], 1), ("需求响应补贴", ["dr_pay"], -1),
        ("短缺考核", ["pen_dev"], 1), ("反弹考核", ["pen_rb"], 1), ("任务延迟", ["cost_delay"], 1), ("期末状态折算", ["term_adj"], 1)]


def fig_decomposition():
    sets = [("_certain", "事件确定，c_rb=3"), ("_certain_crb0", "事件确定，c_rb=0"), ("_e3uncertain", "E3 不确定")]
    data = [(rd(f"exp4{t}.csv"), rd(f"exp4{t}_strategies.csv"), lab) for t, lab in sets]
    data = [x for x in data if x[0] is not None and x[1] is not None]
    if not data: return
    fig, ax = plt.subplots(1, 2, figsize=(12.5, 4.2), gridspec_kw={"width_ratios": [1, 1.25]}); fig.subplots_adjust(wspace=0.45)
    # (a) where JR-D's saving against the stronger tuned benchmark comes from (mean over the MC days)
    a = ax[0]; shades = ["#1c5cab", "#3987e5", "#86b6ef"]; h = 0.26
    for i, (d, s, lab) in enumerate(data):
        idx = dict(zip(s["label"], s["index"]))
        m = d.groupby("strategy").mean(numeric_only=True)
        bench = min(["IR-O*", "IR-P"], key=lambda n: m.loc[idx[n], "net_cost_adj"])
        diff = []
        for name, cols, sg in COMP:
            diff.append(sg * sum(m.loc[idx[bench], c_] - m.loc[idx["JR-D"], c_] for c_ in cols) / 1e4)
        tot = (m.loc[idx[bench], "net_cost_adj"] - m.loc[idx["JR-D"], "net_cost_adj"]) / 1e4
        y = np.arange(len(COMP)) + (i - 1) * (h + 0.03)
        a.barh(y, diff, h, color=shades[i], edgecolor="#fcfcfb", linewidth=1.5, label=f"{lab}（对 {bench}，合计 {tot:.2f} 万元/日）")
    a.axvline(0, color=AXIS, lw=0.8); a.set_yticks(np.arange(len(COMP))); a.set_yticklabels([c_[0] for c_ in COMP]); a.invert_yaxis()
    a.set_xlabel("JR-D 相对较强调优基准的日均节省 / 万元（>0 有利于 JR-D）"); a.set_title("(a) 收益来源拆解（蒙特卡洛均值）")
    a.legend(fontsize=6.8, loc="best")
    # (b) mechanism waterfall: each step adds one coordination mechanism (events certain, c_rb = 3); bars show
    #     the change of the Monte-Carlo mean cost relative to IR-R, so the axis keeps its zero
    b = ax[1]; d, s, lab = data[0]; idx = dict(zip(s["label"], s["index"]))
    m = d.groupby("strategy").net_cost_adj.mean() / 1e4
    steps = [("IR-R", "规则独立恢复\n(IR-R)"), ("IR-O", "+各侧优化\n(IR-O)"), ("IR-O*", "+日前调优\n分摊 (IR-O*)"),
             ("IR-P", "+通道价格\n协调 (IR-P)"), ("JR-M", "+联合分配\n通道 (JR-M)"), ("JR-D", "+跨事件远见\n(JR-D)")]
    steps = [(k, t) for k, t in steps if k in idx]
    vals = [m[idx[k]] for k, _ in steps]; labels = [t for _, t in steps]
    u = next((x for x in data if x[2] == "E3 不确定"), None)
    if u is not None:
        du, su, _ = u; iu = dict(zip(su["label"], su["index"])); mu = du.groupby("strategy").net_cost_adj.mean() / 1e4
        if "JR-S" in iu and "JR-D" in iu:
            vals.append(vals[-1] + (mu[iu["JR-S"]] - mu[iu["JR-D"]])); labels.append("+场景对冲\n(JR-S，E3 不确定)")
    rel = [v - vals[0] for v in vals]
    b.bar(0, 0.0, 0.6, color=MUTED)
    b.text(0, 0, f"IR-R\n{vals[0]:.2f}", ha="center", va="bottom", fontsize=7, color=INK2)
    for i in range(1, len(rel)):
        dv = rel[i] - rel[i - 1]; lo = min(rel[i], rel[i - 1])
        b.bar(i, abs(dv), 0.6, bottom=lo, color="#1c5cab" if dv < 0 else "#e34948", edgecolor="#fcfcfb", linewidth=2)
        b.plot([i - 1 + 0.3, i - 0.3], [rel[i - 1], rel[i - 1]], color=AXIS, lw=0.8)
        b.text(i, lo if dv < 0 else rel[i], f"{dv:+.2f}", ha="center", va="top" if dv < 0 else "bottom", fontsize=7, color=INK2)
    n = len(rel)
    b.bar(n, rel[-1], 0.6, color=MUTED, edgecolor="#fcfcfb", linewidth=2)
    b.text(n, rel[-1], f"{rel[-1]:+.2f}\n({100 * rel[-1] / vals[0]:+.1f}%)", ha="center", va="top" if rel[-1] < 0 else "bottom", fontsize=7, color=INK2)
    b.axhline(0, color=AXIS, lw=0.8)
    b.set_xticks(range(n + 1)); b.set_xticklabels(labels + ["合计"], fontsize=6.8)
    lo_, hi_ = min(rel + [0]), max(rel + [0]); pad = 0.15 * max(hi_ - lo_, 1e-6)
    b.set_ylim(lo_ - pad, hi_ + pad)
    b.set_ylabel("相对 IR-R 的日均成本变化 / 万元"); b.set_title("(b) 机理贡献瀑布（蓝：降低成本，红：增加成本）")
    save(fig, "fig16_decomposition.png")


if __name__ == "__main__":
    fig_case(); fig_mechanism()
    for case in ["DAcommit", "uniform6"]:
        fig_timeseries(case); fig_timeseries(case, "_crb0")
    fig_sensitivity(); fig_sensitivity("_crb0"); fig_map(); fig_mc(); fig_shadow(); fig_commit()
    fig_pareto(); fig_capacity(); fig_stylized(); fig_robust()
    fig_substitution(); fig_risk(); fig_decomposition()
