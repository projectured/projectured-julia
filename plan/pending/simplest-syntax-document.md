# The simplest syntax document: optional delimiters, then real wrapper projections

Goal: **every domain→syntax projection emits the simplest syntax document that expresses what it
means** — a JSON null is one span, not three; a Julia connector node says "concatenate these", not
"a node with three empty delimiters". Today neither is possible, and the cost is measurable.

## The problem

**42.7% of every text span in the corpus is empty** — 1319 of 3088. Measured by flattening each
example's pipeline to its `TextText` and counting zero-length `TextString`s:

| example | spans | empty | | example | spans | empty |
|---|---|---|---|---|---|---|
| sql_syntax | 37 | 25 (67.6%) | | markdown | 129 | 73 (56.6%) |
| json_null | 3 | 2 (66.7%) | | navigator | 351 | 180 (51.3%) |
| julia | 105 | 65 (61.9%) | | filesystem | 354 | 180 (50.8%) |
| sql_update_syntax | 49 | 30 (61.2%) | | sql_insert_syntax | 37 | 18 (48.6%) |
| sql_nested_syntax | 205 | 123 (60.0%) | | xml | 535 | 248 (46.4%) |
| yaml | 211 | 120 (56.9%) | | object | 123 | 57 (46.3%) |
| formula | 109 | 62 (56.9%) | | syntax | 86 | 29 (33.7%) |
| | | | | **corpus** | **3088** | **1319 (42.7%)** |

These spans render nothing. They exist because a syntax document always *materializes* every
delimiter, present or not:

- `SyntaxLeaf`'s `open`/`close` default to `TextString("")`
  ([Syntax.jl:247](../../package/visual/main/syntax/Syntax.jl#L247)), and `SyntaxLeafToText`
  unconditionally emits three spans, `[leaf.open, leaf.value, leaf.close]`.
- `SyntaxNode`'s `open`/`close`/`sep` default the same way, and `SyntaxNodeToText` pushes `node.open`,
  a `node.sep` between children, and `node.close` regardless of content.

So `JsonNullToSyntaxLeaf` — `SyntaxLeaf(TextString("null", prj.style))`, no delimiters — becomes
**three** spans, two empty.

The cost: **phantom carets** (a leaf with no delimiter still offers `.open{0}` / `.close{0}` cursor
positions that render exactly where the value's edge renders), **wasted work** (every empty span is a
reactive cell, an iomap entry, a layout element), and **a navigation bug** — see
[left-motion-stalls-on-introduced-text.md](left-motion-stalls-on-introduced-text.md), which also
records why the tempting fix (skip empty spans in the steppers) is wrong: an undelimited leaf's empty
`.close` is currently a *real* caret, and `json_null`'s end-of-text position IS that empty span.
Removing the delimiter removes the caret honestly, which the stepper hack could not.

## The two ends of one problem

`Syntax.jl` declares six wrapper types — `SyntaxDelimitation`, `SyntaxIndentation`,
`SyntaxCollapsible`, `SyntaxNavigation`, `SyntaxConcatenation`, `SyntaxSeparation` — describing a
compositional model where each projection assembles exactly the structure it needs. None has a
`print_document`, a `render`, or a reference map, so none is constructible. **They are not dead
weight: they are the model the domains are hand-rolling.** From an inventory of all ~340 construction
sites:

- **`SyntaxConcatenation`** — `JuliaToSyntax` builds 19 connector nodes as literally
  `SyntaxNode(TextString(""), TextString(""), TextString(""), [...], 0, false, nothing)`: no
  delimiters, no separator, purely to sequence a fixed child list (`JuliaBinaryOp` L143, `JuliaIf`
  L474/475, `JuliaFunction` L494/495, …). `SqlWhereFilterConditionToSyntaxNode` (L768) is a
  one-child, no-delimiter node — an identity wrapper. `MarkdownStyledInline` (L368) omits all three.
- **`SyntaxSeparation`** — Markdown sets `sep=TextString("")` on five inline/paragraph types
  (L128, 138, 148, 157, 368) just to join runs; SQL's `_comma_node` / `_space_node` (L71-74) pass
  bare `""` open/close with only a real `sep`.
- **`SyntaxIndentation`** — zero uses, yet every domain sets `indentation=` as an inline field on the
  node it is already building (`JsonArray` 1, `FileSystemDirectory` body 2, `DbCatalog` −1,
  `YamlMapping` −1, `JuliaBlock` 1, SQL `_comma_body` 1 / `_newline_body_compact` −1).
- **`SyntaxDelimitation`** — all six SQL helpers (L66-83) pass bare `""` for open/close.

The fat types force every node to carry delimiter slots, so "I need no delimiter" gets written as an
empty string instead of as *absence*. That is the same fact as the 42.7%.

## Target model

`SyntaxNodeToText` today does **five jobs at once**. The six wrappers are exactly those five jobs,
separated — so Phase 2 is a **factoring of existing code**, not new duplication:

| document | the job it takes over from `SyntaxNodeToText` | reference steps it owns |
|---|---|---|
| `SyntaxConcatenation` | splicing children's spans into one element list (`child_elem_ranges`) | `.children[i].^(inner)` |
| `SyntaxSeparation` | the same, plus a separator span *between* children (n−1 of them) | `.children[i].^(inner)`, `.separator{k}` |
| `SyntaxDelimitation` | the open / close spans around content | `.opening_delimiter{k}`, `.content.^(inner)`, `.closing_delimiter{k}` |
| `SyntaxIndentation` | newline + indent chrome, `indent_indices`, the splice-widening machinery | `.content.^(inner)` |
| `SyntaxCollapsible` | the expand/collapse marker span, the ellipsis, `marker_eligible`, `ToggleCollapseOperation`, marker click hit-testing | `.content.^(inner)` |
| `SyntaxNavigation` | the whole-element (`∅`) tree-selection anchor | `.content.^(inner)` |

…plus the Syntax domain's two missing **atoms** (see below):

| document | what it is | reference steps |
|---|---|---|
| `SyntaxNothing` | the domain's empty placeholder — the rendering of a *nothing* value, exactly as `JsonNothing` / `JuliaNothing` / `DocumentNothing` are for theirs | none (`∅` only) |
| `SyntaxInsertion` | the domain's typed-name insertion buffer (`value::String`) | `.value{k}` |

### Overlap between these documents is intentional

`SyntaxLeaf` (value + delimiters + indentation + collapsed) and `SyntaxNode` (children + delimiters +
separator + indentation + collapsed) **stay exactly as they are**, combining several of the concerns
above in one document. That is a feature, not a redundancy to eliminate: a domain that wants a
delimited, indented, collapsible node should say so in one document rather than stack four wrappers.

**A domain picks whichever document fits it best.** JSON's object keeps being a `SyntaxNode`; Julia's
19 connector nodes become `SyntaxConcatenation`; SQL's `_comma_body` becomes a `SyntaxSeparation`
inside a `SyntaxIndentation`. There is no forced march to the fine-grained types and no end state in
which the combined types disappear.

### One shared implementation

The combined types and the fine-grained ones are **implemented on the same core**, not side by side.
Phase 2.1 extracts the machinery currently buried in `SyntaxNodeToText` — child splicing and
`child_elem_ranges`, separator emission, delimiter spans, the `indent_indices` splice-widening, the
collapse marker — into helpers, and then *both* `SyntaxNodeToText` and the new wrapper projections
call them. `SyntaxNode`'s printer becomes the composition of the same pieces `SyntaxConcatenation` +
`SyntaxSeparation` + `SyntaxDelimitation` + `SyntaxIndentation` + `SyntaxCollapsible` use
individually. If a fix is needed in the splice logic, there is one place to fix it.

## Phase 1 — optional delimiters on the fat types — **DONE**

**Result: empty spans went from 42.7% of the corpus to 8.7%** (1319 of 3088 → 190 of 2185).
`julia` 65 empty spans → 1, `xml` 248 → 35, `syntax` 29 → 1, `json_null` from three spans to one.

What landed, beyond the plan:

- **The delimiter defaults live on the fields** (`open::Union{TextString,Nothing} = nothing`, …), and
  the hand-written keyword constructors only *coerce* (`_text`, `_children`) before delegating to the
  `@document` keyword constructor — so a default is declared once. `@document` gates its generated
  keyword constructor on the programmer declaring ≥1 default precisely to leave the zero-positional
  signature to a struct that coerces; the coercing form takes its content positionally
  (`SyntaxLeaf(value; …)`), so the two never collide.
- **An empty delimiter *string* normalizes to absence** in `_text`, so a projection whose delimiter is
  configuration (YAML's block style, SQL's helpers) needed no edit. A `TextString` is passed through
  untouched and never inspected — its content is a reactive cell, and one that is empty *now* may not
  be later (`XmlElement`'s tag close alternates between `" "` and `""`), so dropping its span on a
  momentary emptiness would mean it could never come back.
- **`XmlAttribute` was missing from the `mixed` example's dispatch table**, so any element with
  attributes threw `no projection registered for RXmlAttribute`. That was *every one* of the 93
  pre-existing domain failures (`mixed` 65, `graph` 28 — graph routes through the mixed projection).
  One line: `test_domain` 93 failed → **0**.
- **Eight latently-broken `@reference` literals** in `PrimitiveToSyntax`, `MathToSyntax` and
  `InsertionToSyntax`: a caret path must terminate in `::Position` and these did not, so they threw
  the moment they were reached. Nothing reached them before, because the phantom caret on a bare
  leaf's empty `open` delimiter routed around them — removing the phantom exposed the hole it was
  hiding (it broke `math_table`'s Enter-into-cell).

Navigation, as predicted: `sql_insert_syntax`, `markdown` and `sql_update_syntax` now walk
symmetrically end to end, and `mixed` walks at all. `test_text_nav_invariants_all` 219 pass / 34
broken → **236 / 26**.

### Two things learned the hard way

- **`test_domain` must be in the guard-rail list.** The first Phase 1 commit regressed it 93 → 132
  and it was missed, because only the visual / nav / typein guards were run. It is in the guard rails
  below now.
- **`SyntaxNode`'s children container is load-bearing in two conflicting ways** — recorded in a
  comment in `Syntax.jl`, because it is not guessable and it cost a day:
  - a *hand-written* projection's output node needs a `CellVector`: the reference machinery navigates
    `.children[i]` through its element cells;
  - a `@projection_template` *blueprint* needs a raw `Vector`: the engine detects a fixed-children
    node by `getfield(out, f)[] isa Vector` (`ProjectionTemplate._has_fixed_children`) and walks it to
    resolve the `bound`/`project` markers nested in each child. A `CellVector` is not recognised as a
    blueprint at all, and the markers reach the printer unresolved.

  So a fixed-children template node **cannot** use the keyword form, and cannot even shorten its
  7-arg positional call: at arity 4 the macro's Rule C constructor takes over and wraps the vector.
  `SyntaxNode(nothing, nothing, nothing, [...], 0, false, nothing)` stays until Phase 2, where those
  nodes become `SyntaxConcatenation([...])` — which is both prettier and more precise, and can define
  its own children semantics without fighting this.

  > **Superseded — see "The template-blueprint gap" below.** The two needs are real, but the
  > conclusion drawn from them was wrong: the conflict was in the *engine's detection*, not in the
  > constructor. `_has_fixed_children` now accepts either storage, so a fixed-children template node
  > **can** use the keyword form and the 7-arg positional call is no longer forced.

### The original plan for this phase

## Phase 1 (original) — optional delimiters on the fat types

Contained, unblocks navigation, needs no domain edits. **Absence must be representable before it can
be factored into a wrapper**, so this comes first either way.

```julia
@document struct SyntaxLeaf <: SyntaxDocument
    open::Union{TextString,Nothing}      # was TextString, defaulted to TextString("")
    close::Union{TextString,Nothing}
    value::TextString
    indentation::Int
    collapsed::Bool
end
SyntaxLeaf(value; open=nothing, close=nothing, …)
```

…and the same for `SyntaxNode`'s `open` / `close` / `sep`. The printer then emits only what exists:

```julia
spans = TextDocument[s for s in (leaf.open, leaf.value, leaf.close) if s !== nothing]
```

### 1.1 — Audit the fixed-layout assumptions — **done**

Every place that assumes a fixed span layout. Line numbers as of `4c000502`.

**A. `SyntaxLeafToText` hardcodes the three-span triple** — on a bare leaf, index 1 becomes `.value`:

| where | assumption |
|---|---|
| `map_reference_forward` L47-56 | `_text_elem_path(1\|2\|3, s)` for `.open` / `.value` / `.close` (and the two `proj(_, …)` arms) |
| `map_reference_backward` L58-68 | `span_idx == 1 → .open`, `== 2 → .value`, `== 3 → .close` |
| `print_document` L79-87 | `TextDocument[leaf.open, leaf.value, leaf.close]` — twice (the span list and the cursor's `_flat_to_text_elem_path`) |
| `read_intent(::ReplaceStringRangeOperation)` L100-112 | `span_idx == 2` is the guard that an edit lands on `.value` |
| `_leaf_cursor` L910-931 | `length(leaf.open.content) + k` — reads `.open` unconditionally |

**B. `SyntaxNodeToText` identifies its own chrome by POSITION** — which is precisely what breaks when
a delimiter is absent:

| where | assumption |
|---|---|
| `map_reference_forward` L262-271 | `.open` → element `marker_index[] + 1`; `.close` → element `length(elements)`; `.sep` → `child_elem_ranges[1].stop + 1` |
| `_backward_zone` L350-351 | `j == marker_index[] + 1 → .open`; `j == length(elements) → .close`; anything else → projection-introduced flat offset |
| `print_document` L440-490 | pushes `node.open`, a `node.sep` before each child after the first, and `node.close` unconditionally |

**Decision:** stop inferring by position. The printer already knows where it put each span, so
**record the element indices in the IoMap** — `open_index`, `close_index`, `sep_indices` (0 / empty
when absent) — and have both maps read them. This is not extra scaffolding for Phase 1: it is exactly
what Phase 2's shared core needs, since a `SyntaxDelimitation` wrapping a `SyntaxSeparation` cannot
possibly locate its delimiters positionally either.

**C. `Syntax.jl`:**

- `render(leaf)` L351-353 and `render(node)` L355-358 read `.open.content` / `.sep.content` /
  `.close.content` unconditionally.
- the `_text` helper L199-200 needs a `nothing` pass-through (`_text(::Nothing) = nothing`).
- `splice_value!` (TextModule) splices a TextString field; an absent delimiter has none. This needs no
  guard in practice — with no span there is no caret and no reachable edit — but assert it rather
  than assume it.

**D. `@document` does not enforce or convert field types**, so `Union{TextString,Nothing}` is safe:
`TextNewline` carries `font_color::StyleColor = ""` next to `fill_color::StyleColor = nothing`, and
`Union{X,Nothing}` document fields are already idiomatic (`JuliaFor.step::Union{Document,Nothing}`,
`JsonNumber.value::Union{Real,Nothing}`, `JuliaReturn.value::Union{Document,Nothing} = nothing`).

**E. `_anchor_nonempty` L193-198** (elem → flat → elem) exists *solely* to re-anchor a caret off an
empty span. It is the workaround for the bug this phase removes. Keep it for now — the width-0 indent
slot still needs it — but it should shrink to nothing once that is gone.

### 1.2 — `Syntax.jl`: optional delimiter fields

Field types to `Union{TextString,Nothing}`; keyword constructors default to `nothing`; positional
constructors unchanged. `render` skips an absent delimiter.

### 1.3 — `SyntaxLeafToText`: emit only the spans that exist

Dynamic span list. Forward map `.open{k}` / `.close{k}` → the right index, or **decline** when that
delimiter does not exist. Backward map: index → the right field.

### 1.4 — `SyntaxNodeToText`: same for `open` / `close` / `sep`

Skip absent delimiters when assembling `elements`; keep `child_elem_ranges`, `indent_indices` and
`marker_index` consistent with the now-shorter element list.

### 1.5 — Sweep the domains

Drop explicitly-passed empty delimiters (`open=""`); fix anything relying on a bare leaf having three
spans or an `.open{0}` caret.

### 1.6 — Re-baseline

Caret counts *will* drop — that is the point. `json_null`: 3 spans → 1, and its rightward walk should
now end at `.value{4}`, exactly where Ctrl+End lands, so `right_reaches_end` / `left_reaches_start`
should agree by construction. Re-measure `NAV_LEFT_WALK_STALLS` / `NAV_RIGHT_WALK_MISSES_END` in
[ExampleSweeps.jl](../../package/projectured/test/editor/ExampleSweeps.jl); do not guess.

## Phase 2 — printers and readers for the six wrapper types

Make the wrappers real. Each gets the full projection surface, following the shape of
`SyntaxLeafToText` / `SyntaxNodeToText`:

1. a `<Type>ToText <: Projection` struct, carrying the config that type needs (e.g.
   `SyntaxIndentationToText` takes `indent_size`; `SyntaxCollapsibleToText` takes `expanded_marker` /
   `collapsed_marker` / `marker_eligible` / `ellipsis_text`);
2. an IoMap. The single-child wrappers (`Delimitation`, `Indentation`, `Collapsible`, `Navigation`)
   need a `child_iomap` plus the element range the child occupies; the multi-child ones
   (`Concatenation`, `Separation`) need `child_iomaps` + `child_elem_ranges` + `indent_indices` —
   i.e. the existing `SyntaxNodeToTextIoMap` shape
   ([SyntaxToText.jl:155](../../package/visual/main/syntax/SyntaxToText.jl#L155));
3. `print_document` — splice the child's `output.elements`, adding only this wrapper's own spans;
4. `map_reference_forward` / `map_reference_backward` — peel the one step this wrapper owns and
   delegate the tail to the child's mapper (School A: delegate through the child's IO map, never
   re-walk by document type);
5. `read_intent` for `ReplaceSelectionOperation` (delegate) and `ReplaceStringRangeOperation` (edits
   to this wrapper's own delimiter/separator spans); for `SyntaxCollapsible` also
   `ToggleCollapseOperation` and the 4-arg geometric reader for marker clicks;
6. `render` in `Syntax.jl`;
7. registration in the `SyntaxToText` `TypeDispatchingProjection`
   ([SyntaxToText.jl:818](../../package/visual/main/syntax/SyntaxToText.jl#L818)).

Do them in dependency order, one commit each, each with its own tests:

- **2.1 Extract the shared core — DONE.** The five jobs are now operations on a `SpliceBuffer`: the
  element list under construction plus everything the reference mappers need to know about where each
  span ended up (`child_elem_ranges`, `indent_indices`, `sep_indices`, `open_index`, `close_index`).
  `_push_marker!` / `_push_open!` / `_push_close!` / `_push_separator!` / `_push_ellipsis!` /
  `_push_line_chrome!` / `_splice_child!` are the operations; `_splice_node` is now just their
  composition, in render order, and reads as the five jobs it does.

  **Every operation *records* what it appended** — nothing is inferred from a span's position. That is
  forced by Phase 1: with optional delimiters no position identifies the open span (it is not
  necessarily `marker_index + 1`) or the close span (not necessarily the last element). It is also
  exactly what the wrappers need, since a `SyntaxDelimitation` wrapping a `SyntaxSeparation` cannot
  locate its delimiters positionally either.

  `_indent_span` now takes an `indent_size::Int` rather than the `SyntaxNodeToText` projection — the
  core must not know its caller's type, because the wrapper projections are not `SyntaxNodeToText`.

  Pure refactor, as required: all six guard rails match their baselines exactly (`test_visual`
  49291/0/1, `test_domain` 110766/0/1 err/15, `test_text_nav_invariants_all` 236/0/26, `test_typeins`
  1187/0/23, `test_table_navigation` 63/0/1 err/1, `test_click_roundtrips` 27/2/4).
- **2.2 `SyntaxConcatenation` — DONE, but not the way this plan said.** See "What 2.2 changed about
  the plan" below: there is **one projection for every compound**, not one per wrapper type.
- **2.3 `SyntaxSeparation` — DONE.** As predicted, nearly free: subtype `SyntaxCompound`, answer
  `syntax_separator(s) = :separator => s.separator`, register it in the dispatch table, test. No new
  printer, mapper, reader or metric — the separator machinery was already generic over the field name,
  and it correctly maps `.separator{k}` forward onto the first occurrence while mapping backward as
  projection-introduced chrome. An absent separator makes it render exactly as a `SyntaxConcatenation`,
  which is the whole difference between the two types and is asserted as such.

  **Field order is load-bearing — `separator` must precede `children`.** `@document`'s Rule Y
  ([StructPlan.jl](../../package/kernel/main/cell/StructPlan.jl)) generates a positional constructor
  per arity from `required_count` upward, where `required_count` counts the fields *before the trailing
  run of defaulted ones*. Declared `children, separator=nothing`, the trailing run is
  `separator, selection`, `required_count` is 1, and the generated arity-1 `SyntaxSeparation(Any)`
  collides head-on with the coercing keyword constructor — a **fatal method overwrite during
  precompilation**, not a warning. Leading with the defaulted `separator` (exactly as `SyntaxNode`
  leads with `open`/`close`/`sep`) puts the required field last, so generation starts at arity 2 and
  the arity-1 form is ours. This is the same trap as the Phase 1 note about Rule Y and `req == 0`,
  reached from the other side: there the danger is *widening* the gate, here it is *field order*
  changing what the gate computes.
- **2.4 `SyntaxDelimitation`** — open/close spans around a single child. **Each delimiter is
  independently optional**: `opening_delimiter` and `closing_delimiter` are both
  `Union{TextString,Nothing}`, and either may be present while the other is absent (an opening `"("`
  with no closer, a trailing `";"` with no opener). Absent means *no span emitted and no caret* — not
  `TextString("")`, which is the bug this whole plan exists to remove. The reference maps must
  therefore decline `.opening_delimiter{k}` when there is no opener, and the span indices are
  dynamic (0, 1 or 2 own spans around the content).
- **2.5 `SyntaxIndentation`** — the newline/indent chrome and the `indent_indices` + splice-widening
  machinery. **This is where the width-0 indent slot lives**, so the deferred indent-slot problem
  becomes localized to one projection.
- **2.6 `SyntaxCollapsible`** — the marker span, ellipsis, `marker_eligible`,
  `ToggleCollapseOperation` and the marker-click hit-testing.
- **2.7 `SyntaxNavigation`** — the `∅` whole-element anchor.
- **2.8 `SyntaxNothing` + `SyntaxInsertion`** — the domain's missing atoms; see below.

### 2.8 in detail — the Syntax domain's Nothing / Insertion pair

Every domain is supposed to have an empty placeholder and an insertion buffer: `@domain`
([Domain.jl:396](../../package/base/main/document/Domain.jl#L396)) generates
`XNothing` (the empty placeholder), `XInsertion` (`value::String = ""`, the typed-name buffer), the
Insert-key gesture that turns one into the other, and the traits wiring (`nothing_document`,
`insertion_document`, `domain_prefix`, …). `DocumentNothing`, `JsonNothing` and `JuliaNothing` all
exist. **The Syntax domain has neither** — `SyntaxInsertion` is declared in `Syntax.jl` but has no
traits, no gesture, no printer, and is never constructed; `SyntaxNothing` does not exist at all. The
Syntax domain is directly editable (there is a `syntax` example), so it needs both.

So: adopt the convention rather than hand-rolling it — `@domain Syntax root = SyntaxDocument
insertion = SyntaxInsertion`, generating `SyntaxNothing` and adopting the existing root/insertion.
`@domain`'s docstring explicitly notes the projection-table entries are *not* generated, so add
`SyntaxNothing => SyntaxNothingToText()` and `SyntaxInsertion => SyntaxInsertionToText()` to the
`TypeDispatchingProjection` at
[SyntaxToText.jl:818](../../package/visual/main/syntax/SyntaxToText.jl#L818).

**Layering constraint — check this first.** The existing renderers for these two roles,
`NothingToSyntaxLeaf` and `InsertionToSyntaxLeaf` (with the `_nothing_label` helper that turns
`JsonNothing` into "empty json"), live in
[package/domain/main/insertion/InsertionToSyntax.jl](../../package/domain/main/insertion/InsertionToSyntax.jl)
— the **domain** package, which sits *above* visual. `SyntaxToText` is in visual and cannot import
them. Options, decide before writing code: move the label helper (and possibly the generic
Nothing/Insertion renderers) down to base or visual so both layers share one implementation, or give
`SyntaxNothingToText` its own. Prefer sharing — a second `_nothing_label` is exactly the kind of
duplication this plan is trying to remove.

### What 2.2 changed about the plan

The plan above says each wrapper gets its own `<Type>ToText <: Projection` and its own IoMap. **That
was wrong, and 2.2 does not do it.** After Phase 1, a `SyntaxConcatenation` is not a new *rendering*:
it is a `SyntaxNode` with no delimiters, no separator, no indentation and no collapse, and it emits
exactly the same spans. A projection per wrapper would have been this file's mappers and readers —
child splicing, delegation, the flat metric, click resolution — copied out once per wrapper, for zero
behavioural difference. That is the duplication this plan exists to remove.

The five jobs are properties of the **document**; the projection supplies only **configuration**
(indent size, marker glyphs, ellipsis), and none of that differs per compound type. So:

- **`SyntaxCompound`** — a new abstract document type: a syntax document with a `children` sequence.
  `SyntaxNode` and `SyntaxConcatenation` subtype it (`SyntaxSeparation` will). Everything that walks
  the tree — the splice printer, both mappers, both readers, tree navigation, collapse resolution, the
  flat metric — is now written against `SyntaxCompound`, never `SyntaxNode`.
- **The compound contract** (`Syntax.jl`): `syntax_children` / `syntax_opening` / `syntax_closing` /
  `syntax_separator` / `syntax_indentation` / `syntax_collapsed` / `syntax_collapsible`. A compound
  that lacks a span answers `nothing` and no span — and so no caret — is emitted. An answer names the
  **document field** the span came from (`:open => …`), so a compound may call its delimiters whatever
  it likes and neither the printer nor the mappers care.
- **One projection** (`SyntaxCompoundToText`, renamed from `SyntaxNodeToText`) and **one IoMap**. The
  IoMap *must* be shared: a parent reads its child's `indent_indices` off the child's IoMap to widen
  them on splice, so a wrapper with an IoMap of its own type would be invisible to that read and every
  indent beneath it would silently stop being widened.
- **`own_spans`** replaces `open_index` + `close_index`: element index => document field, recorded by
  the printer. `sep_indices` stays separate on purpose — a separator is **not** backward-addressable
  (one `sep` field renders n−1 spans, so a caret in one of them names no single document position and
  must map back as projection-introduced chrome, exactly as before).
- **`@gestures SyntaxCompound`**, not `@gestures SyntaxNode`. The registry collects a type's own
  bindings plus every supertype's, so one declaration covers every interior node there is or will be.
  A `SyntaxLeaf` is not a compound and is untouched.

Two bugs this shook out, both found by tests, neither guessable:

- **`typeof(doc)` is not the reference node type.** `@document` generates a *reactive* struct, so
  `typeof(node)` is `RSyntaxNode` while the literal `::SyntaxNode` checkpoint means `SyntaxNode`.
  Every type checkpoint built by hand must use `reference_node_type(doc)`.
- **`_tree_navigate` was not canonical.** `:down`/`:left`/`:right` returned *annotated* paths (via
  `@reference(doc, children[i])`), but recursing back out on `:up` spliced a **bare** `∅` terminal.
  Selections are compared with `==`, types included, so a nested `:up` produced a path that *was* the
  child yet did not compare equal to it. Pre-existing; nested `:up` had no test. Fixed by typing the
  terminal (`_typed_terminal`), which also let `_child_element` and the `@reference` form collapse into
  one construction — the existing plain-arrow tests now *prove* the two are identical.

### Guard rails after 2.2

All green, but **`test_domain`'s pass count legitimately drops 110766 → 110182 (−584)**. Do not
"fix" this. The printer walker emits *one assertion per reactive cell*
([PrinterTest.jl](../../package/kernel/test/editor/PrinterTest.jl)), so its count tracks the size of
the reactive graph. Merging `open_index` + `close_index` into one `own_spans` cell removes one `Cell`
per compound IoMap, and there are exactly 584 compound IoMaps across the domain examples — confirmed
by re-adding a dummy `Cell`, which restores the count to 110766 precisely. **New `test_domain`
baseline: 110182 pass / 0 fail / 1 error / 15 broken.** `test_visual` rises to 49294+ (28 new
`SyntaxConcatenation` assertions); every other guard rail is unchanged to the assertion.

## 2.4–2.7 — the four single-child wrappers — **DONE**

`SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible` and `SyntaxNavigation` are now
one-child compounds, exactly as settled. They needed **no printer, no IoMap, no mapper, no reader and
no flat metric of their own** — they get all of it from the compound machinery.

`SyntaxCompound` split into two kinds, which is the only place they genuinely differ:

- **`SyntaxSequence`** — children in a `children::CellVector`, addressed `.children[i]`
  (`SyntaxNode`, `SyntaxConcatenation`, `SyntaxSeparation`).
- **`SyntaxWrapper`** — exactly one child in `content`, addressed `.content`
  (the four above).

The contract grew one member in each direction: `syntax_child_path(doc, i, inner)` **builds** the step
down into a child (the compound answers `.children[i]` or `.content`), and `peel_child_step(path)`
**parses** one back off a path. Every matcher that used to spell `FieldReference("children")` literally
— `_is_tree_selection`, `_promote_to_structural`, `_descend_to_text_cursor`, `_tree_navigate`,
`_resolve_collapsible`, `map_reference_forward`, `_child_elem_range`, `_syntax_to_flat` — now goes
through that pair and no longer knows which kind of compound it is walking. `peel_child_step` is
structural (no document), because `_is_tree_selection` and `_promote_to_structural` are handed a path
with nothing to ask.

A wrapper is a real level of the tree, and that is right: selecting a `SyntaxDelimitation` means *"the
parenthesised thing, including its parens"*, which is a different selection from selecting its content.
Only `SyntaxCollapsible` answers `syntax_collapsible`, so no other wrapper is ever handed a fold marker
that would do nothing when clicked.

Field order again: each wrapper's defaulted fields precede its required `content`, for the Rule Y
reason recorded under 2.3.

### Per-child indentation is not decomposable — the combined type earns its keep

Stacking wrappers **cannot** reproduce `SyntaxNode`'s indented, separated list, and this is inherent:

| built as | renders |
|---|---|
| `SyntaxNode(kids; open="[", close="]", sep=",", indentation=1)` | `[\n  1,\n  2\n]` |
| `Delimitation(Indentation(Separation(kids, ",")))` | `[\n  1,2\n]` |
| `Delimitation(Separation([Indentation(1), Indentation(2)], ","))` | `[\n  1\n,\n  2\n]` |

`SyntaxNode` emits `sep, newline, indent, child` — the separator and the line chrome **interleaved, by
one node**. Split across two nodes, the separator belongs to the separation and the chrome to the
indentation, and whichever is outer emits its spans outside the other's. There is no stacking order
that interleaves them. `SyntaxIndentation` has exactly one child and indents *that one thing*; it is a
different (and perfectly good) job.

**So a per-child indented, separated list IS the combination fitting, and `SyntaxNode` is the right
tool for it.** This is not a gap to close — it is the reason the combined type exists, and it narrows
Phase 3: SQL's `_comma_body` / `_newline_body` / `_newline_body_compact` and every domain's indented
list stay `SyntaxNode`s. Asserted in `SyntaxToTextTest` so nobody "fixes" it later.

### Still open

- **`SyntaxNavigation` does nothing yet.** It is a compound with one child and no spans, so it renders
  as its content and is a selectable tree level — which is *most* of "the `∅` whole-element anchor"
  the plan asked for, but it has no behaviour of its own beyond that. Decide whether it needs any.
- **A wrapper's decoration font.** `_deco_font` deliberately does not consult the children (reading a
  child's spans during the parent's splice would make the printer eager where it must be lazy), so a
  `SyntaxIndentation` with no delimiters of its own gives its newline/indent spans the *default* font
  rather than the content's. On a `SyntaxNode` the delimiters supplied it. Harmless until a domain
  puts an indentation wrapper around content at a non-default size, where it would pin the line height.
- **`SyntaxIndentation` as a nuisance tree level.** Its own spans are pure whitespace, so stopping on
  it in tree navigation may be noise. If it proves so, a per-type `syntax_transparent` knob can hide
  it. Not built — do not build it up front.
- ~~**`SyntaxConcatenation` in a `@projection_template` blueprint does not work.**~~ **FIXED.** See
  "The template-blueprint gap" below. The Phase 1 lesson — that a fixed-children template node cannot
  use the keyword form — **no longer holds**, and the 7-arg positional form is no longer forced.

### The template-blueprint gap — FIXED

Phase 1 recorded that `SyntaxNode`'s children container is "load-bearing in two conflicting ways": a
hand-written projection's output needs a `CellVector` (the reference machinery navigates `.children[i]`
through its element cells), while a `@projection_template` blueprint needs a raw `Vector` (the engine
detects a fixed-children node with `getfield(out, f)[] isa Vector`). The conclusion was that a
fixed-children template node **cannot** use the keyword form and is stuck with the 7-arg positional
call. That conclusion is now obsolete: **the conflict was never in the constructor, it was in the
engine's detection.**

`ProjectionTemplate._has_fixed_children` now accepts *either* storage
([ProjectionTemplate.jl](../../package/kernel/main/projection/ProjectionTemplate.jl)):

- a raw `Vector` counts unconditionally, exactly as before;
- an **element collection** (`is_element_collection` — the document-layer trait `CellVector` opts into;
  the kernel cannot name `CellVector`, which lives in base) counts **only when it carries a marker**.

The marker test is its own predicate, because the engine's existing ones do not answer this question:
the commonest fixed child is a `SyntaxLeaf(bound(:x))`, which is neither a marker (`_is_marker`) nor a
marker-bearing sub-node (`_is_marker_bearing_subnode`) — it is an ordinary document holding a marker in
a *field*. `_has_fixed_children` only ever runs on a builder's blueprint, never on a hand-written
projection's output, so forcing the cells it reads costs nothing at print time.

Gating the new case on "carries a marker" makes the rule **strictly additive**: a marker-free
`CellVector` is an ordinary output subtree and still goes to `_atomic_print`, so no existing template
changes behaviour.

The symptom this removes, reproduced before fixing and now a regression test
([ProjectionTemplateTest.jl](../../package/visual/test/projection/ProjectionTemplateTest.jl)): a
blueprint written `SyntaxConcatenation([...])` fell through to `_atomic_print` and its `bound` markers
reached the printer unresolved, which read `.content` off a `Bound` and died with
`type Bound has no field 'content'`. The test now asserts the same blueprint renders identically
written three ways — positional `SyntaxNode`, `SyntaxConcatenation([...])`, and `SyntaxNode([...]; sep=…)`.

**This unblocks Phase 3.** Julia's 19 connector nodes can now actually be written
`SyntaxConcatenation([...])`, and any fixed-children node can use the keyword form.

### Design decisions to settle in Phase 2 — do not skip these

- **Reference depth.** Every wrapper adds a `.content` hop, so a wrapped node's paths get longer.
  Check the impact on `strip_reference_types`, `@reference_case` patterns, and above all tree
  navigation: `_is_tree_selection` / `_promote_to_structural` / `_descend_to_text_cursor`
  ([Syntax.jl:426-561](../../package/visual/main/syntax/Syntax.jl#L426-L561)) walk chains of
  `.children[i]` steps and must hop transparently over wrapper `.content` steps. `@gestures
  SyntaxNode` ([Syntax.jl:394](../../package/visual/main/syntax/Syntax.jl#L394)) is registered on
  `SyntaxNode` — decide whether tree navigation moves to `SyntaxNavigation` or the gesture table
  follows the content.
- **Collapse semantics.** `ToggleCollapseOperation` carries a `SyntaxNode` today. If collapse moves
  to `SyntaxCollapsible`, the operation and the collapse-lives-at-the-syntax-layer behaviour follow
  it.
- **Layering cost.** Each wrapper is another projection layer per node — more iomaps, more cells.
  `PrinterLocalityTest` is the guard; watch it for reconciliation loss.

## Phase 3 — let each domain pick the document that fits

Opportunistic, one domain per commit, re-baselining each time. This is **not** a forced march: a
domain moves to a finer-grained document only where that document says what it means more directly
than the combined one. Where a `SyntaxNode` is genuinely a delimited, separated, indented node, it
stays a `SyntaxNode`. The inventory gives the clear-cut cases:

- **Julia — DONE (the connector nodes).** All **24** of them (not 19 — the inventory undercounted
  the nested ones) are now `SyntaxConcatenation([...])` instead of
  `SyntaxNode(nothing, nothing, nothing, [...], 0, false, nothing)`. The example renders
  **byte-for-byte identically** (`print_example("julia")` hashes the same before and after), which is
  the invariant that matters: a concatenation is a drop-in for a bare node.

  The win is not spans — Phase 1 already took julia from 65 empty spans to 1. It is **cells**:
  `SyntaxNode` carries 7 (open, close, sep, children, indentation, collapsed, selection),
  `SyntaxConcatenation` carries 2. Five fewer reactive cells per node, and `test_domain`'s pass count
  drops by exactly 130 — the printer walker asserts once per cell, so that is 26 connector-node
  instances × 5. The reactive graph is 130 cells smaller and the code says what it means.

  **Three of them are children *thunks*** (`return` vs `return <value>` — the F2
  conditional-children shape), and they forced a real constraint into `SyntaxConcatenation`: a bare
  `Function` must be stored **as it is**. The engine recognises a conditional-children node by
  finding an unevaluated `Function` in the field; coercing it into a `CellVector` replaces it with a
  cell-wrapping thunk and the markers it returns are never resolved. So
  `SyntaxConcatenation(f::Function)` stores `f` raw, and a hand-written projection that wants
  reactive children says so explicitly: `SyntaxConcatenation(CellVector(f))`.

  Still to do for julia: `JuliaBlock`'s `indentation=1` → `SyntaxIndentation`.
- **SQL** — the six helpers: `_kw` → bare leaf; `_space_node` / `_comma_node` → `SyntaxSeparation`.
  **But `_comma_body` / `_newline_body` / `_newline_body_compact` must STAY `SyntaxNode`s** — see
  "Per-child indentation is not decomposable" below. 16 of 22 node rules still drop their empty
  delimiters.
- **Markdown** — the five `sep=""` types → `SyntaxConcatenation`.
- **JSON / YAML / XML** — entry nodes with explicit `TextString("")` open/close → `SyntaxSeparation`;
  array/object `indentation=` → `SyntaxIndentation`.
- The rest: object, book, conversation, filesystem, dbcatalog, formula, math, gesturemap.

There is no Phase 4. `SyntaxLeaf` and `SyntaxNode` keep every field they have; the combined and the
fine-grained documents coexist permanently, sharing one implementation.

## Guard rails

These must not regress at any point. Baselines **as of the end of Phase 1** (run all of them — the
first Phase 1 commit regressed `test_domain` unnoticed because it was not on this list):

- `test_domain()` — 0 failed / 1 errored / 15 broken.
- `test_visual()` — 0 failed / 1 broken.
- `test_kernel()` / `test_base()` — clean.
- `test_text_nav_invariants_all()` — 236 pass / 0 fail / 26 broken. Improvements expected;
  regressions are not.
- `test_typeins()` — 1187 pass / 23 broken. Typing must still work everywhere it does today.
- `test_table_navigation()` — 63 pass / 0 fail / 1 error / 1 broken.
- `test_click_roundtrips()` — 27 pass / 2 fail / 4 error.
- `test_position_navigations()` — 113 fail / 2 error, all of one pre-existing class (105 `under-typed
  @reference` in Yaml/Sql, 2 `SelectionMismatch`, 1 `MethodError`). Watch the failure *classes*, not
  the counts: the counts move whenever the reachable-caret set changes, which this work does by
  design.
- `PrinterLocalityTest` — the reactive-reuse guard; wrapper layers must not break reconciliation.

## Deferred

- **The width-0 indent slot.** `SyntaxToText` emits an empty `TextString` before each close so
  ancestors always have a slot to widen and element counts do not depend on depth
  ([SyntaxToText.jl:479-486](../../package/visual/main/syntax/SyntaxToText.jl#L479-L486)). Optional
  delimiters do **not** remove it, and it is the remaining source of the left-motion stall. Phase 2.4
  localizes it to `SyntaxIndentationToText`; the fix lands with the text-selection work below.
- **A text-domain reference step that ignores spans.** The span-boundary duplicate — one visual caret,
  two valid paths, `(span, len)` and `(span+1, 0)` — is baked into today's `.elements[i].content{k}`
  representation, and both the cursor steppers and the click round-trip work around it. A reference
  step addressing a *flat character offset* instead would make the duplicate unrepresentable. That is
  the real fix for the caret model; this plan stops manufacturing spans that should never have
  existed.
Nothing else. `SyntaxNothing` and `SyntaxInsertion` are **not** deferred — they are Phase 2.8.
