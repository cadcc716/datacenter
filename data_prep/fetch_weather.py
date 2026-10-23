#!/usr/bin/env python3
"""Download hourly ERA5 weather (Open-Meteo archive API, CC-BY 4.0) in the format of
data/weather_suzhou_2024summer.csv: time (Asia/Shanghai), temp_c, ghi_wm2, rh_pct.

Usage: python3 fetch_weather.py LAT LON START END OUT.csv
Cases used in the paper (Exp18, season / climate generalisation):
  Suzhou-Wujiang winter : 31.16 120.64 2024-11-01 2025-02-28 weather_suzhou_2024winter.csv
  Gui'an (Guizhou) hub  : 26.38 106.45 2024-06-01 2024-08-31 weather_guian_2024summer.csv
"""
import json, sys, urllib.request
import pandas as pd

lat, lon, start, end, out = sys.argv[1:6]
url = ("https://archive-api.open-meteo.com/v1/archive?latitude=%s&longitude=%s&start_date=%s&end_date=%s"
       "&hourly=temperature_2m,shortwave_radiation,relative_humidity_2m&timezone=Asia%%2FShanghai" % (lat, lon, start, end))
with urllib.request.urlopen(url, timeout=120) as r:
    h = json.load(r)["hourly"]
w = pd.DataFrame({"time": h["time"], "temp_c": h["temperature_2m"], "ghi_wm2": h["shortwave_radiation"],
                  "rh_pct": h["relative_humidity_2m"]})
w = w.dropna()
w.to_csv(out, index=False)
print("wrote", out, len(w), "rows,", w.time.iloc[0], "..", w.time.iloc[-1], "Tmax %.1f Tmin %.1f" % (w.temp_c.max(), w.temp_c.min()))
