# Session Analysis Report

**Generated:** 2026-06-20 19:55
**Source:** `C:\Users\balin\.claude\projects\c--Users-balin-gitworkspace-projectured-julia\bf14cd61-be92-427e-8c03-fbb986808985.jsonl`

---

## Session: Rebalance analyze session token costs

Source: `bf14cd61-be92-427e-8c03-fbb986808985.jsonl` | Workspace: `c:\Users\balin\gitworkspace\projectured-julia` | Branch: `database`

> **Cost basis:** subscription-amortized, not API list price. Subscription $20/mo (`--subscription`, default $20) → weekly budget $4.67 (÷ 4.286 wk/mo). Weight = weekly budget ÷ *estimated* weekly usage $371.52 = **×0.0126**. Est. Cost below is this weight applied to list price.

### Token Usage

| Metric | Value | $/MTok | Rel. Weight | Est. Cost | Notes |
|---|---:|---:|---:|---:|---|
| **Effective total** | **6,341,925** | | | **$0.08** | input (all sources) + output |
| Output | 88,385 | $25.00 | **5.0×** | $0.03 | most expensive |
| Fresh input | 14,095 | $5.00 | 1.0× | $0.00 | non-cached input tokens |
| Cache creation | 214,725 | $6.25 | 1.25× | $0.02 | new cache entries |
| Cache read | 6,024,720 | $0.50 | 0.1× | $0.04 | cheapest |
| Effective input | 6,253,540 | | | | fresh + cache creation + cache read |
| Cache hit rate | 96.3% | | | | cache read / effective input |
| Discovery cost | 63,775 | | | | tokens before first Edit/Write |

> **Budget impact:** $0.08 — output tokens account for 33% of cost

### Activity

| Metric | Count | Eff. Input | Output |
|---|---:|---:|---:|
| Assistant turns | 93 | 6,253,540 | 88,385 |
| Files read | 4 | | |
| Files edited | 3 | | |
| Irrelevant reads ≈ | 1 | | |
| Multi-edited ≈ | 3 | | |
| First code at token | 63,775 | | |

### Tool Calls

| Tool | Count | Eff. Input ≈ | Output ≈ |
|---|---:|---:|---:|
| AskUserQuestion | 2 | 88,454 | 6,925 |
| Bash | 4 | 221,699 | 1,508 |
| Edit | 15 | 1,113,094 | 11,105 |
| ExitPlanMode | 2 | 120,260 | 397 |
| Grep | 1 | 35,896 | 1,566 |
| PowerShell | 6 | 516,974 | 1,929 |
| Read | 9 | 573,674 | 2,921 |
| ToolSearch | 1 | 57,289 | 82 |
| Write | 1 | 49,670 | 7,552 |

### Files Read

<details><summary>4 files, ~12,379 est. tokens, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| c:/users/balin/.claude/plans/rebalance-analyze-session-token-jaunty-flame.md | 1 | 412 | $0.00 |
| .gitignore | 1 | 32 | $0.00 |
| session/analyze-session.jl | 5 | 10,044 | $0.00 |
| session/history/0000000000-history-comparison.md | 2 | 1,891 | $0.00 |

</details>

### Files Edited

<details><summary>3 files, ~686 est. tokens, ~$0.00</summary>

| File | Edits | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| c:/users/balin/.claude/plans/rebalance-analyze-session-token-jaunty-flame.md | 2 | 88 | $0.00 |
| .gitignore | 2 | 64 | $0.00 |
| session/analyze-session.jl | 12 | 534 | $0.00 |

</details>

### Irrelevant Reads (approx)

<details><summary>1 files read but never edited, ~1,891 est. tokens wasted, ~$0.00</summary>

| File | Reads | Est. Tokens | Est. Cost |
|---|---:|---:|---:|
| session/history/0000000000-history-comparison.md | 2 | 1,891 | $0.00 |

</details>

