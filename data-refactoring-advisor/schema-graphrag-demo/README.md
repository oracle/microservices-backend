# SchemaRAG Demo

Workload-derived graph annotations on database table metadata that dramatically improve NL2SQL accuracy over standard vector RAG.

---

## Table of Contents

- [The Core Idea](#the-core-idea)
- [Why Your NL2SQL Project Probably Struggled — and What Actually Fixes It](#why-your-nl2sql-project-probably-struggled--and-what-actually-fixes-it)
- [Quick Start](#quick-start)
  - [Prerequisites](#prerequisites)
  - [Setup](#setup)
  - [Configure `.env`](#configure-env)
  - [Database Setup](#database-setup)
  - [Build Pipeline](#build-pipeline)
  - [Step 1 — seed (~2 minutes)](#step-1--seed-2-minutes)
  - [Step 2 — sts (~1 minute)](#step-2--sts-1-minute)
  - [Step 3 — extract (~15 seconds)](#step-3--extract-15-seconds)
  - [Step 4 — community (~1 second)](#step-4--community-1-second)
  - [Step 5 — joinpaths (~15 seconds)](#step-5--joinpaths-15-seconds)
  - [Step 6 — annotate (~25 seconds)](#step-6--annotate-25-seconds)
  - [CLI Spot-Checks](#cli-spot-checks)
- [Run the Demo](#run-the-demo)
- [How the Pipeline Works](#how-the-pipeline-works)
- [UNIV\_EMBEDDINGS — The Central Knowledge Table](#univ_embeddings--the-central-knowledge-table)
- [The Annotation Types](#the-annotation-types)
- [Why Do Annotations Work So Well?](#why-do-annotations-work-so-well)
- [Schema — ~70 University Tables, 10 Communities](#schema--70-university-tables-10-communities)
- [Project Structure](#project-structure)
- [Enterprise Deployment Pattern — LLM-Agnostic Annotation Service](#enterprise-deployment-pattern--llm-agnostic-annotation-service)
- [Your XX\_ Tables Are Where Other NL2SQL Tools Give Up](#your-xx_-tables-are-where-other-nl2sql-tools-give-up)
- [When Annotations Beat DDL Alone — The 12 Scenarios](#when-annotations-beat-ddl-alone--the-12-scenarios)
- [Technology Stack](#technology-stack)
- [Future Enhancements](#future-enhancements)

---

## The Core Idea

Microsoft's GraphRAG enriches *document chunks* with graph-derived community context before embedding. SchemaRAG does the same for *database table metadata* — enriching each table's description with workload-proven join paths, affinity scores, and community membership before embedding. The result: NL2SQL queries that understand which bridge tables to include without custom model training.

### Side-by-side demo

| | Standard RAG | SchemaRAG |
|---|---|---|
| **Query** | "Which students receiving merit scholarships have a SAP probation standing on record?" | ← same |
| **Tables retrieved** | STU_MST, ACAD_STAT_TBL, SCHOLARSHIP_POOL | + STU_FA_XREF, FINANCIAL_AID_APPLICATION, FA_AWARD_HISTORY |
| **Result** | SQL error (ORA-00904: invented column `"XREF"."STU_ID"`) | 198 students flagged |

---

## Why Your NL2SQL Project Probably Struggled — and What Actually Fixes It

If you have already tried Natural Language SQL against your Oracle database, you likely encountered a familiar pattern: the demos looked promising, but production queries were unreliable. The LLM would confidently generate SQL that referenced the wrong columns, missed critical join tables, or returned zero rows with no explanation. Your team spent weeks writing prompt rules. Things improved slightly. Then a new query type broke everything again.

This is not a model quality problem. It is a context problem.

**LLMs are not poor at SQL. They are poor at guessing how *your* database is structured.**

Every enterprise Oracle database has accumulated years of implicit knowledge — which tables are the true hubs of activity, which bridge tables must always be included in certain joins, which column formats are the semantic keys that connect student records to financial aid applications to billing accounts. None of that knowledge is visible in DDL alone. A model reading your `CREATE TABLE` statements sees column names and data types. It does not see that `ENRL_REC` appears in 70% of your production RegistrarCore queries, or that skipping `STU_FA_XREF` in a financial aid query silently produces a SQL error instead of raising a warning.

Standard vector RAG makes this worse, not better. It retrieves tables that *sound* relevant to the question — and confidently misses the bridge tables that make the joins work.

### What SchemaRAG does differently

SchemaRAG reads two sources of knowledge that already exist in your Oracle database and combines them into something no LLM has seen before: **a workload-derived annotation layer that encodes how your database actually behaves.**

**Source 1 — Your SQL Tuning Sets (workload history)**

Oracle's `DBMS_SQLTUNE` has been capturing your production query patterns for years. SchemaRAG parses that history with a graph algorithm, counts how often every pair of tables appears together in a JOIN, and derives an affinity score for each pair. Tables that are joined together thousands of times in production get HIGH affinity. Tables that never appear together get EXCLUDED. This is not a guess — it is a measurement of your actual workload.

**Source 2 — Your data dictionary (`COMMENT ON COLUMN`)**

Oracle DBAs have been writing column comments since Oracle 7. Most enterprise databases have partial documentation already sitting in `ALL_COL_COMMENTS`, unused at runtime. SchemaRAG reads it and includes it in the context the LLM sees — so when a column's name carries no semantic signal (`SFX_FA_NBR` in `STU_FA_XREF`), a column comment explaining its format (`FA0000001 — use TO_NUMBER(SUBSTR(SFX_FA_NBR,3)) to join to FINANCIAL_AID_APPLICATION.FA_ID`) tells the LLM exactly how to write the join expression instead of guessing.

**What the graph adds**

Affinity scores alone are not enough. SchemaRAG runs Louvain community detection on the affinity graph to discover which tables cluster together into functional domains — the equivalent of RegistrarCore, FinancialAid, Bursar — without being told. It then identifies:

- **Hub tables** — the tables that appear at the center of multiple communities, the ones that connect everything. Miss a hub and your query returns nothing.
- **Bridge tables** — the tables that sit between communities and make cross-domain queries possible. These are the tables standard RAG consistently misses.
- **Proven join paths** — multi-hop chains extracted from the workload: `STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK`. Not inferred. Measured.

All of this is encoded into bracket-triple annotations appended to each table's metadata document:

```
[STU_FA_XREF BRIDGES RegistrarCore:FinancialAid]
[ENRL_REC IS_HUB degree:5.0]
[ENRL_REC JOINS_PATH STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK]
[STU_FA_XREF MEDIUM_AFFINITY FINANCIAL_AID_APPLICATION:0.21]
```

When the LLM reads these annotations alongside your query, it does not have to guess which tables to include. The annotations tell it — in a structured format derived from your own production workload — exactly which join paths have been proven to work.

### What this means for your existing Oracle database

You do not need to retrain a model. You do not need to rebuild your schema. You do not need a data science team.

Your SQL Tuning Sets already capture the workload intelligence. Your `COMMENT ON COLUMN` entries already hold the semantic documentation. Your Oracle database already has everything SchemaRAG needs.

The pipeline reads your existing assets, builds the graph, generates the annotations, and stores them in a single table — `UNIV_EMBEDDINGS` — that any LLM-based NL2SQL application can query. From that point forward, every natural language query your users run is grounded in the institutional knowledge your DBAs and workload have accumulated over years.

**The NL2SQL projects that struggled did so because they gave the LLM a schema and asked it to guess. SchemaRAG gives the LLM a schema and the proven knowledge of how that schema behaves.**

---

## Quick Start

### Prerequisites

- Oracle Autonomous Database (pre-provisioned, wallet downloaded)
- Anthropic API key (Claude — for NL2SQL generation)
- Python 3.11+
- [SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) (Oracle command-line SQL client — used to run DDL against ADB)

### Setup

```bash
cd schema-graphrag-demo
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

### Configure `.env`

Copy the example and fill in your values before running any pipeline commands:

```bash
cp .env.example .env
```

**ADB connection**

| Variable | What to set |
|---|---|
| `ADB_DSN` | Service name from your wallet's `tnsnames.ora` — typically `yourdbname_high` |
| `ADB_USER` | `UNIV_SCHEMARAG` — created by the DDL in Database Setup below |
| `ADB_PASSWORD` | Password you choose for the UNIV_SCHEMARAG user — must match `DEFINE ADB_PASSWORD=` when running the DDL |
| `ADB_WALLET_LOCATION` | Full path to the **extracted** wallet directory (not the .zip file) |
| `ADB_WALLET_PASSWORD` | Wallet download password set in the OCI console when you downloaded the wallet |
| `ADB_ADMIN_USER` | `admin` (default for ADB) |
| `ADB_ADMIN_PASSWORD` | Your ADB ADMIN password — used for the STS cursor-cache load step |

For a local Oracle Free Docker container started with:

```bash
docker run -d -p 1521:1521 -e ORACLE_PASSWORD=Welcome12345 gvenzl/oracle-free:latest-faststart
```

use:

```env
ADB_DSN=localhost:1521/FREEPDB1
ADB_USER=UNIV_SCHEMARAG
ADB_PASSWORD=Welcome12345
ADB_WALLET_LOCATION=
ADB_WALLET_PASSWORD=
ADB_ADMIN_USER=system
ADB_ADMIN_PASSWORD=Welcome12345
```

**LLM configuration**

The pipeline defaults to Claude (Opus for SQL generation, Haiku for table retrieval) but works with any LLM — swap in GPT-4, Gemini, or a local model by updating these variables and the corresponding client code in `src/nl2sql/claude_client_ai.py`.

| Variable | Default | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | API key for Claude (console.anthropic.com) |
| `ANTHROPIC_MODEL` | `claude-opus-4-6` | Model used for SQL generation |
| `ANTHROPIC_RETRIEVAL_MODEL` | `claude-haiku-4-5-20251001` | Model used for table retrieval filtering |

**Pipeline tuning** — leave all defaults unless you understand the affinity graph:

The affinity score between two tables is a **Jaccard-based coefficient** computed from the SQL Tuning Set. For every pair of tables that appear together in at least one JOIN, SchemaRAG counts two things: how many *distinct query templates* join those tables (static co-occurrence), and how many *total executions* those queries had (dynamic weight). The two counts are combined and normalised to a 0.0–1.0 score. A score of 1.0 means every query in the workload joins those two tables; a score near 0.0 means they appear together only occasionally. The three threshold variables below define where that continuous score is bucketed into the HIGH / MEDIUM / LOW / EXCLUDED annotation labels that appear in `augmented_text`.

| Variable | Default | Purpose |
|---|---|---|
| `AFFINITY_HIGH_THRESHOLD` | `0.6` | Jaccard score floor for HIGH affinity annotation |
| `AFFINITY_MEDIUM_THRESHOLD` | `0.3` | Jaccard score floor for MEDIUM |
| `AFFINITY_LOW_THRESHOLD` | `0.1` | Jaccard score floor for LOW; pairs below this are excluded |
| `JOIN_PATH_MIN_OCCURRENCES` | `5` | Minimum times a join chain must appear to be recorded |
| `HUB_DEGREE_THRESHOLD` | `4` | Edge degree at which a table is flagged IS_HUB |
| `TOP_K_RETRIEVAL` | `8` | Tables returned per similarity search |

### Database Setup

Use one of the following setup paths before running the workload pipeline.

**Option A — ADB / SQLcl setup**

Run as ADMIN using SQLcl:

Start SQLcl from your terminal:

```bash
sql /nolog
```

Then run the following commands **at the SQLcl `SQL>` prompt**:

```sql
-- Point SQLcl at your ADB wallet (.zip file, not the extracted directory)
set cloudconfig /path/to/Wallet_yourdb.zip

-- Connect as ADMIN
connect admin@yourdb_high

-- Set the password for the UNIV_SCHEMARAG user (must match ADB_PASSWORD in your .env)
DEFINE ADB_PASSWORD=Welcome12345

-- Run the DDL — creates UNIV_SCHEMARAG user + ~70 tables
@sql/university/01_create_schema.sql
```

> Replace `/path/to/Wallet_yourdb.zip` with the full path to your wallet zip file, `yourdb_high` with your ADB service name (found inside the wallet's `tnsnames.ora`), and `Welcome12345` with the value of `ADB_PASSWORD` in your `.env` file.

After this SQLcl setup, continue with the build pipeline below.

**Option B — Python setup for local Docker or fresh databases**

If you want the Python pipeline to create the schema owner and tables from your `.env` settings, run:

```bash
python -m src.pipeline.build_pipeline --schema university --step user
python -m src.pipeline.build_pipeline --schema university --step ddl
```

The `user` step connects as `ADB_ADMIN_USER` and creates `UNIV_SCHEMARAG` plus the required grants. On local Oracle Free Docker, if `system` cannot grant package privileges directly, the step retries those grants as `SYSDBA` using the same `ADB_ADMIN_PASSWORD`. The `ddl` step connects as `UNIV_SCHEMARAG` and creates the university schema tables. These steps are useful for a brand-new local Oracle Docker container.

### Build Pipeline

After Database Setup, each build step can be run individually or all at once:

```bash
# Full build pipeline (seed, workload, graph extraction, annotations)
python -m src.pipeline.build_pipeline --schema university

# Individual steps
python -m src.pipeline.build_pipeline --schema university --step user       # create schema user + grants
python -m src.pipeline.build_pipeline --schema university --step ddl        # create schema tables
python -m src.pipeline.build_pipeline --schema university --step seed
python -m src.pipeline.build_pipeline --schema university --step sts
python -m src.pipeline.build_pipeline --schema university --step extract
python -m src.pipeline.build_pipeline --schema university --step community
python -m src.pipeline.build_pipeline --schema university --step joinpaths
python -m src.pipeline.build_pipeline --schema university --step annotate

# Coarse skips
python -m src.pipeline.build_pipeline --schema university --skip-seed       # data already loaded
python -m src.pipeline.build_pipeline --schema university --skip-workload   # re-annotate only
```

---

### Step 1 — `seed` (~2 minutes)

Populates ~100k rows across all ~70 university tables using Faker (seed=42) in FK dependency order.

**What it does:** Inserts deterministic synthetic data for Westfield University including two demo-critical cohorts:
- Pending grade-change exceptions with positive GPA impact (used in Scenario 1)
- Pending medical withdrawal exceptions not yet approved (used in Scenario 2)

**Validate success** — run in SQLcl as UNIV_SCHEMARAG:

```sql
SELECT 'STU_MST'             AS tbl, COUNT(*) AS cnt FROM stu_mst
UNION ALL SELECT 'ENRL_REC',            COUNT(*) FROM enrl_rec
UNION ALL SELECT 'GRD_HIST',            COUNT(*) FROM grd_hist
UNION ALL SELECT 'FA_AWARD_HISTORY',    COUNT(*) FROM fa_award_history
UNION ALL SELECT 'BURS_CHARGE_LINE',    COUNT(*) FROM burs_charge_line
UNION ALL SELECT 'ACAD_EXCEPTION_WRK',  COUNT(*) FROM acad_exception_wrk
ORDER BY cnt DESC;
```

Expected: STU_MST=8,000 / ENRL_REC=~33,000 / GRD_HIST=~28,000 / BURS_CHARGE_LINE=~24,000 / ACAD_EXCEPTION_WRK=~2,000 / FA_AWARD_HISTORY=~1,300

Validate demo cohorts:
```sql
-- Pending grade changes with positive GPA impact (Scenario 1)
SELECT COUNT(*) FROM acad_exception_wrk
WHERE aew_type_cd = 'GRD_CHNG' AND aew_stat_cd = 'PEND' AND aew_impact_gpa > 0;

-- Pending medical withdrawals not yet approved (Scenario 2)
SELECT COUNT(*) FROM acad_exception_wrk
WHERE aew_type_cd = 'WTHDR_MED' AND aew_stat_cd = 'PEND';
```

---

### Step 2 — `sts` (~1 minute)

Executes ~350 workload queries against the seeded data using server-side PL/SQL loops, then loads the results into the Oracle SQL Tuning Set `UNIV_WORKLOAD`.

**What it does:** Simulates a realistic production workload spanning 14 query families. Queries are weighted by family — Family A (RegistrarCore) runs 1,500× per query, Family C (FinancialAid) 800×, bridge families K–N 400×. High execution counts drive HIGH affinity scores for the most-queried table pairs.

**Validate success** — run in SQLcl as UNIV_SCHEMARAG:

```sql
-- Should be ~350 statements
SELECT COUNT(*) FROM TABLE(DBMS_SQLTUNE.SELECT_SQLSET(
    sqlset_name  => 'UNIV_WORKLOAD',
    sqlset_owner => 'UNIV_SCHEMARAG'
));

-- Top queries should be RegistrarCore/FinancialAid joins with high execution counts
SELECT sql_text, executions
FROM TABLE(DBMS_SQLTUNE.SELECT_SQLSET(
    sqlset_name  => 'UNIV_WORKLOAD',
    sqlset_owner => 'UNIV_SCHEMARAG'
))
ORDER BY executions DESC
FETCH FIRST 5 ROWS ONLY;
```

Expected: top queries join STU_MST↔ENRL_REC and FINANCIAL_AID_APPLICATION↔FA_AWARD_HISTORY with executions in the thousands.

---

### Step 3 — `extract` (~15 seconds)

Parses every SQL statement in the STS with sqlglot, extracts JOIN co-occurrences, computes affinity scores, and writes results to `UNIV_NODES` and `UNIV_EDGES`.

**What it does:** Counts how often each pair of tables appears together in a JOIN across the entire weighted workload. Normalises to a 0.0–1.0 affinity score. Classifies each pair as HIGH (≥0.6) / MEDIUM (≥0.3) / LOW (≥0.1) / EXCLUDED (<0.1).

**Validate success** — run in SQLcl:

```sql
-- Affinity distribution
SELECT affinity_level, COUNT(*) AS cnt,
       ROUND(MIN(total_affinity),3) AS min_score,
       ROUND(MAX(total_affinity),3) AS max_score
FROM univ_edges
GROUP BY affinity_level
ORDER BY max_score DESC;
```

Key pairs to verify:
```sql
SELECT table_name_1, table_name_2, total_affinity, affinity_level
FROM univ_edges
WHERE affinity_level IN ('HIGH','MEDIUM')
ORDER BY total_affinity DESC;
```

Expected HIGH pairs: `FA_AWARD_HISTORY↔FINANCIAL_AID_APPLICATION` (0.72), `STU_MST↔ENRL_REC`, `CRS_CAT↔CRS_SECT`, `BURS_STUDENT_ACCOUNT↔BURS_CHARGE_LINE`.
Expected MEDIUM pairs: `ENRL_REC↔ACAD_EXCEPTION_WRK` (0.22), `STU_FA_XREF↔FINANCIAL_AID_APPLICATION` (0.21).

---

### Step 4 — `community` (~1 second)

Runs Louvain community detection on the affinity graph to discover which tables cluster together, then identifies bridge tables and hub tables.

**What it does:** Loads all edges into NetworkX, runs Louvain (random_state=42) to find communities, names each community against 10 canonical university domains, detects bridges (tables connecting multiple communities) and hubs (tables with ≥4 non-EXCLUDED connections). Writes results to `UNIV_NODES`.

**Validate success** — run in SQLcl:

```sql
SELECT community_name,
       COUNT(*) AS table_count,
       SUM(is_hub) AS hubs,
       SUM(is_bridge) AS bridges
FROM univ_nodes
GROUP BY community_name
ORDER BY table_count DESC;
```

Expected: 10 named communities (RegistrarCore, Curriculum, FinancialAid, Bursar, HousingDining, Research, StudentServices, HR, Compliance, Legacy). `ENRL_REC` should appear as a hub:

```sql
SELECT table_name, community_name, is_hub, is_bridge, hub_degree
FROM univ_nodes
WHERE is_hub = 1 OR is_bridge = 1
ORDER BY is_hub DESC, hub_degree DESC;
```

---

### Step 5 — `joinpaths` (~15 seconds)

Extracts multi-hop join chains from the STS workload and stores them in `UNIV_JOIN_PATHS`.

**What it does:** Parses every SQL statement with sqlglot to extract ordered table sequences from JOIN clauses. Generates all sub-sequences of length ≥ 3. Counts occurrences weighted by execution count. Keeps chains appearing ≥ 5 times (configurable via `JOIN_PATH_MIN_OCCURRENCES`).

**Validate success** — run in SQLcl:

```sql
-- Should be ~48 chains
SELECT COUNT(*) FROM univ_join_paths;

-- Top chains should reflect core academic navigation paths
SELECT anchor_table, join_chain, occurrence_count
FROM univ_join_paths
ORDER BY occurrence_count DESC
FETCH FIRST 10 ROWS ONLY;
```

Expected top chains: `STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK`, `STU_MST→STU_FA_XREF→FINANCIAL_AID_APPLICATION→NEED_ANALYSIS_RESULT`, `STU_MST→ENRL_REC→GRD_HIST`.

---

### Step 6 — `annotate` (~25 seconds)

Generates all 4 patent annotation types for every table and writes augmented metadata to `UNIV_EMBEDDINGS`.

**What it does:** For each of the ~70 tables, combines community membership, hub/bridge status, affinity scores, and join paths into the bracket-triple annotation format. Enforces a 40-line token budget (LOW affinity lines truncated last).

**Validate success:**

```bash
# Hub table — verify IN_COMMUNITY, IS_HUB, JOINS_WITH, JOINS_PATH
python -m src.annotations.annotation_generator --table ENRL_REC

# Bridge table — verify BRIDGES RegistrarCore:FinancialAid
python -m src.annotations.annotation_generator --table STU_FA_XREF

# Opaque work table — verify BRIDGES Bursar:RegistrarCore and join paths through ENRL_REC
python -m src.annotations.annotation_generator --table ACAD_EXCEPTION_WRK
```

Expected for ENRL_REC: `IN_COMMUNITY`, `IS_HUB`, `JOINS_WITH` (×4+), affinity levels, `JOINS_PATH` chains.
Expected for ACAD_EXCEPTION_WRK: `BRIDGES Bursar:RegistrarCore`, `JOINS_WITH ENRL_REC`, and `JOINS_PATH STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK`.

### CLI Spot-Checks

```bash
# Hub table — should show IS_HUB, IN_COMMUNITY, JOINS_WITH (×4+), JOINS_PATH
python -m src.annotations.annotation_generator --table ENRL_REC

# Bridge table — should show BRIDGES RegistrarCore:FinancialAid
python -m src.annotations.annotation_generator --table STU_FA_XREF

# Opaque work table — should show BRIDGES Bursar:RegistrarCore
# Must contain: STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK
python -m src.annotations.annotation_generator --table ACAD_EXCEPTION_WRK

# Side-by-side NL2SQL comparison
python -m src.pipeline.query_pipeline \
  "Which students have a pending grade change exception with a positive GPA impact" \
  --schema university --compare --ddl-baseline --count-total
```

## Run the Demo

`query_pipeline` runs any natural-language question against the university schema and compares standard RAG vs SchemaRAG side-by-side. For all CLI flags and an explanation of how Haiku and Opus divide the work, see [How the Pipeline Works](#how-the-pipeline-works) below.

### Scenario 1 — Opaque Work Table Bridge

Start with Scenario 1 — the core opaque-name bridge demo:

```bash
python -m src.pipeline.query_pipeline \
  "Which students have a pending grade change exception with a positive GPA impact" \
  --schema university --compare --ddl-baseline --count-total
```

**What to look for in the output:**

**Standard RAG (baseline)** — shown in red:
- Tables retrieved will include `STU_MST` and `ENRL_REC` but not `ACAD_EXCEPTION_WRK`
- Nothing in the DDL connects `ACAD_EXCEPTION_WRK` to grade changes — it is a contractor-built work table from 2020 with an acronym name and no FK declarations
- The LLM invents a column name (`ENRL_KEY`, `EXCEPTION_TYPE`, etc.) → `ORA-00904` error or 0 rows

**SchemaRAG (annotated)** — shown in green:
- `ACAD_EXCEPTION_WRK` appears in the retrieved tables because the annotation `[ENRL_REC JOINS_PATH STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK]` is embedded with `ENRL_REC`
- The column comment on `AEW_TYPE_CD` documents valid values — the LLM uses the correct filter `AEW_TYPE_CD = 'GRD_CHNG'`
- Result: **93 rows**

**Expected delta:** SQL error (`ORA-00904`) → 93 rows

> **All 5 scenarios with full SQL, row counts, and annotation traces:**
> [sql/university/UniversityScenarioTests.md](sql/university/UniversityScenarioTests.md)

---

## How the Pipeline Works

```bash
python -m src.pipeline.query_pipeline "<natural language question>" [options]
```

| Flag | What it does |
|---|---|
| `--schema <name>` | Schema to query: `university` (default), `erp`, `erp-large` |
| `--compare` | Run side-by-side: baseline first, then SchemaRAG annotated |
| `--ddl-baseline` | Baseline mode: Haiku selects tables without seeing annotations, Opus gets selected DDL only — this is what today's standard NL2SQL tools do |
| `--no-fk-baseline` | Same as `--ddl-baseline` but FK constraints stripped from DDL |
| `--baseline` | Blind baseline: LLM gets domain description only, no DDL, no annotations |
| `--count-total` | Strips `FETCH FIRST` and runs a `COUNT(*)` wrapper to show the true total row count beyond the 100-row display cap |
| `--show-rows` | Prints the result rows as a formatted table |
| `--top-k <n>` | Number of tables to pass to Haiku for relevance filtering (default: 8) |
| `--debug-annotations` | Prints the full table index sent to the retrieval model and which tables it selects |

**Typical comparison commands:**

```bash
# Standard RAG vs SchemaRAG, show true total row counts
python -m src.pipeline.query_pipeline "your question" --schema university --compare --ddl-baseline --count-total

# Show the actual result rows
python -m src.pipeline.query_pipeline "your question" --schema university --compare --ddl-baseline --show-rows

# Single annotated run (no comparison)
python -m src.pipeline.query_pipeline "your question" --schema university

# Blind baseline only (LLM gets nothing but the domain description)
python -m src.pipeline.query_pipeline "your question" --schema university --baseline
```

---

### How the two-step pipeline works

Every query — baseline and annotated — goes through two LLM calls:

```
NL query
    │
    ▼
Step 1 — Claude Haiku (retrieval)
    Input:  all table names + communities
            + annotation snippets (annotated mode only, up to 6 lines per table)
    Output: JSON array of relevant table names
    Cost:   ~200–400 input tokens, ~50 output tokens
    │
    ▼
Step 2 — Claude Opus (generation)
    Input:  DDL for selected tables (column names, types, FKs, column comments)
            + annotation context block (annotated mode only)
            + domain_description system prompt
    Output: a single SQL statement
    Cost:   ~3,000–8,000 input tokens depending on table count
    │
    ▼
Oracle execution → results
```

**What Haiku decides in each mode:**

| Mode | What Haiku sees | What it can discover |
|---|---|---|
| `--baseline` (blind) | Nothing — skipped entirely | N/A |
| `--ddl-baseline` | Table names + community names only | Tables whose names match the query |
| Annotated (default) | Table names + communities + `JOINS_WITH` / `BRIDGES` annotation snippets | Tables whose *neighbors* match — discovers bridge tables and XX_ custom tables |

**What Opus receives in each mode:**

| Mode | Opus input |
|---|---|
| `--baseline` | Domain description only |
| `--ddl-baseline` | Domain description + DDL for Haiku-selected tables |
| Annotated | Domain description + full annotation context block + DDL for selected tables |

---

### The system prompts

Three system prompts are defined in `src/nl2sql/claude_client_ai.py`. The pipeline selects one based on the mode:

**Annotated mode** (`_SYSTEM_WITH_CONTEXT`):
```
You are an expert Oracle SQL generator for a {domain_description} database.
The schema is owned by {schema_name} and its tables are organised into domain communities.

Below is the graph-derived annotation context for the tables most relevant
to the user's question. Use the [BRIDGES], [JOINS_PATH], [IS_HUB], and
affinity annotations to choose correct join paths and bridge tables.

{context_block}
{ddl_section}

Rules:
- Output ONLY a single SQL statement — no explanation, no markdown fences, no semicolons.
- Use {schema_name}.<TABLE> schema-qualified table names.
- Prefer join paths indicated by JOINS_PATH annotations.
- Always include bridge tables flagged by BRIDGES annotations.
- Limit results to 100 rows unless the question asks for aggregates.
- Use UPPER(column) LIKE '%KEYWORD%' for categorical string filters.
- GROUP BY or use a CTE when mixing aggregates with row-level columns.
```

**DDL baseline mode** (`_SYSTEM_WITH_DDL`):
```
You are an expert Oracle SQL generator for a {domain_description} database schema
owned by the {schema_name} user.

Below is the DDL schema for the tables most relevant to the user's question —
columns, data types, primary keys, foreign keys, and column comments.

{ddl_context}

[same rules as above, minus JOINS_PATH/BRIDGES guidance]
```

**Blind baseline mode** (`_SYSTEM_NO_CONTEXT`):
```
You are an expert Oracle SQL generator for a {domain_description} database schema
owned by the {schema_name} user.

[rules only — no schema context at all]
```

The `{domain_description}` placeholder is the same in all three prompts, which means it acts as shared ground truth across all comparison modes.

---

### The `domain_description` field — schema-level ground truth

`domain_description` is defined per schema in each plugin file (e.g. `src/schemas/erp_large/plugin.py`) and injected into every system prompt regardless of mode. It is the mechanism for telling the LLM facts about the specific database it is querying that cannot be derived from DDL or annotations alone.

**Why this matters for Oracle EBS:** Oracle EBS has dozens of discriminator columns — `ORIGINATION_TYPE`, `TRANSACTION_TYPE_ID`, `ORDER_TYPE`, `STATUS_TYPE` — where the correct filter value depends on the Oracle EBS release version. LLMs are trained on Oracle documentation and community posts spanning EBS 11i, R12.1, and R12.2, which map some of these codes differently. Without an explicit version declaration, the LLM applies its best guess from training data, which is often wrong for a specific installation.

The erp-large `domain_description` pins the EBS release and the key discriminator codes:

```python
domain_description=(
    "Oracle E-Business Suite Release 12.2 (EBS R12.2) ERP schema with ~200 tables "
    "across 13 modules. "
    # ... module list ...
    "Key EBS R12.2 discriminator codes — use these exact values: "
    "MRP_GROSS_REQUIREMENTS.ORIGINATION_TYPE: 1=Discrete Job, 2=Repetitive Schedule, "
    "4=Sales Order (DISPOSITION_ID = OE_ORDER_LINES_ALL.LINE_ID), 5=Forecast, "
    "11=Interorg Transfer. "
    "MRP_RECOMMENDATIONS.ORDER_TYPE: 1=Purchase Requisition, 2=Purchase Order, "
    "3=Discrete Job (WIP_ENTITY_ID populated), 4=Repetitive Schedule, 5=Transfer. "
    "WIP_DISCRETE_JOBS.STATUS_TYPE: 1=Unreleased, 3=Released, 4=Complete, "
    "5=Closed, 6=On Hold, 7=Cancelled. "
    "OE_ORDER_HEADERS_ALL.FLOW_STATUS_CODE active values: BOOKED, ENTERED "
    "(not OPEN — do not use LIKE '%OPEN%'). "
    "Key cross-module join: MRP_GROSS_REQUIREMENTS.DISPOSITION_ID = "
    "OE_ORDER_LINES_ALL.LINE_ID when ORIGINATION_TYPE=4."
),
```

This is the difference between the LLM guessing `ORIGINATION_TYPE = 6` (a value from a different EBS version) and correctly using `ORIGINATION_TYPE = 4`. The same principle applies to any enterprise system with version-specific lookup codes — SAP, Fusion, PeopleSoft. Pinning the version and the key code values in `domain_description` is the fastest fix for discriminator hallucination.

**The `domain_description` is also where universal SQL rules for your schema live.** During the POC we discovered several Oracle-specific patterns that caused failures across multiple queries — and fixed them once here rather than in the query text or annotation layer:

| Rule added to `domain_description` | Problem it prevents |
|---|---|
| `BOOKED, ENTERED` are the active status values (not `OPEN`) | `FLOW_STATUS_CODE LIKE '%OPEN%'` returning 0 rows on every order status query |
| `ORIGINATION_TYPE=4` for Sales Order demand | LLM using version-incorrect value 6, filtering out all MRP demand rows |
| `DISPOSITION_ID = OE_ORDER_LINES_ALL.LINE_ID` when `ORIGINATION_TYPE=4` | LLM not knowing the non-obvious surrogate FK relationship |

When you deploy SchemaRAG against your own Oracle database, start by populating `domain_description` with the EBS version, any non-obvious lookup code mappings you know, and any status values that differ from natural-language expectations. This is the lightest-weight intervention in the entire stack — a string in a Python file — and it resolves an entire class of failures that nothing else in the pipeline can fix.

---

## UNIV_EMBEDDINGS — The Central Knowledge Table

`UNIV_EMBEDDINGS` is the table that sits at the heart of the SchemaRAG pipeline. It is the output of the annotation process and the input to every NL2SQL query. Understanding it is key to understanding the whole system.

### DDL

```sql
CREATE TABLE univ_embeddings (
    table_name        VARCHAR2(100) NOT NULL PRIMARY KEY,  -- one row per table
    community_name    VARCHAR2(100),                       -- e.g. RegistrarCore
    base_metadata     CLOB,    -- plain schema metadata, no annotations
    augmented_text    CLOB,    -- schema metadata + all 4 patent annotation types
    annotation_count  NUMBER(5) DEFAULT 0,
    embedding         VECTOR(1024, FLOAT32),               -- optional OCI GenAI vector
    embedded_at       TIMESTAMP,
    created_at        TIMESTAMP DEFAULT SYSTIMESTAMP,
    updated_at        TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- Separate baseline table for DDL-only comparison mode
CREATE TABLE univ_embeddings_baseline (
    table_name        VARCHAR2(100) NOT NULL PRIMARY KEY,
    base_metadata     CLOB,
    embedding         VECTOR(1024, FLOAT32),
    embedded_at       TIMESTAMP,
    created_at        TIMESTAMP DEFAULT SYSTIMESTAMP
);
```

### What each column contains

| Column | What it holds | Who writes it |
|---|---|---|
| `table_name` | Oracle table name (e.g. `STU_FA_XREF`) | `--step annotate` |
| `community_name` | Louvain community (e.g. `FinancialAid`) | `--step annotate` (reads from `UNIV_NODES`) |
| `base_metadata` | Plain metadata: table name, row count, column names/types, FK refs, Oracle column comments — **no annotations** | `--step annotate` |
| `augmented_text` | Everything in `base_metadata` **plus** all bracket-triple annotations (community, hub, bridges, affinities, join paths) | `--step annotate` |
| `annotation_count` | Number of bracket-triple lines in `augmented_text` | `--step annotate` |
| `embedding` | 1024-dim float32 vector — populated by `--step embed` (optional; the default pipeline uses Claude Haiku for retrieval instead) | `--step embed` |
| `embedded_at` | Timestamp of last embedding call | `--step embed` |

### How it gets populated

`UNIV_EMBEDDINGS` is empty after the DDL runs. It is filled by `--step annotate`, which for each of the ~70 tables:

1. Reads Oracle's data dictionary (`all_tab_columns`, `all_col_comments`, FKs) via `schema_inspector.py`
2. Reads the graph results from `UNIV_NODES`, `UNIV_EDGES`, `UNIV_JOIN_PATHS` via `annotation_generator.py`
3. Assembles a single text document combining both into `augmented_text`
4. Upserts the row (insert on first run, update on re-runs)

Re-running `--step annotate` is safe and idempotent — it updates existing rows rather than inserting duplicates. This means any change to Oracle column comments, graph results, or annotation logic takes effect by simply re-running the step.

### What the augmented_text document looks like

```
TABLE: STU_FA_XREF
ROW_COUNT: 12000
COMMUNITY: FinancialAid

ANNOTATIONS:
  [STU_FA_XREF IN_COMMUNITY FinancialAid]
  [STU_FA_XREF BRIDGES RegistrarCore:FinancialAid]
  [STU_FA_XREF JOINS_WITH STU_MST]
  [STU_FA_XREF JOINS_WITH FINANCIAL_AID_APPLICATION]
  [STU_FA_XREF MEDIUM_AFFINITY FINANCIAL_AID_APPLICATION:0.21]
  ...

COLUMNS:
  SFX_ID (NUMBER) [PK]
  SFX_STU_ID (NUMBER) — foreign key to STU_MST.STU_ID
  SFX_FA_NBR (VARCHAR2) — financial aid application number in format FA0000001;
                           use TO_NUMBER(SUBSTR(SFX_FA_NBR,3)) to join to FINANCIAL_AID_APPLICATION.FA_ID
  ...
```

### How it is used at query time

`UNIV_EMBEDDINGS` is **not queried by vector similarity** in the current implementation (that is the future Option B path). Instead:

1. `query_retriever.py` fetches all ~70 rows from `UNIV_EMBEDDINGS`
2. A Claude Haiku call filters the list to only the tables relevant to the NL query
3. The `augmented_text` for those tables is formatted into a context block
4. Claude Opus receives that context block + the NL query and generates SQL

The LLM never sees the live Oracle schema. It sees only the text documents stored in `UNIV_EMBEDDINGS`. **The quality of the generated SQL is a direct function of the quality of those documents** — which is why accurate column comments and graph-derived annotations matter.

### Validate the current contents

```sql
-- One row per table, showing annotation density
SELECT table_name, community_name, annotation_count, updated_at
FROM univ_embeddings
ORDER BY annotation_count DESC;

-- Inspect the full document for a specific table
SELECT augmented_text
FROM univ_embeddings
WHERE table_name = 'STU_FA_XREF';

-- Verify column comments are flowing through
SELECT augmented_text
FROM univ_embeddings
WHERE table_name = 'STU_FA_XREF';
-- Should contain: SFX_FA_NBR ... — financial aid application number in format FA0000001
```

---

## The Annotation Types

Each annotation is a bracket-triple in the form `[SUBJECT PREDICATE OBJECT]`. The pipeline writes seven kinds of these triples, each answering a different question the LLM might have when deciding which tables to join and how.

### Community membership

```
[ENRL_REC IN_COMMUNITY RegistrarCore]
```

Every table belongs to exactly one Louvain community — a cluster of tables that the workload regularly queries together. The community name gives the LLM an immediate domain signal: if the question is about financial aid, tables tagged `FinancialAid` are candidates; tables tagged `Legacy` are not.

### Hub indicator

```
[ENRL_REC IS_HUB degree:5.0]
```

A hub is a table that sits at the intersection of multiple communities — it appears in queries that span domains. The degree value is the number of distinct communities the table connects to. When the LLM sees `IS_HUB degree:5.0` it knows that this table is a connector, not a leaf, and should be considered even if it was not the obvious first match for the query terms.

### Join indicators

```
[ENRL_REC JOINS_WITH ACAD_EXCEPTION_WRK]
[ENRL_REC JOINS_WITH STU_MST]
```

Every table pair that appeared together in at least one STS query gets a `JOINS_WITH` annotation. This is the minimum signal — it tells the LLM that a direct join between these two tables has actually been executed in production, even when no FK constraint is declared in the DDL.

### Affinity levels

```
[ENRL_REC HIGH_AFFINITY STU_MST:0.71]
[ENRL_REC MEDIUM_AFFINITY ACAD_EXCEPTION_WRK:0.22]
[ENRL_REC LOW_AFFINITY GRD_HIST:0.08]
```

Affinity is a Jaccard-based score (0–1) that combines how many *distinct queries* join two tables (static coefficient) with how many *total executions* those queries had (dynamic coefficient). A HIGH affinity pair is joined constantly by many different queries — a strong signal. A LOW affinity pair is joined occasionally — worth knowing but not primary. Pairs below the exclusion threshold get no annotation at all.

**Thresholds (configured in `.env`):** HIGH ≥ 0.6 / MEDIUM ≥ 0.3 / LOW ≥ 0.1 / EXCLUDED < 0.1

### Bridge indicators

```
[STU_FA_XREF BRIDGES RegistrarCore:FinancialAid]
```

A bridge is a table whose community neighbours span more than one community. The annotation names those communities explicitly. This is the single most powerful annotation for multi-community queries: the LLM does not have to infer that `STU_FA_XREF` connects the registrar and financial aid domains — it is stated directly.

### Join-path chains

```
[ENRL_REC JOINS_PATH STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK]
[ENRL_REC JOINS_PATH ENRL_REC→GRD_HIST→OLD_GRADE_ARCH]
```

A join-path chain is a multi-hop sequence of tables that appeared together in the STS, extracted by `join_path_extractor.py` and recorded only when the chain appeared at least `JOIN_PATH_MIN_OCCURRENCES` times. This is what solves the opaque work-table problem: `ACAD_EXCEPTION_WRK` has no FK declarations and its name gives no semantic clue, but the path `STU_MST→ENRL_REC→ACAD_EXCEPTION_WRK` appears in 14 production queries — so it is recorded. The LLM sees the full route and can follow it.

### Excluded pairs

Tables that were never joined together in the workload receive no annotation. This absence is deliberate and meaningful: `[ENRL_REC JOINS_WITH BURS_STUDENT_ACCOUNT]` will never appear because those two tables have never been joined in any captured query. The LLM learns not just what is connected but what is not — reducing hallucinated joins.

---

## Why Do Annotations Work So Well?

The annotations work as effectively as they do because LLMs are uniquely constructed to consume them. This is not accidental.

### The transformer attention mechanism and structured patterns

LLMs are built on the transformer architecture, where self-attention lets the model find relationships between any tokens in the context window regardless of their distance apart. When Claude sees:

```
[STU_FA_XREF BRIDGES RegistrarCore:FinancialAid]
[STU_FA_XREF MEDIUM_AFFINITY FINANCIAL_AID_APPLICATION:0.21]
```

...and then reads the natural language query *"students with unmet financial need"*, the attention mechanism efficiently connects `unmet need` → `FINANCIAL_AID_APPLICATION` → `MEDIUM_AFFINITY` → `STU_FA_XREF` → `BRIDGES` → `RegistrarCore` in a single forward pass. It does not have to search — attention finds those connections automatically.

### The format mirrors the training data

The bracket-triple `[SUBJECT PREDICATE OBJECT]` structure is nearly identical to RDF triples and knowledge graph notation — formats that appear extensively in LLM training data. Wikipedia infoboxes, Wikidata, knowledge bases, scientific papers — all use subject-predicate-object structures. The LLM has seen millions of examples of this pattern and learned to reason over it efficiently.

The annotation format is essentially a native language the model already speaks fluently.

### LLMs are optimised for in-context instruction-following

A significant portion of LLM training involves instruction-following tasks — being given structured facts in the context and using them to answer questions. The annotation block in the system prompt is architecturally identical to what the model was trained to do: read structured facts, hold them in attention, apply them to a task.

Compare this to embedding-based retrieval, which hopes semantic similarity will surface the right tables. The annotation approach bypasses the probabilistic retrieval step entirely and gives the LLM deterministic facts. LLMs follow explicit instructions far more reliably than they infer from semantic proximity.

### Density: maximum information per token

The bracket-triple format is extremely token-efficient. One line encodes a relationship that would take a paragraph of prose to explain — and the model's attention can process it in parallel across the whole context. Prose descriptions introduce ambiguity; structured triples do not. The model spends no tokens resolving ambiguity.

### The deeper point

What the annotation pipeline builds is a *knowledge injection layer* that speaks the LLM's native reasoning format. Not schema documentation, not prose, not raw DDL — but structured relational facts in a format that maps directly onto how transformer attention reasons about relationships.

That is why it works with *any* capable LLM, not just Claude. GPT-4, Llama, Gemini all share the same transformer architecture and the same training data patterns. The annotations are model-agnostic because the underlying mechanism that makes them effective is universal.

---

## Schema — ~70 University Tables, 10 Communities

| Community | Tables |
|---|---|
| RegistrarCore | STU_MST, ENRL_REC, GRD_HIST, ACAD_HIST, TERM_TBL, ACAD_STAT_TBL, STUDENT_PROFILE, XFER_INST_MAP |
| Curriculum | CRS_CAT, CRS_SECT, DEPT_TBL, INSTR_TBL, ROOM_INVT, CRS_PREREQ, CLASS_SCHED, SCHED_OPTIM_WRK |
| FinancialAid | FINANCIAL_AID_APPLICATION, FA_AWARD_HISTORY, SCHOLARSHIP_POOL, LOAN_DISBURSEMENT, NEED_ANALYSIS_RESULT, AID_PACKAGING_RULE, PELL_ELIGIBILITY_TBL, STU_FA_XREF |
| Bursar | BURS_STUDENT_ACCOUNT, BURS_CHARGE_LINE, BURS_PAYMENT, BURS_TUITION_RATE, BURS_BILLING_PERIOD, BURS_HOLD_CODE, BURS_INSTALLMENT_PLAN, BURS_REFUND_REQUEST, BURS_STUDENT_HOLD, TUTN_APPEAL_WRK |
| HousingDining | HSG_ROOM_INVENTORY, HSG_ROOM_ASSIGNMENT, HSG_CONTRACT, HSG_WAITLIST_WRK, DINING_PLAN, DINING_TRANSACTION, DINING_LOCATION |
| Research | RESEARCH_PROJECT, GRANT_TBL, IRB_PROTOCOL, FACULTY_APPT, PUBLICATION_TBL, GRANT_ALLOC_WRK |
| StudentServices | ADVISOR_ASSIGN, ADVISING_NOTE, CAREER_EMPLOYER, CAREER_PLACEMENT, DISABILITY_ACCOM, TUTORING_SESSION |
| HR | STAFF_HR_XREF, HR_POSITION, HR_APPOINTMENT |
| Compliance | FERPA_CONSENT_LOG, DEGREE_AUDIT_WRK, RETENTION_FLAG, ACAD_EXCEPTION_WRK, ACCRED_METRIC_TBL |
| Legacy | PS_STDNT_ENRL, PS_CLASS_TBL, PS_ACAD_PLAN, PS_TERM_TBL, PS_STDNT_DEGR, OLD_GRADE_ARCH, LEGACY_CRS_TBL |

**Bridge/hub tables:** ENRL_REC (hub, degree:5.0), STU_MST (hub, degree:9.0), ACAD_EXCEPTION_WRK (bridges RegistrarCore↔Compliance), STU_FA_XREF (bridges RegistrarCore↔FinancialAid), STAFF_HR_XREF (bridges Curriculum↔HR)

---

## Project Structure

```
schema-graphrag-demo/
├── sql/
│   └── university/       # DDL, OCI credential, workload queries, STS, vector index
├── src/
│   ├── config.py         # Pydantic Settings
│   ├── db/               # ADB connection, schema inspector, vector store
│   ├── schemas/
│   │   └── university/   # Seed data, plugin, schema context
│   ├── workload/         # STS loader, co-occurrence extractor, affinity calculator
│   ├── graph/            # NetworkX graph, Louvain communities, join-path extractor
│   ├── annotations/      # All 4 annotation types, metadata augmentor
│   ├── embeddings/       # OCI GenAI embedding pipeline (optional)
│   ├── nl2sql/           # Table retrieval, Claude API client, SQL validator
│   └── pipeline/         # Build orchestrator + query pipeline
├── app/
│   ├── streamlit_app.py  # Entry point
│   └── pages/            # 01_Architecture … 06_Comparison
├── notebooks/            # 01_setup … 06_nl2sql_demo
└── tests/                # Unit + integration tests
```

---

## Enterprise Deployment Pattern — LLM-Agnostic Annotation Service

One of the most strategically important properties of this architecture is that **the annotations are a DBA-controlled asset, completely decoupled from the LLM the end user chooses.**

### The DBA owns the annotation layer

The `UNIV_EMBEDDINGS` table holds the curated annotation context:

```
UNIV_EMBEDDINGS
├── table_name
├── augmented_text      ← DBA-controlled annotations (communities, affinities, bridge paths)
├── embedding_vector    ← vector index for semantic search
└── base_metadata       ← raw schema (columns, types, FKs)
```

The DBA writes and maintains the annotations. No LLM has write access to this table. The quality of SQL generation is a function of annotation quality — a DBA asset — not which model a user happens to choose.

### Security controls already available in Oracle

| Control | Purpose |
|---|---|
| **Role-based GRANT on UNIV_EMBEDDINGS** | Apps get read-only access; no modification |
| **Oracle RLS / VPD** | App A sees only the tables it is allowed to query |
| **Oracle ORDS REST endpoint** | Expose `/schema-context` — accepts NL query, returns annotation context; apps never touch the table directly |
| **Oracle Data Redaction** | Strip sensitive column metadata from `base_metadata` while leaving annotations intact |

### The universal integration pattern

```
User NL query
    │
    ▼
Oracle ORDS /schema-context endpoint   ← DBA controls this
    │  (vector search over UNIV_EMBEDDINGS)
    │  returns: annotation context block
    ▼
User passes context + NL query to their LLM of choice
    │  (Claude, GPT-4, Llama, Gemini — anything)
    ▼
LLM reads [BRIDGES] and [JOINS_PATH] annotations,
generates correct SQL with proper join paths
    │
    ▼
SQL executes against Oracle
```

The DBA never needs to know which LLM the user chose. The LLM never sees the raw schema — only the curated annotation context the DBA approved. Swapping Claude for GPT-4 for Llama produces equivalent SQL quality because **correctness follows the annotations, not the model.**

This means a single Oracle installation can serve a heterogeneous user base — internal teams using Claude, external partners using a self-hosted Llama, regulated workloads using an on-premise model — all drawing from the same DBA-governed annotation layer.

### Two-layer prompt architecture

Every LLM-based NL2SQL deployment requires two distinct layers of prompt context, and SchemaRAG cleanly separates them:

| Layer | What it contains | Who owns it | Changes when |
|---|---|---|---|
| **Universal SQL rules** | Dialect rules, aggregation patterns, string-matching conventions, row limits — best practices that apply to any schema and any LLM | Engineering / platform team | Rarely — only when SQL generation patterns need tuning |
| **SchemaRAG annotations** | Community membership, affinities, bridge tables, join paths — knowledge derived from *this* schema's actual workload | DBA | Schema evolves or workload patterns shift |

The annotations are the novel, schema-specific layer the patent describes. The universal rules are the "LLM SQL driver" that makes any capable model behave correctly. They compose independently: update the annotations when the schema changes, update the rules when a new SQL dialect is needed. Neither layer requires model retraining or fine-tuning.

### Rules discovered during POC (the universal layer in practice)

During the POC we encountered a small set of LLM SQL generation patterns that required explicit rules. Each was discovered once, fixed once in the prompt, and now applies to every future query across all users and all LLMs:

| Rule | Problem it prevents |
|---|---|
| Use `UPPER(col) LIKE '%KEYWORD%'` for categorical string filters | Exact-match failures when stored values differ from NL phrasing (e.g. `'Cardiologist'` stored vs `'Cardiology'` guessed) |
| Always `GROUP BY` or use a CTE when mixing aggregates with row-level detail | ORA-00937: invalid aggregate/non-aggregate mixing without GROUP BY |
| Output exactly one SQL statement — no semicolons | ORA-03405: Oracle rejects multi-statement responses from over-eager generation |

This is not a list of bugs — it is the beginning of a **reusable enterprise asset**. Every rule added here improves query reliability for every user, every query, and every LLM the organisation chooses to use. The list grows with usage and stabilises over time as the common failure modes are covered. It is the kind of institutional knowledge that today lives informally in the heads of individual developers; SchemaRAG makes it explicit, versioned, and shared.

## Your XX_ Tables Are Where Other NL2SQL Tools Give Up

Standard Oracle EBS table names — `AP_INVOICES_ALL`, `MTL_SYSTEM_ITEMS_B`, `OE_ORDER_HEADERS_ALL` — are among the most extensively documented objects in enterprise software. Oracle's own manuals, thousands of DBA community posts, and decades of consulting guides have all been published about EBS table structures. An LLM reading those names already knows how they connect, even without FK constraints or annotations. Standard EBS tables are too well-known to stress-test a technique whose value is discovering join paths the LLM cannot infer on its own.

Customer-specific extension tables are the opposite.

### The XX_ prefix: the undocumented layer of every Oracle EBS installation

Every large Oracle EBS installation carries a second class of tables, identified by the `XX_` prefix: tables the customer built on top of EBS to support business logic the product didn't cover.

`XX_ITEM_PLANNING_PARAMS`. `XX_VENDOR_SCORECARD`. `XX_WORK_ORDERS`. These tables:

- Exist nowhere in Oracle documentation, DBA forums, or consultant guides
- Are unique to each customer's implementation — no two are alike
- Were often built by developers who have since left the company
- Carry deliberate column name mismatches (`COMPONENT_ITEM_ID` instead of `INVENTORY_ITEM_ID`, `RENEWAL_TERMS_ID` instead of `TERM_ID`) so their join targets are not inferrable from naming conventions
- Have zero FK constraints and zero column comments

No LLM has ever been trained on them. They are proprietary, unpublished, and unique. An LLM reading the DDL cannot discover they exist, cannot guess their join targets from their column names, and cannot recover from their absence in a query result. The only evidence that `XX_ITEM_PLANNING_PARAMS` joins to `MTL_SYSTEM_ITEMS_B` on `INVENTORY_ITEM_ID` and `ORGANIZATION_ID` is in the SQL Tuning Set — the production workload history where that join has been executed thousands of times.

| | Standard RAG (DDL only) | SchemaRAG (DDL + annotations) |
|---|---|---|
| **Haiku sees** | Table names + communities | Table names + communities + `JOINS_WITH` annotations |
| **Discovers XX_ITEM_PLANNING_PARAMS?** | No — never seen it | Yes — `[MTL_SYSTEM_ITEMS_B JOINS_WITH XX_ITEM_PLANNING_PARAMS]` |
| **SQL generated** | Uses `MTL_SYSTEM_ITEMS_B.MIN_MINMAX_QUANTITY` (NULL in this customer's data) | Uses `XX_ITEM_PLANNING_PARAMS.REORDER_POINT` (populated) |
| **Result** | 0 rows | 50+ items flagged for reorder |

The baseline doesn't fail because it chose the wrong join path. It fails because it didn't know the table existed at all. No amount of prompt engineering, DDL formatting, or FK annotation fixes that — because the table has no public footprint to draw on. The annotation, derived from the SQL Tuning Set, is the only signal.

### Why this represents most large Oracle customers

The XX_ table pattern is not a contrived edge case. It is the normal state of every mature Oracle EBS installation:

- **Every large EBS customer has hundreds of XX_ tables.** Built over 10–20 years of customization, they encode the business logic that makes a retailer different from a manufacturer, a hospital different from a bank.
- **The people who built them have often left.** The join paths, the business rules, the reason `EVAL_PERIOD_NAME` maps to `GL_PERIODS.PERIOD_NAME` — that knowledge exists in the workload history because it was exercised in production, even if the original developer is gone.
- **No LLM will ever be trained on them.** They are proprietary. They were never published. A model trained on all of the internet still knows nothing about `XX_VENDOR_SCORECARD`.
- **Column name mismatches are common.** Extension tables were built by different teams at different times with no naming consistency enforced — `SOURCE_CCID` where a standard table uses `CODE_COMBINATION_ID`, `RENEWAL_TERMS_ID` where a standard table uses `TERM_ID`.

SchemaRAG's value proposition is exactly this gap. The SQL Tuning Set captures how the database was actually used — including every join between well-known EBS tables and the customer-specific XX_ tables that extend them. The annotations surface those join patterns to the LLM. Seeing `[MTL_SYSTEM_ITEMS_B JOINS_WITH XX_ITEM_PLANNING_PARAMS]`, the retrieval step discovers a table it could never have known about from training data alone. The advantage is largest precisely where the LLM's training data is least useful: at the boundary between standard product tables and the custom extensions that make each customer's system unique.

---

## When Annotations Beat DDL Alone — The 12 Scenarios

DDL tells the LLM what exists. Annotations tell it what matters and how things connect. The combination is more powerful than either alone — but the gap is widest in these specific situations, all of which are common in large enterprise Oracle databases.

### 1. Lack of Foreign Keys

The foundational scenario. Oracle E-Business Suite, Fusion, and most large data warehouse schemas define referential integrity at the application layer, not the database layer. FK constraints are absent or declared as disabled and non-validated. Without them, the DDL has no join graph. The LLM has no structural evidence that any two tables connect. Annotations supply a join graph derived from the actual workload — every `JOIN` clause ever executed, counted and weighted.

### 2. Lack of Descriptive Table and Column Names

`MTL_SYSTEM_ITEMS_B`. `RA_CUSTOMER_TRX_ALL`. `SOURCE_CCID`. `RENEWAL_TERMS_ID`. Oracle Applications naming conventions are module-prefixed and opaque to anyone outside the Oracle world — including every LLM ever trained. The LLM cannot infer meaning from the name alone. Community membership annotations (`IN_COMMUNITY Inventory`) give the table a functional identity. Affinity annotations give it proven join targets. Column comments flowing through the DDL give cryptic column names their semantic meaning.

### 3. Incomplete DDL

Partial schemas where some tables have no comments, views that hide the base tables they draw from, tables whose column definitions exist but whose relationships to other tables were never documented. Annotations fill the semantic gap that incomplete DDL leaves empty — because they are derived from workload behavior, not from documentation that may never have been written.

### 4. Long Join Paths

When the correct answer requires 4 or 5 hops — `PATIENTS → ENCOUNTERS → LAB_RESULTS → LAB_TESTS`, or `OE_ORDER_LINES_ALL → MTL_SYSTEM_ITEMS_B → XX_ITEM_PLANNING_PARAMS → MTL_ONHAND_QUANTITIES_DETAIL` — the LLM must guess every intermediate table. One wrong guess produces zero rows or a SQL error. `JOINS_PATH` annotations encode the proven multi-hop chains extracted from the workload. The LLM follows the chain rather than guessing it.

### 5. Lack of Public Schema Documentation

Customer-specific extension tables (`XX_` prefix in Oracle EBS) exist nowhere in public documentation, DBA forums, or LLM training data. The LLM is genuinely blind to them. The only evidence that `XX_ITEM_PLANNING_PARAMS` joins to `MTL_SYSTEM_ITEMS_B` on `INVENTORY_ITEM_ID` and `ORGANIZATION_ID` is in the SQL Tuning Set — years of production queries that executed that join. The `JOINS_WITH` annotation derived from that workload is the only signal available. DDL injection cannot help because the LLM must first know the table exists before it can use its DDL.

### 6. Large Database with Thousands of Tables

At scale, the LLM cannot receive DDL for all tables — token budgets force selection. Name-based selection (Haiku guessing from table names) becomes unreliable as the table count grows and naming conventions become less predictable. Annotation-guided selection is more accurate: Haiku sees `JOINS_WITH` relationships and can follow the graph to discover tables it would never have guessed from the name alone. The advantage of annotation-guided retrieval compounds as schema size increases.

### 7. Schema Evolution Over Time

Tables get renamed, columns get repurposed, legacy columns are kept for backward compatibility long after their original meaning has shifted. The DDL reflects what the schema *is permitted to hold*. The workload reflects what it *is actually used for today*. When those two things diverge — which they always do in a schema that has been running for a decade — annotations derived from current workload are more reliable than DDL derived from original design intent.

### 8. Cross-Module Joins in Suite Products

EBS, Fusion, SAP, and similar suite products span multiple functional modules — Financials, Inventory, Procurement, HR — each with its own table namespace and naming conventions. Correct queries often require joins across module boundaries that have no FK relationship and no obvious naming connection. The workload is the only evidence those cross-module joins exist and are valid. Community detection clusters the modules; bridge annotations identify the tables that connect them.

### 9. Customer-Specific Business Rules Encoded in Join Conditions

Not just which tables join, but *how* they join. `EVAL_PERIOD_NAME = GL_PERIODS.PERIOD_NAME` — a non-obvious string join between a custom scorecard table and the standard GL periods table. `SOURCE_CCID = GL_CODE_COMBINATIONS.CODE_COMBINATION_ID` — a column name mismatch that a naming-convention heuristic would miss entirely. The workload captured these join conditions because they were executed in production. DDL cannot express them because they were never formally documented. Annotations surface them as proven join patterns the LLM can follow.

### 10. Business Questions Whose Concepts Don't Map to Table Names

The most decisive annotation wins come when the user's language has no words in common with the table name. "Which items need reordering" and "which items need replenishment" both require `XX_ITEM_PLANNING_PARAMS` — a table whose name contains none of those words. The baseline has no path to it from the query text alone. The annotation `[MTL_SYSTEM_ITEMS_B JOINS_WITH XX_ITEM_PLANNING_PARAMS]` is the only signal connecting a business question about stock levels to a customer-specific planning table. Both queries produced 0 rows from the baseline and 100 rows from the annotated pipeline.

This is the design principle for any schema intended to demonstrate annotation value: XX_ table names should be opaque. When a table name contains words that appear in typical queries — `XX_APPROVED_VENDOR_LIST`, `XX_BACKORDER_PRIORITIES` — the baseline finds it by name-matching alone and the annotation advantage shifts from table discovery to SQL quality. When the name gives nothing away, the annotation is the only bridge.

### 11. Queries Where the Correct Answer Requires a Table Nobody Mentioned

Annotations surface tables that change the business meaning of the answer, not just the row count. The query "which of our at-risk customers are we going to disappoint this month" is the clearest example. The baseline correctly identified customers with unresolved backorders. The annotated pipeline additionally retrieved `XX_CUSTOMER_PRICE_AGREEMENTS` — because `[XX_CUSTOMER_PRICE_AGREEMENTS HIGH_AFFINITY HZ_CUST_ACCOUNTS]` told the retrieval step that customer accounts and price agreements travel together in the workload. The annotated answer identified customers with both a backorder *and* an active price commitment — the customers a business is most commercially obligated to fulfill. The annotation didn't just find an extra table; it produced a more accurate answer to the same business question.

### 12. Production SQL Quality

Even when the baseline finds the right tables and returns the correct rows, the annotated pipeline consistently produces better-structured SQL. Across every query tested: CTE chains instead of nested subqueries, pre-filtered aggregations rather than full-table scans with late filtering, both effective-date and end-date bounds on time-sensitive joins, supplier reliability checks that include hold flags and enabled status rather than just approved vendor list membership. The LLM has richer context about how the tables relate and writes SQL that reflects that understanding. A DBA reviewing annotated output would ship it. A DBA reviewing baseline output would rewrite it first.

---

## Technology Stack

| Component | Technology |
|---|---|
| Database | Oracle Autonomous Database (wallet mTLS) |
| Workload capture | DBMS_SQLTUNE SQL Tuning Sets |
| Community detection | python-louvain (Louvain, random_state=42) |
| Graph | NetworkX weighted undirected graph |
| NL2SQL generation | Claude API — Opus 4.6 for SQL generation, Haiku 4.5 for table retrieval |
| Demo UI | Python CLI (`query_pipeline.py`) — Streamlit + Pyvis app is a future enhancement (see item 6 below) |

*No OCI GenAI, no onnxruntime, no sentence-transformers, no Ollama. The only external service is the Claude API — making this demo accessible to anyone with an Anthropic API key and an Oracle database.*

---

## Future Enhancements

The following improvements have been identified for future development:

1. **Dynamic table list from UNIV_EMBEDDINGS** — The current Haiku retrieval step has the ~70 table names referenced from the annotated rows fetched at runtime, but the list could be driven entirely by a `SELECT table_name FROM univ_embeddings` query. This would keep the retrieval step automatically in sync with whatever tables have been annotated, with no hardcoding to maintain.

2. **Oracle AI Vector Search for table retrieval** — Replace the Claude Haiku LLM call in the retrieval step with cosine similarity against the `UNIV_EMBEDDINGS.embedding` column using `VECTOR_DISTANCE`. Faster, cheaper, and removes the LLM from the retrieval path entirely. The `VECTOR` column is already in the schema.

3. **Oracle Graph (PGX) for community detection** — Move Louvain community detection from the Python client into Oracle ADB as a scheduled job using PGX. Eliminates all external Python dependencies and enables automatic annotation refresh as schemas evolve.

4. **ORDS REST endpoint `/schema-context`** — A single governed endpoint that any application, LLM, or team can query to receive the annotation context block for a given NL question. The DBA controls what it returns; one endpoint serves the entire enterprise.

5. **Categorical column value annotations** — Include actual stored values from the database in annotations: `VALUES: FRESHMAN | SOPHOMORE | JUNIOR | SENIOR | GRAD`. Eliminates column value hallucination, which is the third most common NL2SQL failure mode after missing bridge tables and incorrect join paths.

6. **Streamlit demo app** — `app/` contains all 6 pages (Architecture, Schema Explorer, Workload Graph, Annotations diff, NL2SQL side-by-side, Comparison) and the Pyvis graph component, but the app has not been tested end-to-end against a live database. Needs a working run path and validation of the NL2SQL page against the university schema before it can be used in a live demo.

7. **OCI GenAI embedding pipeline (`--step embed`)** — The `VECTOR(1024, FLOAT32)` column is already in `UNIV_EMBEDDINGS`, and `src/embeddings/oci_embedder.py` + `embedding_pipeline.py` are written. The step is blocked by the OCI GenAI credential setup (`sql/02_create_oci_credential.sql`) which requires a real OCI API key. Once the credential is in place, running `--step embed` followed by `sql/06_vector_index.sql` enables Oracle AI Vector Search (item 2 above) and unlocks the Comparison page in the Streamlit app.

8. **Jupyter notebooks** — Six explainer notebooks (`notebooks/01` through `06`) are planned but not yet written. They cover: ADB connection and schema verification, workload STS contents and affinity heatmap, graph construction and community visualisation, annotation generation diff viewer, embedding pipeline and cosine similarity matrix, and the NL2SQL demo with results in pandas DataFrames. These are the step-by-step walkthrough layer for anyone wanting to understand the pipeline rather than just run it.

9. **Test suite** — Run `python -m pytest tests/unit -v` for dependency compatibility checks covering SQL parsing, community detection, configuration loading, and the Streamlit landing page. Further tests for `affinity_calculator`, `annotation_generator`, and `join_path_extractor`, plus an end-to-end Scenario 1 integration test against a live ADB connection, are planned.

12. **Annotation-driven token reduction** — Annotations and DDL currently overlap: FK constraints in DDL encode the same structural relationships already expressed in `JOINS_WITH` and `JOINS_PATH` annotations. Two complementary optimisations follow from this. First, in annotated mode, strip FK constraint declarations from the DDL sent to Opus — the join structure is fully covered by annotations, making FK lines redundant noise that consumes tokens without adding information. Second, distinguish *bridge* tables (tables that appear only as connectors in a JOIN chain, never in the SELECT list or WHERE clause) from *primary* tables in the Haiku-selected set; send full DDL only for primary tables and annotation-only context for bridge tables. Together these reduce Opus input by roughly the DDL cost of 2–3 bridge tables per query — a ~30% reduction in generation-step tokens — while tightening context and reducing the chance of the LLM generating SQL against irrelevant columns. Requires changes to `src/nl2sql/claude_client_ai.py` (DDL assembly) and `src/nl2sql/query_retriever.py` (bridge vs. primary table classification). Enhancement 11 (join column pairs) is a prerequisite for the bridge-table optimisation to work safely.

11. **Join column pairs in JOINS_PATH annotations** — The sqlglot AST already contains the ON condition for every JOIN clause (`e.ER_ID = a.AEW_ENRL_KEY`), but the current `join_path_extractor.py` discards it after extracting table names. Capturing and storing these column pairs (with alias resolution) would allow JOINS_PATH annotations to express not just which tables to join but exactly how — e.g. `[ENRL_REC JOINS_PATH STU_MST(STU_ID→ER_STU_ID)→ENRL_REC(ER_ID→AEW_ENRL_KEY)→ACAD_EXCEPTION_WRK]`. This is most valuable for XX_ extension tables where column name mismatches (`SOURCE_CCID` → `CODE_COMBINATION_ID`) are not inferrable from naming conventions alone. Requires changes to `src/graph/join_path_extractor.py`, a `join_conditions CLOB` column added to `UNIV_JOIN_PATHS`, and updated formatting in `src/annotations/annotation_generator.py`.

10. **Oracle Free Docker — full community coverage** — Oracle Free's constrained SGA can leave the shared pool too small for this demo workload, causing cursor cache eviction during the STS workload step: only ~540 of ~722 statements may survive before `LOAD_SQLSET` runs, resulting in 22 annotated tables instead of the full ~55 on ADB. The fix is to increase the shared pool floor to the largest value valid for the root container's `sga_target`, then re-run `--step sts → extract → community → joinpaths → annotate`. Connect to the root service as SYSDBA and check the limit:

    ```bash
    sql sys/<password>@//localhost:1521/FREE as sysdba
    ```

    ```sql
    SHOW PARAMETER sga_target
    SHOW PARAMETER shared_pool_size
    ```

    Oracle requires `shared_pool_size` to be smaller than 20% of the root container's `sga_target`. For example, with `sga_target=1536M`, `512M` and `384M` are invalid, while this setting is valid and has been observed to raise the actual shared pool from ~104M to ~400M:

    ```sql
    ALTER SYSTEM SET shared_pool_size = 256M SCOPE=BOTH;

    SELECT pool, ROUND(SUM(bytes)/1024/1024) AS mb
    FROM v$sgastat
    WHERE pool = 'shared pool'
    GROUP BY pool;
    ```

    Until this is done, Scenario 1 SchemaRAG can fail on Docker because Haiku does not see enough annotation context to select `ENRL_REC`, though all other scenarios may pass.
