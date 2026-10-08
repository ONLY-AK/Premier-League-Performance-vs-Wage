"""Load the project data into SQLite and run the SQL analysis.

Run the notebook first (it writes data/output/tableau_players.csv), then:
    python build_db.py

Creates data/premier_league.db, prints each report in sql/analysis.sql,
and writes data/output/sql_club_efficiency.csv for Tableau.
"""
import re
import sqlite3
import pandas as pd

DB = "data/premier_league.db"
conn = sqlite3.connect(DB)

# Raw tables
pd.read_csv("data/raw/player_stats_2025_26.csv").to_sql("stats", conn, if_exists="replace", index=False)
pd.read_csv("data/raw/player_salaries.csv").to_sql("wages", conn, if_exists="replace", index=False)
(pd.read_csv("data/raw/player_roles_transfermarkt.csv")
   .drop_duplicates("player_name")
   .to_sql("roles", conn, if_exists="replace", index=False))

# Scored results from the notebook, with SQL-friendly column names
players = pd.read_csv("data/output/tableau_players.csv", encoding="utf-8-sig").rename(columns={
    "Player": "player", "Club": "club", "Role": "role", "Minutes": "minutes",
    "Performance Score": "perf_score", "Annual Wage": "annual_wage",
    "Expected Wage": "expected_wage", "Pay Ratio": "pay_ratio", "Verdict": "verdict",
})
players.to_sql("players", conn, if_exists="replace", index=False)

# Views first, then each "-- @report" query
sql = open("sql/analysis.sql").read()
setup, *reports = re.split(r"^-- @report ", sql, flags=re.M)
conn.executescript(setup)

pd.set_option("display.width", 200)
for block in reports:
    title, query = block.split("\n", 1)
    print(f"\n=== {title} ===")
    print(pd.read_sql(query, conn).to_string(index=False))

# Export one SQL result for Tableau
club = re.search(r"Club wage efficiency.*?\n(.*?;)", sql, flags=re.S).group(1)
pd.read_sql(club, conn).to_csv("data/output/sql_club_efficiency.csv", index=False)
conn.close()
print(f"\nSaved {DB} and data/output/sql_club_efficiency.csv")
