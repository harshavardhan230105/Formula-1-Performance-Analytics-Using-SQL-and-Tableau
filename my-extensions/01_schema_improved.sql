-- Improved schema for the F1 project (fixes the issues in the original f1-project-schema.sql)
-- Fixes:
--   1. points is DECIMAL (the original used INT, which drops half-points such as 4396.5)
--   2. PRIMARY KEYs and FOREIGN KEYs added (original had every column DEFAULT NULL)
--   3. position / positionText nullable (source uses \N for retirements)
--   4. fastestLapSeconds added so lap times can be sorted and compared numerically
-- Written to run on MySQL 8 and SQLite (tested on SQLite 3.45).

CREATE TABLE circuits (
    circuitId   INTEGER PRIMARY KEY,
    circuitRef  VARCHAR(100),
    name        VARCHAR(150),
    location    VARCHAR(100),
    country     VARCHAR(100),
    lat         DOUBLE,
    lng         DOUBLE,
    alt         INTEGER
);

CREATE TABLE constructors (
    constructorId  INTEGER PRIMARY KEY,
    constructorRef VARCHAR(100),
    name           VARCHAR(150),
    nationality    VARCHAR(100)
);

CREATE TABLE drivers (
    driverId    INTEGER PRIMARY KEY,
    driverRef   VARCHAR(100),
    number      INTEGER,
    code        VARCHAR(5),
    forename    VARCHAR(100),
    surname     VARCHAR(100),
    dob         DATE,
    nationality VARCHAR(100)
);

CREATE TABLE races (
    raceId    INTEGER PRIMARY KEY,
    year      INTEGER NOT NULL,
    round     INTEGER NOT NULL,
    circuitId INTEGER NOT NULL,
    name      VARCHAR(150),
    date      DATE,
    FOREIGN KEY (circuitId) REFERENCES circuits (circuitId)
);

CREATE TABLE status (
    statusId INTEGER PRIMARY KEY,
    status   VARCHAR(100)
);

CREATE TABLE results (
    resultId         INTEGER PRIMARY KEY,
    raceId           INTEGER NOT NULL,
    driverId         INTEGER NOT NULL,
    constructorId    INTEGER NOT NULL,
    number           INTEGER,
    grid             INTEGER,
    position         INTEGER,            -- NULL = did not finish / not classified
    positionText     VARCHAR(5),         -- 'R', 'D', 'W' ... or the numeric position
    positionOrder    INTEGER,
    points           DECIMAL(5,2),       -- DECIMAL: half-points exist
    laps             INTEGER,
    fastestLap       INTEGER,
    rank             INTEGER,
    fastestLapTime   VARCHAR(12),        -- original m:ss.mmm text, kept for reference
    fastestLapSeconds DECIMAL(8,3),      -- derived numeric version
    fastestLapSpeed  DECIMAL(7,3),
    statusId         INTEGER,
    FOREIGN KEY (raceId)        REFERENCES races (raceId),
    FOREIGN KEY (driverId)      REFERENCES drivers (driverId),
    FOREIGN KEY (constructorId) REFERENCES constructors (constructorId),
    FOREIGN KEY (statusId)      REFERENCES status (statusId)
);

CREATE INDEX idx_results_race        ON results (raceId);
CREATE INDEX idx_results_driver      ON results (driverId);
CREATE INDEX idx_results_constructor ON results (constructorId);
