# Generic depth-limited `show` for `Document`

## Goal

Provide **one** `Base.show(io::IO, ::Document)` in the core so that every document
type gets a sensible, **recursion-bounded** debug rendering for free — instead of
each domain hand-writing a per-type `show` that re-implements the same
constructor/summary form and risks exploding when documents nest deeply.

Then delete **all** per-type `show` methods on `Document` subtypes — both the
debug constructor/summary forms *and* the "semantic" source renderings.

### Why semantic `show` methods go too

Semantic rendering of a document (JSON/Julia/SQL/NED source, math infix, etc.) is
the job of the **projection pipeline**, not `show`. A document is rendered
properly by a compound projection / `path` that maps it to text with full
fidelity (fonts, colors, selection, bidirectional editing). The per-type `show`
methods that reproduce a flattened source form are a redundant, lower-fidelity
second renderer. With a *general* depth-limited generic `show` in place, a
per-type `show` "barely buys anything" — it just duplicates either the generic
constructor form or the projection's semantic form. So the only `show` we keep on
documents is the single generic one, as a cheap REPL/debug aid; anyone who wants
the real rendering goes through a projection.

## Why this is the right place

- Every concrete document subtypes `Document`
  ([program/src/api/Document.jl:33](../../program/src/api/Document.jl#L33)).
- A generic `show(io, ::Document)` is the *least specific* method, so it only
  fills in for types without their own `show`. Existing, more-specific methods
  keep winning — there is no dispatch ambiguity. We are only replacing Julia's
  built-in `show_default` fallback, which is exactly the thing that recurses
  unboundedly.
- omnetpp-pred (and any other downstream domain) imports this `Document`, so they
  inherit the behaviour automatically. See the sibling plan
  `omnetpp-pred/plan/pending/generic-document-show.md`.

## Key facts discovered during investigation

1. **No generic `show(io, ::Document)` currently exists.**
2. **The `@document` macro stores every field as a `Cell`** and routes `obj.foo`
   through a custom `getproperty` that unwraps it
   ([program/src/common/Document.jl:79-93](../../program/src/common/Document.jl#L79-L93)).
   A reflection-based generic `show` MUST read through `getproperty(x, f)`, **not**
   `getfield`, or it will print `Cell(...)` wrappers.
3. **Projection printers do not consume document `show` output.** Printers build
   `TextString`/spans directly from fields (e.g. `ReferenceToText.jl`,
   `SyntaxToText.jl` use `string(...)` on primitives, not `show` on documents).
   So these `show` methods are debug/REPL conveniences — removing/altering them
   does not change rendered output. The only consumers to watch are **test
   baselines** and REPL ergonomics.
4. There are ~190 `Base.show(io, …)` methods in `program/src/`. They fall into
   three buckets (see Categorization).

## The generic method

Add to `DocumentModule` in
[program/src/common/Document.jl](../../program/src/common/Document.jl), next to the
`selection` accessor:

```julia
"""
    show(io::IO, x::Document)

Default depth-limited debug rendering for documents. Prints constructor-style
`TypeName(field, field, …)`, reading each field through `getproperty` so the
underlying `Cell`s are unwrapped. Recursion is bounded by the `:document_depth`
IOContext key so deeply nested documents do not explode. The `selection` field
(present on every document) is omitted as noise.

A domain may override this with a more specific method when it wants a semantic
rendering (e.g. source syntax) instead of the constructor form.
"""
function Base.show(io::IO, x::Document)
    depth = get(io, :document_depth, 0)
    print(io, nameof(typeof(x)), "(")
    if depth ≥ DOCUMENT_SHOW_MAX_DEPTH
        print(io, "…")
    else
        inner = IOContext(io, :document_depth => depth + 1)
        first = true
        for f in fieldnames(typeof(x))
            f === :selection && continue
            first || print(io, ", ")
            show(inner, getproperty(x, f))
            first = false
        end
    end
    print(io, ")")
end

const DOCUMENT_SHOW_MAX_DEPTH = 2   # tune; start conservative
```

Notes / caveats to verify during implementation:

- `:document_depth` propagates through `show(io, ::AbstractArray)` because array
  show passes the same `io` to element show — so a vector field of child
  documents is also depth-bounded. Confirm with a nested example.
- This is a *display* form, deliberately not round-trippable. Documents
  reconstruct via the `I`-prefix snapshot constructors, never via `show`, so this
  is fine.
- 2-arg `show` covers nested/array/`repr` contexts; the REPL's 3-arg
  `show(io, ::MIME"text/plain", x)` falls back to it. No 3-arg method needed.

## Categorization of existing `show` methods

> The generic method only affects types that have **no** specific `show`. The
> policy is simple now: **every `show` on a `Document` subtype is removed**; only
> `show` methods on non-`Document` types stay.

### REMOVE — every per-type `show` on a `Document` subtype

This includes both buckets that the earlier draft split apart:

- **Debug / constructor / summary forms** — most of `Widget.jl` (32),
  `Workbench.jl` (10), `Book.jl` (5), `Graphics.jl` (8), `Layout.jl` (6),
  `GraphLayout.jl` (4), `Graph.jl` (3), `Conversation.jl` (5), `DbCatalog.jl` (5),
  `Tabular.jl` (3), `Versioning.jl` (3), `Component.jl`, `Dragging.jl`,
  `Screen.jl` (2), `Image.jl` (2), `FileSystem.jl` (2), `Evaluator.jl` (2),
  `DatabaseInstance.jl` (2), `Clipboard.jl` (2), `Formula.jl` (3),
  `Workspace.jl` (2), `Tooltip.jl`, `Collection.jl` (4), `Document.jl` (3),
  including count summaries like `WidgetTree(N)` / `SqlStatementList(N)` — the
  generic depth limit replaces them.
- **Semantic / source renderings** — `Json.jl`, `Julia.jl` (31), `Sql.jl` (8),
  `Xml.jl`, `Math.jl`, `Primitive.jl`, `Text.jl`, `Syntax.jl`. These move to the
  projection pipeline's responsibility (see "Why semantic `show` methods go too").
  Delete them; do **not** preserve the source form in `show`.

For each method, verify the receiver type is `<:Document` (it almost always is in
`document/`), then delete the method.

### NOT a `Document` — out of scope, do not touch

The generic method does not dispatch on these; leave their `show` alone.

- `common/Reactive.jl` — `Cell`.
- `reference/Reference.jl` (8) — reference path steps.
- `document/Geometry.jl` — `Inset`, `Point2D` (value types; verify not `<:Document`).
- `document/StyleText.jl`, `document/StyleStroke.jl` — verify whether `<:Document`.
  If **not** a `Document`, leave their `show` as-is. If they **are** documents,
  they fall under REMOVE like everything else.
- `external/Database.jl` — `RawDatabaseResult`.

## Risks

- **Bigger baseline churn than the first draft.** Removing the *semantic* `show`
  methods changes any debug/REPL output that previously showed source form to the
  generic constructor form. Before deleting, grep non-test code for incidental
  consumers — `repr(`, `sprint(`, `string(<doc>)`, `"$(<doc>)"` on a document —
  to confirm nothing outside the projection pipeline depends on the source form.
  (Investigation so far: projection printers build spans from fields, not from
  document `show`, so this is expected to be clean — but re-verify per domain.)
- **Test baselines.** Some tests may assert exact `show`/`repr` output. After each
  removal batch, run the relevant printer/REPL tests and diff. Update baselines
  only where the change is intended.
- **`StyleText`/`StyleStroke`/`Geometry` membership.** Confirm whether they
  subtype `Document`. Non-documents keep their `show`; documents get it removed.
- **Depth threshold.** `MAX_DEPTH = 2` is a starting guess; adjust after eyeballing
  real nested documents (e.g. a `Workbench` or `WidgetComposite` tree).

## Steps

1. **Add the generic method** to `DocumentModule` with `DOCUMENT_SHOW_MAX_DEPTH`.
   Export nothing new. Commit.
   - Verify: in the REPL, `show` a couple of types that currently have **no**
     `show` (or temporarily none) and confirm depth bounding + Cell unwrapping.
   - Test: `test_cell()` plus one domain that has nested documents, e.g.
     `test_repl(<a widget/workbench example>)`.
2. **Confirm the NOT-A-DOCUMENT set** by checking supertypes (`x isa Document`)
   for the ambiguous ones (`StyleText`, `StyleStroke`, `Geometry`). Record findings
   inline in this plan. Also grep non-test code for incidental `show`/`repr`/
   `string` consumers of documents (see Risks). Commit (plan only).
3. **Delete every per-type `show` on a `Document` subtype**, in small per-file
   batches (semantic domains like `Julia.jl`/`Sql.jl`/`Json.jl` included). After
   each file:
   - Delete just the `show` methods.
   - Run the narrowest test that touches that domain (e.g. `test_repl(...)` /
     `test_printer(...)`) and check for baseline diffs.
   - Commit per file (or per small group).
4. **Final sweep**: run `test_printers()` / `test_repls()` once to catch any
   baseline drift, fix/accept, commit.
5. Move this plan to `plan/done/`. Coordinate with the omnetpp-pred sibling plan.

## Out of scope

- Changing how projections render (printers don't use document `show`).
- 3-arg `show(::MIME"text/plain", …)` customisation.
- Round-trippable / parseable `show` output.

## Implementation outcome (done)

Implemented on branch `generic-document-show` (worktree
`../projectured-julia-show`).

- **Generic method added** to `DocumentModule`
  ([program/src/common/Document.jl](../../program/src/common/Document.jl)).
  Commit `d5ffad6`.
- **All 172 per-type document `show` methods removed** across 32 files
  (`program/src/document/*` plus `document/Document.jl`). Commit `068d3ef`.
- **`Cell.show` fixed to forward the IOContext** (`show(io, c.value)` instead of
  `repr(c.value)`, which built a fresh buffer that dropped `:document_depth`).
  Because every document field is Cell-wrapped, the old `repr` reset the depth at
  each Cell, so the limit only bit within a single getproperty-chain and full
  trees still printed (e.g. the whole `ini` document). Forwarding `io` makes the
  depth limit **general** across Cell-wrapped subtrees — this is what makes the
  generic `show` actually worth having. Output for non-document Cell values is
  unchanged. (`common/Reactive.jl`.)
- **Confirmed non-document keep-list** (left untouched): `Cell`
  (`common/Reactive.jl`), the 8 `Reference*` steps/paths
  (`reference/Reference.jl`), `Inset`/`Point2D` (`document/Geometry.jl`),
  `StyleText`, `StyleStroke`, and `RawDatabaseResult` (`external/Database.jl`).
  `StyleText`/`StyleStroke`/`Geometry` are plain structs, **not** `<:Document`,
  so they keep their `show` — they are not documents, so the "no exceptions for
  documents" rule does not touch them.
- **No incidental consumers**: grep confirmed projection printers build spans
  from fields (`string(...)` on primitives), never from document `show`/`repr`.
- **Verification**:
  - Package precompiles cleanly after the deletions.
  - Generic `show` exercised on the real nested `json` and `ini` example
    documents — Cells unwrapped, constructor form, depth cutoff renders `…` at
    the boundary (json: 559-char bounded output showing all top-level keys; ini:
    `IniSection("General", true, CellVector(…), false)` style).
  - Full `test_printers()` + `test_readers()` + `test_repls()` sweep over all 84
    examples, **after the `Cell.show` change** (pervasive): **165,711 pass,
    5 fail**. The 5 failures are all in `sql_table` and are a **pre-existing**
    `length(::Cell)` bug — verified identical on unmodified `main` (378 pass /
    5 fail). This change regresses nothing.
- **Depth threshold `DOCUMENT_SHOW_MAX_DEPTH = 3`.** With the Cell fix the limit
  became effective; a `CellVector` plumbing wrapper costs one depth level, so `2`
  collapsed even section names. `3` shows each document's own scalar fields and
  collapses nested collections to `…` — a good default for both json and ini.
  Revisit only if a domain wants more/less.
