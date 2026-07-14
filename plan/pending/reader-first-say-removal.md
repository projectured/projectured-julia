# Reader: remove "first say", let the input domain override *knowingly*

## Summary

`ChainingProjection`'s reader has a pre-pass that gives the **first** (input-domain)
stage a direct read of the raw gesture before any output-domain operation is threaded
back. That pre-pass exists to work around a one-line defect: the generic
`Intent` → 3-arg bridge **drops the gesture** whenever an operation is present, so no
step in the backward thread can override.

The cost is paid in the domains. Because the pre-pass hands the domain an *empty*
operation slot, the domain must reconstruct — from the reference path alone — what the
output layers *would have* done with the key, in order to decline. That reconstruction
is ~90 of the 134 lines of reader helpers in `package/domain/main/json/Json.jl`, and it
is duplicated **verbatim** (modulo renaming; only comments differ) in
`package/domain/main/yaml/Yaml.jl`.

This plan removes the pre-pass, restores the gesture to the backward thread, and gives
a gesture binding an explicit `override` flag for the one case that genuinely needs to
beat a text edit. The domains then stop guessing.

## The two defects

**Defect 1 — the bridge drops the gesture.**
[`package/kernel/main/projection/Projection.jl:194`](../../package/kernel/main/projection/Projection.jl#L194):

```julia
function read_intent(p::Projection, recursion, change::Intent, iomap)
    payload = change.operation === nothing ? change.gesture : change.operation
    op = read_intent(p, iomap, payload)
    return Intent(change.gesture, op)
end
```

`Intent` carries `(gesture, operation)` at every step *by design* — `Chaining.jl`'s own
docstring says "the gesture rides along for free — it is a field of the threaded
`Intent`, constant at every step". But the bridge collapses it to a single payload, so a
step reached during the backward translate pass only ever sees the operation. The last
step of the read — the input domain, which owns the meaning of the edit — is
structurally blind to the key that caused it.

**Defect 2 — the workaround.**
[`package/base/main/projection/higherorder/Chaining.jl:146-152`](../../package/base/main/projection/higherorder/Chaining.jl#L146-L152):

```julia
if n >= 2 && g !== nothing && change.operation === nothing
    first_out = read_intent(seq.projections[1], recursion, Intent(g, nothing), iomap.step_iomaps[1][])
    first_out.operation === nothing || return first_out
end
```

Reading is already last→first: the `while` fallback loop below this block offers the raw
gesture to stage `n`, then `n-1`, … down to stage 1, so **the domain already gets its say
whenever the output layers decline.** The pre-pass adds nothing for that case; it only
changes precedence when *both* the text layer and the domain would produce an operation —
i.e. it grants the domain an override it mostly does not want, with no information about
what it is overriding.

## Why the guards and the pre-pass cancel out

Traced against JSON with the pre-pass deleted and no other change:

| Caret | Key | Text layer | Without first-say | Today |
|---|---|---|---|---|
| text cursor in a string | `,` | produces the char edit | comma inserted | `_in_string_context` declines → comma inserted |
| whole node | `n` | declines (no cursor) | fallback scan reaches stage 1 → replace with null | domain fires → replace with null |
| introduced caret (delimiter) | `,` | declines | fallback reaches stage 1 → insert sibling | domain fires → insert sibling |
| whole number | digit | typein path produces the edit | digit appended | `_replace_number` declines → digit appended |

Identical in every row. `_is_char_cursor`, `_char_cursor_owner`, `_in_string_context` and
the char-cursor half of `_json_replaceable` exist **purely to hand back a privilege the
kernel forced on the domain**. Phase 1 below tests this claim empirically before anything
else is built on it.

The one binding that genuinely relies on first-say is XML's `_xml_insert_element`: `<`
typed mid-tag-name inserts a child element rather than a `<` character, and it carries no
text-cursor guard. That is a *real* override, and Phase 2 makes it an explicit, informed
one.

## Design

**Reading is a pure last→first thread. The gesture is present at every step. Any step may
override, but overriding is opt-in and the overriding step can see what it is
superseding.**

Three pieces:

1. **`Chaining.read_intent`** — delete the pre-pass. The existing fallback scan +
   backward translate loop is the whole algorithm.

2. **The bridge / the template reader** — a step reached in the translate pass with
   `change.operation !== nothing` and a raw `change.gesture` may still consult its input
   document's gestures. The 4-arg `Intent` form is already the overridable seam; what is
   missing is a `ProjectionTemplate` 4-arg `read_intent(p, recursion, change::Intent,
   iomap::RuleIoMap)` that:
   - `change.operation === nothing` → today's raw-gesture path (descend to focused child,
     else `read_gesture(input, evt)`), with *all* bindings eligible;
   - `change.operation !== nothing` → try the same descent, but only bindings marked
     `override` may fire; if none does, fall through to translating `change.operation`
     exactly as now.

3. **`GestureBinding` gains an `override::Bool` field** (default `false`, via an outer
   constructor so the ~35 hand-written 5-arg construction sites keep compiling), and
   `fire_gesture_bindings` takes a `claimed` argument: when `claimed !== nothing`, skip
   every binding with `override == false`. `@gestures` gains an `override(PATTERN) => …`
   rule form.

The key consequence: **a domain gesture body never needs to inspect `claimed`.** In the
raw-gesture path `claimed` is `nothing` by construction (the output layers already
declined), and in the translate path only `override` bindings run. The default — "fire
only on a key nobody else claimed" — is exactly what JSON and YAML want, so their guards
delete rather than move.

Deliberately *not* doing: passing `claimed` into gesture bodies so they can inspect or
rewrite the claimed operation. Binary override is enough for every current case; note it
as an extension point.

## Phases

### Phase 0 — baseline ✅ done

Measured on `afd65682` (pristine worktree):

| | reader | repl | typein |
|---|---|---|---|
| json | 225 / 225 | 225 / 225 | 160 / 160 |
| yaml | 224 / **1 fail** | 225 / 225 | 138 / **3 fail** |
| xml | 225 / 225 | 225 / 225 | 516 / 516 |

The 4 YAML failures are pre-existing (1 reader, 3 typein) and unrelated.

### Phase 1 — prove the cancellation ✅ done — **hypothesis CONFIRMED**
- [x] Delete the first-say block from `Chaining.read_intent`.
- [x] Delete from `Json.jl`: `_is_char_cursor`, `_char_cursor_owner`, `_in_string_context`,
      the `_is_char_cursor` exclusion in `_json_replaceable`, and `_replace_number`'s
      "already a number" guard (folded back into a plain `_replace`).
- [x] Same deletions in `Yaml.jl`. (91 lines gone across the two files.)
- [x] Re-ran the Phase 0 tests: **every count identical**, including YAML's 4 pre-existing
      failures. The pre-pass and the guards do cancel out exactly.

**Finding: the test suite is blind to the XML override.** XML did *not* regress in the
suite — but only because nothing tests it:

- `test_reader` types only `'a' 'Z' '0' ' ' ',' '.' '\n' 'é' '€'` — never `<` or `"`.
- `test_xml_to_syntax_reader` drives `RecursiveProjection(XmlToSyntax())`, a **single**
  stage. First-say only ever applied with `n ≥ 2`, so a one-stage test cannot see it.

Driving the full chain by hand shows the regression is real:

| caret | key | baseline (first-say) | Phase 1 |
|---|---|---|---|
| `tag{1}` | `<` | CompoundOperation (insert child) | **ReplaceStringRangeOperation** |
| `tag{1}` | `"` | CompoundOperation (insert text) | **ReplaceStringRangeOperation** |
| `tag{1}` | `x` | ReplaceStringRangeOperation | ReplaceStringRangeOperation ✓ |
| `∅` | `<` | CompoundOperation | CompoundOperation ✓ |

- [x] New `test_xml_override_gestures()` (`XmlToSyntaxTest.jl`) drives the **full chain**
      and pins all four rows. The two override rows are `@test_broken` until Phase 2.
- [x] `MousePress` routing: **the pre-pass was breaking it.** First-say pre-offered a raw
      `MousePress` to stage 1 *before any geometry was resolved*. Dropping it repaired
      collapse-on-header-click: the six `@test_broken` markers in `AssistantMvpTest.jl`
      ("collapse-on-header click routing regressed") now pass and are promoted to `@test`.
      `test_split_pane_drag` and the workbench click/key tests are unchanged.

Commit: `refactor: read last→first — drop ChainingProjection's input-domain "first say"`

### Phase 2 — the override seam (restores XML, on purpose this time) ✅ done
- [x] `GestureBinding`: add `override::Bool`; outer constructor defaults it to `false`.
- [x] `fire_gesture_bindings(bindings, target, selection, event, claimed)`: skip
      non-`override` bindings when `claimed !== nothing`. Threaded `claimed` through
      `read_bound_gesture` / `read_gesture` as a **keyword** defaulting to `nothing`.
      Safe because `read_gesture` turned out to have exactly *one* method (the reified-table
      interpreter) — the `read_gesture(::TextText, …)` the `Console.jl` comment names does
      not exist, so no hand-written method chokes on the new kwarg.
- [x] `@gestures` / `@gesture_set`: parse an `override(PATTERN) => …` rule form.
- [x] `ProjectionTemplate`: the 4-arg reader, plus the `ClaimedGesture` payload.
- [x] `Xml.jl`: `<` and `"` marked `override`. `:insert` / `:space` / `=` did **not** need
      it — they are not printable characters the text layer would claim.
- [x] Un-broke the XML assertions from Phase 1; re-ran the Phase 0 tests: **every count
      identical to baseline** (json 225/225/160, yaml 224+1f/225/138+3f, xml 225/225/516),
      and `test_xml_override_gestures` is now 37/37 with no `@test_broken`.

**Where the 4-arg reader hangs — three decisions the obvious design gets wrong.**

*It is emitted per concrete projection type, not keyed on `RuleIoMap`.* A method
`read_intent(p::Projection, recursion, ::Intent, iomap::RuleIoMap)` is ambiguous with
`RecursiveProjection`/`TypeDispatching`'s own 4-arg methods (more specific in arg 1, less
in arg 4) — and those wrappers are transparent, so they *do* get handed a `RuleIoMap`.
So `@projection_template` emits the 4-arg entry (74 of them, one per template projection),
each delegating to `template_read_intent`. This is also why the fix cannot simply live in
the generic bridge: `Projection.jl` loads before `ProjectionTemplate.jl` and cannot name
`RuleIoMap`.

*The gesture rides `read_intent` as a `ClaimedGesture` payload, not a fifth generic
function.* Descent already dispatches on what the payload *is* (raw event / `Operation`);
a new function to descend with would be a new interface obligation on every projection.

*But the claimed-gesture descent is a private `RuleIoMap`-only walk
(`_read_override_gesture`), not the `read_intent` recursion the unclaimed path uses.*
Two reasons, either one fatal:
  - ~40 hand-written readers take an **untyped** payload argument
    (`read_intent(p::TextToGraphics, iomap::…, evt)`). A `ClaimedGesture` reaching one is
    either mistaken for an event or ambiguous with the `RuleIoMap` method.
  - The claimed operation is expressed in the **enclosing** stage's output vocabulary. A
    child that translated it instead of declining would map a reference it does not own.
Nothing is lost by the private walk: only a template node hosts gestures, and a gesture is
all this is looking for.

**Full-suite diff against the pristine baseline `afd65682`** (per-package suites; the
targeted json/yaml/xml tests alone would have missed both findings below):

| suite | baseline | Phase 1+2 |
|---|---|---|
| kernel | 425 / 425 | 425 / 425 |
| base | 97 / 97 | 97 / 97 |
| visual | 51846 pass, 1 broken | 51846 pass, 1 broken |
| domain | 125963 P / 93 F / 1 E / 15 B | 125975 P / 93 F / 1 E / 9 B |

No new failure or error anywhere; domain's 93 F / 1 E (`mixed`, `graph`,
`TableNavigation`) are pre-existing. The two things that *did* move:

- **`JsonToSyntaxTest`'s "digit gating"** asserted that a digit at a character cursor in a
  number *declines* — at a **single stage**, where there is no text layer. That was
  `_replace_number`'s guard, and it is exactly the reconstruction this plan removes. The
  gating is real but belongs to the chain: single-stage now yields a `CompoundOperation`
  (the domain replaces), the full chain a `ReplaceNumberRangeOperation` (the text layer
  claims the digit). Rewritten to pin both. Same class as the XML finding, opposite sign —
  a single-stage test cannot see a cross-stage rule.
- **Six `@test_broken` markers now pass** (see Phase 1's MousePress item).

Commit: `feat: gesture bindings can override a claimed key (replaces "first say")`

### Phase 3 — name the residual kernel concepts
What survives in `Json.jl` after Phase 1 is the *node-naming* question, not caret
archaeology: `_is_introduced` (a `ProjectionReference` head — this idiom appears at 12+
sites across kernel/visual/domain and has no name) and `_replace`'s normalization of an
introduced caret to `∅`.

- [ ] `ReferenceModule`: `try_evaluate_reference(doc, ref, default = nothing)` — kills the
      `try evaluate_reference(...) catch; nothing end` idiom at its 10 sites.
- [ ] Kernel predicate for "the caret sits on a projection-introduced token"
      (`is_introduced_reference` or similar), plus the "which node does this caret name"
      normalization. Reference or selection layer — decide during implementation; the
      selection layer is a seal candidate (`plan/pending/selection-layer-seal-handoff.md`),
      so check that first.
- [ ] Rewrite `Json.jl` / `Yaml.jl` / `Xml.jl` against them.

Commit per extraction.

### Phase 4 — declarative extractions (orthogonal to Phases 1-3; do last)
- [ ] **Type-to-replace from the domain kit.** `@gestures JsonDocument`'s
      `n`/`f`/`t`/`"`/`[`/`:`/`{`/digit table is a shortcut-key layer over
      `make_insertion_document` — the same machinery `JsonInsertion`'s typed-name buffer
      already uses. Add an `insertion_key(::Type{JsonString}) = '"'` trait beside
      `@insertion` in `DomainModule`, and have `@domain` emit one generic gesture set over
      `insertion_candidates(root)`. Deletes both `@gestures <X>Document` blocks and
      `_replace` / `_replace_number` entirely.
- [ ] **Append-into-collection.** `_array_insert`, `_object_insert`,
      `_xml_insert_element` / `_text` / `_node` / `_attr` are one shape:
      `n = length(field); insert_elements(ref, n, [new], ref[n+1]…cursor)` — and the cursor
      they hand-write is *already* the selection `make_insertion_document(T)` carries. Add
      `append_insertion_operation(doc, :elements, JsonInsertion)` concatenating the
      insertion's own embedded selection. Covers 5 of the 15 `insert_elements` sites in the
      domain package.
- [ ] **Field-to-field motion.** JSON/YAML Tab (key→value) and XML `=` (name→value) are one
      `move_to_field(doc, sel, from, to)`.

## Expected outcome

`Json.jl`'s reader region: 134 lines → ~35 after Phase 1-3, → near zero after Phase 4.
`Yaml.jl` becomes ~80 lines of pure declaration. The point is not tidiness: only **json,
yaml, xml and workbench** have `@gestures` at all today — Sql, Julia, Ini, Ned, Markdown
and Book have *zero authoring*, and 134 lines of caret archaeology per domain is a
plausible reason why.

## Risks

- **The cancellation hypothesis is the load-bearing claim.** Phase 1 tests it directly and
  cheaply. Everything else is contingent on it.
- **Pass-through readers returning raw gestures.** The scars in
  `WorkspaceToFileSystem.jl:56` and `:86` (a `read_intent` pass-through must return an
  `Operation` or `nothing`, never the bare gesture) do **not** go away: the fallback scan
  hands bare gestures to earlier stages too. Keep that contract; consider asserting it.
- **`MousePress` through first-say** (see Phase 1) — the least-understood consumer of the
  pre-pass.
- **`applicable` arity.** Deliberately *not* widened to `(doc, sel, claimed)`: that would
  touch ~35 hand-written `GestureBinding(...)` sites across base/visual/domain. The
  `override::Bool` field keeps the change to one optional field plus the firing loop.

## Conventions

- Work in a dedicated git worktree, not the main checkout (the main checkout sees
  concurrent user edits — commit explicit paths, never `git commit` pathless).
- Tests: narrowest scope first (`test_typein(json_example)` etc.), never `test_all()`.
