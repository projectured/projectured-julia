# Narrow the composition point without closing it

## Why

A document field that composes domains is declared `Any`. That is how an XML
element goes into a JSON array, and the freedom is the point of the editor.

But `Any` says more than the design means. It conflates two statements:

1. **"this field composes domains"** — open when a person authors a document,
   and **enumerable at build time**
2. **"this field holds anything at all"** — never enumerable

The design means (1). The annotation says (2). Everything below follows from
that one sentence.

The cost of the difference is visible where the editor is compiled ahead of
time. In `omnet-julia`, `tool/trim-routing/routing.seal.jl` carries seven
seals — four `seal_argument` and three `seal_compile` — for one call:

```julia
==(a::ProjectionReferenceStep, b::ProjectionReferenceStep) =
    a.output_path == b.output_path && ...
```

`output_path` reads out of a cell as `Any`, so the site is `==(Any, Any)`,
**225 methods match**, and some of them can never have an instance — the build
demands `==(Core.PhiNode, Core.PhiNode)`. The seal file's own comment says the
promise "restates the program's own declaration", because the field IS declared
`output_path::Reference`.

The seal file also records what happened when someone narrowed `==` globally:
`ProjectionReferenceStepModule.:(==)` **is** `Base.==` re-exported, so the
promise reached every `==` in the image and the build died inside `Dict`, at
`isslotfilled → != → == at int.jl:564`.

## The idea

`abstract type Document` already exists in
[DocumentInterface.jl](../../source/kernel/document/DocumentInterface.jl), and
`@document` gives every schema that supertype unless one is written — see
[DocumentMacro.jl](../../source/kernel/document/DocumentMacro.jl), where the
default is applied.

So the open set already has a nominal name. **Openness by subtyping rather
than by absence of a type.** A new domain subtypes `Document` and no existing
code changes, exactly as today; but the set is enumerable at build time,
because at build time no new subtype can appear.

## What this plan does NOT do

**It does not introduce an `Embed` node.** Wrapping a foreign document in a
kernel `Embed` type would close every container's element type completely, and
it was considered and rejected: **projections combine the same way documents
do**, so an `Embed` in the document forces every projection to handle it and
to carry it forward. The concept would have to exist twice, and the second
copy buys nothing the first does not.

**It does not type a cell.** A reactive cell holds `Any` on purpose. A cell
with a concrete element type would fix, when the document type is written,
which domains may ever meet in that field. Storage stays `Any` in both stages
below.

**It does not parameterize containers.** `JsonArray{T}` looks like the tidy
answer and makes the ahead-of-time problem worse: `switchtupleunion` splits a
`Union` and cannot split a `UnionAll`, so a site whose argument is
`JsonArray{T} where T` produces no instance at all and the verifier reports
only the caller. The routing seal file already carries three seals of exactly
that shape.

---

## Stage A — mint a generic for structural equality

**The hypothesis, which must be checked before any code is written.** The
problem is not that the value is `Any`. It is that `==` at `Any` matches 225
methods, nearly all of them Base's. A generic function the kernel owns would
match only its own.

### Check this first

1. Count the methods that match `==(Any, Any)` today.
2. Count the `Base.==` overloads on document, reference and step types. The
   survey found about eleven, in `ReferencePath.jl`, `ReferenceStep.jl`,
   `ReferenceRules.jl` and `ProjectionReferenceStep.jl`.
3. Confirm that a total fallback which does not dispatch further —
   `document_equal(@nospecialize(a), @nospecialize(b)) = a === b` — is
   compilable at `(Any, Any)`, where `==` is not.

**If (3) is false the stage does not work**, and the fallback to the accessor
assertion described in `omnet-julia`'s `plan/pending/seals-into-source.md`
takes its place.

### The change

Mint a name rather than overload a universal one. `document_equal` is the
working name; the rule is that a colliding keyword gets fresh vocabulary, and
`==` is the most universal keyword there is.

**Keep `Base.==` for people.** It stays defined and delegates:

```julia
Base.:(==)(a::Document, b::Document) = document_equal(a, b)
```

**Call `document_equal` inside the kernel.** Every internal structural
comparison — the reference path, the steps, the projection step — calls the
minted generic, so the inner call site's method table is the kernel's own and
not all of Base's.

### The files, and the seals

| file | seal | holds |
| --- | --- | --- |
| [reference/ReferencePath.jl](../../source/kernel/reference/ReferencePath.jl) | 🔒 **sealed** | four `==` overloads |
| [reference/ReferenceStep.jl](../../source/kernel/reference/ReferenceStep.jl) | ⬜ | five |
| [reference/ReferenceRules.jl](../../source/kernel/reference/ReferenceRules.jl) | ⬜ | two |
| [projection/ProjectionReferenceStep.jl](../../source/kernel/projection/ProjectionReferenceStep.jl) | ⬜ | one |

**The user allowed unsealing for this work (2026-09-04.)** Follow the
convention: flip `🔒` to `⬜` in [SEALING.md](../../SEALING.md) in the same
commit that edits the file, say in the entry why it was unsealed and on whose
direction, and re-audit against
[architecture-invariants.md](../../documentation/rule/architecture-invariants.md)
before offering to seal it again. Do not remove or reorder entries.

### Gate

- `test_kernel()` passes, and the count of `Broken` does not change.
- A comparison of two documents of different domains still answers correctly.
- Re-measure `routing.seal.jl`: the `==` block — four `seal_argument` and
  three `seal_compile` — deletes and the build error count does not rise.

---

## Stage B — say `Document` where a field composes domains

**The hypothesis.** Most `::Any` in a document schema is a composition point,
and its honest type is `Union{Document, <the leaves it holds>}`.

### Check this first

`source/` holds about 690 `::Any` declarations. They are not one population.
Sort them before changing any:

1. **composition points** — the field holds a child document. These become
   `Document`.
2. **leaves** — the field holds a string, a number, a boolean. These are
   already honest and want a concrete type or a small union, not `Document`.
3. **fields that hold a function.** A function in a cell field becomes a
   thunk, and `ImmutableCell{Any}` is the documented way to stop that. **Leave
   these alone.**

A field's real population is a question about running documents, not about the
source. Use the walkers — `walk_printer_output`, `explore_position_selections`
— over the examples to record what each field actually holds, rather than
reading the declarations and guessing.

### The change

One field at a time:

```julia
children::Union{Document, String, Real, Bool, Nothing}
```

A small closed union beside one enumerable abstract type. Every call that
reads the field narrows at once, with no change to the cell and no change to
how domains compose.

### Order

Start with the fields the routing seal file names, because those have a
measurement attached and the effect is visible immediately. Widen from there
only while each step pays.

### Gate

Per field: `test_kernel()`, then the domain suite of whatever domain owns the
schema. A field whose union turns out to be wrong throws where it used to
accept, so a failure names itself.

---

## What it is worth

Stage A removes seven seals from the routing build and fixes a latent defect —
a promise about `Base.==` reaches every `==` in the image. It is worth doing
for the defect alone.

Stage B has no fixed size. Each field converted narrows the calls that read it,
and the campaign can stop at any point without leaving the tree inconsistent.

Neither stage changes how a domain composes with another. Putting an XML
element into a JSON array works the same way after both.

## Status

Not started. Every claim above is reasoning over the seal file, the document
macro and the reference sources. **Nothing has been compiled, and Stage A's
hypothesis is a hypothesis.** Do the three checks first and record their
answers here before writing code.
