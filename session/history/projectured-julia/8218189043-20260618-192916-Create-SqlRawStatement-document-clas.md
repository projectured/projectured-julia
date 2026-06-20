# Session Analysis Report

**Generated:** 2026-06-20 19:55
**Source:** `C:\Users\balin\.claude\projects\c--Users-balin-gitworkspace-projectured-julia\23551ff7-3510-43d5-9afb-23cad3594c19.jsonl`

---

## Session: Create SqlRawStatement document class

Source: `23551ff7-3510-43d5-9afb-23cad3594c19.jsonl` | Workspace: `c:\Users\balin\gitworkspace\projectured-julia` | Branch: `database`

> **Cost basis:** subscription-amortized, not API list price. Subscription $20/mo (`--subscription`, default $20) → weekly budget $4.67 (÷ 4.286 wk/mo). Weight = weekly budget ÷ *estimated* weekly usage $371.52 = **×0.0126**. Est. Cost below is this weight applied to list price.

### Token Usage

| Metric | Value | $/MTok | Rel. Weight | Est. Cost | Notes |
|---|---:|---:|---:|---:|---|
| **Effective total** | **15,118,777** | | | **$0.17** | input (all sources) + output |
| Output | 53,221 | $25.00 | **5.0×** | $0.02 | most expensive |
| Fresh input | 312 | $5.00 | 1.0× | $0.00 | non-cached input tokens |
| Cache creation | 817,317 | $6.25 | 1.25× | $0.06 | new cache entries |
| Cache read | 14,247,927 | $0.50 | 0.1× | $0.09 | cheapest |
| Effective input | 15,065,556 | | | | fresh + cache creation + cache read |
| Cache hit rate | 94.6% | | | | cache read / effective input |
| Discovery cost | 565 | | | | tokens before first Edit/Write |

> **Budget impact:** $0.17 — output tokens account for 10% of cost

### Activity

| Metric | Count | Eff. Input | Output |
|---|---:|---:|---:|
| Assistant turns | 214 | 15,065,556 | 53,221 |
| Files read | 12 | | |
| Files edited | 7 | | |
| Irrelevant reads ≈ | 5 | | |
| Multi-edited ≈ | 6 | | |
| First code at token | 565 | | |

### Tool Calls

| Tool | Count | Eff. Input ≈ | Output ≈ |
|---|---:|---:|---:|
| Agent | 2 | 136,414 | 736 |
| Bash | 13 | 713,172 | 1,939 |
| Edit | 45 | 3,769,690 | 16,425 |
| ExitPlanMode | 3 | 221,694 | 115 |
| Glob | 2 | 58,094 | 251 |
| Grep | 20 | 1,478,553 | 3,119 |
| Read | 46 | 3,001,774 | 5,067 |
| ToolSearch | 2 | 111,755 | 79 |
| Write | 8 | 548,919 | 23,813 |

### Files Read

<details><summary>12 files, ~55,628 est. tokens, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| c:/users/balin/.claude/plans/cached-snuggling-avalanche.md | 1 | 298 | $0.00 |
| plan/pending/bound-sql-statement.md | 2 | 2,493 | $0.00 |
| plan/pending/sql-parser.md | 5 | 11,695 | $0.00 |
| plan/pending/sql-statement.md | 1 | 2,697 | $0.00 |
| program/src/common/document.jl | 1 | 585 | $0.00 |
| program/src/document/sql.jl | 5 | 6,081 | $0.00 |
| program/src/projection/primitive/sqlrawtosql.jl | 12 | 3,097 | $0.00 |
| program/src/projection/primitive/sqltosyntax.jl | 5 | 17,756 | $0.00 |
| program/src/projectured.jl | 8 | 6,193 | $0.00 |
| test/src/projection/sqlrawtosqltest.jl | 2 | 2,967 | $0.00 |
| test/src/projection/sqltosyntaxtest.jl | 3 | 1,540 | $0.00 |
| test/src/projecturedtest.jl | 1 | 226 | $0.00 |

</details>

### Files Edited

<details><summary>7 files, ~1,534 est. tokens, ~$0.00</summary>

| File | Edits | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| c:/users/balin/.claude/plans/cached-snuggling-avalanche.md | 3 | 71 | $0.00 |
| plan/pending/sql-parser.md | 4 | 109 | $0.00 |
| program/src/document/sql.jl | 4 | 56 | $0.00 |
| program/src/projection/primitive/sqlrawtosql.jl | 6 | 197 | $0.00 |
| program/src/projectured.jl | 3 | 84 | $0.00 |
| test/src/projection/sqlrawtosqltest.jl | 32 | 989 | $0.00 |
| test/src/projecturedtest.jl | 1 | 28 | $0.00 |

</details>

### Irrelevant Reads (approx)

<details><summary>5 files read but never edited, ~25,071 est. tokens wasted, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| plan/pending/bound-sql-statement.md | 2 | 2,493 | $0.00 |
| plan/pending/sql-statement.md | 1 | 2,697 | $0.00 |
| program/src/common/document.jl | 1 | 585 | $0.00 |
| program/src/projection/primitive/sqltosyntax.jl | 5 | 17,756 | $0.00 |
| test/src/projection/sqltosyntaxtest.jl | 3 | 1,540 | $0.00 |

</details>

