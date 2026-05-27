# Generic Annotation Support

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

> A generic annotation facility: arbitrary user- or projection-supplied notes,
> highlights, comments, type hints, error markers, review remarks, etc. that
> are attached to specific locations in a document and rendered visually
> alongside the projected output through normal projection composition.

---

## Motivation

Many useful editor features amount to *"attach extra information to this
particular spot in the document and show it next to that spot"*:

- review comments on a JSON node
- inferred types hovering over Julia expressions
- error/warning markers under a syntax node
- highlights or colored spans on character ranges
- TODO markers, reminders, "look at this" pointers
- pinned notes left between sessions
- output of an external analyzer attached to the input it refers to

Today there is no general way to express this. Each candidate feature would
either invent its own ad-hoc decoration channel or be wedged into the
underlying domain (polluting JSON with comment-shaped fields it does not
want). A separate **annotation document** plus a small projection family
solves all of these uniformly: annotations live *next to* the document, are
anchored by **reference paths**, and become visual the same way every other
domain becomes visual — by being projected.

---

## Design Summary

1. An annotation is just `(target, annotation)`: *where* it sticks and *what*
   it says. Both halves are full documents.
2. Annotations live in a sibling document — an `AnnotationLayer` —
   independent of the annotated document. The annotated document itself is
   untouched.
3. The *where* is a `Reference` / `ReferencePath` into the annotated
   document — exactly the same path type used by selections — so anchoring
   reuses the existing reference machinery, including its projection-aware
   forward/backward mapping.
4. Rendering is performed by an **annotating projection** that pairs the
   annotated document with its annotation layer, runs the normal pipeline on
   the annotated document, and then attaches each annotation's projected
   visual at the screen position of its anchor.
5. The annotation's own visual is produced by an inner projection — any
   projection chain that goes from the annotation's content domain to
   graphics. Text bubbles, colored underlines, icons, mini-widgets — all are
   different content domains plus different inner pipelines.

The whole thing is additive. Domains do not change. No document gains an
"annotations" field unless its author wants annotations to be a first-class
part of it.

---

## Domain

A new minimal domain:

```julia
@document struct AnnotationLayer <: Document
    target::Document                # the annotated document (shared, not owned)
    annotations::CellVector         # of Annotation
    selection::Reference
end

@document struct Annotation <: Document
    anchor::Reference               # ReferencePath into `target`
    body::Document                  # the annotation content (any domain)
    selection::Reference
end
```

Notes:

- `target` is held by reference (a `Cell` pointing at the same live document
  the editor edits). It is not a copy; reactivity through the cells keeps
  the layer in sync with edits.
- `body` is intentionally a `Document`, not a string. An annotation can be
  a `TextText`, a `JsonObject` (structured review metadata), a
  `ConversationConversation` (threaded discussion), a `BookParagraph`, etc.
- `anchor` is a full `ReferencePath`, so it can point at a field, an
  element, a character range, or a projection-introduced position.

---

## Anchoring

The anchor is the load-bearing concept. Three operations matter:

### Resolving an anchor

Given an annotated document and an `anchor` path, `evaluate_reference`
already returns the target node/value. No new machinery required.

### Surviving edits

When the annotated document changes, an anchor may become stale (range
shifted, element deleted, field renamed). Handling, in order of effort:

1. **Naïve (v1):** anchors are static `ReferencePath` values. After an edit
   the editor re-validates each annotation; invalid ones are flagged
   ("orphaned") and either hidden or shown in a dedicated panel. Cheap, and
   sufficient for read-mostly use cases (review comments on a snapshot).
2. **Reactive (v2):** the relevant pieces of the anchor are themselves
   `Cell`s — e.g. a `RangeReference` whose `start`/`stop` are cells that
   participate in the same shifting logic the selection uses on edits.
   Same problem as keeping the selection alive across edits, same answer.
3. **Identity-based (v3, optional):** assign stable IDs to interesting
   nodes and let an anchor be `id + offset` rather than a path. Solves
   rename/move; introduces a new concept. Defer.

Start with (1) and lift to (2) where it is obviously needed (text-range
annotations, where character insertions otherwise misalign the highlight).

### Anchor through projections

The anchor lives in the annotated document's domain. To render the
annotation in *graphics*, the editor needs the screen position of that
anchor. The projection system already provides this via
`map_reference_forward`: take the anchor reference, push it forward through
the projection chain attached to the annotated document, and obtain a
reference in the graphics domain (typically a `PointReference` or a
range of pixel coordinates). That is precisely where the annotation's
visual should be placed.

This means anchoring is **free** for any document that already has a
projection pipeline to graphics: the same machinery that turns a selection
into a blinking cursor turns an anchor into an annotation hot-spot.

---

## Projections

Two new projections, both leaving the underlying domain pipeline of the
annotated document alone.

### 1. `AnnotationVisualProjection` — annotation → graphics

A per-annotation pipeline from `Annotation.body` to `GraphicsCanvas`.
Implemented as a normal `SequentialProjection` chosen by the user
(e.g. `TextToGraphics` for prose, `JsonToSyntax → SyntaxToText →
TextToGraphics` for structured bodies, a dedicated icon projection for
single-glyph markers).

The annotation's *style* (bubble, underline, gutter icon, ribbon) is
expressed as a tiny outermost projection — e.g. `BubbleDecoration`,
`UnderlineDecoration`, `GutterIconDecoration` — that wraps the body's
graphics with the chrome appropriate for that presentation. These are
just normal `GraphicsCanvas → GraphicsCanvas` projections.

### 2. `AnnotatingProjection` — pairs an annotated pipeline with a layer

A higher-order projection. Inputs:

- `inner` — the normal pipeline from the annotated document to graphics.
- `layer_path` — how to locate the `AnnotationLayer` in the editor's
  document (often the workbench/root holds both side by side).
- `visual` — the `AnnotationVisualProjection` used for each annotation
  (can also be picked per-annotation via a predicate-dispatching
  projection).

Printer:

1. Run `inner` on the annotated document. Capture its `GraphicsCanvas`
   and its `iomap`.
2. For each annotation in the layer:
   a. Map `annotation.anchor` forward through `inner.iomap` to get a
      graphics-domain reference (point, rect, or run).
   b. Project `annotation.body` through `visual` to get the annotation's
      `GraphicsCanvas`.
   c. Composite that canvas at/relative to the mapped anchor position.
3. Return the composited canvas + an iomap that records, per annotation,
   the screen region it occupies (so the reader can route clicks).

Reader:

- Events that fall on the annotation's region are routed to `visual`'s
  reader and produce operations on `annotation.body`.
- Events elsewhere are routed to `inner`'s reader (i.e. normal editing of
  the annotated document continues to work).
- A dedicated gesture (e.g. right-click + "Annotate", or a configurable
  shortcut) produces a `CollectionInsertOperation` on the layer with a
  new annotation whose `anchor` is `map_reference_backward` of the
  click — i.e. the user clicks where they want the annotation, and the
  reverse map yields the structural anchor automatically.

This keeps annotations bidirectional like every other projection:
editing the visualised annotation edits the annotation document; clicking
on the underlying content stays a content operation.

---

## Visual Styles (sketch, not prescriptive)

A handful of obvious presentations, all expressible as a `visual`
projection plus a positioning rule:

| Style | Positioning | Example use |
|---|---|---|
| Floating bubble | near anchor, line-leader to it | review comment |
| Inline underline / colored span | range overlay | error, lint warning |
| Gutter icon | left margin, line of anchor | breakpoint, TODO |
| Ribbon / banner | top of containing node | "needs review" |
| Tooltip-style popup | follows pointer | hover-only annotations |

The first three are enough for v1. The tooltip-style overlap with the
[tooltip plan](../pending/tooltip.md) is real — see *Relationship* below.

---

## Storage and Lifecycle

- A workbench (or whatever root the editor opens) carries a parallel
  `AnnotationLayer` next to each annotated document. Layers are persisted
  alongside the document but in a separate file, so the annotated file
  stays clean.
- Loading: open the annotated document; check for a sibling layer file
  (`foo.json` ↔ `foo.json.annotations`); attach if present.
- Saving: serialise the layer separately. Annotation bodies serialise via
  their own domain's existing save path.
- Multiple layers can coexist (e.g. "review", "type-inference",
  "personal notes") — modelled as multiple `AnnotationLayer`s wrapped by
  multiple `AnnotatingProjection`s in sequence. Layer visibility becomes a
  trivial flag.

---

## Implementation Steps

### 1. Domain types

- Add `program/src/document/Annotation.jl` with `Annotation` and
  `AnnotationLayer`.
- Export from `Projectured.jl`.
- Add reference-step coverage in `guide/editor/reference.md`.

### 2. Resolve and validate anchors

- Reuse `evaluate_reference` for resolution.
- Add `is_anchor_valid(layer, annotation)` — true iff
  `evaluate_reference(layer.target, annotation.anchor)` does not throw.
- Add a simple post-edit sweep that marks orphaned annotations.

### 3. `AnnotationVisualProjection` examples

- A prose-annotation pipeline: `TextToGraphics` + `BubbleDecoration`.
- A range-highlight pipeline: a domain-preserving graphics overlay that
  paints a colored rect over a graphics range.
- A gutter-icon pipeline: a fixed-size canvas placed at the line margin.

### 4. `AnnotatingProjection`

- Implement the higher-order projection described above.
- Forward anchor mapping via existing `map_reference_forward` on the
  inner pipeline; no new mapping machinery required.
- Composite annotation canvases on top of (or around) the primary canvas
  using existing `GraphicsCanvas` primitives.
- Backward routing for events on annotation regions.

### 5. Authoring gestures

- Right-click → "Add annotation" (or Ctrl-' / configurable) on the
  inner pipeline produces a `CollectionInsertOperation` on
  `layer.annotations` with `anchor` set to the backward-mapped click
  position and `body` set to an empty `TextText` (or whichever default
  body the visual prescribes).
- Existing editing gestures work on the new annotation body the moment
  it is selected, because it's just another document.

### 6. Persistence

- Sidecar file format: serialise the `AnnotationLayer` using existing
  domain serializers. Anchor paths serialise as the same string
  produced by `@reference`-style printing.
- Load on document open; save on document save.

### 7. Anchor-stability upgrade (deferred)

- For range anchors on text, switch `RangeReference` fields to cells
  that participate in the edit-shift logic used by selections.
- Decide later whether to introduce stable node IDs.

---

## Open Questions

- **Composition order.** When multiple `AnnotatingProjection`s stack
  (review layer + type layer + lint layer), in what order are their
  visuals composited? Bottom-up is natural; explicit z-order per layer
  is the obvious escape hatch.
- **Collision / clutter.** When many annotations cluster on the same
  anchor (or the same line), how do they lay out? Start: stacked
  vertically, line-leaders to the anchor. Defer fancier strategies.
- **Selection inside an annotation.** Editing an annotation body needs
  its own selection. Treat each annotation body as a sub-editor (its
  own selection cell, its own focus state) and rely on the existing
  selection mechanism — no new concept. The outer editor's selection
  refers to the layer's `Annotation` element; the inner body's
  selection lives in the body document, exactly like nested documents
  today.
- **Anchors into projection-introduced positions.** Already supported by
  `ProjectionReference`; should "work" but needs a test (e.g. anchoring
  on the opening delimiter `{` of a JSON object).
- **Read-only documents.** Annotations should still be addable when the
  underlying document is read-only — annotations live in the layer,
  not the target, so this is automatic. Worth an explicit test.
- **Cross-document anchors.** Should an annotation in document A be
  allowed to anchor at a node in document B? Out of scope for v1; the
  layer's `target` is a single document.
- **Cell vs. plain value for anchor.** If anchors must shift on edits,
  the path components are cells (already true of `RangeReference`).
  If they do not need to shift, plain values are fine. Pick per
  annotation kind; the path type accommodates either.

---

## Relationship to Existing Plans

| Plan | Overlap |
|---|---|
| [tooltip.md](../pending/tooltip.md) | A hover-only annotation is a special case: ephemeral, single-instance, computed (not stored). Tooltip plan can become a presentation style of this system — the body is computed by a function rather than stored in a layer. |
| [gesture-help.md](gesture-help.md) | Different mechanism; no overlap beyond "popup near cursor". |
| [logging.md](logging.md) | Log entries could be modelled as auto-generated annotations on the line/expression they reference. Possible future unification, not a goal for v1. |
| [workbench-assistant.md](workbench-assistant.md) | An assistant could *produce* annotations (review comments, type hints) as a normal output, written into a layer. |

---

## Dependencies

- Existing reference / projection-mapping machinery (no changes
  required for v1).
- Existing `CellVector`, `@document`, and serialization paths.
- No backend changes for the in-canvas presentation styles (bubble,
  underline, gutter). Floating-window presentation (true OS popups)
  would depend on the [tooltip](../pending/tooltip.md) multi-output
  work, but is not required.
