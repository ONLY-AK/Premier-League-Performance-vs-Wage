-- Premier League wages vs performance: SQL analysis
-- Tables (loaded by build_db.py):
--   stats    raw match stats, 2025-26
--   wages    raw wage estimates, 2024-25
--   roles    Transfermarkt positions
--   players  scored results from the notebook (one row per regular starter)

-- 1. Join raw stats to Transfermarkt roles and keep regular starters
DROP VIEW IF EXISTS starters;
CREATE VIEW starters AS
SELECT s.player_name,
       s.team_name,
       COALESCE(r.sub_position, s.position) AS position,
       s.minutesPlayed,
       ROUND(s.goals * 90.0 / s.minutesPlayed, 2)         AS goals_per90,
       ROUND(s.expectedGoals * 90.0 / s.minutesPlayed, 2) AS xg_per90
FROM stats s
LEFT JOIN roles r ON r.player_name = s.player_name
WHERE s.minutesPlayed >= 1500;

-- 2. Rank players within their role by performance and by wage (window functions)
DROP VIEW IF EXISTS ranked;
CREATE VIEW ranked AS
SELECT player, club, role, minutes, perf_score, annual_wage, expected_wage, pay_ratio,
       RANK() OVER (PARTITION BY role ORDER BY perf_score DESC)  AS perf_rank_in_role,
       RANK() OVER (PARTITION BY role ORDER BY annual_wage DESC) AS wage_rank_in_role,
       COUNT(*) OVER (PARTITION BY role)                         AS players_in_role
FROM players;

-- 3. Rank gap: positive = paid higher in his role than he performs
DROP VIEW IF EXISTS rank_gap;
CREATE VIEW rank_gap AS
SELECT *, perf_rank_in_role - wage_rank_in_role AS rank_gap
FROM ranked;

-- @report Top 10 overpaid (actual / expected wage)
SELECT player, club, role, ROUND(pay_ratio, 2) AS pay_ratio,
       annual_wage, ROUND(expected_wage) AS expected_wage
FROM players
WHERE verdict = 'Overpaid'
ORDER BY pay_ratio DESC
LIMIT 10;

-- @report Top 10 underpaid
SELECT player, club, role, ROUND(pay_ratio, 2) AS pay_ratio,
       annual_wage, ROUND(expected_wage) AS expected_wage
FROM players
WHERE verdict = 'Underpaid'
ORDER BY pay_ratio ASC
LIMIT 10;

-- @report Best performer in each role (CTE + window function)
WITH best AS (
    SELECT player, club, role, ROUND(perf_score, 2) AS perf_score, annual_wage,
           ROW_NUMBER() OVER (PARTITION BY role ORDER BY perf_score DESC) AS rn
    FROM players
)
SELECT player, club, role, perf_score, annual_wage
FROM best
WHERE rn = 1
ORDER BY perf_score DESC;

-- @report Pay vs performance by role
SELECT role,
       COUNT(*)                          AS players,
       ROUND(AVG(annual_wage) / 1e6, 1)  AS avg_wage_m,
       ROUND(AVG(perf_score), 2)         AS avg_perf_score,
       SUM(verdict = 'Overpaid')         AS overpaid,
       SUM(verdict = 'Underpaid')        AS underpaid
FROM players
GROUP BY role
ORDER BY avg_wage_m DESC;

-- @report Club wage efficiency: total spent vs total expected
SELECT club,
       COUNT(*)                                              AS players,
       ROUND(SUM(annual_wage) / 1e6, 1)                      AS wages_m,
       ROUND(SUM(expected_wage) / 1e6, 1)                    AS expected_m,
       ROUND(SUM(annual_wage) * 1.0 / SUM(expected_wage), 2) AS club_pay_ratio
FROM players
GROUP BY club
HAVING COUNT(*) >= 4
ORDER BY club_pay_ratio DESC;

-- @report Biggest rank gaps within a role
SELECT player, club, role, perf_rank_in_role, wage_rank_in_role, rank_gap
FROM rank_gap
ORDER BY ABS(rank_gap) DESC
LIMIT 10;
