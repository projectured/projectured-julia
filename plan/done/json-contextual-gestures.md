# Contextual JSON authoring gestures (gesture overrides text-insert)

> **Implemented (verified).** Key deviations from the design below, discovered
> during implementation:
> - The override lives in the **`SequentialProjection` reader**, not a leaf 4-arg
>   `Change` reader. A leaf `(Projection, _, Change, RuleIoMap)` method was
>   method-ambiguous with the `TypeDispatchingProjection` / `RecursiveProjection`
>   wrapper readers, and (for introduced carets) the text-insert op *dies at the
>   Syntax layer* before the JSON layer is reached. Instead, `Sequential` gives
>   the **first stage** (input-domain projection) a direct read of the raw gesture
>   before threading any output op; a firing structural gesture wins. Clean, no
>   ambiguity, and reaches the gesture regardless of where the text op would die.
> - Introduced-caret type-to-replace is scoped to **`JsonInsertion` + containers**
>   (not concrete scalars' quotes/keyword) so the minimal `json_null` / `json_string`
>   leaf-projection examples survive the repl sweep.
> - **`json_insertion_example` switched to the full json projection** (a
>   `JsonInsertion` must be replaceable; the leaf projection can't render the
>   result). Its dead leaf projection function/export were removed.
> - Part C string siblings use a single plain **`Right`** (verified to land on a
>   structural caret) instead of `Alt+Up`; number/bool siblings drop the escape;
>   level-change `Alt+Up`s stay. Replaying the edited `json_build_live` builds
>   exactly `make_json_document_example()` (modulo the known multi-digit→Float).

## Goal

Make JSON structural authoring gestures work **directly from the text caret**,
so the user does not have to switch to a structural selection first. Concretely:

- `,` at the end of (or inside) a just-typed value inserts a **sibling**
  element/entry in the enclosing array/object — no `Alt+Up` first.
- `[` / `{` / `"` / `:` / `n` / `t` / `f` / digit on a `JsonInsertion`
  placeholder (or any whole/introduced caret) replace it with the new value.

The visible payoff is a **much shorter `json_build_live`** keystroke script: the
`Alt+Up` "switch to structural selection" steps become unnecessary.

## Mechanism (user's framing)

The reader threads a `Change` that **always carries the original gesture**
alongside the operation produced so far. The pipeline reads last-stage-first, so
`TextToGraphics` turns a printable key into a character-insert op early; but
`JsonToSyntax` is the **last** projection in the read direction, so it can
inspect `change.gesture` and **override** whatever the child/text projections
produced — the same gesture, understood structurally in context.

The `@gestures` tables (`document/Json.jl`) are already correct and already
reachable once a structural selection is in hand (verified:
`document_read(JsonArray, ',')` fires `_array_insert`). What is missing is the
**override**: today, when the text layer produces a valid character-insert
(caret inside an editable value) that op wins and the structural gesture never
gets a say. So `,` at the end of `"Alice"` inserts a literal comma instead of a
sibling entry, which is why the live script must `Alt+Up` out of the value first.

## Design

### Part A — gesture-first override at the template layer (`projection/ProjectionTemplate.jl`)

Add a 4-arg `Change` reader for template (`RuleIoMap`) projections that tries the
**original gesture** as a structural authoring gesture *before* falling back to
the threaded operation:

```julia
function projection_read(p::Projection, recursion, change::Change, iomap::RuleIoMap)
    g = change.gesture
    if g isa Union{KeyPress, KeyDown}
        gop = projection_read(p, iomap, g)        # recursive gesture reader → document_read (bubbles up)
        gop === nothing || return Change(g, gop)  # OVERRIDE the text-edit op
        change.operation === nothing && return Change(g, nothing)
    end
    return Change(g, projection_read(p, iomap, change.operation))
end
```

- The recursive gesture reader (`projection_read(::Projection, ::RuleIoMap,
  ::KeyPress/KeyDown)`, already present) descends to the focused child and
  **bubbles** to the nearest enclosing structural node's `document_read`, so a
  caret inside `name`'s value routes `,` to the enclosing object's
  `_object_insert`.
- Gating is by the `@gestures` **preconditions**, so ordinary typing is
  untouched:
  - type-to-replace (`n`/`t`/`f`/`"`/`[`/`{`/`:`/digit) is guarded by
    `_json_replaceable`, which **declines a char cursor inside an editable
    value** (`_is_char_cursor`) → the gesture returns `nothing` → the
    text-insert op is used.
  - `,` is guarded so it is **literal only in a string context** (see Part B):
    a char cursor inside a `JsonString` value or an object key → decline →
    text-insert → a literal comma in the string/key. Everywhere else (numbers,
    bools, nulls, whole / introduced carets, delimiters) → structural insert.
  - Navigation keys (arrows) have no JSON gesture → decline → op used.
- Add the `RecursiveProjection` disambiguation shim
  (`projection_read(::RecursiveProjection, recursion, ::Change, ::RuleIoMap)`
  → defer to the wrapper), mirroring the existing op/evt shims (lines ~1042 /
  ~1072), since `RecursiveProjection <: Projection` and `iomap::RuleIoMap` tie.

Lives in the generic template engine, so it benefits every `@gestures`-backed
template domain (JSON, SQL, INI). SQL/INI reader baselines must stay green
(see Risks).

Secondary robustness: opaque atomic leaves (`bound_field === nothing`) reject
text-edit ops (`projection_read(::Projection, ::RuleIoMap,
::StringReplaceRangeOperation)` returns `nothing` for them), so a non-gesture key
on `JsonInsertion`/`JsonNull` is a clean NO-OP instead of a bogus op against an
introduced position.

### Part B — JSON gestures accept introduced / whole carets (`document/Json.jl`)

Decision confirmed: **fully consistent** — any caret targeting a node is the
node. `evaluate_reference(doc, introduced_sel)` throws, which is the only reason
`_json_replaceable` rejects an introduced caret today.

- `_is_introduced(sel) = sel isa ConcreteReferencePath && sel.head isa ProjectionReference`.
- `_json_replaceable`: an introduced caret ⇒ treat as whole (`doc` is the
  target; replaceable unless `doc isa JsonObjectEntry`) — do not call
  `evaluate_reference` on it.
- `_replace`: when the selection is introduced, replace against `∅`
  (`replace_document(EmptyReferencePath(), newdoc)`; verified to yield the
  whole-replace op) instead of the proj-wrapped ref.

**`,` literal-in-string guard** (`@gestures JsonArray` *and* `@gestures
JsonObject`). Add a `when(!_in_string_context(doc, sel))` precondition to the
`,` rule so it inserts a sibling everywhere *except* when the caret is editing
string text:

- `_in_string_context(doc, sel)` ⇒ `sel` is a char cursor whose terminal field
  is `key{…}` (object keys are strings → always literal), **or** `value{…}`
  whose owning node resolves to a `JsonString`. A `value{…}` cursor owned by a
  `JsonNumber` is **not** a string context → `,` stays structural (numbers can't
  contain a comma).
- When the caret is in a string, the container `,` rule declines → the override
  falls back to the text-insert op → a literal comma lands in the string. Tab /
  `_object_tab` is unchanged.

> Consequence: a char cursor at the **end** of a string is still a string
> context (that is where you type, including a trailing comma), so completing a
> string then pressing `,` inserts a literal comma — to add a sibling after a
> string value you must first leave the string. There is no way to both type a
> trailing comma left-to-right *and* treat end-of-string `,` as structural.

### Part C — simplify `json_build_live` (`example/src/LiveExamples.jl`)

`,` now inserts a sibling in the **immediate** container directly from a
non-string value caret. Same-container siblings whose value is **not a string**
no longer need to escape first:

- **Number / bool siblings** — drop the escape entirely (`,` straight from the
  number caret / whole-selected bool): `age` (l.203), `scores[0]=95` (l.211),
  `scores[1]=87` (l.212), `version` (l.222); `active`/`draft` already escape-free.
- **String siblings** — `,` in a string is a literal comma, so the author must
  still leave the string before `,`. Replace the structural `Alt+Up`
  (`_jb_up(1)`) with a single **plain `Right`** (text-mode move past the closing
  quote to a non-string caret), if that lands on a structural-eligible position
  — *verify during implementation*; otherwise keep `Alt+Up`. Affects `name`
  (l.202), `street` (l.206), `city` (l.207), `tags[0]`/`tags[1]` (l.216/217),
  `created` (l.221).
- **Level-changing escapes** (`_jb_up(4/3)`, lines 209/214/219/224) stay — `,`
  only reaches the immediate container, so adding a root-level sibling after a
  nested container still needs explicit upward tree navigation. Re-verify each
  count against the new bubbling.
- Update the file comment to describe the contextual `,` behaviour.

Net: the 4 number/bool escapes vanish and the 6 string escapes become plain
text-mode moves (no "switch to structural selection"), directly addressing the
"constantly switches to structural selection" complaint. The replayed document
must still equal the intended structure.

## Note on the string trade-off (resolved)

`,` is structural *unless* the caret is editing string text (string value or
key), so a literal comma is fully typeable inside a string. The unavoidable
consequence is that completing a string value and pressing `,` types a comma
rather than a sibling — adding a sibling after a string needs one move out of
the string first (see Part C). This is the rule you specified and is kept.

## Test plan

- Regression probe (extend `scratchpad/repro.jl`): from an end-of-value char
  cursor, `,` yields an insert op in the enclosing container; on a
  `JsonInsertion`, `[`/`{` yield whole-replace; ordinary letters/digits inside a
  string/number still yield `StringReplaceRangeOperation`.
- Replay the simplified `json_build_live` headless and assert the final document
  equals the intended structure (the live script is exercised by
  `walk_repl_loop`-style replay or by evaluating the gesture stream).
- Targeted suites: `test_example(json_insertion_example)`,
  `test_example(json_example)`, `test_json_to_syntax()`, `test_syntax_to_text()`.
  Mind known baselines (memory: `json-reader-test-length-preexisting`,
  `typein-json-xml-baseline`).
- Broader only after green: `test_readers()` / `test_repls()` (SQL/INI ride the
  same template engine).

## Risks

- The `,` structural override could change a test that types `,` into a
  non-string value expecting text — audit `test_typein` / repl suites. (Strings
  keep literal-comma behaviour via the guard.)
- The template-layer override fires for SQL/INI too; their `@gestures` now
  override text-ops. Intended generalization, but verify their reader baselines.
- `_in_string_context` resolves the char-cursor owner via `evaluate_reference`;
  guard it with try/catch (an introduced/odd ref must not throw the precondition).
- Gesture-first runs the recursive gesture reader on every key — extra
  descent/bubble work, but it short-circuits (`nothing`) for non-JSON gestures.

## Status

- [ ] Part A gesture-first `Change` reader + RecursiveProjection shim (+ opaque-leaf suppression)
- [ ] Part B.1 `_json_replaceable` / `_replace` introduced-caret normalize (JsonDocument)
- [ ] Part B.2 `_in_string_context` guard on `,` (JsonArray + JsonObject)
- [ ] Part C simplify `json_build_live`, update comment
- [ ] Regression probe + targeted suites green; SQL/INI baselines unaffected
