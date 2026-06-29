# Natural projection — one generic "render almost any document to graphics"

## Goal

Provide a single, reusable projection factory — **`NaturalToGraphics(…)`** — that takes
*almost any* document and projects it (recursively, bidirectionally) to a
`GraphicsCanvas`. It covers the common domain documents, the most common
combinator/collection documents, and arbitrary nestings of them, with a
reflection-based universal fallback (`ObjectToSyntax`) so genuinely unknown
values still render.

The driving use case is the **assistant conversation**: a `ConversationPart`'s
`content::Document` can be anything (prose, Julia code, an evaluator form, JSON,
XML, a table, …). Today each rendering context hand-assembles its own
`RecursiveProjection(TypeDispatchingProjection(…))` table. We want one canonical
renderer the assistant (and everything else) can drop in to "display almost
anything."

Non-goal: support *every* nesting combination or every per-context nuance
(placeholder text, per-domain wrap choices). It must handle the common cases and
degrade gracefully (the `Any` fallback) for the rest.

**Out of scope by decision: structural-to-widget shells (Conversation,
Workbench).** Those are projected to widgets by their *own* panels as a special
top-level stage; the natural projection renders the *content/data* documents
that appear inside them, not the chat/workbench chrome. This keeps the core a
plain, knot-free recursive dispatcher (see "Why this stays a one-shot
dispatcher"). A `ConversationDocument`/`WorkbenchDocument` reaching a *content*
slot (a rare nested case) falls through to the `Any` fallback and renders as a
reflected object tree — acceptable degradation; a caller wanting the real
chat-bubble rendering can inject an entry via `extra`.

## Why this is mostly composition, not new mechanism

The four-function projection contract already makes this work. The pieces exist:

- `TypeDispatchingProjection(pairs…)` — ordered first-match on `input isa T`
  ([higherorder/TypeDispatching.jl](../../package/kernel/src/projection/higherorder/TypeDispatching.jl)).
  It is **transparent**: it returns the matched inner projection's IoMap
  directly and re-derives the matched entry on the reader/mapper side, so it
  implements all four functions with no per-entry wiring. Keys may be concrete
  types, abstract supertypes (`TextDocument`, `ConversationDocument`), `Union`s,
  or `Any`. **Order matters** (first `isa` wins): subtype before supertype,
  `Any` last.
- `RecursiveProjection(inner)` passes *itself* as the `recursion` argument, so
  every embedding document (a `WidgetCard.content`, a `LayoutDocument` child, a
  `CellVector` element, a `ConversationPart.content`) recurses its inner
  content back through the **whole** dispatcher and is routed by type. This is
  what gives cross-domain nesting "for free" — a JSON inside a conversation part
  inside a collection just works, because each level delegates one step through
  `recursion` ([the recursion contract](../../documentation/projection-system.md#the-recursion-contract)).
- `WidgetToGraphics(font; measure)` and `LayoutToGraphics()` already **return a
  dispatcher and expose a `.dispatch::Vector{Pair{Type,Any}}`** field meant to be
  spliced (`vcat(w2g.dispatch, …)`) into a larger table. We reuse those verbatim.
- `ObjectToSyntax()` is `RecursiveProjection(TypeDispatchingProjection(… Any =>
  ObjectNodeToSyntaxNode …))` — a reflection-driven renderer for *any* Julia
  value. It is the universal backstop.

Because the natural projection is built entirely from already-bidirectional
projections, **it inherits the printer, reader, and both reference mappers for
free**. The only new code is a factory function. No new `projection_print` /
`projection_read` / `map_reference_*` methods.

### Why this stays a one-shot dispatcher

Every entry in the table is a **terminal renderer**: `Widget→Graphics`,
`Layout→Graphics`, `Table→Graphics`, or a `*ToSyntax → SyntaxToText →
Text→Graphics` chain that ends in graphics. None of them produces a *widget*
tree that would have to be re-fed through the renderer. The only projections that
do that are the structural-to-widget shells (`ConversationToWidget`,
`WorkbenchToWidget`) — and those are **out of scope** (handled by their panels).
So the renderer is a plain `RecursiveProjection(TypeDispatchingProjection(table))`
built in one shot, with no forward reference / knot-tying.

## The duplication we are replacing

The same `RecursiveProjection(TypeDispatchingProjection(vcat(layout.dispatch,
w2g.dispatch, [per-domain chains…])))` shape is hand-written in at least:

- [example/src/projection/Workbench.jl](../../package/example/src/projection/Workbench.jl) — the most complete table (Book/Json/Xml/Text/Julia/ListNode/CellVector/Primitive/Conversation/Workspace/FileSystem/EditorIntrospection)
- [example/src/projection/Assistant.jl](../../package/example/src/projection/Assistant.jl) (`_conversation_widget_graphics`, `make_assistant_projection_example`)
- [example/src/projection/Conversation.jl](../../package/example/src/projection/Conversation.jl) (three variants)
- [example/src/projection/Wrapper.jl](../../package/example/src/projection/Wrapper.jl) (`make_workbench_projection`, introspection, text-configuring)
- [example/src/projection/Widget.jl](../../package/example/src/projection/Widget.jl), [Table.jl](../../package/example/src/projection/Table.jl), [Mixed.jl](../../package/example/src/projection/Mixed.jl), [ObjectToWidget.jl](../../package/example/src/projection/ObjectToWidget.jl)

Each is a slightly different subset, drifting independently. `NaturalToGraphics`
becomes the single source of truth; callers pass context-specific overrides.

## Design

### Shape (as implemented)

```
NaturalToGraphics(; measure, font=font_ubuntu_monospace_regular_24,
                    wrap=true, extra=Pair{Type,Any}[])
  → RecursiveProjection(TypeDispatchingProjection(table))
```

The implementation refined the original sketch into **two recursion fabrics**
instead of enumerating every domain in the to-graphics layer. This handles
collections and cross-domain mixes uniformly and shrinks the to-graphics table
to four kinds of entry.

**Fabric 1 — `natural_to_syntax_dispatch()`** (the shared *to-syntax* table).
Every syntax-producible domain → its `*ToSyntax`; collections → `CollectionToSyntax`;
then `ObjectToSyntax().dispatch` spliced as the tail
(`Cell`/`Nothing`/`Bool`/`Number`/`String`/`Symbol`/`Char`/`Any`). Wrapped in a
`RecursiveProjection`, this is the shared element-recursion fabric: a
mixed-domain `CellVector`, or any cross-domain nesting, projects to one syntax
tree because each element re-enters this table by type. `CollectionToSyntax`'s
elements recurse through *this* fabric (its docstring: "element projection is
supplied by the surrounding `recursion`").

```julia
natural_to_syntax_dispatch() = vcat(
    Pair{Type,Any}[
        JsonDocument => JsonToSyntax(), XmlDocument => XmlToSyntax(),
        MathDocument => MathToSyntax(), JuliaDocument => JuliaToSyntax(),
        BookDocument => BookToSyntax(), PrimitiveDocument => PrimitiveToSyntax(),
        FileSystemDocument => FileSystemToSyntax(),
    ],
    CollectionToSyntax().dispatch,   # CellVector, ListNode
    ObjectToSyntax().dispatch,       # leaves + Any => reflected node
)
```

**Fabric 2 — the to-graphics dispatcher** (what `NaturalToGraphics` returns).
Ordered, specific → general:

1. **`extra`** — caller overrides, first so they win the `isa` race.
2. **`LayoutToGraphics().dispatch`** — layout combinators. **Before widgets**: a
   `WidgetTable` builds a `GridLayout` recursed through this same dispatcher.
3. **`w2g.dispatch`** — every `WidgetDocument` node (incl. `WidgetTable`; there
   is **no** separate `TableToGraphics` — the Table domain converged on
   `WidgetTable`).
4. **`TextDocument => prose_chain`** — prose, word-wrapped when `wrap`.
5. **`Any => syntax_to_graphics`** — everything else (JSON, XML, Math, Julia,
   Book, Primitive, FileSystem, collections, and unknown values) goes through
   `RecursiveProjection(natural_to_syntax) → SyntaxToText → Text→Graphics`. The
   `Any` catch-all means the renderer **never errors**: an unregistered value
   degrades to a reflected object tree.

```julia
function NaturalToGraphics(; measure, font=font_ubuntu_monospace_regular_24,
                           wrap=true, extra=Pair{Type,Any}[])
    w2g = WidgetToGraphics(font; measure=measure)
    prose_chain = wrap ?
        SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)) :
        TextToGraphics(measure=measure)
    syntax_to_graphics = SequentialProjection(
        RecursiveProjection(TypeDispatchingProjection(natural_to_syntax_dispatch())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure))
    table = vcat(
        Pair{Type,Any}[p for p in extra],
        LayoutToGraphics().dispatch, w2g.dispatch,
        Pair{Type,Any}[ TextDocument => prose_chain, Any => syntax_to_graphics ])
    RecursiveProjection(TypeDispatchingProjection(table))
end
```

Built in one shot — no forward reference, because no entry produces widgets that
must re-enter the renderer (see "Why this stays a one-shot dispatcher").

### Parameters (as implemented)

- `measure` — **required**; the backend text-measurement fn. No domain-level
  default (`truetype_measure_text` is in the Pdf backend / SDL is heavier);
  callers pass it.
- `font` — defaults to `font_ubuntu_monospace_regular_24` (domain `FontModule`).
- `wrap::Bool=true` — word-wrap prose only. Structured syntax/code is **always**
  no-wrap (its layout carries meaning; overflow is the viewport's job). Simpler
  than the originally-planned `:auto/:always/:never`; per-domain wrap can be a
  follow-up via `extra`.
- `extra` — `Pair{Type,Any}` entries prepended; first match wins, so a caller can
  override or add routing (placeholder text chain, a real renderer for a
  structural document) without forking the table.

## Phasing

### Phase 1 — The renderer ✅ DONE
The renderer (Fabric 1 + Fabric 2 above). Lives at domain level:
[NaturalProjection.jl](../../package/domain/src/projection/primitive/NaturalProjection.jl),
included in `ProjecturedDomain` and auto-reexported by the umbrella (`NaturalToGraphics`,
`natural_to_syntax_dispatch`). Registered a heterogeneous example —
`natural_example`, a mixed-domain `CellVector` of [JSON, Math, Text, XML]
([document/Natural.jl](../../package/example/src/document/Natural.jl),
[projection/Natural.jl](../../package/example/src/projection/Natural.jl)).

Verified: `test_printer(natural_example)` + `test_reader(natural_example)` pass
(13944 assertions). Headless smoke (stub measure) via `walk_printer_output` /
`walk_repl_loop` over json/xml/text/math/julia/book/collection/mixed, a
mixed-domain `CellVector`, and an unknown struct — all produce a `GraphicsCanvas`,
reader cycle clean.

### Phase 3 — Wire into the assistant ✅ DONE
`_conversation_widget_graphics` ([projection/Assistant.jl](../../package/example/src/projection/Assistant.jl))
— the renderer of conversation part content within the widget chat bubbles,
shared by the assistant, workbench, and wrapper panels — is now
`NaturalToGraphics(measure=…, extra=[Julia/JSON/XML overrides])`. So a
conversation part can hold *any* content document and render; unknown types
degrade to the reflective `Any` fallback instead of erroring. Behavior-preserving
for known types (Julia/JSON/XML kept as `extra`; prose/layouts/widgets identical
or a superset). No regressions: `test_printer`+`test_reader` pass for
`assistant` (2161), `workbench` (27059), `conversation_widget` (2966),
`conversation_editor` (954).

The structural stage stays explicit in the caller: the assistant is still
`SequentialProjection(RecursiveProjection(WorkbenchToWidget()), …NaturalToGraphics…)`
— special structural stage in front, universal renderer behind.

### Phase 2 — Migrate remaining callers (follow-up, optional)
The on-target caller (the conversation/assistant content renderer) is migrated
in Phase 3. The remaining hand-rolled tables —
`make_workbench_projection_example`'s inline JSON/XML/Book/Workspace/FileSystem
entries, `make_mixed_projection_example`, `make_table_projection_example`,
`make_conversation_projection_example` — can likewise be reduced to
`NaturalToGraphics(; extra=…)`. Deferred: it is duplication cleanup with
regression risk, lower value than the stated goal, and each needs its
context-specific overrides (no-wrap, placeholders, EditorIntrospection) audited
against the generic defaults before swapping. Do it incrementally, re-running
each affected example's `test_printer`/`test_reader`.

### Stretch / follow-ups
- **Prose-in-collection (known limitation).** A `TextText` placed *directly* in a
  collection recurses through `natural_to_syntax`, which has no `TextText` entry
  (a multi-run/multi-line `TextText` ≠ one `SyntaxLeaf` value), so it reflects via
  `ObjectToSyntax` instead of rendering as prose. Prose at top level or embedded
  in a widget (conversation-part content) renders correctly via the to-graphics
  `TextDocument` entry. **Cleaner fix:** a to-graphics `CellVector`/`ListNode`
  entry that lays elements out as stacked graphics blocks — each element
  re-enters the to-graphics fabric, so prose→prose, JSON→JSON, widget→widget —
  rather than collapsing the collection to one syntax tree. This generalizes
  collection rendering and removes the wart.
- `SqlDocument`, `DbCatalog`/`DatabaseInstance`, `GraphDocument`,
  `WorkspaceDocument`; a `wrap`-per-category table; optional `GraphicsCaching` tail.

## Testing

Per repo guidance, keep scopes narrow (no `test_all`).

- Per-domain parity: project each existing single-domain example through
  `NaturalToGraphics` and `test_printer` / `test_reader` it; output should match
  the domain's own example pipeline.
- A new **mixed/natural example** (heterogeneous nesting) — `test_example` it
  (printer + reader + text-navigation).
- Recursion-contract validation: run the external validator
  ([testing.md](../../documentation/testing.md#validating-the-recursion-contract))
  over `NaturalToGraphics` composed with the mixed example, to confirm every
  level delegates through the four functions (no School-B self-walk).
- The `Any` fallback: feed a plain Julia struct (no registered entry) and
  confirm it renders via `ObjectToSyntax` rather than erroring.

## Open questions / decisions

- **Naming**: `NaturalToGraphics(…)` (matches the `*ToGraphics` factory family,
  e.g. `WidgetToGraphics`, `TextToGraphics`) vs `make_natural_projection(…)`
  (matches `make_*_projection_example`). Recommend `NaturalToGraphics`; keep
  `make_natural_projection` as an alias if helpful.
- **Domain vs example placement**: it depends on concrete domain projections
  (Conversation, Workbench, Sql, FileSystem, …), so it must live in
  `ProjecturedDomain`, not the kernel. Confirm it doesn't pull anything
  example-only into domain.
- **`wrap=:auto` categorization**: which domains wrap vs not. The workbench
  example's choice (prose/Book wrap; JSON/XML/FileSystem no-wrap) is a good
  default.
- **Editability of the `Any` fallback**: `ObjectToSyntax` gives navigation/
  selection but not general round-trip editing of arbitrary objects. Acceptable
  for "display"; note it.
