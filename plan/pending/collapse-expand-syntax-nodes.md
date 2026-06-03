# Collapsing / expanding syntax nodes

End-to-end goal: a user can fold a `SyntaxNode` so it renders as a short
placeholder (e.g. `{…}`) and unfold it back. The same gesture works on a JSON
object/array and an XML element edited through the standard
`JsonToSyntax → SyntaxToText → TextToGraphics` /
`XmlToSyntax → SyntaxToText → TextToGraphics` pipeline. JSON and XML domain
types already carry a `collapsed::Cell` field that is currently dormant — the
plan wires that field through without changing the shape of either domain.

The user-visible behaviour after this plan:

- Cursor inside any node (JSON object, JSON array, XML element, syntax node)
  + a fold keybinding ⇒ the node renders as its open delimiter, an ellipsis
  glyph, and its close delimiter on a single line. Children are not laid out.
- Same keybinding on an already-collapsed node ⇒ expanded.
- Click on the ellipsis ⇒ expand.
- Selection round-trip is preserved: setting the cursor "inside" a collapsed
  node lands it on the ellipsis (or on the opening delimiter — see §4); the
  reader maps clicks on the ellipsis to a deterministic point in the source
  domain (the head of the first child for JSON/XML, the head of `.children[1]`
  for raw syntax).

---

## 0. What already exists in the codebase

Verified by reading the code, not by running:

- [`SyntaxNode`](../../program/src/document/Syntax.jl#L270) and
  [`SyntaxLeaf`](../../program/src/document/Syntax.jl#L228) both carry a
  `collapsed::Bool` field today. No printer/reader looks at it
  (`grep collapsed` over `program/src/projection/primitive/SyntaxToText.jl`
  returns no hits).
- A dedicated [`SyntaxCollapsible`](../../program/src/document/Syntax.jl#L128)
  wrapper exists with the same intent — also unused. The plan picks **one**
  of the two representations (the field on the node) and removes the other
  (§9).
- `JsonObject` / `JsonArray` / `JsonObjectEntry`
  ([Json.jl#L177](../../program/src/document/Json.jl#L177),
   [Json.jl#L207](../../program/src/document/Json.jl#L207),
   [Json.jl#L236](../../program/src/document/Json.jl#L236))
  and `XmlElement` ([Xml.jl#L162](../../program/src/document/Xml.jl#L162))
  each have a `collapsed::Cell` field today. `JsonArrayToSyntaxNode` and
  `JsonObjectToSyntaxNode` build `SyntaxNode`s with **hard-coded**
  `Cell(false)` ([JsonToSyntax.jl#L235](../../program/src/projection/primitive/JsonToSyntax.jl#L235),
   [JsonToSyntax.jl#L324](../../program/src/projection/primitive/JsonToSyntax.jl#L324)).
  Wiring the field through is a one-line change per call site.
- `BookBook`/`BookChapter`/`BookList` already pass `b.collapsed` into the
  `SyntaxNode` constructor
  ([BookToSyntax.jl#L137](../../program/src/projection/primitive/BookToSyntax.jl#L137),
   [BookToSyntax.jl#L244](../../program/src/projection/primitive/BookToSyntax.jl#L244),
   [BookToSyntax.jl#L362](../../program/src/projection/primitive/BookToSyntax.jl#L362)).
  After this plan ships, Book inherits the behaviour without any further
  change — the only reason it doesn't visibly collapse today is that
  `SyntaxToText` ignores the field.

The structural conclusion: **JSON, XML, and Book already expose collapse
state. The plan is mostly about teaching the Syntax layer to honour it, with
a one-line hookup at each domain printer.** The JSON / XML / Book domains do
not need any other change.

---

## 1. What collapsed should print as

In the Syntax → Text projection, when a `SyntaxNode` has `collapsed == true`:

```
<open><ellipsis><close>
```

`<ellipsis>` is a configurable `TextString` ("…" by default, styled with a
muted color so it is visually distinct from real content). Examples:

| Node                                  | Expanded                    | Collapsed   |
|---------------------------------------|-----------------------------|-------------|
| `JsonArray([1, 2, 3])`                | `[1, 2, 3]`                 | `[…]`       |
| `JsonObject({"a":1, "b":2})`          | `{ "a": 1, "b": 2 }`        | `{…}`       |
| `XmlElement(<div>…)`                  | `<div>…</div>`              | `<div>…</div>` *(see §1.1)* |
| `BookChapter` with title + paragraphs | title \n paragraphs         | title \n `…`|
| A `SyntaxNode` with empty delimiters  | `child₁<sep>child₂…`        | `…`         |

Notes:

- No newlines or indentation are produced for the collapsed body. A
  collapsed node always fits on the line it starts on (modulo whatever line
  the open delimiter ended up on after word-wrap upstream).
- A collapsed node is treated as a **leaf-shaped span** by the word-wrap
  layer: open + ellipsis + close render as three contiguous spans with no
  internal break opportunity.
- Child cells are not read while collapsed (see §6). This keeps the
  reactive graph clean — collapsed subtrees do not re-render on child
  changes.

### 1.1 XML special case: tags carry the name

XML's open/close are `<div>` / `</div>` — the collapsed form is
`<div>…</div>` rather than `<div></div>`, and that is fine: the open and
close delimiters already encode the name. No XML-side change is required.

### 1.2 Collapsing a leaf

Leaves *can* carry the `collapsed` field too (it already exists on
`SyntaxLeaf`). For the first slice **we do nothing with `SyntaxLeaf.collapsed`**
— leaves are usually short enough that folding them adds no value. The
field stays for forward compatibility (a future "fold long string" feature)
but no printer reads it in this plan. Decision is reversible; see §10.

---

## 2. How to read the toggle operation

A new `ToggleCollapseOperation` lives in
[`program/src/operation/Operation.jl`](../../program/src/operation/Operation.jl).
It is parameterless — it toggles the `collapsed` field of *whatever node the
current selection points at*. The toggle is implemented at the editor
level, not as a `set_selection!` derivative:

```julia
struct ToggleCollapseOperation <: Operation end

function apply_operation!(doc, ::ToggleCollapseOperation)
    target = _resolve_collapsible(doc, doc.selection)
    target === nothing && return false
    target.collapsed = !target.collapsed
    return true
end
```

`_resolve_collapsible` walks the selection path from the document root and
returns the **innermost ancestor** whose type has a `collapsed` field. The
"innermost" rule means typing the key on a cursor that is anywhere inside a
JSON object collapses the most deeply nested array/object that contains it
— matching the behaviour of every code editor's fold gesture. If the
selection is empty or no ancestor has the field, the operation no-ops.

### 2.1 Where the operation enters

Three entry points; all three end up calling `apply_operation!(doc, ToggleCollapseOperation())`:

1. **Keybinding.** A new key handler in `TextToGraphics.projection_read`
   recognises a configurable chord (default `Ctrl+.` — leaves the more
   common `Tab`/`Shift+Tab` free for indentation work). The handler returns
   `ToggleCollapseOperation()`; `SequentialProjection.read` forwards it up
   the chain unchanged because no projection rewrites it.
2. **Mouse click on the ellipsis.** A click whose target syntax-domain path
   lands on the ellipsis glyph (a `ProjectionReference` of the wrapper
   projection — see §3.2) is reinterpreted by `SyntaxToText.projection_read`
   into a `ToggleCollapseOperation` *before* it propagates up.
3. **Programmatic.** `apply_operation!` may be called by tests or by other
   editor commands (e.g. an "outline view" projection that folds everything
   below depth N).

### 2.2 Why a dedicated operation, not a state mutation

A bare `node.collapsed = true` works in unit tests but bypasses the
operation pipeline. The pipeline gives us:

- undo/redo (every operation passes through `apply_operation!` and is
  recorded — see how `ReplaceSelectionOperation` is handled today),
- consistent multi-window propagation (collapses on the underlying document
  show up in every projection of it),
- a single place to also call `clear_selection!` if the selection is sitting
  inside the just-collapsed subtree (see §4).

---

## 3. Syntax → Text printer changes

### 3.1 Branching on `collapsed`

`SyntaxNodeToText.projection_print` today emits open, children-with-sep
(and indent newlines when `node.indentation > 0`), then close. The change:

```julia
spans = TextDocument[]
push!(spans, node.open)
if node.collapsed
    push!(spans, p.ellipsis_text)  # TextString configured on the projection
else
    # existing layout: children + sep + optional indent newlines
end
push!(spans, node.close)
```

The `ellipsis_text` is a `TextString` field on the `SyntaxNodeToText`
projection struct (default `"…"`, default styled with `color_solarized_gray`
+ `font_ubuntu_monospace_regular_24`). Configurable per projection
instance.

### 3.2 IoMap

The ellipsis span is *projection-introduced* — there is no source position
for it in the input `SyntaxNode`. Its index in the rendered `TextText` is
recorded so the reader (§5) can recognise clicks on it. The simplest
representation: a new field on `SyntaxNodeToTextIoMap`:

```julia
struct SyntaxNodeToTextIoMap <: IoMap
    projection::Any
    input::SyntaxNode
    output::TextText
    ellipsis_index::Int   # 0 when the node was expanded
end
```

`0` means "no ellipsis present"; any positive value points at
`output.elements[ellipsis_index]`.

### 3.3 Span/flat calculation while collapsed

`_subtree_len`, `_collect_spans`, and `_pos_to_selection` in
`SyntaxToText.jl` must each check `node.collapsed` first:

- `_subtree_len(node)` collapsed = `length(open) + length(ellipsis) + length(close)`.
- `_collect_spans` collapsed = `[open, ellipsis, close]`, no recursion.
- `_pos_to_selection(node, k)` collapsed = the same `.open{k}` / `.close{k}`
  cases as today for the delimiters; **a position in the ellipsis range
  becomes a `ProjectionReference(p, {k_local})`** so the cursor has a
  well-defined home there (see §4 for why this is the right choice).

These branches are localised: every place that today reads
`node.children` is gated on `!node.collapsed`. Searching for
`node.children` in `SyntaxToText.jl` enumerates the call sites.

### 3.4 Reactivity

`node.collapsed` is a `Cell{Bool}`. Reading it inside the printer's
reactive cells (the `TextText.spans` cell and the `selection` cell)
registers it as a dependency. Toggling the field invalidates exactly those
cells and the printer re-runs. No additional plumbing needed; this is how
every other cell in the file already works.

---

## 4. Selection while collapsed

Question: if the cursor was at `.children[2].value{3}` of a node and the
user collapses the node, what becomes of the selection?

Three options, with the trade-offs spelled out:

- **(a) Keep the path; the cursor effectively "hides" until expand.** The
  cursor disappears visually, but `set_selection!` of the same path while
  collapsed is a no-op-display: no glyph to draw. Re-expanding restores
  the cursor at the original character. **Simplest; recommended.**
- **(b) Hoist the selection to the collapsed node's open delimiter.**
  Visually the cursor lands at `<open>`. Mechanically: the
  `ToggleCollapseOperation` handler rewrites the document's selection if
  the path descends into the just-collapsed subtree, replacing it with the
  path to that subtree's `.open{0}`.
- **(c) Park the selection on the ellipsis.** As (b), but landing on the
  ellipsis (`ProjectionReference(p, {0})`). Less surprising for users used
  to IDE fold behaviour but couples the source-domain selection to a
  projection-introduced glyph.

This plan picks **(a)**. Rationale: the syntax-domain `selection` is the
authoritative source-of-truth; collapsing should only affect *rendering*,
not source state. Cursor visibility while collapsed is a UI concern that
can be solved later by an outer projection (e.g. show a thin highlight on
the collapsed node when its `selection` is non-null), without touching the
data model.

When a click *lands* on the ellipsis while collapsed (and the keybinding
isn't pressed), the reader (§5) translates it into a
`ToggleCollapseOperation` — i.e. clicking an ellipsis expands. Clicks on
the delimiters behave as today (cursor moves to that character).

---

## 5. Reader changes

### 5.1 `SyntaxNodeToText.projection_read`

Two new cases, both checked before falling through to the existing
positional logic:

```julia
function projection_read(p::SyntaxNodeToText, iomap::SyntaxNodeToTextIoMap, op::ReplaceSelectionOperation)
    # Click on the ellipsis while collapsed ⇒ expand.
    if iomap.input.collapsed && _path_targets_ellipsis(op.path, iomap.ellipsis_index)
        return ToggleCollapseOperation()
    end
    # ... existing behaviour: backward-map text position → syntax position
end
```

`_path_targets_ellipsis(path, idx)` returns true iff the leading
`ElementReference` (the `TextText` element index) equals `idx`. The
returned `ToggleCollapseOperation` propagates up the chain unchanged: no
upstream `*ToSyntax` projection rewrites it, so it reaches
`apply_operation!` on the root document.

### 5.2 Keyboard

The fold keybinding is read at the bottom of the chain. The Text →
Graphics layer is the lowest projection that *sees* `KeyDown`, so the
handler lives in
[`TextToGraphics.projection_read`](../../program/src/projection/primitive/TextToGraphics.jl#L86):

```julia
function projection_read(p::TextToGraphics, iomap, evt::KeyDown)
    if evt.key === :period && :ctrl in evt.modifiers
        return ToggleCollapseOperation()
    end
    # ... existing nav-key handling
end
```

Just like `ReplaceSelectionOperation`, the `ToggleCollapseOperation` walks
up the `SequentialProjection` chain unchanged because none of the upstream
projections has a method for it.

### 5.3 Forward / backward reference maps

`map_reference_forward` and `map_reference_backward` for
`SyntaxNodeToText` do *not* need new cases: while collapsed, the only
forward-mappable input references are `.open{k}` and `.close{k}`, which
work the same as today (the open/close span indices don't change). A
`.children[i]…` input reference while collapsed correctly returns
`nothing` because there is no rendered text to point at.

---

## 6. Reactivity and recursion contract

Per
[`guide/selection-deep-dive.md`](../../guide/selection-deep-dive.md#8-selection-projection-under-recursion)
the selection cell and the children cell of a `SyntaxNode` printer must
share the same projected children (so a selection-cell read doesn't see a
stale child iomap). The collapsed branch sidesteps the problem: while
collapsed, no children are projected at all, so there is no shared state
to keep in sync.

Specifically:

- The `child_iomaps` cell becomes conditional on `node.collapsed`:
  empty list when collapsed, full list otherwise.
- The `output.selection` cell reads `node.collapsed` first; while
  collapsed it can short-circuit to "no cursor" or to the ellipsis
  position (see §4 for the choice).
- This means **collapsing prunes the reactive graph** of the subtree.
  Editing a value deep inside a collapsed `JsonObject` will trigger no
  re-render of the syntax/text output of the collapsed wrapper. (It still
  re-renders the source-domain cells — the user's edits are preserved;
  they just don't show up in this view until the node is expanded again.)

---

## 7. Hooking the JSON and XML domains in

This is the "without disturbing the domains" question. The domains
already carry `collapsed::Cell` fields. Three one-line changes:

### 7.1 `JsonArrayToSyntaxNode.projection_print`

[JsonToSyntax.jl#L229-L236](../../program/src/projection/primitive/JsonToSyntax.jl#L229-L236):

```julia
# Before:
node = SyntaxNode(..., 1, Cell(false), sel)
# After:
node = SyntaxNode(..., 1, getfield(j, :collapsed), sel)
```

Reading `getfield(j, :collapsed)` returns the underlying `Cell` so the
`SyntaxNode` shares the same reactive cell as the source. Toggling
`j.collapsed = !j.collapsed[]` propagates to the syntax-domain printer
immediately.

### 7.2 `JsonObjectToSyntaxNode.projection_print`

Same change at the outer node
([JsonToSyntax.jl#L299-L325](../../program/src/projection/primitive/JsonToSyntax.jl#L299-L325)).
The per-entry pair `SyntaxNode`s ([JsonToSyntax.jl#L305-L319](../../program/src/projection/primitive/JsonToSyntax.jl#L305-L319))
are left non-collapsible for now: collapsing an entry pair makes little
visual sense (it would render `"key": …` which is what you'd want, but
adding that without also adding an entry-level fold gesture is mostly
decoration — defer to a follow-up; see §10).

### 7.3 `XmlElementToSyntaxNode.projection_print`

(File:
[`program/src/projection/primitive/XmlToSyntax.jl`](../../program/src/projection/primitive/XmlToSyntax.jl).)
Same shape — pass `getfield(e, :collapsed)` into the `SyntaxNode`
constructor. The collapsed render is `<tag>…</tag>` which is the
expected XML idiom.

### 7.4 Reverse path: ToggleCollapse on JSON / XML domains

`ToggleCollapseOperation` propagates *up the chain unchanged*. It reaches
`apply_operation!` on the root JSON / XML document. The implementation
of `apply_operation!(_, ::ToggleCollapseOperation)` lives in
`Operation.jl` and walks the document's `selection` path: for each
visited node, if its type has a `collapsed` field, remember it; the last
such node wins, and its `collapsed` cell is flipped.

This rule does not need any domain-specific code: it inspects fields
generically. It also works for the syntax domain directly (when the
"root" document *is* a `SyntaxNode`, e.g. in the `syntax` example) — the
walk finds the syntax node whose `collapsed` field to toggle.

### 7.5 What this does **not** touch in the JSON / XML domain

- No new field on any domain type.
- No change to `_forward_json_path` / `_translate_json_path` /
  `_forward_xml_path` / `_translate_xml_path`. The selection path
  vocabulary is unchanged.
- No new operation handlers on `JsonObject` / `XmlElement` themselves.
  The toggle is dispatched generically by `apply_operation!` in
  `Operation.jl`.

So the JSON and XML domains stay untouched in terms of their public
API; only their printers gain a one-line hookup.

---

## 8. Tests

Three layers, mirroring the existing `test_selections` / `test_printers`
structure:

### 8.1 Syntax printer unit tests
(`test/src/projection/SyntaxToTextCollapseTest.jl`)

- Build a `SyntaxNode` with two leaves; flip `collapsed` to `true`; assert
  the rendered string is `<open><ellipsis><close>` and matches the
  expected length.
- Assert `_pos_to_selection` on the collapsed node returns `.open{k}`,
  `ProjectionReference(_, {k})` for ellipsis range, `.close{k}` —
  exhaustively over every offset.
- Assert that toggling back to `false` restores byte-for-byte the
  expanded output.
- Reactivity: register a `Cell.subscribe` on the output's spans cell,
  toggle `collapsed`, assert exactly one invalidation fires.

### 8.2 Reader unit tests
(`test/src/projection/SyntaxToTextCollapseReadTest.jl`)

- Build a collapsed `SyntaxNode`; synthesise a `MousePress` at the
  ellipsis's bounding-box centre; assert the returned `Operation` is a
  `ToggleCollapseOperation` (not a `ReplaceSelectionOperation`).
- Synthesise a `Ctrl+.` `KeyDown` via `TextToGraphics`; assert the same.
- After applying the operation, assert `node.collapsed[] == false` and
  the rendered string equals the expanded form.

### 8.3 End-to-end tests
(`test/src/editor/CollapseRoundtripTest.jl`)

- Three examples: `json`, `xml`, `syntax` (and the `book` examples since
  they're already wired).
- For each: set the cursor inside an inner array/object/element; issue
  `Ctrl+.`; assert the rendered text now contains the ellipsis glyph and
  *not* the inner content; issue `Ctrl+.` again; assert restoration.
- Add to `test_selections()`: when a node is collapsed, the reachable
  state set is *smaller* than expanded (sanity check the BFS terminates
  and stays sane).

### 8.4 Re-enable / extend `test_mouse_clicks`

When the JSON-navigation plan
([plan/pending/json-navigation-and-clicks.md](json-navigation-and-clicks.md))
lands, add a smoke test that clicking on the ellipsis triggers expand in
the live editor. Out of scope for this plan if the JSON-nav plan hasn't
landed yet — track and defer.

---

## 9. Cleanup: remove `SyntaxCollapsible`

After §3 lands, `SyntaxCollapsible` is dead weight: a wrapper that does
the same thing as the field on the node it wraps. Delete it:

- Remove the type from
  [`Syntax.jl`](../../program/src/document/Syntax.jl#L128).
- Remove the export and the `ISyntaxCollapsible` interface declaration.
- `grep` for `SyntaxCollapsible` across `program/`, `example/`, `test/`,
  `guide/` and remove any lingering references (the doc comment at
  [`Syntax.jl#L12`](../../program/src/document/Syntax.jl#L12) needs an
  edit too).

This is the only delete required. The "two ways to express the same
thing" (field vs. wrapper) was already a latent footgun; collapsing the
two into one is part of shipping the feature, not a separate refactor.

---

## 10. Out of scope (followups, not this plan)

- **Folding a leaf** ("…rest…" for long strings). The field exists; no
  printer reads it yet. Add when there's a use case.
- **Folding a JSON object entry** (`"key": …`). Same: useful but no
  current ask.
- **Persistent fold state across document reloads.** Today `collapsed`
  is in-memory only. A serializer would be needed; out of scope.
- **A gutter UI with triangle widgets.** This plan only adds the
  inline ellipsis. A gutter / fold-marker projection would be a
  separate higher-order projection wrapping `SyntaxToText`.
- **"Fold all at depth N" command.** Trivial follow-up once
  `ToggleCollapseOperation` and `_resolve_collapsible` exist.
- **`SyntaxDelimitation` / `SyntaxIndentation` / `SyntaxNavigation`
  wrappers.** None of these are currently emitted by any
  `*ToSyntax` projection (`grep` for the wrapper names in
  `program/src/projection`); leave them alone in this plan and let the
  syntax-tree-selection cleanup ([syntax-tree-selection.md](syntax-tree-selection.md))
  decide their fate.

---

## 11. Implementation order, in commits

| # | Commit | Tests it must keep green |
|---|---|---|
| 1 | Add `ToggleCollapseOperation` + `_resolve_collapsible` + `apply_operation!` dispatch | existing tests; add a unit test for `_resolve_collapsible` |
| 2 | Teach `SyntaxNodeToText` to honour `collapsed` (printer + ellipsis IoMap field) | `test_printers()`, new `SyntaxToTextCollapseTest` |
| 3 | Teach `SyntaxNodeToText.projection_read` to translate ellipsis clicks into `ToggleCollapseOperation` | new `SyntaxToTextCollapseReadTest` |
| 4 | Add `Ctrl+.` to `TextToGraphics.projection_read` | smoke via end-to-end test |
| 5 | Hook `getfield(j, :collapsed)` into `JsonArrayToSyntaxNode` and `JsonObjectToSyntaxNode` | `test_selections()` for `json*` examples; new `CollapseRoundtripTest` for `json` |
| 6 | Hook the same into `XmlElementToSyntaxNode` | `test_selections()` for `xml`; `CollapseRoundtripTest` for `xml` |
| 7 | Remove `SyntaxCollapsible` (§9) | full suite |

Each commit ships green tests. If a commit reveals a deeper bug, stop
and add a unit-level regression test before fixing — same rule as the
other slice plans.

---

## 12. Acceptance check — what "done" means

A single command at the repo root passes:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy julia --project=. \
  -e 'using Projectured, ProjecturedExample, ProjecturedTest; \
      test_selections(); \
      test_printers(); \
      test_readers(); \
      test_collapse_roundtrip()'
```

Zero `@warn`s, zero failures. Manual smoke:

- `run_example("json")` → cursor inside the inner array, `Ctrl+.`,
  array renders as `[…]`. `Ctrl+.` again, array expands.
- `run_example("xml")` → cursor inside an element, `Ctrl+.`, element
  renders as `<tag>…</tag>`. `Ctrl+.` again, element expands.
- `run_example("syntax")` → same, on a hand-built syntax tree.
- `run_example("book")` → collapsing a chapter hides its paragraphs.
  (No code change in the Book layer was needed.)

---

## 13. Risks and decision points

- **Selection-while-collapsed (§4).** Decision (a) chosen; (b)/(c)
  remain available in a follow-up if usability testing pushes back.
- **The default chord `Ctrl+.`** clashes with VS Code's "quick fix" — we
  are not VS Code but it is worth documenting. The chord is a one-line
  change in `TextToGraphics.projection_read` and can be re-bound.
- **`ToggleCollapseOperation` vs. a generic `MutateFieldOperation`.**
  A generic operation is more powerful but invites footguns and has no
  current users. Keep the toggle dedicated; promote later if a second
  similar feature lands.
- **Reactive-graph pruning while collapsed (§6) might mask a stale
  selection.** When the user edits the source while a view is
  collapsed and then expands, the cursor reappears at the path it had
  before collapse. If the surrounding source no longer has that path
  (e.g. the user deleted the index), `set_selection!`'s standard
  no-target handling applies. This is the same behaviour as today's
  edit-while-elsewhere; no special handling needed.
- **JSON object entries' `collapsed` field stays dormant.** Listed in
  §10 as a deliberate follow-up. Worth a doc comment update on
  [`JsonObjectEntry`](../../program/src/document/Json.jl#L207) noting
  the field is reserved for entry-level folding (not implemented).
