# Session Analysis Report

**Generated:** 2026-06-20 19:55
**Source:** `C:\Users\balin\.claude\projects\c--Users-balin-gitworkspace-projectured-julia\e32135b4-3814-4342-996c-678bc6bfbb35.jsonl`

---

## Session: Understand rebase safety and database branch preservation

Source: `e32135b4-3814-4342-996c-678bc6bfbb35.jsonl` | Workspace: `c:\Users\balin\gitworkspace\projectured-julia` | Branch: `database`

> **Cost basis:** subscription-amortized, not API list price. Subscription $20/mo (`--subscription`, default $20) → weekly budget $4.67 (÷ 4.286 wk/mo). Weight = weekly budget ÷ *estimated* weekly usage $371.52 = **×0.0126**. Est. Cost below is this weight applied to list price.

### Token Usage

| Metric | Value | $/MTok | Rel. Weight | Est. Cost | Notes |
|---|---:|---:|---:|---:|---|
| **Effective total** | **2,890,070** | | | **$0.03** | input (all sources) + output |
| Output | 14,275 | $25.00 | **5.0×** | $0.00 | most expensive |
| Fresh input | 131 | $5.00 | 1.0× | $0.00 | non-cached input tokens |
| Cache creation | 95,529 | $6.25 | 1.25× | $0.01 | new cache entries |
| Cache read | 2,780,135 | $0.50 | 0.1× | $0.02 | cheapest |
| Effective input | 2,875,795 | | | | fresh + cache creation + cache read |
| Cache hit rate | 96.7% | | | | cache read / effective input |
| Discovery cost | 7,911 | | | | tokens before first Edit/Write |

> **Budget impact:** $0.03 — output tokens account for 15% of cost

### Activity

| Metric | Count | Eff. Input | Output |
|---|---:|---:|---:|
| Assistant turns | 93 | 2,875,795 | 14,275 |
| Files read | 6 | | |
| Files edited | 5 | | |
| Irrelevant reads ≈ | 1 | | |
| Multi-edited ≈ | 4 | | |
| First code at token | 7,911 | | |

### Tool Calls

| Tool | Count | Eff. Input ≈ | Output ≈ |
|---|---:|---:|---:|
| Bash | 38 | 1,113,583 | 5,529 |
| Edit | 9 | 348,916 | 4,370 |
| Read | 11 | 370,520 | 1,192 |

### Files Read

<details><summary>6 files, ~5,593 est. tokens, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| example/src/examples.jl | 1 | 834 | $0.00 |
| program/src/projection/primitive/sqltosyntax.jl | 3 | 1,487 | $0.00 |
| program/src/projection/primitive/texttowidget.jl | 3 | 724 | $0.00 |
| program/src/projection/primitive/widgettographics.jl | 1 | 470 | $0.00 |
| program/src/projectured.jl | 2 | 1,250 | $0.00 |
| test/src/projecturedtest.jl | 1 | 828 | $0.00 |

</details>

### Files Edited

<details><summary>5 files, ~272 est. tokens, ~$0.00</summary>

| File | Edits | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| example/src/examples.jl | 1 | 27 | $0.00 |
| program/src/projection/primitive/sqltosyntax.jl | 2 | 66 | $0.00 |
| program/src/projection/primitive/texttowidget.jl | 2 | 67 | $0.00 |
| program/src/projectured.jl | 2 | 56 | $0.00 |
| test/src/projecturedtest.jl | 2 | 56 | $0.00 |

</details>

### Irrelevant Reads (approx)

<details><summary>1 files read but never edited, ~470 est. tokens wasted, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| program/src/projection/primitive/widgettographics.jl | 1 | 470 | $0.00 |

</details>

