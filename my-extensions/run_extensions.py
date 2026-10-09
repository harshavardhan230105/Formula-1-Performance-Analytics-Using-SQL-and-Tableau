"""Load the F1 CSVs into SQLite using the improved schema, run the queries, export CSVs + charts.

Usage:  python run_extensions.py <folder with Ergast/Kaggle F1 CSVs> [last_year=2020]
"""
import csv
import re
import sqlite3
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).parent
data_dir = Path(sys.argv[1])
last_year = int(sys.argv[2]) if len(sys.argv) > 2 else 2020


def clean(v):
    return None if v in ("\\N", "") else v


def lap_seconds(t):
    """'1:05.619' -> 65.619"""
    if not t:
        return None
    m, s = t.split(":")
    return round(int(m) * 60 + float(s), 3)


def rows(name):
    with open(data_dir / name, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys = ON")
db.executescript((HERE / "01_schema_improved.sql").read_text())


def load(table, filename, cols, keep=lambda r: True):
    n = 0
    ph = ",".join("?" * len(cols))
    for r in rows(filename):
        if keep(r):
            db.execute(f"INSERT INTO {table} ({','.join(cols)}) VALUES ({ph})",
                       [clean(r[c]) for c in cols])
            n += 1
    return n


load("circuits", "circuits.csv", ["circuitId", "circuitRef", "name", "location", "country", "lat", "lng", "alt"])
load("constructors", "constructors.csv", ["constructorId", "constructorRef", "name", "nationality"])
load("drivers", "drivers.csv", ["driverId", "driverRef", "number", "code", "forename", "surname", "dob", "nationality"])
load("status", "status.csv", ["statusId", "status"])
load("races", "races.csv", ["raceId", "year", "round", "circuitId", "name", "date"],
     keep=lambda r: int(r["year"]) <= last_year)
valid = {r[0] for r in db.execute("SELECT raceId FROM races")}

cols = ["resultId", "raceId", "driverId", "constructorId", "number", "grid", "position", "positionText",
        "positionOrder", "points", "laps", "fastestLap", "rank", "fastestLapTime", "fastestLapSpeed", "statusId"]
for r in rows("results.csv"):
    if int(r["raceId"]) in valid:
        vals = [clean(r[c]) for c in cols]
        db.execute(f"INSERT INTO results ({','.join(cols)}, fastestLapSeconds) VALUES ({','.join('?' * len(cols))}, ?)",
                   vals + [lap_seconds(clean(r["fastestLapTime"]))])
db.commit()

print("Loaded:", {t: db.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                  for t in ["circuits", "constructors", "drivers", "races", "results"]})
print("FK violations:", db.execute("PRAGMA foreign_key_check").fetchall())

# ---- validation of the ORIGINAL analysis (does the author's output reproduce?) ----
checks = {
    "most_races": """SELECT d.forename||' '||d.surname, COUNT(*) FROM results r JOIN drivers d USING(driverId)
                     GROUP BY d.driverId ORDER BY 2 DESC LIMIT 3""",
    "most_points": """SELECT d.forename||' '||d.surname, SUM(r.points) FROM results r JOIN drivers d USING(driverId)
                      GROUP BY d.driverId ORDER BY 2 DESC LIMIT 3""",
    "best_avg_finish_min20": """SELECT d.surname, ROUND(AVG(r.position),3), COUNT(*) FROM results r JOIN drivers d USING(driverId)
                      GROUP BY d.driverId HAVING COUNT(*)>20 ORDER BY 2 LIMIT 3""",
    "worst_avg_finish_min20": """SELECT d.surname, ROUND(AVG(r.position),3), COUNT(*) FROM results r JOIN drivers d USING(driverId)
                      GROUP BY d.driverId HAVING COUNT(*)>20 ORDER BY 2 DESC LIMIT 3""",
    "fastest_lap_ex_sakhir": """SELECT d.surname, r.fastestLapTime, c.name FROM results r JOIN races ra USING(raceId)
                      JOIN drivers d USING(driverId) JOIN circuits c ON ra.circuitId=c.circuitId
                      WHERE r.fastestLapSeconds IS NOT NULL AND ra.raceId<>1046 ORDER BY r.fastestLapSeconds LIMIT 3""",
}
print("\n=== Reproduction of original findings ===")
for k, q in checks.items():
    print(k, db.execute(q).fetchall())

# ---- run extension queries ----
sql = (HERE / "02_extension_queries.sql").read_text()
parts = re.split(r"^-- (Q\d+): (.*)$", sql, flags=re.M)
out = {}
(HERE / "results").mkdir(exist_ok=True)
(HERE / "charts").mkdir(exist_ok=True)
for i in range(1, len(parts), 3):
    qid, title, body = parts[i], parts[i + 1], parts[i + 2]
    body = "\n".join(l for l in body.splitlines() if not l.strip().startswith("--")).strip()
    cur = db.execute(body)
    header = [c[0] for c in cur.description]
    data = cur.fetchall()
    out[qid] = (title, header, data)
    with open(HERE / "results" / f"{qid}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(data)
    print(f"\n=== {qid}: {title} ===")
    print(header)
    for row in data:
        print(row)


def bar(qid, label_i, val_i, title, xlabel, fname, color, reverse=True):
    _, _, data = out[qid]
    labels = [str(r[label_i]) for r in data]
    vals = [r[val_i] for r in data]
    if reverse:
        labels, vals = labels[::-1], vals[::-1]
    plt.figure(figsize=(9, 5))
    plt.barh(labels, vals, color=color)
    plt.title(title)
    plt.xlabel(xlabel)
    plt.tight_layout()
    plt.savefig(HERE / "charts" / fname, dpi=130)
    plt.close()


bar("Q1", 0, 1, f"Fastest lap by track (seconds, to {last_year}; Sakhir 2020 excluded)", "seconds", "q1_fastest_lap_by_track.png", "#c0392b")
bar("Q2", 0, 3, "Constructors: average finish position (min 20 races)", "avg finish (lower = better)", "q2_constructor_avg_finish.png", "#2c3e50")
bar("Q4", 0, 3, "Win rate % (min 50 races) - era independent", "% of starts won", "q4_win_rate.png", "#d4a017")

_, _, d5 = out["Q5"]
plt.figure(figsize=(8, 4.5))
plt.plot([r[0] for r in d5], [r[3] for r in d5], marker="o", color="#8e44ad")
plt.title("DNF rate by decade (%)")
plt.ylabel("% of entries not finishing")
plt.xlabel("decade")
plt.grid(alpha=.3)
plt.tight_layout()
plt.savefig(HERE / "charts" / "q5_dnf_rate_by_decade.png", dpi=130)
plt.close()

_, _, d8 = out["Q8"]
plt.figure(figsize=(7, 4.5))
plt.bar([str(r[0]) for r in d8], [r[2] for r in d8], color="#16a085")
plt.title("Win rate % by starting grid slot")
plt.xlabel("grid position")
plt.ylabel("win rate %")
plt.tight_layout()
plt.savefig(HERE / "charts" / "q8_grid_vs_win_rate.png", dpi=130)
plt.close()
print("\nCharts and CSVs written.")
