# `@projection_template` generalizations (Stage C enabler)

> **Status: DONE.** All five generalizations (A–E) are implemented in
> `package/domain/src/projection/ProjectionTemplate.jl` and proven by driving the
> full omnetpp-pred INI/NED refactor (all 22 projections now template-derived).
> Regression gate held throughout: `test_json_to_syntax` 11/11, `test_sql_to_syntax`
> 19/19, `test_text_navigation(json_example; check_reaches_all=true)` 543/543. The
> consumer end-to-end gate (omnetpp-pred): `test_printer` ini 3538 / ned 5870,
> `test_text_navigation` ini 820 / ned 711 — identical before and after every gap.
> Commits: A+B `05b9822`, C `f96902a`, E `e8dbce5`, D `7918035`.
>
> - **A** named-field `bound` — DONE (`_atomic_print` value-lens).
> - **B** top-level fixed-children node — DONE (`rule_print`→`_fixed_print`; KeySlot
>   cursor auto-wiring also retired JSON's `_entry_key_sel`).
> - **C** fixed prefix + spliced collection — DONE (`MixedNodeWiring`).
> - **E** computed inline-token node — DONE (`tokens(thunk)` / `InlineWiring`; the
>   reactive per-recompute marker-strip handles a varying token count).
> - **D** section-grouped, skip-empty — DONE (`sections([...])` / `SectionsWiring`;
>   consumer `make_wrapper` keeps the engine output-neutral).

Follow-up to [projection-template-engine.md](projection-template-engine.md). That
plan built the builder/walk engine and converted JSON (fully) and SQL (leaves).
Its "Stage C — sweep other `XToSyntax` projections" needs the engine to express a
few shapes it currently can't. This plan specifies those generalizations.

Driver: refactoring **omnetpp-pred** INI/NED projections onto the template
(`omnetpp-pred/plan/pending/projection-template-refactor.md`). But every
generalization here is **domain-independent** — the engine names no input or
output type (it classifies fields by *value* via reflection and keys off the
marker's `:field` symbol), so a capability added "for NED" is automatically
available to every domain. JSON and SQL already share the identical engine with
zero per-type code; these gaps extend that shared machinery.

## Why this is broadly useful, not INI/NED plumbing

Only 2 of 14 `*ToSyntax` projections use the template today; **12 are still
100% hand-written** with `SimpleIoMap`/`ChildrenIoMap` (call-sites: Book 27,
Julia 31, DbCatalog 22, Math 18, Object 12, Xml 11, Formula 9, FileSystem 9,
Conversation 6, DocumentInsertion 6, Collection 5, Primitive 15; SQL nodes 101).
Each gap is a generic *projection shape* those files are full of:

| Gap (generic shape) | Beneficiaries beyond INI/NED |
|---|---|
| **A** named-field `bound` (editable field ≠ `value`) | Xml names, Julia identifiers, FileSystem names, Book/Conversation text |
| **B** top-level fixed-children record | DbCatalog/SQL column defs, Xml `name="value"`, Object field rows |
| **C** fixed leaf + spliced collection | Xml (tag + children), FileSystem (dir + entries), Book (heading + body) |
| **D** section-grouped, skip-empty | DbCatalog table (columns/constraints/indexes), Object class (fields/methods) |
| **E** inline variable-token leaf | Julia/Math/Formula highlighted tokens — any multi-color single leaf |

Caveat: the **Syntax flat-offset fallback reader** (`_syntax_to_flat` →
proj-wrapped `PositionReference`) that nodes carry is *Syntax-output*-specific, but
it already lives in the per-projection `projection_read` (JSON nodes have it too),
**not** in the engine. The A–E wiring/mappers stay output-domain-agnostic.

Engine file: `package/domain/src/projection/ProjectionTemplate.jl` (post-reorg).

---

## Gap A — named-field `bound` (value-lens) · SMALL · prereq for B/C/E

Today `bound(:f, T, render)` only renders a cursor when `f === :value`: the bound
mappers (`_atomic_forward`/`_atomic_backward`) already remap `.f ↔ .value`
generically, but `_atomic_print` shares `doc.selection` **raw** into the leaf's
selection cell, and `SyntaxToText._leaf_cursor` only recognises `.value{k}` /
`.open{k}` / `.close{k}`. So a `bound(:text, …)` leaf puts `.text{k}` in the cell
→ `_leaf_cursor` returns −1 → no cursor.

Change (`_atomic_print`): three-way selection-cell wiring.

```julia
iomap = RuleIoMap(p, doc, out, wiring, nothing)
sel =
    wiring.bound_field === nothing ? Cell(() -> map_reference_forward(p, nothing, doc.selection)) : # opaque
    wiring.bound_field === :value  ? getfield(doc, :selection) :                                    # transparent fast path (JSON/SQL — unchanged)
                                     Cell(() -> map_reference_forward(p, iomap, doc.selection))      # value-lens
setfield!(out, :selection, sel)
```

The value-lens cell yields `::Leaf.value::TS{k}` for a char cursor (checkpoints
stripped by `_leaf_cursor` → `.value{k}`, identical cursor) and `::Leaf` for
whole-element (→ −1, no interior cursor, correct). JSON/SQL keep the raw-share fast
path, so they're byte-for-byte unchanged.

Unlocks: editable leaves on any non-`value` field.
Regression gate: `test_json_to_syntax`, `test_sql_to_syntax`, full-reach
`test_text_navigation(json_example; check_reaches_all=true)`.

## Gap B — top-level fixed-children node · MEDIUM (depends on A)

`FixedNodeWiring` + `_fixed_print`/`_fixed_forward`/`_fixed_backward` already exist
but are only reached *inside* a templated collection. `rule_print` only branches
atomic vs. `collection`-node, so a top-level fixed node falls into `_atomic_print`
(wrong).

Change (`rule_print`): add a third branch.

```julia
coll !== nothing && return _node_print(…)
_has_fixed_children(out) && return _fixed_print(p, recursion, doc, ctx, out)   # a children Vector with markers
return _atomic_print(p, doc, out)
```

`_fixed_print` already classifies each child generically: `project(:f)` →
ProjectSlot, a leaf carrying a `bound(:f,…)` marker → `KeySlot(in_field=f)` (whole
→ `.children[k]`, char → `.children[k].value`), else IntroSlot. `KeySlot` already
stores `in_field`, so distinct fields (`.key`/`.value`/`.comment`) already work.
Optional children fall out (absent slot ⇒ mapper returns `nothing`).

Two implementation notes:
- The builder must keep a **raw `Vector`** of children (the keyword `SyntaxNode([…])`
  normalises to a CellVector). Use the positional `SyntaxNode(open,close,sep,
  [children…], indent, collapsed, sel)` form, as JSON's pair node already does.
- **KeySlot cursor auto-wiring (engine simplification):** in `_fixed_print`, set each
  KeySlot child leaf's own selection cell to a generic `in_field{k}→value{k}` remap
  of `doc.selection`, instead of requiring the builder to pass one. This also lets
  `JsonToSyntax` drop `_entry_key_sel` (verify with `test_json_to_syntax`).

Unlocks: any record-shaped leaf node (multiple editable fields on one line,
optional trailing fields).

## Gap C — fixed leaf(s) + spliced collection · MEDIUM

A node whose children are a fixed prefix **plus** a collection spliced as siblings
(heading leaf + entry siblings). Today a node is *either* one `collection` *or*
fixed children.

Change: allow the builder's children list to mix fixed marker children with one
`collection(:field)` that **splices**. New `MixedNodeWiring{prefix_slots,
coll_field, offset}`. Mappers compose `_fixed_*` over the prefix and `_node_*` over
the collection with `offset = length(prefix)`:
`.field[i] ↔ .children[offset+i]`, `.<prefix_field> ↔ .children[1]`.

Unlocks: tag/heading + children-as-siblings.

## Gap D — section-grouped node (multi-collection, skip-empty) · LARGE

Children = one labelled wrapper `SyntaxNode(label, …)` per **non-empty** input
collection field; each wrapper's children are that field's delegated collection.
`.field[i] ↔ .children[sec].children[i]`, where `sec` is the index among
**non-empty** sections (dynamic). Node `open`/`close` are reactive text
(e.g. `network Name extends … like … {`), already supported via thunked
`TextString`; the conditional `close` (`}` vs `""`) is ordinary builder logic.

Change: a `sections([(label, :field), …])` builder marker producing a new
`SectionWiring` that (a) emits a labelled wrapper per non-empty field, (b) keeps
the dynamic section index, (c) delegates each wrapper's collection (School A).

Unlocks: records whose children are several labelled homogeneous groups.

## Gap E — inline variable-token node · MEDIUM/LARGE

An inline node (indent 0) whose **computed, variable-length** token-leaf vector
colours each run; one token (a fixed child index) is editable (`bound(:name,…)`),
the rest are decorative (IntroSlot, selecting one → flat fallback).

`_fixed_print` walks a **static** `Vector` once; here the children are a
`CellVector` recomputed per render with a varying token count. Change: support a
fixed node over a **computed** children vector, re-walking reactively so the slots
(wiring) and the stripped output children both track the token vector. One KeySlot
at the known index; others default IntroSlot.

Unlocks: any single logical leaf rendered as multiple coloured spans with one
editable span (pervasive in highlighted-source projections).

---

## Order & gating

A → B → E → C → D (ascending risk; A is JSON-preserving and unblocks the rest).
After each gap, re-run the JSON/SQL gates (no regression) and the consuming
omnetpp-pred example as end-to-end proof of the new capability. Per CLAUDE.md,
commit each gap separately and update this plan with decisions discovered during
implementation; move to `plan/done/` when all five land and Stage C of the engine
plan can proceed for the other 12 domains.

## Out of scope (unchanged from engine plan)

- Authoring readers (keystroke→new-document) stay hand-written.
- Escape-aware character mapping.
- Non-Syntax output domains (engine already neutral; no builders targeted).
