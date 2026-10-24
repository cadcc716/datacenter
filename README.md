# 计及跨事件算储联合恢复的数据中心综合能源系统连续需求响应优化调度

Coordinated scheduling for consecutive demand response (DR) in AI data-center integrated energy
systems (AIDC-IES) considering cross-event computing-storage recovery — reproducible MATLAB study
(revised after the simulated peer review and upgraded against an Applied Energy benchmark paper).

* **Paper idea, model, theory, experiments and results (Chinese):** [`docs/论文主要思路.md`](docs/论文主要思路.md)
* **Proofs (Lemma 1, Propositions 1–3, Theorem 1):** [`docs/理论推导.md`](docs/理论推导.md)
* **Review, revision tracking, benchmark gap analysis, handover:** [`docs/审稿意见.md`](docs/审稿意见.md),
  [`docs/修改进度.md`](docs/修改进度.md), [`docs/AE对标分析与优化方案.md`](docs/AE对标分析与优化方案.md),
  [`docs/交接文档.md`](docs/交接文档.md)
* **MATLAB code:** [`matlab/`](matlab) — runs in MATLAB (Optimization Toolbox, or Gurobi) or GNU Octave (glpk)
* **Data (derived from public traces):** [`data/`](data), provenance in [`data_prep/README.md`](data_prep/README.md)
* **Figures:** [`matlab/figures/`](matlab/figures) (Chinese labels) and [`matlab/figures_en/`](matlab/figures_en)
  (English), rendered by `tools/plot_results.py` and `tools/draw_diagrams.py`
* The first version (before the review) is kept on branch `Firstthinking`.

## Key results (reproduced by `main_run_all`)

16 000-GPU AI data center with PV, gas engine + absorption chiller, chilled-water storage and a 6 MW / 12 MWh
battery; three DR events 17–18, 19–20, 21–22 h under the Jiangsu settlement rules (80 % validity, 120 % pay cap).
Benchmarks are the strongest independent strategies: static split tuned day-ahead (IR-O\*), day-ahead
channel-price coordination (IR-P) and event-by-event joint recovery (JR-M). The independent benchmarks'
compute scheduler may use the gas engine's available output in its power budget; with that, deadline misses
are negligible for every strategy (at most 4 GPU·h·h in a single run).

| 52 operating days, uniform 6 MW per event | All three events valid | Fulfilment | Total cost (paired daily difference) |
|---|---|---|---|
| Events certain, rebound charge 3 CNY/kW: JR-D vs IR-P | 100 % vs 94 % of days | 99.9 % vs 98.3 % | **−2.9 %** (cheaper on 50 of 52 days, p < 10⁻⁹) |
| Events certain, Jiangsu rules only: JR-D vs IR-O\* | 100 % vs 98 % of days | 99.9 % vs 99.2 % | **−3.1 %** (52 of 52 days) |
| Last event called with p = 0.6: JR-D vs IR-P | 100 % vs 94 % of days | 100 % vs 97.6 % | **−4.0 %** (51 of 52 days) |

* **Reliable capacity is the main value.** Requiring all events valid on ≥ 95 % of days, joint recovery can
  commit 8 MW per event instead of 6 MW (+33 %). In perfect-information sweeps this is worth about
  9–12 MWh of battery energy or 2.9 MW of connection capacity (Exp13). Larger batteries are not always
  better: their normal peak-price discharge lowers the DR baseline by about 0.6 MW per 6 MWh.
* **Mechanism.** After a 6 MW × 2 h event, independent recovery leaves 38–39 % of the next event's
  stand-alone capability for gaps ≤ 1 h. Joint recovery from the same post-event state restores 96 %
  within 0.75 h, because it repays only what the next event needs and carries long-deadline work across
  events.
* **Where the saving comes from.** With a rebound charge, 78 % comes from the rebound charge; under the
  Jiangsu rules alone, 86 % comes from DR payments kept valid. Energy cost is almost unchanged.
  Event-by-event joint recovery without cross-event foresight is worse than price coordination.
* **Commitment.** Coupled day-ahead commitment with joint recovery costs 12.6 % less than today's
  single-event assessment with independent recovery. Distributionally robust commitments (Proposition 3,
  exact MILP) lower both the mean and the worst-10 %-day cost out of sample.
* **Robustness.** The result holds for five tariff shapes (−2.1 % to −2.9 %), Suzhou winter and the
  Gui'an hub climate (−2.6 % to −2.8 %, every event valid), liquid cooling (−7.4 %), GPU power capping
  and server-room thermal inertia (−2.2 %). A PUE cap of 1.25 costs about 0.24 × 10⁴ CNY per day. Tight
  IT or tie-line ramp limits shrink the benefit.
* **Computation.** Intraday MPC solves in under 2 s with 10 scenarios; the day-ahead model in 3–25 s.

![architecture](matlab/figures/fig00_architecture.png)

## Quick start

```matlab
cd matlab
main_run_all                              % all 23 experiments (Octave/glpk, one process: ~14 h)
QUICK = true; main_run_all                % smoke run (small grids, 1-2 Monte-Carlo days)
RUN = [2 5]; main_run_all                 % subset
```

Parallel run in GNU Octave: `tools/run_parallel.sh <tag> "RUN=[...];"` starts one part in the background
(Exp1–18 in four parts take about 2.5 h, Exp19–23 about 2 h more; run Exp14, the timing study, alone on an
idle machine). Then
`python3 tools/summarize_results.py` prints every number quoted in the paper notes (95 % confidence
intervals, paired Wilcoxon tests), `python3 tools/plot_results.py [--en]` renders the figures and
`python3 tools/draw_diagrams.py [--en]` the architecture and framework diagrams (numpy, pandas, scipy,
matplotlib).

Requirements: MATLAB R2019b+ with Optimization Toolbox (`linprog`, `intlinprog`), or Gurobi's MATLAB
interface on the path, or GNU Octave 6+ (built-in `glpk`). All randomness is replaced by deterministic
scenario selection and low-discrepancy event draws, so MATLAB and Octave give the same results up to
solver tolerances. The committed results come from GNU Octave 8.4 + glpk.

## Layout

```
data/                        derived inputs (PAI GPU trace, Acme LLM-development trace, job-size distributions,
                             Azure LLM trace, ERA5 weather: Suzhou summer/winter, Gui'an; ERA5 offshore wind)
data_prep/                   prepare_data.py (PAI, Azure), prepare_acme.py (Acme, job sizes), fetch_weather.py,
                             fetch_wind.py (Open-Meteo ERA5)
matlab/main_run_all.m        entry point (RUN, QUICK, NMC, MC_PART options)
matlab/config/dcdr_params.m  all parameters, each tagged [S] source / [D] data-derived / [A] assumption
matlab/src/                  model and solvers
   build_model.m             joint recovery MILP (dual state, IES, Jiangsu settlement; optional thermal inertia,
                             PUE / green-share constraints, DRO / CVaR risk measure of the scenario costs)
   build_compute_model.m     IT-only scheduler (independent benchmarks, stage 1)
   dayahead_commit.m         day-ahead two-stage commitment (coupled / single-event; SP, DRO, RO, CVaR)
   prepare_benchmarks.m      day-ahead tuning of IR-O* and the IR-P price signal
   planner_jr.m / planner_iro.m / planner_irr.m   joint / independent (optimised) / independent (rule) MPC
   event_activity.m          which events a planner sees (call probability, scenario tree, myopic JR-M)
   evaluate_run.m            Jiangsu settlement and all evaluation metrics
   plant_step.m              plant simulator (EDF backlog tracking, IES balances, thermal state, limit enforcement;
                             optional rigid-job recovery bound, pause overhead, capping levels)
   job_gen.m / job_replay.m  job-level validation: gang-job population drawn from the traces, execution of a
                             fluid schedule with rigid jobs, checkpoint / restart overheads, minimum pause
   kmeans_scen.m             K-means reduction of the joint day-ahead scenarios (non-uniform probabilities)
   cap_curve.m               convex piecewise-linear GPU capping curve (one or several levels)
   solve_milp.m              solver wrapper: Gurobi | linprog/intlinprog | Octave glpk (MIP time limit 300 s)
matlab/experiments/          exp1 ... exp23 (see below)
matlab/tests/                smoke tests (QUICK settings, results to tempdir)
tools/                       summarize_results.py, plot_results.py, draw_diagrams.py, run_parallel.sh
```

## Experiments

| # | Script | Question |
|---|---|---|
| 1 | `exp1_mechanism` | How the dual recovery demand of event A limits event B (+ Proposition 1 bound) |
| 2 | `exp2_main` | Case day: all strategies under identical commitments, c_rb = 3 CNY/kW and 0 |
| 3 | `exp3_sensitivity` | Duration, interval, connection margin, commitment level; τ × γ map (perfect information) |
| 4 | `exp4_montecarlo` | 52 operating days: events certain (two rebound policies) and E3 called with p = 0.6 |
| 5 | `exp5_shadow` | Shadow prices of the recovery channel and of both recovery states; Proposition 2 check |
| 6 | `exp6_commitment` | Commitment–operation pairing (single-event, scaled single-event, coupled) |
| 7 | `exp7_ablation` | Value of each flexibility source; best static split |
| 8 | `exp8_rebound` | Rebound assessment as a policy parameter (0–6 CNY/kW) |
| 9 | `exp9_price` | DR unit price × shortfall coefficient |
| 10 | `exp10_realism` | Liquid cooling, IT ramp limits, pre-event load-up charge, GPU power capping |
| 11 | `exp11_stylized` | Closed-form Theorem 1 vs LP |
| 12 | `exp12_capacity` | Reliably deliverable capacity (Monte-Carlo commitment sweep) |
| 13 | `exp13_substitution` | Virtual–physical substitution: battery energy and connection capacity worth of joint recovery |
| 14 | `exp14_timing` | Model size and solve time vs horizon, scenarios and number of events |
| 15 | `exp15_risk` | Risk-averse day-ahead commitment (SP / DRO / RO / CVaR, Proposition 3), out of sample |
| 16 | `exp16_tariff` | Time-of-use tariff shape (flat, two-tier, critical peak, duck curve) |
| 17 | `exp17_policy` | Thermal inertia as a third recovery state, green-electricity share, PUE cap |
| 18 | `exp18_climate` | Season and climate (Suzhou winter, Gui'an summer) |
| 19 | `exp19_workload` | LLM-era workload (Acme 2023) and rigid-job recovery; every run also executed at job level |
| 20 | `exp20_jobsim` | Job-level execution on the case day: job mix (PAI, Acme Seren / Kalos, larger gangs), pause overheads |
| 21 | `exp21_wind` | Green-power direct connection: offshore wind behind the meter (0–40 MW) |
| 22 | `exp22_overhead` | Pause / resume overhead and several GPU capping levels in the fluid model |
| 23 | `exp23_scenarios` | Day-ahead scenarios: K-means reduction with non-uniform probabilities, seasonal drift |

## Data licences and citations

PAI trace: please cite Weng et al., NSDI 2022. Acme trace (Shanghai AI Lab): CC BY 4.0, cite Hu et al.,
NSDI 2024. Azure LLM inference trace 2024: CC-BY 4.0, cite Stojkovic et al., HPCA 2025. Weather and wind:
Open-Meteo / ERA5, CC-BY 4.0. Only aggregated 15-min profiles and binned job-size distributions derived
from these sources are stored in this repository.
