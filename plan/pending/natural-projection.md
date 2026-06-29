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

### Shape

```
NaturalToGraphics(; measure, font, theme, wrap=:auto, extra=Pair{Type,Any}[])
  → RecursiveProjection(TypeDispatchingProjection(table))
```

`table` (ordered, specific → general):

1. **`extra`** — caller overrides, first so they win the `isa` race (e.g. the
   assistant routing `PrimitiveDocument` to a placeholder-bearing text chain, or
   forcing a no-wrap variant).
2. **`LayoutToGraphics().dispatch`** — layout combinators (`GridLayout`,
   `HorizontalLayout`, `VerticalLayout`, …). **Must precede widgets**: a
   `WidgetTable` builds a `GridLayout` and recurses it through this same
   dispatcher (see the comment in
   [Workbench.jl](../../package/example/src/projection/Workbench.jl#L19-L23)).
3. **`w2g.dispatch`** — every `WidgetDocument` node type (from `WidgetToGraphics`).
4. **Domain documents**, each with its known chain to graphics:
   - `TextDocument`      → `WordWrapping?` → `TextToGraphics`
   - `JsonDocument`      → `JsonToSyntax` → `SyntaxToText` → text→graphics
   - `XmlDocument`       → `XmlToSyntax` → …
   - `JuliaDocument`     → `JuliaToSyntax` → …
   - `MathDocument`      → `MathToSyntax` → …
   - `BookDocument`      → `BookToSyntax` → …
   - `PrimitiveDocument` → `PrimitiveToSyntax` → …
   - `TableDocument`     → `TableToGraphics` (direct)
   - `FileSystemDocument`→ `FileSystemToSyntax` → …
   - `CellVector` / `CellMatrix` / `CellTable` / `ListNode` → `CollectionToSyntax` → …
   - (stretch) `SqlDocument`, `DbCatalog`, `GraphDocument`, `WorkspaceDocument`
5. **`Any => object_chain`** — `ObjectToSyntax → SyntaxToText → text→graphics`.
   The backstop that lets the assistant render literally anything.

Each syntax-backed chain is built by a local helper
`syntax_chain(p) = SequentialProjection(RecursiveProjection(p),
RecursiveProjection(SyntaxToText(…)), text_chain)` so the table reads as a flat
list of `Domain => syntax_chain(DomainToSyntax())`.

```julia
function NaturalToGraphics(; measure, font, theme=…, wrap=:auto, extra=Pair{Type,Any}[])
    w2g         = WidgetToGraphics(font; measure, theme)
    text_chain  = SequentialProjection(WordWrapping(measure), TextToGraphics(measure))  # per `wrap`
    syntax_chain(p) = SequentialProjection(RecursiveProjection(p),
                                           RecursiveProjection(SyntaxToText(…)), text_chain)
    object_chain = syntax_chain(ObjectToSyntax())
    table = vcat(
        extra,
        LayoutToGraphics().dispatch,
        w2g.dispatch,
        Pair{Type,Any}[
            TextDocument      => text_chain,
            JsonDocument      => syntax_chain(JsonToSyntax()),
            XmlDocument       => syntax_chain(XmlToSyntax()),
            JuliaDocument     => syntax_chain(JuliaToSyntax()),
            MathDocument      => syntax_chain(MathToSyntax()),
            BookDocument      => syntax_chain(BookToSyntax()),
            PrimitiveDocument => syntax_chain(PrimitiveToSyntax()),
            TableDocument     => TableToGraphics(),
            FileSystemDocument=> syntax_chain(FileSystemToSyntax()),
            CellVector        => syntax_chain(CollectionToSyntax()),
            ListNode          => syntax_chain(CollectionToSyntax()),
            Any               => object_chain,
        ],
    )
    RecursiveProjection(TypeDispatchingProjection(table))
end
```

Built in one shot — no forward reference, because no entry needs to re-enter the
renderer (see "Why this stays a one-shot dispatcher").

### Parameters

- `measure` / `font` / `theme` — threaded to `WidgetToGraphics`, `TextToGraphics`,
  `WordWrapping`, matching the existing factories' signatures.
- `wrap` — `:auto` (default; prose wraps, code/data render no-wrap like the
  workbench), `:always`, or `:never`. Controls whether `WordWrapping` is in the
  text chain per category.
- `extra` — `Pair{Type,Any}[]` prepended so a caller can override or add entries
  without forking the whole table.

## Phasing

### Phase 1 — The renderer
The full table above (layout + widgets + domain chains + `Any` fallback). This
already "displays almost anything," including heterogeneous nestings, because
embedding points recurse through the renderer. Lives at domain level (it
references concrete domain projections): new file
`package/domain/src/projection/NaturalProjection.jl`, exported from the domain
module. Add a heterogeneous example (a `CellVector` / layout holding [Text,
Julia, JSON, Table]) to the example registry and verify with `test_printer` /
`test_reader`.

### Phase 2 — Migrate callers
Reimplement the hand-rolled tables in terms of `NaturalToGraphics(; extra=…)`:
start with `make_conversation_projection_example`, `_conversation_widget_graphics`,
`make_mixed_projection_example`, then `make_workbench_projection(_example)`. Each
becomes `NaturalToGraphics(measure=…, extra=[context-specific overrides])`. This
both removes duplication and is the real regression test for the abstraction.

The structural stages stay explicit in the callers that own them: e.g. the
assistant remains `SequentialProjection(RecursiveProjection(ConversationToWidget()),
NaturalToGraphics(extra=…))` — special structural stage in front, universal
renderer behind. Where a caller *embeds* a conversation/workbench as content
(e.g. the workbench's assistant panel), it supplies that entry via `extra`
(a `SequentialProjection(RecursiveProjection(ConversationToWidget()),
NaturalToGraphics(…))` two-stage chain it builds itself — the knot lives in the
caller that needs it, not in the generic projection).

### Phase 3 — Wire into the assistant
Use `NaturalToGraphics` as the part-content renderer behind the assistant's
`ConversationToWidget` stage, so any future content document type renders
without touching the panel. (`ConversationToWidget` leaves part content embedded;
the renderer picks it up by type.)

### Stretch
`SqlDocument`, `DbCatalog`/`DatabaseInstance`, `GraphDocument`,
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
