# Selection layer — API hardening + seal handoff

> **Layout note.** This plan was written when every domain lived in one
> `ProjecturedDomain` package. Each domain is its own package now — see
> [documentation/domains.md](../../documentation/domains.md). A path or a
> module name below that still says `package/domain/` or `ProjecturedDomain`
> needs translating when the plan is picked up.

Handoff for continuing the **"seal the kernel main folder"** effort. Written after
hardening the selection API (Layer 4) and just before sealing its files.

## The overarching task

Files in `package/kernel/main/` are audited against
[documentation/architecture-requirements.md](../../documentation/architecture-requirements.md)
(the `AR-N` rules) and **sealed one at a time**. The authoritative, ordered
inventory with per-file `🔒`/`⬜` status is the **"`package/kernel/main/` seal
status"** section of [CLAUDE.md](../../CLAUDE.md) at the repo root — read it first.

Seal protocol (from CLAUDE.md):
- Introduce the next file → **audit it against architecture-requirements.md and
  present the audit** before inviting review or offering to seal.
- A file seals only once it complies, **or** a specific non-compliance is
  explicitly accepted by the user in the conversation.
- When sealing, flip its `⬜`→`🔒` in CLAUDE.md **in the same commit**.
- Never modify a `🔒` file without showing the diff and getting explicit
  per-change approval first.

## Where we are

- **Layer 1 (cell), 2 (document), 3 (reference): fully sealed 🔒.**
- **Layer 4 (selection): all four files still `⬜`** — `SelectionLayer.jl`,
  `SelectionModule.jl`, `Interface.jl`, `Selection.jl`. The API was reworked this
  session (below) before sealing, so the files must be **re-audited** against the
  AR rules before sealing.
- Layers 5–10 (operation, device, backend, projection, agent, editor): `⬜`.

The selection layer was recently extracted as kernel Layer 4 (see
`plan/done/extract-selection-layer.md`) and split into an interface fragment
(`Interface.jl`, declaration-only generics) and an implementation fragment
(`Selection.jl`, default methods + private helpers).

## What this session changed (all pushed to `origin/claude/seal-kernel-main-folder-c9qdvk`)

1. **`b283613f` — Unify `replace_selection!` / `update_selection!`.**
   They produced the same stored selection state. `update_selection!` (the
   in-place, minimally-invalidating version the editor actually used) was folded
   into `replace_selection!` and **removed**. `replace_selection!` is now the
   single public "set the selection" mutator: it canonicalizes the path (like
   `set_selection!`) then writes the shared selection chain **in place** via
   `_sync_selection!` (only cells whose content changed are touched; a caret move
   mutates just the terminal step). `ReplaceSelectionOperation` and all
   docs/comments now reference `replace_selection!`.

2. **`24964b4a` — Selection apply is atomic: match-or-fail before writing.**
   `set_selection!`, `with_selection` (calls `set_selection!`), and
   `replace_selection!` now go through `_matched_selection(document, path)`:
   canonicalize → **require the path to match** → else `throw(SelectionMismatch(...))`
   **before any cell is written**. A stale/cross-domain path no longer clears the
   old selection and stores an unresolvable partial one — it either matches and
   applies, or fails leaving the selection untouched.
   - **Match rule** (`_selection_matches` in `Selection.jl`): delegate the routing
     validation to the reference layer's tested `is_valid_reference`, **after
     dropping a terminal caret** (`_drop_terminal_cursor`). Rationale: a cursor
     step (`start == stop`) addresses a position *inside* a leaf, and a text leaf
     (`TextString`) exposes no `length`/`getindex`, so `is_valid_reference` would
     wrongly reject a real caret (documented at
     `package/base/test/document/SelectionEnumeration.jl:109`). So we strictly
     validate the routing (fields exist, element indices in range, folded node
     types hold) and accept the terminal caret by reachability, exactly as the
     selection enumeration does.
   - `SelectionMismatch` is a new exported exception (`SelectionModule` export).
   - Fail mode = **throw** and scope = **all apply entry points** were the user's
     explicit choices.

3. **`177db56c` — Import `reference_node_type` into `ProjectionModule`.**
   Pre-existing bug (not caused by the above): `package/kernel/main/projection/Projection.jl`
   used `reference_node_type` at lines 80/100 (whole-element reference mapping) but
   never imported it → `UndefVarError` whenever a whole-element selection was mapped
   through a projection (xml repl was 110/225 failing). One-line import fix.

## Verification status

Green (all `0 Fail / 0 Error`): `test_kernel()` 338, `test_base()` 82 (includes the
SelectionEnumeration whole-element + caret suites), `test_selection_locality` +
`test_repl` on `json_example` and `julia_example` (the latter uses `TextString`
leaves — the critical caret case), `test_repl(xml_example)` now 225 (was 110
failing). **Zero `SelectionMismatch` false rejections observed anywhere.**

**NOT yet verified: workbench.** The new match-or-fail gate has not been run
against workbench examples, whose tabbed panes exercise container / Document→Document
tab-boundary selections and end-cursors. This is the main remaining risk of a
false rejection.

## Next steps (recommended order)

1. **Run the workbench sweep** before sealing: `test_selection_locality(<workbench
   example>)` and `test_repl(<workbench example>)`. Watch for any
   `SelectionMismatch` in output — that would be a false rejection (a bug in
   `_selection_matches`, not a real mismatch) to fix. Find the exact workbench
   example binding by grepping `ProjecturedDomainExample` (package/domain/...).
2. **Re-audit the four selection files** against architecture-requirements.md (the
   API changed, so any earlier audit is stale), present the audit, then **seal them
   one at a time in load order**: `SelectionLayer.jl` → `SelectionModule.jl` →
   `Interface.jl` → `Selection.jl`, flipping `⬜`→`🔒` in CLAUDE.md per seal commit.
3. **Continue the seal effort** into Layer 5 (operation) and onward.

## Working constraints (do not rediscover these the hard way)

- **Sealed files**: never edit a `🔒` file without showing the diff and getting
  explicit per-change approval — blanket permission does not waive per-change review.
- **No backward-compat framing**: pre-release; never label code "legacy" /
  "backward-compatible" / "compatibility shim". Reword such labels, but do not
  degrade working code to chase the wording.
- **Tests**: run the *smallest covering test*, never `test_all()` (slow, floods
  context). Per-package: `test_kernel()`/`test_base()`/`test_visual()`/`test_domain()`
  (each in its own `package/<pkg>/test` project). Single example: `test_repl(ex)`,
  `test_printer(ex)`, `test_selection_locality(ex)`, etc. Umbrella suites (locality)
  run from the root project `--project=.` with
  `using ProjecturedTest, ProjecturedDomainExample, ProjecturedKernelTest`.
- **Git**: commit to the current branch; no `Co-Authored-By` trailer.
- **Env note**: the root `Manifest.toml` is currently **modified but uncommitted**
  (a `Pkg.resolve()` during testing added missing test-package entries). It is
  unrelated drift — do **not** commit it with feature work. Scratch files
  `_chk_*.jl` / `_enum_*.jl` at the repo root are pre-existing and untracked.

## Key source locations

- `package/kernel/main/selection/Interface.jl` — the 5 generics (declaration-only):
  `get_selection`, `clear_selection!`, `set_selection!`, `with_selection`,
  `replace_selection!`; docstrings carry the match-or-throw contract.
- `package/kernel/main/selection/Selection.jl` — default methods + private helpers
  (`_matched_selection`, `_selection_matches`, `_drop_terminal_cursor`,
  `_set_selection_walk!`, `_sync_selection!`, `_selection_child`,
  `_mutate_terminal_step!`) + `SelectionMismatch`.
- `package/kernel/main/selection/SelectionModule.jl` — imports + exports (note
  `is_valid_reference`, `EmptyReferencePath` imports; `SelectionMismatch` export).
- Reference-layer validity primitives (sealed): `is_valid_reference` /
  `get_valid_reference_prefix` at `package/kernel/main/reference/Reference.jl:488-538`.
