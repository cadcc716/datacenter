#!/usr/bin/env python3
"""Draw the system-architecture and method-framework diagrams (paper Fig. 1 and Fig. 2).

Usage: python3 tools/draw_diagrams.py [figure_dir] [--en]
Flow colours follow fixed roles: electricity, cooling, heat, gas, information, computing workload.
"""
import os, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
from matplotlib import font_manager

HERE = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
FIG = args[0] if args else os.path.join(HERE, "..", "matlab", "figures")
EN = "--en" in sys.argv
os.makedirs(FIG, exist_ok=True)
for f in ["Noto Sans CJK SC", "WenQuanYi Micro Hei", "SimHei", "Microsoft YaHei"]:
    if any(f in x.name for x in font_manager.fontManager.ttflist):
        plt.rcParams["font.sans-serif"] = [f, "DejaVu Sans"]
        break
plt.rcParams.update({"axes.unicode_minus": False, "font.size": 8.5, "savefig.bbox": "tight", "figure.dpi": 150,
                     "figure.facecolor": "#fcfcfb", "savefig.facecolor": "#fcfcfb"})  # = BG
INK, INK2, MUTED, LINE, BG = "#0b0b0b", "#52514e", "#898781", "#c3c2b7", "#fcfcfb"
FLOW = {"el": "#2a78d6", "cool": "#1baf7a", "heat": "#eb6834", "gas": "#eda100", "info": "#6250d6", "work": "#e87ba4"}


def T(zh, en):
    return en if EN else zh


def box(ax, x, y, w, h, title, sub="", fc="#ffffff", ec=LINE, lw=1.0, tc=INK, fs=8.5, bold=True, r=0.012):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle=f"round,pad=0.004,rounding_size={r}", fc=fc, ec=ec, lw=lw, zorder=2))
    ax.text(x + w / 2, y + h / 2 + (0.012 if sub else 0), title, ha="center", va="center", fontsize=fs, color=tc,
            fontweight="bold" if bold else "normal", zorder=3)
    if sub:
        ax.text(x + w / 2, y + h / 2 - 0.022, sub, ha="center", va="center", fontsize=fs - 1.6, color=INK2, zorder=3)


def arrow(ax, p, q, kind, lw=1.6, ls="-", both=False, rad=0.0, text=None, toff=(0, 0.012)):
    st = "<|-|>" if both else "-|>"
    a = FancyArrowPatch(p, q, arrowstyle=st, mutation_scale=9, lw=lw, color=FLOW[kind], ls=ls,
                        connectionstyle=f"arc3,rad={rad}", zorder=1, shrinkA=2, shrinkB=2)
    ax.add_patch(a)
    if text:
        label(ax, (p[0] + q[0]) / 2 + toff[0], (p[1] + q[1]) / 2 + toff[1], text, va="bottom")


def label(ax, x, y, text, ha="center", va="center", fs=6.6):
    ax.text(x, y, text, ha=ha, va=va, fontsize=fs, color=INK2, zorder=4,
            bbox=dict(boxstyle="round,pad=0.12", fc=BG, ec="none"))


def elbow(ax, pts, kind, ls="--", lw=1.6):
    """Orthogonal connector: plain segments, arrow head on the last one."""
    xs, ys = zip(*pts[:-1])
    ax.plot(xs, ys, color=FLOW[kind], lw=lw, ls=ls, zorder=1, solid_capstyle="butt")
    arrow(ax, pts[-2], pts[-1], kind, lw=lw, ls=ls)


def group(ax, x, y, w, h, label, ec):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.006,rounding_size=0.018", fc="none", ec=ec, lw=1.0,
                                ls=(0, (4, 3)), zorder=0))
    ax.text(x + 0.008, y + h - 0.006, label, ha="left", va="top", fontsize=8, color=ec, fontweight="bold")


def architecture():
    fig, ax = plt.subplots(figsize=(12.6, 6.6)); ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off")
    # ---------------- physical layer ----------------
    group(ax, 0.01, 0.02, 0.63, 0.96, T("物理层：数据中心综合能源系统（电—冷—热—气）", "Physical layer: AIDC integrated energy system"), INK2)
    ax.add_patch(FancyBboxPatch((0.03, 0.885), 0.33, 0.045, boxstyle="round,pad=0.004,rounding_size=0.01", fc="#fff3f3",
                                ec="#e34948", lw=0.9, zorder=2))
    ax.text(0.195, 0.907, T("恢复通道：事件间隔内 H=Σ(P̄−P^b)⁺Δt，补算与回充争用", "Recovery channel H = Σ(P̄−P^b)⁺Δt: catch-up vs recharge"),
            ha="center", va="center", fontsize=7.2, color="#b42f2f", zorder=3)
    box(ax, 0.03, 0.74, 0.13, 0.10, T("电网", "Utility grid"), T("并网上限 P̄=γP̂", "limit P̄ = γP̂"), fc="#eef4fc")
    box(ax, 0.03, 0.58, 0.13, 0.10, T("光伏 8 MWp", "PV 8 MWp"), "", fc="#fff8e6")
    box(ax, 0.03, 0.38, 0.13, 0.12, T("燃气内燃机 3 MW", "Gas engine 3 MW"), T("η_e=0.38，余热 0.45", "η_e 0.38, heat 0.45"), fc="#fff4ec")
    box(ax, 0.03, 0.18, 0.13, 0.10, T("天然气", "Natural gas"), "", fc="#fdf6e3")
    box(ax, 0.22, 0.60, 0.11, 0.24, T("电母线", "AC bus"), T("电平衡", "power balance"), fc="#f4f8fd", fs=8)
    box(ax, 0.22, 0.40, 0.11, 0.12, T("电储能", "Battery"), "6 MW / 12 MWh", fc="#eef4fc")
    box(ax, 0.22, 0.18, 0.11, 0.12, T("吸收式制冷", "Absorption chiller"), "COP 0.75", fc="#eefaf5")
    box(ax, 0.38, 0.40, 0.10, 0.12, T("电制冷", "Electric chiller"), T("COP(T)", "COP(T)"), fc="#eefaf5")
    box(ax, 0.38, 0.25, 0.10, 0.11, T("蓄冷罐", "Cold storage"), "10 MWh", fc="#eefaf5")
    box(ax, 0.52, 0.18, 0.10, 0.34, T("冷冻水环路", "Chilled-water loop"), T("冷平衡", "cooling balance"), fc="#eefaf5", fs=8)
    # data center
    group(ax, 0.38, 0.58, 0.25, 0.37, T("AI 数据中心（16 000 GPU）", "AI data center (16 000 GPUs)"), FLOW["work"])
    box(ax, 0.395, 0.82, 0.225, 0.05, T("在线推理（Flex 0，不可延迟）", "Online inference (Flex 0)"), "", fc="#fdf0f5", fs=7.3, bold=False)
    box(ax, 0.395, 0.755, 0.225, 0.05, T("不可延迟训练（Flex 0）", "Non-deferrable training (Flex 0)"), "", fc="#fdf0f5", fs=7.3, bold=False)
    box(ax, 0.395, 0.62, 0.225, 0.115, T("可延迟作业 C1/C2/C3", "Deferrable jobs C1/C2/C3"),
        T("时限 0.5/1.5/3 h → 积压 B_c ≤ B̄_c", "lags 0.5/1.5/3 h → backlog B_c ≤ B̄_c"), fc="#fbe4ee", fs=7.6)
    # electricity
    arrow(ax, (0.16, 0.79), (0.22, 0.79), "el", both=True, text=T("购电 P^G", "import P^G"))
    arrow(ax, (0.16, 0.63), (0.22, 0.66), "el")
    arrow(ax, (0.16, 0.46), (0.22, 0.63), "el", rad=-0.15)
    arrow(ax, (0.275, 0.60), (0.275, 0.52), "el", both=True)
    arrow(ax, (0.33, 0.79), (0.395, 0.79), "el", text=T("IT 用电", "IT power"))
    arrow(ax, (0.33, 0.64), (0.42, 0.52), "el", rad=0.12)
    # gas, heat, cooling
    arrow(ax, (0.095, 0.28), (0.095, 0.38), "gas")
    arrow(ax, (0.16, 0.40), (0.22, 0.27), "heat", rad=0.1, text=T("余热", "waste heat"), toff=(-0.012, 0.0))
    arrow(ax, (0.48, 0.46), (0.52, 0.46), "cool")
    arrow(ax, (0.48, 0.305), (0.52, 0.305), "cool", both=True)
    arrow(ax, (0.33, 0.205), (0.52, 0.205), "cool", text=T("吸收式冷量", "absorption cooling"), toff=(0.0, 0.004))
    arrow(ax, (0.555, 0.52), (0.555, 0.62), "cool")
    label(ax, 0.548, 0.545, T("冷量", "cooling"), ha="right")
    arrow(ax, (0.60, 0.62), (0.60, 0.52), "heat", ls="--")
    label(ax, 0.607, 0.545, T("IT 散热", "IT heat"), ha="left")
    # ---------------- decision / information layer ----------------
    group(ax, 0.675, 0.02, 0.315, 0.96, T("决策与信息层", "Decision and information layer"), FLOW["info"])
    box(ax, 0.695, 0.80, 0.275, 0.12, T("电网 / 负荷聚合商", "Grid operator / aggregator"),
        T("江苏细则：基线、80%/120%、通知时间、考核", "Jiangsu rules: baseline, 80%/120%, notice, penalties"), fc="#f3f1fc")
    box(ax, 0.695, 0.61, 0.275, 0.13, T("日前：耦合承诺（两阶段随机/分布鲁棒 MILP）", "Day-ahead coupled commitment (SP/DRO MILP)"),
        T("一阶段 C_k；二阶段 场景联合恢复运行", "1st stage C_k; 2nd stage joint recovery per scenario"), fc="#f3f1fc", fs=7.6)
    box(ax, 0.695, 0.38, 0.275, 0.17, T("日内：联合恢复 MPC（每 15 min）", "Intraday: joint-recovery MPC (every 15 min)"),
        T("状态 (B₁,B₂,B₃,E,S)、场景树（含事件是否调用）\n优化补算、回充、IES，执行首步", "state (B,E,S), scenario tree incl. event calls\noptimise catch-up, recharge, IES; apply 1st step"),
        fc="#f3f1fc", fs=7.6)
    box(ax, 0.695, 0.18, 0.275, 0.12, T("执行与结算", "Execution and settlement"),
        T("EDF 执行、并网约束，江苏规则结算", "EDF execution, grid limit, Jiangsu settlement"), fc="#f3f1fc", fs=7.6)
    box(ax, 0.695, 0.05, 0.275, 0.08, T("数据：PAI / Azure 轨迹、ERA5 气象、江苏分时电价", "Data: PAI/Azure traces, ERA5 weather, Jiangsu TOU"), "",
        fc="#ffffff", fs=7.2, bold=False)
    for (p, q, t) in [((0.8325, 0.80), (0.8325, 0.74), T("事件预告/确认", "event notice/confirm")),
                      ((0.8325, 0.61), (0.8325, 0.55), T("承诺 C_k、终端 SOC", "C_k, terminal SOC")),
                      ((0.8325, 0.38), (0.8325, 0.30), T("调度指令", "set-points")),
                      ((0.8325, 0.13), (0.8325, 0.18), "")]:
        arrow(ax, p, q, "info", ls="--", text=t, toff=(0.065, -0.02))
    xc = 0.6575                                                     # corridor between the two layers
    elbow(ax, [(0.695, 0.52), (xc, 0.52), (xc, 0.675), (0.622, 0.675)], "info")
    label(ax, xc, 0.60, T("算力\n调度", "work-\nload"))
    elbow(ax, [(0.695, 0.42), (xc, 0.42), (xc, 0.33), (0.622, 0.33)], "info")
    label(ax, xc, 0.375, T("设备\n调度", "IES\nset-pts"))
    # legend
    lx, ly = 0.04, 0.065
    for i, (k, lab) in enumerate([("el", T("电", "electricity")), ("cool", T("冷", "cooling")), ("heat", T("热", "heat")),
                                  ("gas", T("气", "gas")), ("info", T("信息/指令", "information")), ("work", T("算力负荷", "workload"))]):
        x = lx + i * 0.095
        ax.plot([x, x + 0.03], [ly, ly], color=FLOW[k], lw=2, ls="--" if k == "info" else "-")
        ax.text(x + 0.035, ly, lab, va="center", fontsize=7, color=INK2)
    name = "fig00_architecture_en.png" if EN else "fig00_architecture.png"
    fig.savefig(os.path.join(FIG, name), dpi=200); plt.close(fig); print("wrote", name)


def framework():
    fig, ax = plt.subplots(figsize=(12.6, 2.4)); ax.set_xlim(0, 1); ax.set_ylim(0, 1); ax.axis("off")
    steps = [
        (T("历史数据", "Historical data"), T("26 个工作日联合场景\n（算力–推理–光伏–气温）", "joint scenarios of\ncompute, inference, PV, temp.")),
        (T("日前耦合承诺", "Day-ahead commitment"), T("两阶段 MILP：C_k 共享\n场景内联合恢复；SP/CVaR/DRO", "two-stage MILP, shared C_k\njoint recovery; SP/CVaR/DRO")),
        (T("基准调优", "Benchmark tuning"), T("IR-O* 回测选 α\nIR-P 取对偶通道价格", "IR-O*: back-tested α\nIR-P: dual channel price")),
        (T("日内滚动 MPC", "Intraday MPC"), T("15 min 步长、18 h 时域\n场景树含事件调用", "15-min step, 18-h horizon\nscenario tree incl. calls")),
        (T("仿真与结算", "Plant and settlement"), T("EDF 执行、并网限制\n江苏规则、指标统计", "EDF, grid limit\nJiangsu settlement, metrics")),
    ]
    w, h, y, dx = 0.16, 0.52, 0.44, 0.198
    for i, (t, s) in enumerate(steps):
        x = 0.02 + i * dx
        hot = i in (1, 3)
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.004,rounding_size=0.012",
                                    fc="#f3f1fc" if hot else "#ffffff", ec=FLOW["info"] if hot else LINE, lw=1.0, zorder=2))
        ax.text(x + w / 2, y + h - 0.13, t, ha="center", va="center", fontsize=9, color=INK, fontweight="bold", zorder=3)
        ax.text(x + w / 2, y + 0.17, s, ha="center", va="center", fontsize=7.2, color=INK2, zorder=3)
        if i < len(steps) - 1:
            arrow(ax, (x + w, y + h / 2), (x + dx, y + h / 2), "info")
    arrow(ax, (0.02 + 4 * dx + w / 2, y), (0.02 + 3 * dx + w / 2, y), "info", ls="--", rad=-0.3)
    label(ax, 0.02 + 3.5 * dx + w / 2, 0.20, T("实测状态反馈（每步）", "measured state fed back every step"), fs=7)
    name = "fig00_framework_en.png" if EN else "fig00_framework.png"
    fig.savefig(os.path.join(FIG, name), dpi=200); plt.close(fig); print("wrote", name)


if __name__ == "__main__":
    architecture(); framework()
