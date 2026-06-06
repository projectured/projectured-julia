# Bringing `JsonToSyntax` up to the Lisp reference's capabilities

## Origin

This plan comes from comparing the Julia
[`JsonToSyntax.jl`](../../program/src/projection/primitive/JsonToSyntax.jl)
against the original Common Lisp
[`json-to-syntax.lisp`](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp).
The Julia port's **printer** is sound (and its School-A reference mapping is
cleaner than the Lisp original — keep it). The gap is almost entirely on the
**reader / authoring** side, plus a few rendering-fidelity details. This plan
closes that gap.

The Lisp reader gives the editor its entire JSON-authoring vocabulary
([json-to-syntax.lisp:424-628](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L424-L628)):

- `json/read-command` — type `n`/`f`/`t`/`"`/`[`/`{`/`:`/digit to **replace**
  the selection with null / false / true / string / array / object / entry /
  number ([:424-473](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L424-L473)).
- array reader — `,` and Insert to **insert** an element
  ([:537-571](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L537-L571)).
- object reader — `,` and Insert to **insert** an entry
  ([:604-628](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L604-L628)).
- object-entry reader — **Tab** to move the cursor from key to value
  ([:587-600](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L587-L600)).
- `text/make-default-text` placeholders — `"enter json number"`,
  `"enter json string"`, `"enter key"`
  ([:327](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L327),
  [:339](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L339),
  [:391](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L391)).

The Julia version has none of these. Its readers
([JsonToSyntax.jl:135](../../program/src/projection/primitive/JsonToSyntax.jl#L135),
[:199](../../program/src/projection/primitive/JsonToSyntax.jl#L199),
[:295](../../program/src/projection/primitive/JsonToSyntax.jl#L295),
[:451](../../program/src/projection/primitive/JsonToSyntax.jl#L451),
[:459](../../program/src/projection/primitive/JsonToSyntax.jl#L459))
only re-target *existing* string/number edits and replace-selection.

---

## 0. Scope, and what is delegated to other plans

Two items from the original comparison already have dedicated plans. This plan
does **not** re-do them; it depends on them:

- **Wiring the dormant `collapsed` field** (`Cell(false)` →
  `getfield(j, :collapsed)`) and rendering folded nodes is
  [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md) §7.1–§7.2.
  The Lisp `(collapsed-p -input-)` hookup
  ([json-to-syntax.lisp:355](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L355),
  [:417](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L417))
  is exactly that plan's deliverable. **Out of scope here.**
- **Typing characters into a `JsonString` / `JsonNumber` value or an object
  key** is [text-syntax-json-typein.md](text-syntax-json-typein.md) Phase 3.
  That plan establishes the producer→translator pattern (raw key event enters
  at `TextToGraphics`, propagates up the `SequentialProjection` reader chain,
  each `*ToSyntax` translates it into its own input domain). **Out of scope
  here**, but this plan reuses its event-routing mechanism (§2).

What remains — and what this plan covers:

- **A.** New operation types for *structural* change (replace-with-primitive,
  collection insert) that the Lisp reader relies on and Julia lacks (§1).
- **B.** The JSON reader command set: type-to-replace, structural insert, Tab
  navigation (§3).
- **C.** A placeholder / default-text mechanism for empty fields and
  `JsonInsertion` (§4).
- **D.** Selection / render fidelity nits: array separator spacing, boolean
  literal addressing, number navigation wrapper, fine-grained delimiter
  selection (§5).

---

## 1. New operations (prerequisite — roadmap item #3)

Today the only document-mutating operations are
`ReplaceSelectionOperation` (cursor move,
[Operation.jl:42-50](../../program/src/common/Operation.jl#L42-L50)) and
`StringReplaceRangeOperation` / `NumberReplaceRangeOperation` (in-place text
edit). There is **no** operation that swaps the document at a selection, and
**none** that inserts/removes a collection element. The Lisp reader is built
on exactly those two:

- `make-operation/replace-target nil <new-document>` — replace the selected
  element wholesale (every `json/read-command` clause uses it).
- `make-operation/sequence/replace-range` + `make-operation/replace-selection`
  in a `make-operation/compound` — insert an element/entry and move the cursor
  into it.

### 1.1 `ReplaceDocumentOperation`

```julia
struct ReplaceDocumentOperation <: Operation
    path::ReferencePath        # selection path whose target document is replaced
    document::Document         # the replacement (carries its own initial selection)
end
```

`evaluate_operation(editor, ::ReplaceDocumentOperation)` walks `path` to the
**parent container + slot** (array element, object-entry value, or the root),
writes the new document into that slot's `Cell`, then
`replace_selection!(editor.document, path ⧺ new_document.selection)` so the
cursor lands inside the freshly-created value. This is the direct analogue of
`replace-target`. Mirror `evaluate_reference` traversal already used by the
`StringReplaceRangeOperation` evaluator (see typein plan §0).

### 1.2 `CollectionInsertOperation` / `CollectionDeleteOperation`

```julia
struct CollectionInsertOperation <: Operation
    path::ReferencePath        # .elements / .entries of the container
    index::Int                 # 0-based insertion point (1-based after +1)
    items::Vector{<:Document}
end
```

`evaluate_operation` resolves the container's `CellVector` and `insert!`s each
item. The reader pairs it with a `ReplaceSelectionOperation` (a small compound,
or just evaluate both) so the cursor moves to the new element — matching the
Lisp `make-operation/compound`. `CollectionDeleteOperation` is the inverse;
include it now so undo (roadmap #4) has a defined inverse for both.

These belong in [`program/src/common/Operation.jl`](../../program/src/common/Operation.jl)
(or a new `program/src/operation/` file if that module split has happened by
then — check before adding).

---

## 2. Event routing (reuse, do not rebuild)

The Lisp `json/read-command` matches on raw gestures inside the projection's
reader. In Julia, raw `KeyDown`/`KeyPress` events enter at the bottom of the
chain (`TextToGraphics`) and the `SequentialProjection` reader walks steps
last→first until one returns non-`nothing`
([Sequential.jl:78-92](../../program/src/projection/higherorder/Sequential.jl#L78-L92));
unhandled keys are returned so upper layers get a turn. So each JSON command
is a `projection_read(::JsonXToSyntax…, iomap, ::KeyPress)` /
`::KeyDown` method on the JSON projection — the same shape the typein plan adds
for character edits. **This routing is a dependency on the typein plan landing
first**; this plan adds JSON-specific reader methods on top of it.

A subtlety the Lisp handles and we must too: a creation command (`[`, `{`,
digit, …) should fire **only when the selection is on a replaceable JSON value**
(typically a `JsonInsertion` placeholder or a primitive), not while editing
text inside a string. The Lisp guards the number case with
`(not (typep printer-input 'json/number))`
([json-to-syntax.lisp:464-465](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L464-L465));
replicate that selection-state gating per command.

---

## 3. The JSON reader command set

All methods live in
[`JsonToSyntax.jl`](../../program/src/projection/primitive/JsonToSyntax.jl),
alongside the existing `projection_read` methods.

### 3.1 Type-to-replace (`json/read-command`)

On any JSON projection whose selection is a replaceable value, catch the
type-in `KeyPress` and return a `ReplaceDocumentOperation` with a fresh
document whose initial selection is pre-placed (mirroring the `:selection`
literals the Lisp constructs):

| Key   | Replacement document                          | Lisp ref |
|-------|-----------------------------------------------|----------|
| `n`   | `JsonNull()`                                  | [:427-430](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L427-L430) |
| `f`   | `JsonBool(false)`                             | [:431-435](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L431-L435) |
| `t`   | `JsonBool(true)`                              | [:436-440](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L436-L440) |
| `"`   | `JsonString("")`                              | [:441-445](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L441-L445) |
| `[`   | `JsonArray([JsonInsertion()])`                | [:446-451](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L446-L451) |
| `:`   | `JsonObjectEntry("", JsonInsertion())`        | [:452-457](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L452-L457) |
| `{`   | `JsonObject` with one `JsonInsertion` entry   | [:458-463](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L458-L463) |
| digit | `JsonNumber(parse(Int, ch))`                  | [:464-473](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L464-L473) |

A single shared helper `json_read_command(iomap, evt)` (the Julia counterpart
of the Lisp function) keeps the table in one place; each JSON projection's
`projection_read(::KeyPress)` calls it first, then falls through to its
existing translators. The digit case must be gated so it does **not** fire when
already editing a `JsonNumber` (let the typein path handle that instead).

### 3.2 Structural insert

- **Array** (`JsonArrayToSyntaxNode`): `,` inserts a `JsonInsertion` at the end
  of `.elements` and moves the cursor into it; Insert does the generic
  document-insertion variant. Lisp:
  [:550-569](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L550-L569).
  Julia: emit `CollectionInsertOperation(@reference(elements), n, [JsonInsertion()])`
  + a follow-up `ReplaceSelectionOperation` into the new element.
- **Object** (`JsonObjectToSyntaxNode`): `,` inserts a
  `JsonObjectEntry("", JsonInsertion())` into `.entries` and moves the cursor
  to its key. Lisp:
  [:607-626](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L607-L626).

### 3.3 Tab: key → value navigation

On `JsonObjectEntry` (handled by `CopyingProjection` today — this needs a real
reader, or the navigation handled at `JsonObjectToSyntaxNode`): Tab while the
cursor is in `.key` moves it to the head of `.value`. Lisp:
[:587-600](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L587-L600).
Julia: return `ReplaceSelectionOperation(@reference entries[i].value.<head>)`,
computing the value head from the entry's value document type.

---

## 4. Placeholder / default text

The Lisp `text/make-default-text value placeholder …` shows a muted hint when
the field is empty. Julia has no such mechanism: `JsonInsertion` hardcodes the
literal `"insert JSON here"` as *content*
([JsonToSyntax.jl:69](../../program/src/projection/primitive/JsonToSyntax.jl#L69)),
and empty strings/numbers/keys render blank.

Add a placeholder concept at the `TextString` (or `SyntaxLeaf`) level:

- `TextString` (or a thin `DefaultTextString` wrapper) gains an optional
  `placeholder::String` shown, styled muted, **iff** the live content is empty.
  This keeps "empty value" and "the literal text 'insert JSON here'"
  distinguishable — important so the reader (§3) can tell a real
  `JsonInsertion` apart from a string that happens to read `insert JSON here`.
- Use it for: `JsonInsertion` (placeholder, empty content), `JsonString`
  (`"enter json string"`), `JsonNumber` (`"enter json number"`), and the object
  key leaf (`"enter key"`).

Confirm whether the downstream `SyntaxToText`/`TextToGraphics` need to know
about placeholders or whether a computed-content `TextString` (content = value
or placeholder) suffices for rendering while a flag distinguishes them for the
reader. Prefer the smallest change that keeps the reader's emptiness test
correct.

---

## 5. Selection / render fidelity nits

Lower priority; each is independent and small.

### 5.1 Array separator trailing space
The array uses `", "` plus `indentation=1`
([JsonToSyntax.jl:277-282](../../program/src/projection/primitive/JsonToSyntax.jl#L277-L282)),
so multi-line output emits a trailing space before each newline (`1, ⏎  2`).
The Lisp switches to bare `","` in deep (multi-line) mode
([json-to-syntax.lisp:368](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L368)).
Either drop the space when `indentation > 0` (needs the separator to be
indentation-aware in `SyntaxToText`) or accept the cosmetic diff — decide when
implementing.

### 5.2 Boolean literal addressing
Lisp models `true-value-of` / `false-value-of` as distinct editable string
slots and picks the right one on read
([json-to-syntax.lisp:212](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L212)).
Julia computes `"true"/"false"` and identity-maps `value{s:e}`
([JsonToSyntax.jl:97-98](../../program/src/projection/primitive/JsonToSyntax.jl#L97-L98)),
but `JsonBool.value` is a `Bool`, so a character edit cannot map back. Since
editing a bool is normally done via the `f`/`t` replace commands (§3.1), the
simplest correct behaviour is to make the bool leaf's value **read-only** to the
typein path (reader returns `nothing` for `.value` edits) and rely on `f`/`t`.
Document the decision either way.

### 5.3 Number navigation wrapper
Lisp wraps numbers in `syntax/navigation`
([json-to-syntax.lisp:322-330](../../../projectured-lisp/source/projection/primitive/json-to-syntax.lisp#L322-L330)); Julia uses a plain
`SyntaxLeaf` ([JsonToSyntax.jl:126-128](../../program/src/projection/primitive/JsonToSyntax.jl#L126-L128)).
`SyntaxNavigation` exists in the Julia domain
([Syntax.jl:147-152](../../program/src/document/Syntax.jl#L147-L152)) but is
unused by any printer. Only adopt it if a navigation-point feature needs it;
otherwise leave the leaf as-is and note the divergence. **Likely won't-do.**

### 5.4 Fine-grained delimiter selection
Julia collapses all projection-introduced structural positions (`[`, `]`, `{`,
`}`, `,`, `:`) into one flattened `proj(p, {flat})` offset
([JsonToSyntax.jl:288-301](../../program/src/projection/primitive/JsonToSyntax.jl#L288-L301)),
where the Lisp addresses each delimiter precisely. This is a deliberate
simplification and round-trips fine. Only revisit if a feature needs to target
an individual delimiter; the §3 command set does not. **Defer / likely won't-do.**

---

## 6. Phasing

| Phase | Deliverable | Depends on |
|-------|-------------|-----------|
| 1 | `ReplaceDocumentOperation` + evaluator + unit test (§1.1) | typein plan §0 evaluator pattern |
| 2 | Type-to-replace command set (§3.1) wired into each JSON projection's `projection_read(::KeyPress)` | Phase 1; typein event routing (§2) |
| 3 | `CollectionInsert/DeleteOperation` (§1.2) + array/object `,`/Insert (§3.2) | Phase 1 |
| 4 | Tab key→value navigation (§3.3) | Phase 2 |
| 5 | Placeholder / default text (§4) | none |
| 6 | Fidelity nits (§5) as separate commits, each optional | none |

Phases 1–4 are the substance (the Lisp reader). Phase 5 is independent and can
land any time. Phase 6 items are individually optional.

---

## 7. Tests

Extend [`test/src/projection/JsonToSyntaxTest.jl`](../../test/src/projection/JsonToSyntaxTest.jl)
(printer-only today) with a reader section, mirroring the Lisp behaviours:

- **Type-to-replace**: with the cursor on a `JsonInsertion`, feed
  `KeyPress('[')` / `'{'` / `'"'` / `'n'` / `'t'` / `'f'` / `':'` / `'5'`;
  assert a `ReplaceDocumentOperation` whose `document` is the expected type and
  whose pre-placed selection matches; apply it and assert the document tree and
  selection.
- **Digit gating**: `KeyPress('5')` while editing a `JsonNumber` returns
  `nothing` from the command path (lets the typein edit win).
- **Array insert**: `KeyPress(',')` on `JsonArray([JsonNumber(1)])` yields a
  `CollectionInsertOperation` at index 1 + selection into the new element;
  after apply, `length == 2` and the cursor is in element 2.
- **Object insert**: `KeyPress(',')` on an object adds an entry and selects its
  key.
- **Tab**: cursor in `entries[1].key`, `KeyDown(:tab)` →
  `ReplaceSelectionOperation` into `entries[1].value`.
- **Placeholder**: render an empty `JsonString` / `JsonInsertion`; assert the
  placeholder hint text is present and the emptiness flag is set; after typing a
  character, the hint is gone.

Add the reader tests to `test_readers()` so they run under
`SDL_VIDEODRIVER=dummy` like the other reader suites.

---

## 8. Acceptance

`run_example("json")` supports authoring a document from scratch:

- Start on a `JsonInsertion`; press `{` → an object with one empty entry; type a
  key, Tab, type `[`, then `,` to add elements, digits/`"`/`t`/`f`/`n` to fill
  them — matching the Lisp editor's flow.
- `test_printers()`, `test_readers()`, `test_selections()` all green, zero
  `@warn`.

---

## 9. Out of scope

- Collapse wiring & rendering → [collapse-expand-syntax-nodes.md](collapse-expand-syntax-nodes.md).
- Character editing of existing values/keys → [text-syntax-json-typein.md](text-syntax-json-typein.md).
- Undo/redo (roadmap #4) — but `CollectionInsert/Delete` are designed with
  inverses so it can build on them.
- The `syntax/navigation` wrapper for numbers (§5.3) and fine-grained delimiter
  selection (§5.4) — likely won't-do; documented for completeness.
- Escape-aware string offset mapping (same caveat the printer already carries).
- IME / non-ASCII input.

---

## 10. What to keep (the Julia version is already better here)

Do **not** "fix" these toward the Lisp shape — they are deliberate improvements:

- **School-A delegation** in the reference mappers
  ([JsonToSyntax.jl:224-251](../../program/src/projection/primitive/JsonToSyntax.jl#L224-L251),
  [:337-381](../../program/src/projection/primitive/JsonToSyntax.jl#L337-L381))
  vs. the Lisp's hand-reconstructed structure. (See memory: prefer School-A
  delegation.)
- **Multiple-dispatch readers** vs. the Lisp `typecase` operation-mapper
  lambdas.
- **`json_escape`** ([JsonToSyntax.jl:483-500](../../program/src/projection/primitive/JsonToSyntax.jl#L483-L500))
  — proper JSON escaping the Lisp printer lacks.
- The heavy inline rationale comments.
</content>
</invoke>
