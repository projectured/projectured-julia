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

### Phase 3 — name the residual kernel concepts ✅ done

- [x] `try_evaluate_reference(doc, ref, default = nothing)` — six sites, plus a `::Nothing`
      path method so "no selection resolves to no node" needs no guard. **Two of the six
      caught for *control flow*, not a value** (a `break` in `Focusing.jl`, an early
      `return` in `ClipboardToAny.jl`); they pass an explicit `missing` default, because a
      path that resolves to an *empty field* is still a resolution and must not be
      mistaken for a failure. A `nothing` default there would have been a silent bug.
- [x] `is_introduced_reference(reference[, projection])` + `named_node_reference`.
- [x] Rewrote `Json.jl` / `Yaml.jl` / `Xml.jl`, and folded the other 11 open-coded copies.

**The layer question the plan left open is settled by the layering itself.**
`ProjectionReference` is a *projection*-layer type (11); the reference (7) and selection
(8) layers load before it and cannot name it. So the predicate lives in
`projection/ProjectionReference.jl` — **not** the selection layer, whose seal is therefore
untouched (`plan/pending/selection-layer-seal-handoff.md` is unaffected).

`ProjectionTemplate` already had the two-argument form privately named —
`_own_introduced(p, reference)` — sitting next to *five copies of its own body*. That is
the tell: an unnamed concept gets rewritten, not reused. No raw
`head isa ProjectionReference` survives in any main source file except the definition.

### Phase 4 — declarative extractions

- [x] **Append-into-collection.** `append_insertion_operation(doc, :children, XmlText)`.
      Eight hand-written appenders (JSON 2, YAML 2, XML 4) were one shape. The cursor was
      never a choice: `make_insertion_document(T)` already carries the selection its
      `@insertion` factory declared, so each appender was re-deriving the cursor its own
      factory had already stated.
- [x] **Field-to-field motion.** `move_to_field(doc, :key, :value)`. Where the cursor
      lands is decided by what the target *is* — a child document is named whole, a
      primitive text field takes a caret at its start. That is exactly what the three
      versions encoded by hand (JSON/YAML `.value` whole because it is a `Document`, XML
      `value{0}` because it is a `String`), so it needs no policy argument.
- **Type-to-replace from the domain kit — dropped as obsolete.** The finding below is why:
  the premise does not survive contact. What this item was really reaching for — the
  domains stop hand-rolling their authoring — arrived instead as the four domain-kit verbs
  (`insert` / `append` / `move` / `replace`), which is where the duplication actually was.

**Two things the extraction surfaced.**

`sel` is **not in scope** in a `@gestures` right-hand side — only `doc` and `event` are
(the rhs closure is `(doc, event)`; `sel` belongs to the `when(...)` precondition).
`Gestures.jl`'s header comment claims both. That comment is wrong and should be fixed.

The Tab op's terminal type checkpoint is now the value's **concrete** type
(`::JsonNumber`), not the declared field type (`::Document`) the old code spelled by
hand. This is the canonical annotated form — `set_selection!` refines the declared path
to exactly this when it stores it, so the hand-written checkpoint was being replaced on
storage anyway. (Verified directly: `set_selection!(obj, …value::Document)` reads back as
`…value::JsonNumber`.) One test pinned the pre-refinement form; updated.

**Finding — the `insertion_key` trait does not pay for itself, and is obsolete.** The plan
claimed it "deletes both `@gestures <X>Document` blocks and `_replace` / `_replace_number`
entirely". It cannot:

- A `Type → Char` trait is **not injective and cannot seed a value**. `t`/`f` are two keys
  mapping to *one* type (`JsonBool`) with different values, and the digit row carries data
  from the key into the document (`JsonNumber(parse(Int, string(c)))`). Those rows must
  stay hand-written, so `_replace` survives and the `@gestures` block does not vanish.
- For the rows it *does* cover, it is a **1:1 line trade**:
  `KeyPress('"') => … make_insertion_document(JsonString)` becomes
  `insertion_key(::Type{JsonString}) = '"'`. No line is saved.

Stripped of the line-count argument, all it offered was **lowering the barrier for a new
domain** — and the domain-kit verbs deliver that without a new `@domain` emission or a
`replaceable(doc, sel)` precondition trait. A gesture table that reads
`KeyPress('[') => replace_selected_document(doc, make_insertion_document(JsonArray))` is
already declarative; moving the key into a trait would only move the same line elsewhere
while leaving the value-carrying rows (`t`, digits) behind as an exception. Dropped.

## Expected outcome

`Json.jl`: **201 → 163 lines**; its reader region 134 → 68. The plan predicted "~35 after
Phase 1-3, near zero after Phase 4" — that assumed the whole gesture table would evaporate,
which the finding above rules out. `Yaml.jl` is now pure declaration apart from the same
value-carrying tail.

The point was never tidiness: only **json, yaml, xml and workbench** have `@gestures` at
all — Sql, Julia, Ini, Ned, Markdown and Book have *zero authoring*. Phases 1-3 removed the
reason (134 lines of caret archaeology per domain); Phase 4's remaining item is what would
actually make authoring declarative.

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
