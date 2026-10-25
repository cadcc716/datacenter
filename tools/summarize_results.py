#!/usr/bin/env python3
"""Print every number quoted in docs/论文主要思路.md from matlab/results/*.csv (revised version).

Usage: python3 tools/summarize_results.py [results_dir]
Monte-Carlo statistics: mean with 95 % t-confidence interval; paired comparisons use the
per-realisation differences (mean, 95 % CI) and the Wilcoxon signed-rank test.
"""
import os, sys
import numpy as np
import pandas as pd
from scipy import stats

HERE = os.path.dirname(os.path.abspath(__file__))
RES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "matlab", "results")
pd.set_option("display.width", 220); pd.set_option("display.max_columns", 40)

# month-to-date maximum demand before the DR day: largest daily peak import of the 5 baseline workdays
# (computed by compute_baseline; the peaks occur at night, during valley-price storage charging)
D_REF = 15.29          # MW
C_DEM = 40.0e3         # CNY per MW and month: two-part tariff demand charge, typical provincial 1-10 kV level [A]
KEY = ["fulfil_rate_pct", "n_valid", "max_rebound_MW", "max_rebound6_MW", "payback_gap_MWh", "preload_vs_nodr_MW",
       "true_red_mean", "term_backlog_GPUh", "cost_op", "cost_delay", "dr_pay", "pen_dev", "pen_rb", "net_cost_adj",
       "net_cost_excl_rb", "co2_t", "gas_MWh"]


def rd(n):
    p = os.path.join(RES, n)
    return pd.read_csv(p) if os.path.exists(p) else None


def rd_parts(prefix):
    """concatenate <prefix>.csv and <prefix>_<part>.csv (experiments split over several processes)"""
    fs = sorted(f for f in os.listdir(RES) if f.startswith(prefix) and f.endswith(".csv")) if os.path.isdir(RES) else []
    parts = [pd.read_csv(os.path.join(RES, f)) for f in fs]
    return pd.concat(parts, ignore_index=True) if parts else None


def ci(x):
    x = np.asarray(x, float); x = x[~np.isnan(x)]
    if len(x) < 2: return (np.nan, np.nan)
    h = stats.t.ppf(0.975, len(x) - 1) * x.std(ddof=1) / np.sqrt(len(x))
    return (x.mean() - h, x.mean() + h)


def pct(a, b):
    return 100.0 * (a - b) / abs(b) if b not in (0, np.nan) else np.nan


def header(t):
    print("\n" + "=" * 100 + f"\n{t}\n" + "=" * 100)


# ------------------------------------------------------------------ Exp2
header("Exp2  main comparison on the case day")
for tag, lab in [("", "c_rb = 3 CNY/kW"), ("_crb0", "c_rb = 0 (Jiangsu rules only)")]:
    for case in ["DAcommit", "uniform6"]:
        d = rd(f"exp2_{case}{tag}.csv")
        if d is None: continue
        d = d.set_index("label")
        print(f"\n--- {case}, {lab}")
        print(d[[k for k in KEY if k in d.columns]].round(2).to_string())
        if "NoDR" in d.index and "peak_grid_MW" in d.columns:
            ref = max(D_REF, d.loc["NoDR", "peak_grid_MW"])
            dd = (d.peak_grid_MW - ref).clip(lower=0)
            print("  demand-charge exposure (peak above max(month peak, same-day no-DR peak), MW / CNY per month): " +
                  ", ".join(f"{i} {v:.2f}/{C_DEM * v:.0f}" for i, v in dd.items()))
        for p in ["JR-D", "JR-S"]:
            for b in ["IR-O*", "IR-P", "JR-M", "IR-O", "IR-R"]:
                if p in d.index and b in d.index:
                    a, r = d.loc[p], d.loc[b]
                    print(f"  {p} vs {b:5s}: fulfil {a.fulfil_rate_pct - r.fulfil_rate_pct:+6.2f} pp | max rebound "
                          f"{pct(a.max_rebound_MW, r.max_rebound_MW):+6.1f}% | net cost (adj) {pct(a.net_cost_adj, r.net_cost_adj):+6.1f}% | "
                          f"cost excl. rebound charge {pct(a.net_cost_excl_rb, r.net_cost_excl_rb):+6.1f}%")
        a = rd(f"exp2_alpha_{case}{tag}.csv")
        if a is not None:
            j = a.mean_net_cost_adj.idxmin(); print(f"  alpha* = {a.alpha[j]:.1f} (day-ahead back-test, mean fulfil {a.mean_fulfil_pct[j]:.1f}%)")

# ------------------------------------------------------------------ Exp4 / MC
def mc_report(tag, title):
    d = rd(f"exp4{tag}.csv"); s = rd(f"exp4{tag}_strategies.csv")
    if d is None or s is None: return
    names = dict(zip(s["index"], s["label"]))
    d["name"] = d.strategy.map(names)
    N = d.realisation.nunique()
    header(f"Exp4{tag}  {title}  (N = {N} realisations)")
    rows = []
    for nm in s["label"]:
        q = d[d.name == nm]
        r = {"strategy": nm}
        for col, lab in [("fulfil_rate_pct", "fulfil%"), ("all_valid", "all_valid"), ("max_rebound_MW", "maxRb"),
                         ("max_rebound6_MW", "maxRb6h"), ("payback_gap_MWh", "payGap"), ("net_cost_adj", "net_adj"),
                         ("net_cost_excl_rb", "net_exrb"), ("co2_t", "co2")]:
            lo, hi = ci(q[col]); r[lab] = q[col].mean(); r[lab + "_ci"] = f"[{lo:.4g}, {hi:.4g}]"
        r["fulfil_std"] = q.fulfil_rate_pct.std(ddof=1)
        rows.append(r)
    t = pd.DataFrame(rows).set_index("strategy")
    print(t[["fulfil%", "fulfil%_ci", "fulfil_std", "all_valid", "maxRb", "maxRb6h", "payGap", "net_adj", "net_adj_ci", "net_exrb", "co2"]].round(3).to_string())
    prop = [p for p in ["JR-S", "JR-D"] if p in names.values()]
    for p in prop:
        for b in [x for x in s["label"] if x not in ("JR-D", "JR-S")] + (["JR-D"] if p == "JR-S" else []):
            P = d[d.name == p].set_index("realisation"); B = d[d.name == b].set_index("realisation")
            out = []
            for col in ["fulfil_rate_pct", "max_rebound_MW", "net_cost_adj", "net_cost_excl_rb"]:
                diff = (P[col] - B[col]).dropna()
                lo, hi = ci(diff)
                try:
                    pv = stats.wilcoxon(diff, zero_method="zsplit").pvalue if np.any(np.abs(diff) > 1e-9) else 1.0
                except ValueError:
                    pv = np.nan
                rel = 100 * diff.mean() / abs(B[col].mean()) if col != "fulfil_rate_pct" else diff.mean()
                out.append(f"{col}: {diff.mean():+.4g} [{lo:+.4g},{hi:+.4g}] ({rel:+.1f}{' pp' if col == 'fulfil_rate_pct' else '%'}, p={pv:.2g})")
            better = int((P.net_cost_adj < B.net_cost_adj - 1e-6).sum())
            print(f"  {p} - {b:5s}: " + " | ".join(out) + f" | days {p} cheaper: {better}/{N}")
    if "called_E3" in d.columns and d.called_E3.nunique() > 1:
        print("  by E3 call status (mean fulfil % / net_adj):")
        print(d.groupby(["called_E3", "name"])[["fulfil_rate_pct", "net_cost_adj"]].mean().round(1).unstack(0).to_string())


mc_report("_certain", "Monte-Carlo, all events certain, c_rb = 3 CNY/kW")
mc_report("_certain_crb0", "Monte-Carlo, all events certain, c_rb = 0")
mc_report("_e3uncertain", "Monte-Carlo, E3 called with p = 0.6 (1 h notice), c_rb = 3 CNY/kW")

# ------------------------------------------------------------------ Exp12 capacity
header("Exp12  reliably deliverable capacity (Monte-Carlo commitment sweep, c_rb = 0)")
d = rd("exp12_capacity_crb0.csv"); s = rd("exp12_strategies_crb0.csv")
if d is not None and s is not None:
    names = dict(zip(s["index"], s["label"])); d["name"] = d.strategy.map(names)
    g = d.groupby(["C", "name"]).agg(fulfil=("fulfil_rate_pct", "mean"), all_valid=("all_valid", "mean"),
                                     net_adj=("net_cost_adj", "mean"), dr_pay=("dr_pay", "mean"), maxRb=("max_rebound_MW", "mean"))
    print(g.round(3).unstack(1).to_string())
    for nm in s["label"]:
        q = g.xs(nm, level=1)
        rel = q[q.all_valid >= 0.95].index.max() if (q.all_valid >= 0.95).any() else np.nan
        cbest = q.net_adj.idxmin()
        print(f"  {nm:6s}: largest C delivered on >=95% of days = {rel} MW per event; profit-maximising C = {cbest} MW "
              f"(mean net cost {q.net_adj.min():.0f} CNY)")

# ------------------------------------------------------------------ Exp6 pairing
header("Exp6  commitment-operation pairing (case day and Monte-Carlo means)")
for tag in ["", "_crb0"]:
    d = rd(f"exp6_commitment{tag}.csv")
    if d is None: continue
    print(f"--- c_rb = {'0' if tag else '3 CNY/kW'}")
    cols = ["label", "C1", "C2", "C3", "C_total", "alpha_star", "fulfil_rate_pct", "net_cost_adj", "mc_fulfil_rate_pct", "mc_share_all_valid", "mc_net_cost_adj", "mc_net_cost_excl_rb"]
    print(d[[c for c in cols if c in d.columns]].round(2).to_string(index=False))
    th = rd(f"exp6_theta{tag}.csv")
    if th is not None: print("  theta back-test:", th.round(2).to_dict("list"))

# ------------------------------------------------------------------ Exp8 rebound policy
header("Exp8  rebound assessment as a policy parameter (uniform 6 MW, case day)")
d = rd("exp8_rebound.csv"); s = rd("exp8_strategies.csv")
if d is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"])))
    print(d.pivot(index="c_rb", columns="name", values=["fulfil_rate_pct", "max_rebound_MW", "payback_gap_MWh", "net_cost_excl_rb"]).round(1).to_string())

# ------------------------------------------------------------------ Exp9 price
header("Exp9  DR unit price x shortfall coefficient (uniform 6 MW, case day)")
d = rd("exp9_price.csv"); s = rd("exp9_strategies.csv")
if d is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"])))
    print(d.pivot_table(index=["price", "kappa"], columns="name", values=["fulfil_rate_pct", "net_cost_adj"]).round(1).to_string())

# ------------------------------------------------------------------ Exp10 realism
header("Exp10  realism (liquid cooling, IT ramp limits, load-up charge)")
d = rd("exp10_realism.csv")
if d is not None:
    print(d[["label", "Pcap", "alpha_star"] + [k for k in KEY if k in d.columns]].round(2).to_string(index=False))

# ------------------------------------------------------------------ Exp3
header("Exp3  sensitivity (perfect information; 1 IR-R, 2 IR-O, 3 IR-O*(hindsight), 4 IR-P, 5 JR)")
for tag in ["", "_crb0"]:
    for f in ["duration", "interval", "gamma", "commitment"]:
        d = rd(f"exp3_{f}{tag}.csv")
        if d is None: continue
        print(f"--- {f}{tag}")
        print(d.pivot(index="x", columns="strategy", values=["fulfil_rate_pct", "max_rebound_MW", "net_cost_adj"]).round(1).to_string())
    d = rd(f"exp3_map{tag}.csv")
    if d is not None:
        a = d[d.strategy == 5].set_index(["gamma", "x"])
        b = d[d.strategy.isin([3, 4])].groupby(["gamma", "x"])
        print(f"--- map{tag}: fulfilment gain of JR over the best of IR-O*/IR-P (pp)")
        print((a.fulfil_rate_pct - b.fulfil_rate_pct.max()).unstack(1).round(1).to_string())
        print(f"--- map{tag}: cost reduction of JR vs the cheaper of IR-O*/IR-P (%)")
        best = b.net_cost_adj.min()
        print((100 * (best - a.net_cost_adj) / best).unstack(1).round(1).to_string())

# ------------------------------------------------------------------ Exp5
header("Exp5  shadow prices and Proposition 2 check (perfect information, uniform 6 MW)")
for tag in ["", "_crb0", "_gamma100", "_gamma100_crb0"]:
    d = rd(f"exp5_shadow{tag}.csv"); k = rd(f"exp5_kkt{tag}.csv")
    if d is None: continue
    print(f"--- {tag or 'base'}")
    for a, b, lab in [(17, 18, "E1"), (18, 19, "gap1"), (19, 20, "E2"), (20, 21, "gap2"), (21, 22, "E3"), (22, 30, "after")]:
        q = d[(d.hour >= a) & (d.hour < b)]
        print(f"  {lab:6s} lambda_el {q.lambda_el.mean():7.0f}  lambda_cap {q.lambda_cap.mean():7.0f}  lambda_rb {q.lambda_rb.mean():7.0f}  "
              f"value_E {q.value_E.mean():6.0f}  cost_B1/2/3 {q.cost_B1.mean():6.2f} {q.cost_B2.mean():6.2f} {q.cost_B3.mean():6.2f}")
    if k is not None: print("  KKT residuals:", k.round(6).to_dict("records"))

# ------------------------------------------------------------------ Exp1
header("Exp1  mechanism (ratio to single-event capability)")
for f in ["exp1_mechanism_CA6_DA2.csv", "exp1_mechanism_CA6_DA1_DB2.csv"]:
    d = rd(f)
    if d is None: continue
    for c in ["G_IR", "G_IRJ", "G_JR", "G_bound"]: d[c + "_r"] = d[c] / d.G0
    ok = bool((d.G_IRJ <= d.G_bound + 1e-3).all()); tight = int((d.G_bound - d.G_IRJ < 0.05).sum())
    print(f"--- {f}  bound valid: {ok}, tight (<0.05 MW): {tight}/{len(d)}")
    print(d[["gamma", "tau_h", "G0", "G_IR_r", "G_IRJ_r", "G_JR_r", "G_bound_r", "Rcomp_MWh", "Rstor_MWh", "Headroom_MWh"]].round(2).to_string(index=False))

# ------------------------------------------------------------------ Exp7 / Exp11
header("Exp7  ablation  /  Exp11 stylised theorem")
for f in ["exp7_ablation.csv", "exp7_alpha.csv"]:
    d = rd(f)
    if d is not None: print(d.round(2).to_string(index=False))
d = rd("exp11_stylized.csv")
if d is not None:
    e = max((d.G_JR_closed - d.G_JR_lp).abs().max(), (d.G_IR_closed - d.G_IR_lp).abs().max())
    print(f"Exp11: {len(d)} cases, max |closed form - LP| = {e:.2e} MW")

# ------------------------------------------------------------------ helpers for the AE-upgrade experiments
def paired(P, B, col="net_cost_adj"):
    diff = (P[col].values - B[col].values)
    lo, hi = ci(diff)
    try:
        pv = stats.wilcoxon(diff, zero_method="zsplit").pvalue if np.any(np.abs(diff) > 1e-9) else 1.0
    except ValueError:
        pv = np.nan
    return diff.mean(), lo, hi, 100 * diff.mean() / abs(B[col].mean()), pv


def rel_cap(q):
    ok = q[(q.fulfil_rate_pct >= 99 - 1e-6) & (q.n_valid == 3)]
    return float(ok.C.max()) if len(ok) else np.nan


# ------------------------------------------------------------------ deadline check (all Monte-Carlo files)
header("Deadline check: lateness (GPU-h*h) > 0 in any run")
for f in sorted(os.listdir(RES)) if os.path.isdir(RES) else []:
    if f.startswith(("exp19", "exp20")): continue      # job-level experiments: see the job-level service check
    if f.endswith(".csv") and "lateness_GPUh_h" in (open(os.path.join(RES, f)).readline()):
        d = pd.read_csv(os.path.join(RES, f)); n = int((d.lateness_GPUh_h > 1e-3).sum())
        if n: print(f"  {f}: {n} rows with lateness, max {d.lateness_GPUh_h.max():.1f}")
print("  (no line above = no deadline missed anywhere)")

# ------------------------------------------------------------------ Exp13 substitution
header("Exp13  virtual-physical substitution (perfect information, c_rb = 0)")
d = rd("exp13_substitution.csv"); s = rd("exp13_strategies.csv")
if d is not None and s is not None:
    names = dict(zip(s["index"], s["label"])); d["name"] = d.strategy.map(names)
    for sw, lab in [(1, "battery energy E (MWh)"), (2, "connection margin gamma")]:
        q = d[d.sweep == sw]; vals = sorted(q.value.unique())
        tab = pd.DataFrame({nm: [rel_cap(q[(q.value == v) & (q.name == nm)]) for v in vals] for nm in s["label"]}, index=vals)
        print(f"--- reliable capacity (>=99 %, all valid) vs {lab}"); print(tab.to_string())
        base = 12 if sw == 1 else 1.1
        if base in vals:
            tgt = tab.loc[base, "JR"]; best = tab[["IR-O*", "IR-P"]].max(axis=1)
            need = next((v for v in vals if best[v] >= tgt - 1e-9), None)
            print(f"  JR at {base}: {tgt} MW; the better independent strategy reaches it at {need} (base {base})")
        jr = q[q.name == "JR"]
        for v in vals:
            c = rel_cap(jr[jr.value == v]); r = jr[(jr.value == v) & (jr.C == c)]
            if len(r): print(f"  JR {lab}={v}: virtual storage before E2/E3 at its reliable capacity {c} MW: "
                             f"{r.virtual_E2_MWh.iloc[0]:.2f} / {r.virtual_E3_MWh.iloc[0]:.2f} MWh")

# ------------------------------------------------------------------ Exp14 timing
header("Exp14  computational performance")
d = rd("exp14_timing.csv")
if d is not None: print(d.round(3).to_string(index=False))

# ------------------------------------------------------------------ Exp15 risk-averse commitment
header("Exp15  risk-averse day-ahead commitment, out of sample with JR-D")
c = rd("exp15_commit.csv"); s = rd("exp15_settings.csv"); o = rd("exp15_oos.csv")
if c is not None and s is not None:
    c["label"] = c.setting.map(dict(zip(s["index"], s["label"])))
    print(c.round(2).to_string(index=False))
if o is not None and s is not None:
    lab = dict(zip(s["index"], s["label"])); rows = []
    for k, q in o.groupby("setting"):
        v = np.sort(q.net_cost_adj.values)[::-1]; n10 = max(1, int(round(0.1 * len(v))))
        lo, hi = ci(q.net_cost_adj)
        rows.append({"setting": lab[k], "mean": q.net_cost_adj.mean(), "ci": f"[{lo:.0f}, {hi:.0f}]", "cvar90": v[:n10].mean(),
                     "worst": v[0], "all_valid": q.all_valid.mean(), "fulfil": q.fulfil_rate_pct.mean(), "dr_pay": q.dr_pay.mean(),
                     "pen": (q.pen_dev + q.pen_rb).mean()})
    t = pd.DataFrame(rows).set_index("setting"); print(t.round(3).to_string())
    sp = o[o.setting == 1].set_index("realisation")
    for k in sorted(o.setting.unique()):
        if k == 1: continue
        m, lo, hi, rel, pv = paired(o[o.setting == k].set_index("realisation").loc[sp.index], sp)
        print(f"  {lab[k]:14s} - SP: net cost {m:+.0f} [{lo:+.0f}, {hi:+.0f}] ({rel:+.2f}%, Wilcoxon p={pv:.2g})")

# ------------------------------------------------------------------ Exp16 tariff shape
header("Exp16  tariff shape (same daily mean price)")
d = rd("exp16_tariff.csv"); s = rd("exp16_shapes.csv"); m = rd("exp16_tariff_mc.csv")
NM3 = {1: "IR-O*", 2: "IR-P", 3: "JR"}
if d is not None and s is not None:
    d["shape_name"] = d["shape"].map(dict(zip(s["index"], s["label"]))); d["name"] = d.strategy.map(NM3)
    print(d.pivot_table(index=["shape_name", "C"], columns="name", values=["fulfil_rate_pct", "net_cost_adj"]).round(1).to_string())
if m is not None and s is not None:
    for j, nm in zip(s["index"], s["label"]):
        q = m[m["shape"] == j]; J = q[q.strategy == 3].set_index("realisation")
        best = min([1, 2], key=lambda i: q[q.strategy == i].net_cost_adj.mean()); B = q[q.strategy == best].set_index("realisation")
        mm, lo, hi, rel, pv = paired(J, B.loc[J.index])
        print(f"  {nm:9s} MC (N={len(J)}): means IR-O* {q[q.strategy == 1].net_cost_adj.mean():.0f}  IR-P {q[q.strategy == 2].net_cost_adj.mean():.0f}  "
              f"JR-D {J.net_cost_adj.mean():.0f} | JR-D - {NM3[best]}: {mm:+.0f} [{lo:+.0f}, {hi:+.0f}] ({rel:+.2f}%, p={pv:.2g}) | "
              f"fulfil {q[q.strategy == 1].fulfil_rate_pct.mean():.1f}/{q[q.strategy == 2].fulfil_rate_pct.mean():.1f}/{J.fulfil_rate_pct.mean():.1f}")

# ------------------------------------------------------------------ Exp17 policy
header("Exp17  thermal inertia, green-electricity share, PUE cap")
d = rd("exp17_policy.csv")
if d is not None:
    d["name"] = d.strategy.map(NM3)
    for sw, lab in [(1, "thermal inertia off/on x C"), (2, "green share g"), (3, "PUE cap"), (5, "tie-line ramp limit (MW/15 min)")]:
        q = d[d.sweep == sw]
        idx = ["value", "C"] if sw == 1 else ["value"]
        print(f"--- {lab}")
        vals = ["fulfil_rate_pct", "net_cost_adj", "pue", "th_max_K", "cost_green"] + (["ramp_up_max_MW", "ramp_dn_max_MW"] if sw == 5 else [])
        if len(q): print(q.pivot_table(index=idx, columns="name", values=[v for v in vals if v in q.columns]).round(3).to_string())
    q = d[d.sweep == 4]
    if len(q):
        J = q[q.strategy == 3].set_index("value")
        for b in [1, 2]:
            B = q[q.strategy == b].set_index("value")
            mm, lo, hi, rel, pv = paired(J, B.loc[J.index])
            print(f"  MC with inertia (N={len(J)}): JR-D - {NM3[b]}: {mm:+.0f} [{lo:+.0f}, {hi:+.0f}] ({rel:+.2f}%, p={pv:.2g}); "
                  f"means {B.net_cost_adj.mean():.0f} vs {J.net_cost_adj.mean():.0f}; fulfil {B.fulfil_rate_pct.mean():.1f} vs {J.fulfil_rate_pct.mean():.1f}")

# ------------------------------------------------------------------ Exp18 climate
header("Exp18  season and climate")
d = rd("exp18_climate.csv"); s = rd("exp18_cases.csv"); m = rd("exp18_climate_mc.csv")
if s is not None: print(s.round(3).to_string(index=False))
if d is not None and s is not None:
    for j, nm in enumerate(s["label"], start=1):
        q = d[d["case"] == j]
        print(f"  {nm:14s} reliable capacity: " + ", ".join(f"{NM3[i]} {rel_cap(q[q.strategy == i])}" for i in [1, 2, 3]))
if m is not None and s is not None:
    for j, nm in enumerate(s["label"], start=1):
        q = m[m["case"] == j]; J = q[q.strategy == 3].set_index("realisation")
        if not len(J): continue
        best = min([1, 2], key=lambda i: q[q.strategy == i].net_cost_adj.mean()); B = q[q.strategy == best].set_index("realisation")
        mm, lo, hi, rel, pv = paired(J, B.loc[J.index])
        print(f"  {nm:14s} MC (N={len(J)}): fulfil {q[q.strategy == 1].fulfil_rate_pct.mean():.1f}/{q[q.strategy == 2].fulfil_rate_pct.mean():.1f}/"
              f"{J.fulfil_rate_pct.mean():.1f}; all valid {q[q.strategy == 1].all_valid.mean():.2f}/{q[q.strategy == 2].all_valid.mean():.2f}/{J.all_valid.mean():.2f}; "
              f"JR-D - {NM3[best]}: {mm:+.0f} [{lo:+.0f}, {hi:+.0f}] ({rel:+.2f}%, p={pv:.2g})")

# ------------------------------------------------------------------ helpers for the job-level experiments
def best_ir(q, col):
    """name of the independent strategy (IR-O*, IR-P) with the lower mean of col"""
    m = {nm: q[q.name == nm][col].mean() for nm in ["IR-O*", "IR-P"] if (q.name == nm).any()}
    return min(m, key=m.get) if m else None


def jr_vs_best(q, col, lab):
    b = best_ir(q, col)
    if b is None or not (q.name == "JR-D").any(): return
    J = q[q.name == "JR-D"].set_index("realisation"); B = q[q.name == b].set_index("realisation").loc[J.index]
    m, lo, hi, rel, pv = paired(J, B, col)
    print(f"    {lab:9s} JR-D - {b:5s}: {m:+8.0f} [{lo:+.0f}, {hi:+.0f}] CNY/day ({rel:+.2f}%, Wilcoxon p={pv:.2g}), "
          f"cheaper on {(J[col].values < B[col].values).sum()}/{len(J)} days")


# ------------------------------------------------------------------ Exp19 workload and recovery model
header("Exp19  LLM-era workload (Acme) and rigid-job recovery, every run also executed at job level")
s = rd("exp19_strategies.csv"); v = rd("exp19_variants.csv")
parts = [rd(f) for f in sorted(os.listdir(RES)) if f.startswith("exp19_workload") and f.endswith(".csv")] if os.path.isdir(RES) else []
parts = [q for q in parts if q is not None]
if parts and s is not None and v is not None:
    d = pd.concat(parts, ignore_index=True)
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"]))); vl = dict(zip(v["index"], v["label"]))
    for k in sorted(d.variant.unique()):
        q = d[(d.variant == k) & (d.realisation > 0)]; c0 = d[(d.variant == k) & (d.realisation == 0)]
        print(f"\n--- {vl[k]}  (N = {q.realisation.nunique()} Monte-Carlo days)")
        if len(c0):
            t = c0.set_index("name")[["n_valid", "net_cost_adj", "job_n_valid", "job_net_cost_adj", "job_rmse_pg", "job_rec_short",
                                      "job_lag_ratio_C1", "job_lag_ratio_C2", "job_lag_ratio_C3", "job_ovh_GPUh", "job_lost_GPUh",
                                      "job_B_end", "B_start_E3", "term_backlog_GPUh"]]
            print("  case day:"); print(t.round(2).to_string())
        rows = []
        for nm in s["label"]:
            z = q[q.name == nm]
            if not len(z): continue
            rows.append({"strategy": nm, "fluid_net": z.net_cost_adj.mean(), "fluid_allvalid": z.all_valid.mean(),
                         "fluid_fulfil": z.fulfil_rate_pct.mean(), "fluid_late": z.lateness_GPUh_h.mean(),
                         "job_net": z.job_net_cost_adj.mean(), "job_allvalid": z.job_all_valid.mean(),
                         "job_fulfil": z.job_fulfil_rate_pct.mean(), "job_vs_fluid_pct": 100 * (z.job_net_cost_adj.mean() / z.net_cost_adj.mean() - 1),
                         "rmse_MW": z.job_rmse_pg.mean(), "rec_short_GPUh": z.job_rec_short.mean(), "late_share_max": z[["job_late_share_C1", "job_late_share_C2", "job_late_share_C3"]].max(axis=1).mean(),
                         "ovh_MWh": z.job_ovh_MWh.mean(), "pauses": z.job_n_pause.mean()})
        if rows: print(pd.DataFrame(rows).set_index("strategy").round(3).to_string())
        jr_vs_best(q, "net_cost_adj", "fluid")
        jr_vs_best(q, "job_net_cost_adj", "job-level")
    print("\n  job-level service check: max lateness (GPU-h*h) over all job-level executions: "
          f"{d.job_lateness.max():.2f} (the executor runs a job when its slack is exhausted)")

# ------------------------------------------------------------------ Exp20 job-level sensitivity
header("Exp20  job-level execution on the case day: job mix and pause overheads")
d = rd("exp20_jobsim.csv"); se = rd("exp20_settings.csv"); s = rd("exp20_strategies.csv")
if d is not None and se is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"])))
    lab = {(w, i): l for w, i, l in zip(se["workload"], se["index"], se["label"])}
    for (w, mdl), q in d.groupby(["workload", "model"]):
        print(f"\n--- workload {'PAI' if w == 1 else 'Acme'}, {'fluid' if mdl == 0 else 'rigid-job'} recovery model")
        q = q.copy(); q["setting_name"] = [("fluid evaluation" if k == 0 else lab[(w, k)]) for k in q.setting]
        t = q.pivot_table(index="setting_name", columns="name", values="net_cost_adj", sort=False)
        t2 = q.pivot_table(index="setting_name", columns="name", values="n_valid", sort=False)
        print("  net cost (CNY):"); print(t.round(0).to_string())
        print("  valid events:"); print(t2.round(0).to_string())
        x = q[q.setting > 0].groupby("setting_name", sort=False)[["job_rmse_pg", "job_rec_short", "job_ovh_GPUh", "job_lost_GPUh", "job_n_pause", "job_step_max_MW", "job_gang_max_MW"]].mean()
        print("  job-level statistics (mean over strategies):"); print(x.round(2).to_string())

# ------------------------------------------------------------------ Exp21 wind
header("Exp21  green-power direct connection: offshore wind behind the meter")
cu = rd("exp21_curve.csv")
if cu is not None:
    g = cu.groupby("wind_MW")
    t = pd.DataFrame({"wind_MWh": g.wind_MWh.mean(), "share_cons_mean": 100 * g.res_share_cons.mean(),
                      "share_cons_p10": 100 * g.res_share_cons.quantile(0.1), "selfuse_mean": 100 * g.res_selfuse.mean(),
                      "selfuse_p10": 100 * g.res_selfuse.quantile(0.1), "days_share>=30%": 100 * g.res_share_cons.apply(lambda v: (v >= 0.3).mean()),
                      "days_selfuse>=60%": 100 * g.res_selfuse.apply(lambda v: (v >= 0.6).mean()), "grid_cost_kCNY": g.grid_cost_CNY.mean() / 1e3})
    print("green-power curve (no-DR operation, case day + all Monte-Carlo days):"); print(t.round(1).to_string())
d = rd_parts("exp21_wind"); s = rd("exp21_strategies.csv")
if d is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"])))
    for p, q in d.groupby("wind_MW"):
        c0 = q[q.realisation == 0]; m = q[q.realisation > 0]
        jd = m[m.name == "JR-D"]
        cs = jd[["C1", "C2", "C3"]]
        print(f"\n--- wind {p:g} MW: case-day wind {c0.wind_MWh_day.iloc[0]:.1f} MWh, C {c0[['C1', 'C2', 'C3']].iloc[0].tolist()}; "
              f"MC: wind {jd.wind_MWh_day.mean():.1f} MWh/day, declared C sum {cs.sum(axis=1).mean():.2f} MW/day "
              f"(mean C {cs.mean().round(2).tolist()}), events declared {100 * (cs > 0).values.mean():.0f}%")
        print(c0.set_index("name")[["n_valid", "net_cost_adj", "net_cost_excl_rb", "green_share_pv", "res_selfuse", "cost_energy", "dr_pay", "pen_rb"]].round(3).to_string())
        t = m.groupby("name")[["fulfil_rate_pct", "all_valid", "net_cost_adj", "net_cost_excl_rb", "dr_pay", "pen_dev", "pen_rb",
                               "cost_energy", "cost_delay", "green_share_pv", "res_selfuse"]].mean()
        print(t.round(3).to_string())
        jr_vs_best(m, "net_cost_adj", "MC")
        jr_vs_best(m, "net_cost_excl_rb", "MC (Jiangsu rules only)")

# ------------------------------------------------------------------ Exp22 overhead and capping levels
header("Exp22  pause / resume overhead and several capping levels (fluid model)")
d = rd_parts("exp22_overhead"); se = rd("exp22_settings.csv"); s = rd("exp22_strategies.csv")
if d is not None and se is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"]))); lab = dict(zip(se["index"], se["label"]))
    for k, q in d.groupby("setting"):
        c0 = q[q.realisation == 0]; m = q[q.realisation > 0]
        print(f"\n--- {lab[k]}: case day " + ", ".join(f"{a} {b:.0f}" for a, b in zip(c0.name, c0.net_cost_adj)))
        t = m.groupby("name")[["fulfil_rate_pct", "all_valid", "net_cost_adj", "pause_ovh_GPUh"]].mean()
        print(t.round(3).to_string())
        jr_vs_best(m, "net_cost_adj", "MC")

# ------------------------------------------------------------------ Exp24 winter waste-heat recovery
header("Exp24  winter waste-heat recovery (heat pump, hot-water tank, gas-boiler backup)")
d = rd_parts("exp24_heat"); se = rd("exp24_settings.csv"); s = rd("exp24_strategies.csv")
if d is not None and se is not None and s is not None:
    d["name"] = d.strategy.map(dict(zip(s["index"], s["label"]))); lab = dict(zip(se["index"], se["label"]))
    cols = ["fulfil_rate_pct", "all_valid", "net_cost_adj", "dr_pay", "pen_rb", "cost_energy", "cost_boiler", "hp_MWh", "boiler_MWh",
            "heat_rec_share", "co2_t", "php_events_MW", "H_start_E1", "H_start_E2", "H_start_E3"]
    for k, q in d.groupby("setting"):
        c0 = q[q.realisation == 0]; m = q[q.realisation > 0]
        print(f"\n--- {lab[k]}: case-day heat demand {c0.heat_demand_MWh.iloc[0]:.1f} MWh_th; MC mean {m.groupby('realisation').heat_demand_MWh.first().mean():.1f}")
        print("  case day: " + ", ".join(f"{a} {b:.0f}" for a, b in zip(c0.name, c0.net_cost_adj)))
        print(m.groupby("name")[cols].mean().round(3).to_string())
        jr_vs_best(m, "net_cost_adj", "MC")
    ref = d[(d.setting == 1) & (d.realisation > 0)]
    for k in sorted(d.setting.unique()):
        if k == 1: continue
        q = d[(d.setting == k) & (d.realisation > 0)]
        for nm in ["JR-D", "IR-P"]:
            a = q[q.name == nm].set_index("realisation"); b = ref[ref.name == nm].set_index("realisation").loc[a.index]
            print(f"  value of heat recovery, {lab[k]:10s} vs boiler ({nm}): {(a.net_cost_adj - b.net_cost_adj).mean():+8.0f} CNY/day "
                  f"({100 * (a.net_cost_adj - b.net_cost_adj).mean() / b.net_cost_adj.mean():+.1f}%), CO2 {(a.co2_t - b.co2_t).mean():+.1f} t/day")

# ------------------------------------------------------------------ Exp23 scenario generation
header("Exp23  day-ahead scenarios: K-means reduction and seasonal drift (out of sample with JR-D)")
c = rd("exp23_commit.csv"); se = rd("exp23_settings.csv"); o = rd("exp23_oos.csv")
if c is not None and se is not None:
    c["label"] = [l for l in se["label"]]
    print(c.round(2).to_string(index=False))
if o is not None and se is not None:
    lab = {(p, k): l for p, k, l in zip(se["part"], se["setting"], se["label"])}
    for p, q in o.groupby("part"):
        rows = []
        for k, z in q.groupby("setting"):
            v_ = np.sort(z.net_cost_adj.values)[::-1]; n10 = max(1, int(round(0.1 * len(v_))))
            rows.append({"setting": lab[(p, k)], "mean": z.net_cost_adj.mean(), "cvar90": v_[:n10].mean(), "all_valid": z.all_valid.mean(),
                         "fulfil": z.fulfil_rate_pct.mean(), "dr_pay": z.dr_pay.mean()})
        print(f"--- part {p}"); print(pd.DataFrame(rows).set_index("setting").round(3).to_string())
        ref = q[q.setting == 1].set_index("realisation")
        for k in sorted(q.setting.unique()):
            if k == 1: continue
            m, lo, hi, rel, pv = paired(q[q.setting == k].set_index("realisation").loc[ref.index], ref)
            print(f"  {lab[(p, k)]:16s} - {lab[(p, 1)]}: {m:+.0f} [{lo:+.0f}, {hi:+.0f}] ({rel:+.2f}%, p={pv:.2g})")

# ------------------------------------------------------------------ Exp25 capability region
header("Exp25  cross-event deliverable capability region (virtual-battery description)")
cs = rd("exp25_case.csv"); sw = rd("exp25_sweep.csv"); mc = rd("exp25_mc.csv"); ip = rd("exp25_irp.csv"); rad = rd("exp25_radial.csv")
if cs is not None:
    for _, r in cs.iterrows():
        box = r.G1 + r.G2 + r.G3
        print(f"--- case {int(r['case'])}: gamma {r.gamma:.2f}, tau {r.tau_h:g} h; G = ({r.G1:.2f}, {r.G2:.2f}, {r.G3:.2f}) MW (sum {box:.2f})")
        print(f"  support h12 {r.h12:.2f} h13 {r.h13:.2f} h23 {r.h23:.2f} h123 {r.h123:.2f}; energy bound {r.bound123:.2f} "
              f"= Xbar {r.Xbar:.2f} + Es {r.Es:.2f} + H {r.H:.2f} + gD {r.gD:.2f} + Delta {r.Delta:+.2f} (gap {r.bound123 - r.h123:.2f} MWh)")
        print(f"  template exact {int(r.exact)} (theta {r.theta:.4f}, {int(r.n_vertices)} vertices); volume template {r.vol_template:.1f}, box {r.vol_box:.1f}")
        print(f"  uniform capability: JR {r.u_JR:.2f}, IR-P+ {r.u_IRPp:.2f}, IR-O* {r.u_IROs:.2f} (alpha {r.alpha_u_IROs:.1f}), IR-O {r.u_IRO:.2f}, IR-P {r.u_IRP:.2f} MW")
        print(f"  largest total commitment: JR {r.h123:.2f}, IR-O* {r.tmax_IROs:.2f}, IR-O {r.tmax_IRO:.2f} MW; volume / JR: IR-O* {r.vol_IROs / r.vol_JR:.3f}, "
              f"IR-O {r.vol_IRO / r.vol_JR:.3f}, IR-P {r.vol_IRP / r.vol_JR:.3f}, IR-P+ {r.vol_IRPp / r.vol_JR:.3f}")
    if rad is not None:
        for ci_, q in rad.groupby("case"):
            ok = q.t_JR > 1e-6; rr = (q.t_IROs / q.t_JR)[ok]
            print(f"  case {ci_}: IR-O*/JR along the rays min {rr.min():.3f} (at d = {q[ok].loc[rr.idxmin(), ['d1', 'd2', 'd3']].values.round(2)}), "
                  f"share of rays with no loss {np.mean(rr > 0.999):.2f}")
if ip is not None:
    print(ip.round(3).to_string(index=False))
if sw is not None:
    print("--- interval x margin (uniform capability, MW; bound gap where the energy cut binds)")
    sw["box"] = sw[["G1", "G2", "G3"]].sum(axis=1); sw["binding"] = sw.h123 < sw.box - 0.01
    print(sw[["gamma", "tau_h", "h123", "box", "bound123", "u_JR", "u_IRPp", "u_IROs", "u_IRO", "u_IRP"]].round(2).to_string(index=False))
    b = sw[sw.binding]
    if len(b): print(f"  energy bound - h123 where the cut binds ({len(b)} cases): max {(b.bound123 - b.h123).max():.2f} MWh, "
                     f"max relative {100 * ((b.bound123 - b.h123) / b.h123).max():.1f}%")
if mc is not None:
    mc["box"] = mc[["G1", "G2", "G3"]].sum(axis=1); bind = mc.h123 < mc.box - 0.01
    print(f"--- Monte-Carlo days (N = {len(mc)}): cut binding on {bind.sum()} days")
    for col in ["u_JR", "u_IRPp", "u_IROs", "u_IRO", "u_IRP"]:
        r_ = mc[col] / mc.u_JR
        print(f"  {col:7s}: mean {mc[col].mean():.2f} MW [min {mc[col].min():.2f}, max {mc[col].max():.2f}]; ratio to JR mean {r_.mean():.3f} min {r_.min():.3f}")
    if bind.any():
        g_ = (mc.bound123 - mc.h123)[bind]
        print(f"  energy bound - h123 on binding days: mean {g_.mean():.2f}, max {g_.max():.2f} MWh ({100 * (g_ / mc.h123[bind]).max():.1f}%)")
    print(f"  bound >= h123 on all days: {bool((mc.bound123 >= mc.h123 - 1e-6).all())}")
fe = rd("exp25_irp_eps.csv")
if fe is not None:
    print("--- optimistic IR-P with near-optimal IT responses (IT objective within 0.1 % of its optimum)")
    for ci_, q in fe[fe.part == 1].groupby("id"):
        ok = q.t_JR > 1e-6; r_ = (q.t_IRPe / q.t_JR)[ok]
        print(f"  case {ci_}: ratio to JR min {r_.min():.3f}, mean {r_.mean():.3f}, rays at the JR boundary {np.mean(np.abs(q.t_IRPe - q.t_JR)[ok] <= 0.02):.2f}")
    q = fe[fe.part == 2]; r_ = q.t_IRPe / q.t_JR
    print(f"  sweep centre rays ({len(q)}): ratio to JR min {r_.min():.3f}")
    q = fe[fe.part == 3]; r_ = q.t_IRPe / q.t_JR
    print(f"  Monte-Carlo days ({len(q)}): ratio to JR mean {r_.mean():.4f}, min {r_.min():.3f}")

# ------------------------------------------------------------------ Exp26 distributed coordination (ADMM)
header("Exp26  distributed joint recovery: IT and facility exchange only the IT power plan and its price (ADMM)")
cv = rd("exp26_conv.csv"); rf = rd("exp26_ref.csv"); pz = rd("exp26_price.csv")
if cv is not None and rf is not None:
    J = rf.J_joint.iloc[0]
    print(f"--- open loop, case day: joint {J:.0f}; IR-P {100 * (rf.J_IRP.iloc[0] / J - 1):+.2f}%, IR-O* (alpha {rf.alpha_IROs.iloc[0]:.1f}) "
          f"{100 * (rf.J_IROs.iloc[0] / J - 1):+.2f}%")
    for rho_, q in cv.groupby("rho"):
        q = q.set_index("k"); g = 100 * (q.J_impl / J - 1)
        kP = g[(g < 100 * (rf.J_IRP.iloc[0] / J - 1)) & (q.valid == 1)].index.min(); k01 = g[g < 0.1].index.min()
        print(f"  rho {rho_:5.0f}: gap " + ", ".join(f"k={k} {g.get(k, np.nan):.3f}%" for k in [1, 3, 5, 10, 20, 50, 100]) +
              f"; better than IR-P from k={kP}, below 0.1% from k={k01}; first all-valid k={q[q.valid == 1].index.min()}")
if pz is not None:
    for rho_, q in pz.groupby("rho"):
        dlt = np.abs(q.lambda_admm - q.lambda_joint)
        print(f"  price rho {rho_:5.0f}: steps within 1 CNY/MWh {np.mean(dlt < 1):.2f}, max deviation {dlt.max():.0f} CNY/MWh "
              f"(joint price {q.lambda_joint.min():.0f}-{q.lambda_joint.max():.0f})")
m = rd_parts("exp26_mc"); s26 = rd("exp26_strategies.csv")
if m is not None and s26 is not None:
    m["name"] = m.strategy.map(dict(zip(s26["index"], s26["label"])))
    days = m[m.realisation > 0]
    print(f"--- closed loop: case day + {days.realisation.nunique()} Monte-Carlo days")
    c0 = m[m.realisation == 0].set_index("name")
    print("  case day: " + ", ".join(f"{n} {c0.loc[n, 'net_cost_adj']:.0f} ({int(c0.loc[n, 'n_valid'])} valid)" for n in s26["label"]))
    ref = days[days.name == "JR-D"].set_index("realisation")
    for n in s26["label"]:
        q = days[days.name == n].set_index("realisation").loc[ref.index]
        mu, lo, hi, rel, pv = paired(q, ref)
        print(f"  {n:7s}: mean {q.net_cost_adj.mean():9.0f}, all valid {100 * (q.n_valid == 3).mean():5.1f}% of days, "
              f"vs JR-D {rel:+.2f}% [{100 * lo / ref.net_cost_adj.mean():+.2f}, {100 * hi / ref.net_cost_adj.mean():+.2f}] (p={pv:.2g}), "
              f"run time {q.run_time_s.mean():.0f} s/day")
    best = None
    for b in ["IR-P", "IR-O*"]:
        q = days[days.name == b].set_index("realisation").loc[ref.index]
        if best is None or q.net_cost_adj.mean() < best[1].net_cost_adj.mean(): best = (b, q)
    gap_ir = best[1].net_cost_adj.mean() - ref.net_cost_adj.mean()
    for n in [x for x in s26["label"] if x.startswith("JR-A")]:
        q = days[days.name == n].set_index("realisation").loc[ref.index]
        print(f"  {n}: recovers {100 * (best[1].net_cost_adj.mean() - q.net_cost_adj.mean()) / gap_ir:.0f}% of the JR-D advantage over {best[0]}")
r26 = rd_parts("exp26_rho")
if r26 is not None:
    print("--- case day, K = 3, rho sensitivity:", ", ".join(f"rho {a:.0f}: {b:.0f}" for a, b in zip(r26.rho, r26.net_cost_adj)))
