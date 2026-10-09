-- Extension queries (run against 01_schema_improved.sql, data restricted to seasons <= 2020
-- to match the scope of the original analysis).
-- Each query is tagged "-- Q<n>: name" so run_extensions.py can export it to results/<n>.csv.

-- Q1: Fastest lap per track in SECONDS (fix: numeric times, Sakhir 2020 outer-layout race excluded)
SELECT c.name AS track,
       MIN(r.fastestLapSeconds) AS fastest_lap_seconds
FROM results r
JOIN races ra   ON r.raceId = ra.raceId
JOIN circuits c ON ra.circuitId = c.circuitId
WHERE r.fastestLapSeconds IS NOT NULL
  AND ra.name <> 'Sakhir Grand Prix'
GROUP BY c.name
ORDER BY fastest_lap_seconds ASC
LIMIT 15;

-- Q2: Constructors by average finish, min 20 races (fix: join to constructors, count DISTINCT races,
--     no join on constructor_results which multiplied rows in the original)
SELECT co.name AS constructor,
       COUNT(DISTINCT r.raceId)         AS races_entered,
       COUNT(*)                         AS entries,
       ROUND(AVG(r.position), 2)        AS avg_finish_position
FROM results r
JOIN constructors co ON r.constructorId = co.constructorId
WHERE r.position IS NOT NULL
GROUP BY co.constructorId, co.name
HAVING COUNT(DISTINCT r.raceId) > 20
ORDER BY avg_finish_position ASC
LIMIT 15;

-- Q3: Constructor wins and win rate (min 100 entries)
SELECT co.name AS constructor,
       COUNT(*) AS entries,
       SUM(CASE WHEN r.positionOrder = 1 THEN 1 ELSE 0 END) AS wins,
       ROUND(100.0 * SUM(CASE WHEN r.positionOrder = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_rate_pct
FROM results r
JOIN constructors co ON r.constructorId = co.constructorId
GROUP BY co.constructorId, co.name
HAVING COUNT(*) >= 100
ORDER BY wins DESC
LIMIT 10;

-- Q4: Era-independent driver ranking: win rate and podium rate (min 50 races)
--     Points systems changed, so win/podium rate avoids the modern-era bias noted in the original.
SELECT d.forename || ' ' || d.surname AS driver,
       COUNT(*) AS races,
       SUM(CASE WHEN r.positionOrder = 1 THEN 1 ELSE 0 END) AS wins,
       ROUND(100.0 * SUM(CASE WHEN r.positionOrder = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_rate_pct,
       ROUND(100.0 * SUM(CASE WHEN r.positionOrder <= 3 THEN 1 ELSE 0 END) / COUNT(*), 1) AS podium_rate_pct
FROM results r
JOIN drivers d ON r.driverId = d.driverId
GROUP BY d.driverId, d.forename, d.surname
HAVING COUNT(*) >= 50
ORDER BY win_rate_pct DESC
LIMIT 10;

-- Q5: Per-decade trend: races, entries and DNF rate
--     "Finished" = status 'Finished' or '+N Lap(s)'. Entries that never started (did not qualify,
--     did not prequalify, withdrew, etc.) are excluded so they do not inflate the DNF rate.
SELECT (ra.year / 10) * 10 AS decade,
       COUNT(DISTINCT ra.raceId) AS races,
       COUNT(*) AS entries,
       ROUND(100.0 * SUM(CASE WHEN s.status = 'Finished' OR s.status LIKE '+% Lap%' THEN 0 ELSE 1 END) / COUNT(*), 1) AS dnf_rate_pct
FROM results r
JOIN races ra  ON r.raceId = ra.raceId
JOIN status s  ON r.statusId = s.statusId
WHERE s.status NOT IN ('Did not qualify','Did not prequalify','Withdrew','Not classified','107% Rule','Excluded','Disqualified')
GROUP BY (ra.year / 10) * 10
ORDER BY decade;

-- Q6: Most common retirement reasons in the 1950s vs the 2010s (reliability improvement)
WITH reasons AS (
    SELECT (ra.year / 10) * 10 AS decade,
           s.status AS reason,
           COUNT(*) AS occurrences,
           RANK() OVER (PARTITION BY (ra.year / 10) * 10 ORDER BY COUNT(*) DESC) AS reason_rank
    FROM results r
    JOIN races ra ON r.raceId = ra.raceId
    JOIN status s ON r.statusId = s.statusId
    WHERE NOT (s.status = 'Finished' OR s.status LIKE '+% Lap%')
      AND s.status NOT IN ('Did not qualify','Did not prequalify','Withdrew','Not classified','107% Rule','Excluded','Disqualified')
      AND (ra.year / 10) * 10 IN (1950, 2010)
    GROUP BY (ra.year / 10) * 10, s.status
)
SELECT decade, reason, occurrences, reason_rank
FROM reasons
WHERE reason_rank <= 5
ORDER BY decade, reason_rank;

-- Q7: Driver with most wins in each decade (window function RANK)
WITH wins AS (
    SELECT (ra.year / 10) * 10 AS decade,
           d.forename || ' ' || d.surname AS driver,
           COUNT(*) AS wins
    FROM results r
    JOIN races ra   ON r.raceId = ra.raceId
    JOIN drivers d  ON r.driverId = d.driverId
    WHERE r.positionOrder = 1
    GROUP BY (ra.year / 10) * 10, d.driverId, d.forename, d.surname
), ranked AS (
    SELECT decade, driver, wins,
           RANK() OVER (PARTITION BY decade ORDER BY wins DESC) AS rnk
    FROM wins
)
SELECT decade, driver, wins FROM ranked WHERE rnk = 1 ORDER BY decade;

-- Q8: Does starting on pole matter? Win rate by grid position (grid 1-5)
SELECT r.grid AS grid_position,
       COUNT(*) AS starts,
       ROUND(100.0 * SUM(CASE WHEN r.positionOrder = 1 THEN 1 ELSE 0 END) / COUNT(*), 1) AS win_rate_pct
FROM results r
WHERE r.grid BETWEEN 1 AND 5
GROUP BY r.grid
ORDER BY r.grid;
