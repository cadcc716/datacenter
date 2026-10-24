# Data preparation

The MATLAB experiments read small derived files in `data/` (already committed).
This folder documents how they were produced from public sources, so they can be rebuilt.

| Derived file | Source | Licence / citation |
|---|---|---|
| `data/pai_gpu_occupancy_15min.csv` | Alibaba PAI GPU cluster trace v2020, `pai_task_table` ([alibaba/clusterdata](https://github.com/alibaba/clusterdata/tree/master/cluster-trace-gpu-v2020)) | cite Weng et al., *MLaaS in the Wild*, NSDI 2022 |
| `data/azure_llm_tokens_15min_local.csv` | Azure LLM inference trace 2024 (code + conversation, 1 week) ([Azure/AzurePublicDataset](https://github.com/Azure/AzurePublicDataset/blob/master/AzureLLMInferenceDataset2024.md)) | CC-BY 4.0; cite Stojkovic et al., *DynamoLLM*, HPCA 2025 |
| `data/weather_suzhou_2024summer.csv` | Open-Meteo historical weather API (ERA5 reanalysis), 31.16 N 120.64 E, 2024-06-15..2024-08-31 | CC-BY 4.0 (Open-Meteo / Copernicus ERA5) |
| `data/weather_suzhou_2024winter.csv`, `data/weather_guian_2024summer.csv` | same API (`fetch_weather.py`), Suzhou winter 2024-11-01..2025-02-28, Gui'an 26.38 N 106.45 E 2024-06-01..2024-08-31 | CC-BY 4.0 |
| `data/acme_seren_gpu_occupancy_15min.csv` | AcmeTrace (Shanghai AI Lab, LLM development, March-August 2023), `trace_seren.csv` ([Qinghao/AcmeTrace](https://huggingface.co/datasets/Qinghao/AcmeTrace)) | CC BY 4.0; cite Hu et al., *Characterization of Large Language Model Development in the Datacenter*, NSDI 2024 |
| `data/job_dist.csv`, `data/job_class_stats.csv` | gang size x run time of the GPU jobs of each runtime class: PAI (`pai_trace.csv` as redistributed in AcmeTrace), Acme Seren and Kalos | as above (PAI: Weng et al., NSDI 2022; Acme: CC BY 4.0, Hu et al., NSDI 2024) |
| `data/wind_rudong_2024summer.csv` | Open-Meteo ERA5 100-m wind speed, Rudong offshore wind area 32.60 N 121.60 E, 2024-06-01..2024-08-31 (`fetch_wind.py`) | CC-BY 4.0 |

## Rebuild

```bash
# 1. PAI trace (about 95 MB compressed); checksums are listed in the trace README
mkdir -p raw/pai && cd raw/pai
curl -O https://aliopentrace.oss-cn-beijing.aliyuncs.com/v2020GPUTraces/pai_task_table.tar.gz
tar -xzf pai_task_table.tar.gz && cd ../..
# 2. Azure LLM inference trace 2024 (about 1.8 GB)
mkdir -p raw/azure && cd raw/azure
for f in code conv; do curl -LO https://github.com/Azure/AzurePublicDataset/releases/download/dataset-llm-2024/AzureLLMInferenceTrace_${f}_1week.csv; done; cd ../..
# 3. Weather
curl -o raw/weather.csv "https://archive-api.open-meteo.com/v1/archive?latitude=31.16&longitude=120.64&start_date=2024-06-15&end_date=2024-08-31&hourly=temperature_2m,shortwave_radiation,relative_humidity_2m&timezone=Asia%2FShanghai&format=csv"
# 4. Derive
pip install numpy pandas
python3 prepare_data.py --pai raw/pai --azure raw/azure --weather raw/weather.csv --out ../data
# 5. LLM-era workload and job-size distributions (Acme, review issue 6f; about 310 MB)
mkdir -p raw/acme && cd raw/acme
for f in trace_seren.csv trace_kalos.csv trace_previous_work/pai_trace.csv; do
  curl -LO https://huggingface.co/datasets/Qinghao/AcmeTrace/resolve/main/data/job_trace/$f; done; cd ../..
python3 -I prepare_acme.py --seren raw/acme/trace_seren.csv --kalos raw/acme/trace_kalos.csv --pai raw/acme/pai_trace.csv --out ../data
# 6. Other weather and the offshore wind speed
python3 fetch_weather.py 31.16 120.64 2024-11-01 2025-02-28 ../data/weather_suzhou_2024winter.csv
python3 fetch_weather.py 26.38 106.45 2024-06-01 2024-08-31 ../data/weather_guian_2024summer.csv
python3 fetch_wind.py 32.60 121.60 2024-06-01 2024-08-31 ../data/wind_rudong_2024summer.csv
```

## Processing choices

* **PAI**: only `Terminated` tasks with `plan_gpu > 0`. Busy GPUs = `inst_num * plan_gpu / 100`, spread
  uniformly over `[start_time, end_time]` at 1-min resolution, averaged to 15 min. Time of day uses
  UTC+8 (the trace keeps the original time of day in that zone). Tasks are split by runtime into
  C1 (<= 1 h), C2 (1-12 h), C3 (> 12 h). Days 7-64 are kept (the first and last days of the trace are
  truncated). Shares of GPU-hours: C1 6.6 %, C2 43.9 %, C3 49.5 %.
* **Azure LLM**: requests aggregated to 15 min; load index = context + generated tokens, normalised per
  service. The trace is in UTC and peaks at 13-21 UTC (US business hours), so it is shifted to UTC-4 and
  its *local-time shape* is used for the data centre's inference demand (stated as an assumption).
* **Weather**: hourly 2 m temperature and GHI; GHI is the mean of the preceding hour and is centred on
  the half hour before interpolation to 15 min. PV power uses a PVWatts-v5-type model.
* **Acme (LLM era)**: every GPU job of `trace_seren.csv` that ran (`gpu_num > 0`, valid start and end),
  whatever its final state: most GPU-hours of pretraining belong to jobs that users cancelled
  (Hu et al., NSDI 2024), and they drew power while running. Times are local (UTC+8; Kalos is converted
  from UTC). Same runtime classes and 1-min / 15-min aggregation as PAI; stable days 2023-03-13..2023-08-16;
  `day` counts from 2023-03-01. Shares of GPU-hours: C1 5.3 %, C2 14.2 %, C3 80.5 % (PAI 6.6 / 43.9 / 49.5 %).
* **Job-size distributions**: for each source and class the GPU jobs are pooled by gang size and by run time
  in logarithmic bins of 0.05 decades (bin mean kept). `job_class_stats.csv` gives the share of
  GPU-hours, mean and GPU-hour-weighted gang size, the gang-weighted mean run time (the rigid-job recovery
  time constant `par.it.rec_tau`) and the mean residual run time of a busy GPU.
* **Wind**: hourly 100-m wind speed (instantaneous), interpolated to 15 min; IEA 15-MW reference turbine
  curve (cut-in 3 m/s, rated 10.59 m/s, cut-out 25 m/s, cubic in between) and a farm efficiency of 0.9
  (`load_inputs.m`, `par.wind`). Summer capacity factor 0.35 (0.40-0.43 in 17-22 h).
