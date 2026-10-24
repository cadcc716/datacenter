#!/usr/bin/env python3
"""LLM-era workload inputs from the Acme trace and job-size distributions for the job-level validation.

Sources (download first, see data_prep/README.md):
  * AcmeTrace, Shanghai AI Lab, March-August 2023 (Hu et al., NSDI'24; CC BY 4.0),
    https://huggingface.co/datasets/Qinghao/AcmeTrace :
      data/job_trace/trace_seren.csv, data/job_trace/trace_kalos.csv
  * Alibaba PAI GPU trace 2020 (Weng et al., NSDI'22), task table as redistributed in the same
    dataset: data/job_trace/trace_previous_work/pai_trace.csv

Outputs (written to ../data):
  acme_seren_gpu_occupancy_15min.csv  busy GPUs per 15 min by runtime class, same layout as
                                      pai_gpu_occupancy_15min.csv (day = days since 2023-03-01, local
                                      time UTC+8, dow 0 = Monday), stable days 2023-03-13 .. 2023-08-16
  job_dist.csv                        joint distribution of gang size and run time per runtime class
                                      (source, cls, gpus, dur_min, count); run times pooled in
                                      logarithmic bins (mean run time of the bin kept)
  job_class_stats.csv                 per source and class: jobs, share of GPU-hours, mean gang size,
                                      GPU-hour-weighted gang size, gang-weighted mean run time (h) and
                                      mean residual run time of a busy GPU (h)

Every Acme GPU job that ran is counted, whatever its final state: most GPU-hours of pretraining
belong to jobs that users cancelled (Hu et al., Table 2), and they drew power while running.
PAI keeps the filter of prepare_data.py (terminated tasks), so the two PAI products agree.

Usage:
  python3 -I prepare_acme.py --seren FILE --kalos FILE --pai FILE --out ../data
"""
import argparse
import os

import numpy as np
import pandas as pd

CLASS_EDGES_H = (1.0, 12.0)          # same runtime classes as prepare_data.py
SEREN_DAY0 = "2023-03-01"
SEREN_STABLE = ("2023-03-13", "2023-08-16")
LOGBIN = 0.05                        # run-time bins: 0.05 decades (12 % wide)


def classify(dur_h):
    return np.where(dur_h <= CLASS_EDGES_H[0], 1, np.where(dur_h <= CLASS_EDGES_H[1], 2, 3))


def acme_jobs(path):
    t = pd.read_csv(path, usecols=["gpu_num", "state", "start_time", "end_time"])
    t = t[t.gpu_num > 0].copy()
    st = pd.to_datetime(t.start_time, utc=True, errors="coerce").dt.tz_convert("Asia/Shanghai")
    en = pd.to_datetime(t.end_time, utc=True, errors="coerce").dt.tz_convert("Asia/Shanghai")
    ok = st.notna() & en.notna() & (en > st)
    t, st, en = t[ok], st[ok], en[ok]
    out = pd.DataFrame({"gpus": t.gpu_num.astype(float).values, "start": st.reset_index(drop=True),
                        "end": en.reset_index(drop=True)})
    out["dur_min"] = (en - st).dt.total_seconds().values / 60.0
    out["cls"] = classify(out.dur_min.values / 60.0)
    return out


def pai_jobs(path):
    t = pd.read_csv(path, usecols=["inst_num", "status", "start_time", "end_time", "plan_gpu"])
    t = t[(t.status == "Terminated") & (t.plan_gpu > 0)].dropna(subset=["start_time", "end_time", "inst_num"])
    t = t[t.end_time > t.start_time]
    out = pd.DataFrame({"gpus": np.round(t.inst_num.values * t.plan_gpu.values / 100.0, 2),
                        "dur_min": (t.end_time.values - t.start_time.values) / 60.0})
    out["cls"] = classify(out.dur_min.values / 60.0)
    return out[out.gpus > 0]


def occupancy(jobs, day0, first, last):
    t0 = pd.Timestamp(day0, tz="Asia/Shanghai")
    a = ((jobs.start - t0).dt.total_seconds() // 60).astype(np.int64).values
    b = ((jobs.end - t0).dt.total_seconds() // 60).astype(np.int64).values
    nb = int(b.max()) + 2
    occ = np.zeros((3, nb))
    for c in (1, 2, 3):
        s = (jobs.cls.values == c) & (a >= 0)
        diff = np.zeros(nb + 1)
        np.add.at(diff, a[s], jobs.gpus.values[s])
        np.add.at(diff, b[s], -jobs.gpus.values[s])
        occ[c - 1] = np.cumsum(diff)[:nb]
    n15 = nb // 15
    occ15 = occ[:, :n15 * 15].reshape(3, n15, 15).mean(axis=2)
    k1 = (pd.Timestamp(first, tz="Asia/Shanghai") - t0).days
    k2 = (pd.Timestamp(last, tz="Asia/Shanghai") - t0).days
    rows = []
    for k in range(k1, k2 + 1):
        dow = (t0 + pd.Timedelta(days=k)).dayofweek
        for s in range(96):
            i = k * 96 + s
            rows.append((k, dow, s, occ15[0, i], occ15[1, i], occ15[2, i]))
    return pd.DataFrame(rows, columns=["day", "dow", "slot", "gpus_c1", "gpus_c2", "gpus_c3"])


def distribution(jobs, source):
    lb = np.floor(np.log10(np.maximum(jobs.dur_min.values, 1e-3)) / LOGBIN).astype(int)
    g = pd.DataFrame({"cls": jobs.cls.values, "gpus": jobs.gpus.values, "bin": lb, "dur": jobs.dur_min.values})
    agg = g.groupby(["cls", "gpus", "bin"]).agg(count=("dur", "size"), dur_min=("dur", "mean")).reset_index()
    agg["source"] = source
    return agg[["source", "cls", "gpus", "dur_min", "count"]]


def class_stats(jobs, source):
    gh = jobs.gpus * jobs.dur_min / 60.0
    rows = []
    for c in (1, 2, 3):
        s = jobs.cls.values == c
        g, d = jobs.gpus.values[s], jobs.dur_min.values[s] / 60.0
        w = gh.values[s]
        rows.append({"source": source, "cls": c, "jobs": int(s.sum()), "gpuh_share": w.sum() / gh.sum(),
                     "mean_gang": g.mean(), "gpuh_weighted_gang": np.sum(w * g) / w.sum(),
                     "gang_weighted_runtime_h": np.sum(g * d) / g.sum(),
                     "mean_residual_h": np.sum(g * d * d) / (2 * np.sum(g * d))})
    return pd.DataFrame(rows)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--seren", required=True)
    ap.add_argument("--kalos", required=True)
    ap.add_argument("--pai", required=True)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    seren = acme_jobs(a.seren)
    kalos = acme_jobs(a.kalos)
    pai = pai_jobs(a.pai)
    occupancy(seren, SEREN_DAY0, *SEREN_STABLE).to_csv(
        os.path.join(a.out, "acme_seren_gpu_occupancy_15min.csv"), index=False, float_format="%.2f")
    dist = pd.concat([distribution(pai, "pai"), distribution(seren, "seren"), distribution(kalos, "kalos")])
    dist.to_csv(os.path.join(a.out, "job_dist.csv"), index=False, float_format="%.3f")
    stats = pd.concat([class_stats(pai, "pai"), class_stats(seren, "seren"), class_stats(kalos, "kalos")])
    stats.to_csv(os.path.join(a.out, "job_class_stats.csv"), index=False, float_format="%.4f")
    print(stats.to_string(index=False))
    print("rows in job_dist.csv:", len(dist))
