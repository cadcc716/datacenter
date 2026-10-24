#!/usr/bin/env python3
"""Download hourly ERA5 100-m wind speed (Open-Meteo archive API, CC-BY 4.0) for the green-power
direct-connection case (M5): time (Asia/Shanghai), ws100_ms.

Usage: python3 fetch_wind.py LAT LON START END OUT.csv
Case used in the paper (Exp21):
  Rudong offshore wind area, Jiangsu : 32.60 121.60 2024-06-01 2024-08-31 wind_rudong_2024summer.csv
"""
import json
import sys
import urllib.request

import pandas as pd

lat, lon, start, end, out = sys.argv[1:6]
url = ("https://archive-api.open-meteo.com/v1/archive?latitude=%s&longitude=%s&start_date=%s&end_date=%s"
       "&hourly=wind_speed_100m&wind_speed_unit=ms&timezone=Asia%%2FShanghai" % (lat, lon, start, end))
with urllib.request.urlopen(url, timeout=120) as r:
    h = json.load(r)["hourly"]
w = pd.DataFrame({"time": h["time"], "ws100_ms": h["wind_speed_100m"]}).dropna()
w.to_csv(out, index=False)
print("wrote", out, len(w), "rows,", w.time.iloc[0], "..", w.time.iloc[-1],
      "mean %.2f m/s, max %.1f m/s" % (w.ws100_ms.mean(), w.ws100_ms.max()))
