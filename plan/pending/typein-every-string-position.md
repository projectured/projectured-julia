# Type-in at every string position

## Goal

`test_typein` exercises **one** cursor position per editable string: in
[`_typein_one`](../../package/visual/test/editor/TypeinTest.jl#L179) the cursor is
placed at `k = min(1, n)` — one character into the string (or `0` if empty).
Everything else about the cycle (project → assert a cursor renders → `KeyPress` →
`ReplaceStringRangeOperation` → evaluate → compare the string) is already there.

Run that same cycle at **every character boundary of every editable string in the
document domain** — `k = 0 … n` for a string of length `n`, the `n + 1` cursor
positions `collect_position_selections` calls "the carets".

The boundary carets are where the bugs are: `k = 0` and `k = n` sit exactly where
the projection also renders the neighbouring chrome (a quote, a delimiter, the next
token), so those are the positions where a typed character can land in the wrong
slot or produce no operation at all. The current test never visits them.

## Prerequisite: the test is vacuous today — it must be fixed first

**Measured on the current tree: `walk_typein` reports 0 ok / 113 targets across all
six sweep examples** (json 0/23, json_string 0/1, text 0/1, xml 0/52, book 0/22,
syntax 0/14). Every target fails at step 2 with `"no cursor in Graphics image"`, so
**no type-in has ever reached the reader** — steps 3–6 (`read_intent`,
`evaluate_operation`, the string comparison) are dead code in every run. The memory
notes recording "json 0/22 / xml 0/51 pre-existing no-cursor fails" are this same
bug, mis-attributed to the domains.

Two independent defects, both cheap to fix:

1. **`hasproperty(iomap, :output)` is always `false` for a chained projection.**
   [`ChainingProjectionIoMap`](../../package/base/main/projection/higherorder/Chaining.jl#L29)
   synthesizes `:output` in a `Base.getproperty` override (it pulls the last stage's
   iomap) but never extends `Base.propertynames`, which therefore reports only the
   three real fields. So `iomap.output` *works* while `hasproperty(iomap, :output)`
   is `false` — and [`_cursor_present`](../../package/visual/test/editor/TypeinTest.jl#L155)
   is `hasproperty(iomap, :output) && _find_cursor_rect(iomap.output) !== nothing`,
   which short-circuits to `false` for every example (they are all chains).
   *Fix (main code, `Chaining.jl`, not a sealed file):*
   `Base.propertynames(io::ChainingProjectionIoMap) = (fieldnames(ChainingProjectionIoMap)..., :output)`
   — `propertynames` must agree with `getproperty`. Only `:output` is synthesized;
   the `hasproperty(iomap, :input)` guards in the kernel hit a real field and are
   unaffected.

2. **`_find_cursor_rect` accepts the "no cursor" rect.** The caret is a
   `GraphicsRect` that is *always* in the canvas: its width cell is `2` when a
   cursor exists and `0` when it does not
   ([TextToGraphics.jl:257](../../package/visual/main/text/TextToGraphics.jl#L257)).
   The predicate is `Int(x.w) <= 5`, which a zero-width rect satisfies — so once
   defect 1 is fixed, the check would pass *unconditionally* instead of failing
   unconditionally. It must require a visible caret: `1 <= Int(x.w) <= 5`.

Fixing 1 without 2 replaces a test that always fails with a test that always
passes. Both, or neither.

## Design

### 1. Enumerate positions per target

Keep `_collect_string_refs` exactly as it is — same targets, same skips
(`selection`, `StyleFont`, `SyntaxLeaf`/`SyntaxNode` `open`/`close`/`sep`), same
three kinds (`:plain` / `:textstring` / `:texttext`). This change is only about how
many cursor positions each target is tested at. Restructure the driver as:

- `_typein_positions(n, policy)` → the `Vector{Int}` of boundaries to test.
- `_typein_at(document, projection, target, k, ch)` → today's six-step cycle with
  `k` passed in (this is `_typein_one`, parameterized).
- `_typein_target(document, projection, target, ch, policy)` → read the pristine
  string once, then for each `k`: run `_typein_at`, then restore (below).

`walk_typein` returns one record per `(target, k)`: `(ref, position, ok, message)`.
`test_typein` emits one `@test` per record and names the position in the `@warn`.

### 2. Restore the document between positions

Every position must be typed into the *same* pristine string, so the edit at `k`
must be undone before `k + 1`. Undo with the operation that made it:

```julia
ReplaceStringRangeOperation(append_reference(target.cursor, RangeReference(k, k + length(ch))), "")
```

`evaluate_operation` splits the reference into `(target_path, field_name, range_step)`
and hands the field's value to `splice_value!`, which dispatches on the value's
*representation* — so one op covers all three kinds: plain String, `TextString`
span, and `TextText` flat offset across spans
([Text.jl:263](../../package/visual/main/text/Text.jl#L263); the insert lands in the
first span containing the offset and the delete hits that same span, so the undo is
exact). **Verified in the prototype: zero restore failures across 1188 positions.**

After each undo, re-read and compare against the pristine string. On mismatch,
record a `"document not restored after typing at k"` failure and skip that target's
remaining positions — never keep testing a corrupted document. Other targets
continue.

### 3. Exceptions must not abort the walk

`book` currently throws out of `_cursor_present` — the cursor search forces the
lazy graphics cells, and forcing them raises `under-typed @reference (missing node
types)` from [BookToSyntax.jl:129](../../package/domain/main/book/BookToSyntax.jl#L129).
`print_document` is inside a `try`, but the *forcing* happens later, in the cursor
search, which is not. Wrap the cursor check so a throwing domain becomes a failed
record instead of killing the whole walk.

### 4. Position policy (cost control)

```julia
walk_typein(document, projection; replacement="X", positions=:all)
```

- `:all` — every boundary `0:n` (the new default).
- `:ends` — `unique([0, min(1, n), n])`: both boundary carets plus one interior one.
- `:first` — today's `[min(1, n)]`, so the old cost is reproducible.

### 5. Out of scope

- **Cursor-moves check.** `_cursor_present` only asserts *some* caret rect exists,
  not that it is at position `k`. Asserting the rect *moves* between consecutive `k`
  is a stronger test but fragile across line wraps — follow-up, not this change.
- **Walker convergence.** `collect_position_selections`
  ([base/test SelectionEnumeration.jl](../../package/base/test/document/SelectionEnumeration.jl#L100))
  already enumerates every caret of every text leaf for the navigation-completeness
  suite, and after this change the type-in walk enumerates the same set — but the two
  walkers disagree: `_walk_document` has no `TextText` flat-offset leaf (it descends
  into the spans and yields `.content.elements[i].content{k}` instead of the flat
  `.content{k}` the reader uses), and it does not skip `StyleFont` or syntax chrome.
  Converging them would delete a walker, but it moves the *navigation* ground truth
  too. Follow-up.

## Measurements

Prototyped with both prerequisite fixes applied and the every-position loop +
inverse-op restore in place (scratch script, not committed):

| example | targets | boundaries (Σ len+1) | every-position result | time | ms/cycle |
|---|---|---|---|---|---|
| json | 23 | 160 | **160/160** | 9.1 s | 57 (incl. JIT warm-up) |
| json_string | 1 | 13 | **12/13** | 0.5 s | 37 |
| text | 1 | 449 | **449/449** | 1.0 s | 2 |
| xml | 52 | 516 | **516/516** | 16.5 s | 32 |
| syntax | 14 | 50 | **50/50** | 0.5 s | 9 |
| book | 22 | 1003 | throws (see §3) | — | — |
| **total** | **113** | **2191** | | **~28 s** (5 of 6) | |

String lengths: json median 6 (max 11), xml median 5 (max 62), syntax median 1
(max 9), text a single 448-char paragraph, book median 46 (max 143).

**The full-position sweep costs ~30–60 s across the six examples** (≈19× the cycles
of the one-position walk, at 2–57 ms each). That is affordable: `positions=:all` can
be the default for both `test_typein` and the `test_typeins()` sweep, with `:ends`
held in reserve.

## Findings (from the prototype — the harvest this change is for)

Once the cursor check works, the domains are in far better shape than the memory
notes suggest — the "wholesale type-in failures" were the broken check, not the
domains. The real defects the every-position walk exposes:

1. **`json_string`, `k = n` (last caret, 12-char string): `KeyPress` produces
   `nothing`** — no operation at the end of the string. The only genuine
   position-dependent failure in 1188 positions. Typing at the very end of that
   document's string is a no-op in the editor.
2. **`book` throws** `under-typed @reference (missing node types)`
   ([BookToSyntax.jl:129](../../package/domain/main/book/BookToSyntax.jl#L129)) as
   soon as the graphics cells are forced with a caret set. A real reference-typing
   bug, masked until now.
3. `k = 0` (the caret before the first character) passes everywhere it was reachable
   — the boundary that looked most at risk is fine.

Fixing 1 and 2 is separate work; this plan's job is to *surface* them and leave them
recorded here.

## Steps

1. **Fix the vacuous cursor check** (the two prerequisite defects):
   `Base.propertynames` on `ChainingProjectionIoMap`, and `1 <= w <= 5` in
   `_find_cursor_rect`. Run `test_typein` on json / json_string / text / xml /
   syntax and confirm the counts flip from 0/113 to passing. Commit — this is a
   standalone bug fix and should land on its own.
2. **Catch exceptions around the cursor check** so `book` reports a failed record
   instead of aborting the walk (§3). Commit.
3. **Refactor to a position loop.** Split `_typein_one` into `_typein_at(…, k, …)` +
   `_typein_target`, add `_typein_positions(n, policy)`, thread `positions` through
   `walk_typein` / `test_typein`, extend the record with `position`. Run with
   `positions=:first` and confirm the step-1 counts are unchanged — a provable no-op
   refactor. Commit.
4. **Add the restore** (inverse `ReplaceStringRangeOperation` + post-undo
   verification). Still `:first`. Commit.
5. **Switch the default to `:all`** and run the sweep. Expect the numbers in
   *Measurements*; anything else is new information — triage it into the *Findings*
   section by position class (`k = 0` / interior / `k = n`) and target kind before
   committing.
6. **Docs + baselines.** Update
   [documentation/testing.md](../../documentation/testing.md) (the `test_typeins()`
   row, "one `@test` per string" → per string *position*, and the `walk_typein` row
   in the walker table), the `TypeinTest.jl` header, and the `ProjecturedVisualTest`
   docstring. Re-record the type-in baselines in memory — the json/xml, ned, and
   julia baseline notes are all wrong (they blame the domains for the broken check).
7. Move this plan to `plan/done/`. Open the two real bugs (Findings 1 and 2) as
   their own work.

## Follow-ups (not this plan)

- Fix the `json_string` end-of-string no-op and the `book` under-typed `@reference`.
- Assert the caret rect *moves* between consecutive positions.
- Converge `_walk_strings!` with `_walk_document` / `collect_position_selections`
  (needs a `TextText` flat leaf in the base walker).
- `ned` / `julia` type-in baselines (34 and 6 failures per memory) should be
  re-measured after step 1 — they may be largely the same broken check.
