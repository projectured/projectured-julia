# Precompile workloads: compile every (printer, node type) pair at build time

> **Status (2026-08-12): DONE, and extended by a follow-on plan.** The whole
> scope below — the exhaustiveness check, the Julia atom gap, the remaining atom
> gap, the atom-driven `@compile_workload`, and the parser precompile — landed on
> `main` (`package/projectured/example/Precompile.jl`,
> `package/projectured/test/projection/CatalogCoverageTest.jl`). The two items
> this plan left open (the file round-trip workload, `OmnetppPresentationExample`'s
> 13 pairs) are also done:
> `omnetpp-julia`'s `package/presentation/example/src/Precompile.jl` exists and
> compiles that package's own atoms. Further work — recording real editor
> sessions instead of only walking atoms, because a workload that only prints
> never compiles the read path — is its own plan, now also done:
> [plan/done/recorded-precompile-workload.md](../done/recorded-precompile-workload.md).
> The measurement table below (package names `ProjecturedDomain`/`ProjecturedVisual`/
> `ProjecturedBase`) predates the twenty-domain-package split and is kept as the
> historical snapshot it was measured against, not a current path.

## The problem, measured

Opening a page of the omnetpp-julia demo catalog takes ~13 s the first time, and
essentially none of it is work. `@timed` reports 99–100 % compile time on every
step, and a *second, fresh* document in the same warm process does the same
thing in 0.06 s. Bringing the window up costs another 5.4 s for the same reason.

**There is no cross-session cache for this.** Julia caches only what is compiled
during *package precompilation*, into the package image
(`~/.julia/compiled/v1.12/…/*.so`). Code compiled by the JIT while a program
runs lives in that process and dies with it. Every fresh process in these
measurements paid the same ~13 s; with a workload compiled into the package
image, a fresh process paid 0.04 s. This is why a warm-up performed at startup —
before bringing the window up — cannot help: it moves the stall from the click
to the splash screen and pays it again every session.

## The coverage unit is (printer, document node type)

Rendering a page with a Julia fragment compiles 18 separate `Julia*ToSyntax*`
printers at a mean of **201 ms each**, and that figure is flat regardless of the
printer: a one-line `JuliaFloatToSyntaxLeaf` costs 210 ms, a large
`JuliaFunctionToSyntaxNode` 250 ms. What is inferred is the projection-template
machinery instantiated for that node type, not the printer body.

That set is not a matter of taste — it is enumerable exactly, from the method
table:

| package | (printer, node type) pairs |
|---|---|
| `ProjecturedDomain` | 192 |
| `ProjecturedVisual` | 94 |
| `OmnetppPresentation` | 13 |
| `ProjecturedBase` | 9 |
| `ProjecturedSdl` | 1 |
| **total** | **309**, over 254 distinct document types |

## Two things that do not work, and why

**Precompiling by signature.** Walk `methods(print_document)`, instantiate each
document type reactively (the runtime type is always the all-`ReactiveCell{Any}`
one, so it follows from the `UnionAll`'s arity — no naming convention needed),
and emit `precompile` for the signature. Measured: 290 signatures, all accepted,
**29.8 s — and the click only improved 12.9 s → 9.5 s**, with `open_page!`
unmoved.

The reason is laziness. Printing builds thunks; the printers run when the cells
are forced, and much of the cost is in the anonymous closures they create,
called dynamically through the cell machinery. A `precompile` call cannot name
those, and inferring the entry point does not compile them. **A workload has to
run the pipeline and force the output.**

**Sampling a document.** Rendering one representative Julia source file plus a
markdown page plus one simulation card costs 20 s and gets the click to 3.8 s —
better, but the sample is arbitrary and its coverage is whatever happens to be
in it. Rejected as inaccurate.

## What the registry is for, and where it stands

`ProjecturedExample.atomic_documents()` is exactly the missing ingredient: one
minimal hand-authored document per node type, per domain, under the directive in
[`catalog-all-documents.md`](catalog-all-documents.md) that *all documents must
be in the catalog — don't skip any*.

Measured against the method table, it is **110 atoms covering 104 of the 254
document types that have a printer — 150 missing.** The gap is why a
catalog-driven warm-up underperformed a hand-picked source file in testing: with
the whole catalog printed and forced (325 entries, 9.8 s), the demo's render
still cost 4.0 s, and the trace named what was left — `JuliaStructToSyntaxNode`,
`JuliaMacroCallToSyntaxNode`, `JuliaCurlyToSyntaxNode`,
`JuliaSubtypeToSyntaxNode`, `JuliaAnonymousTypeAnnotationToSyntaxNode`. All five
have printers. None has an atom. The Julia domain has 33 atoms against 54
printers.

The directive exists; nothing checks it against the method table.

## The plan

- [x] **Make exhaustiveness an assertion, not a directive.**
      `test_catalog_coverage` in
      `package/projectured/test/projection/CatalogCoverageTest.jl`. A printer
      added later whose document type has no atom fails unmarked; the standing
      debt is one `@test_broken` plus the named `_NO_ATOM` list; and a name still
      listed after its atom is written is asserted stale, so the list cannot
      outlive the gap it records.

      The gap is **130, not 150**. The earlier figure counted seven Base types
      (`Array`, `Bool`, `Symbol`, …) and four abstract ones, neither of which can
      be instantiated and both of which are reached through a concrete document
      already in the set. Test-package fixtures (`ProbeDoc`, `Pair2`) are
      excluded too — real documents with real printers, but counting them would
      make the answer depend on what happens to be loaded.

- [x] **Close the Julia gap** — 22 atoms, taking that domain from 33/54 to 54/54
      and the total from 130 to 108. `julia/empty` is marked broken for position
      navigation: `JuliaEmpty` renders to nothing, so there is no caret to seed.
      Arguably correct rather than broken, and marked rather than skipped for the
      reason the catalog plan gives — the atom is still printed and read like any
      other.

- [x] **Close the remaining gap.** 105 atoms: 59 visual (the widget set, the
      layouts, the bare text spans, a syntax leaf), 40 domain (workbench,
      conversation, fsm, dbcatalog, formula, graph, chart, the sql fragments,
      workspace), 6 base collections and wrappers. `catalog_coverage_gap()`
      returns empty and `test_catalog_coverage`'s `@test_broken` is now a plain
      assertion.

      **108 became 105**: `ConcreteReference`, `EmptyReference` and `ReactiveCell`
      have printers but are not `<: Document` — a reference is an address into a
      document, a cell is where a document's field is kept, and neither is
      something an `AtomicDocument` can hold. The check now decides that by
      subtyping instead of by a list of names.

      Several atoms turned out to be written already and merely unregistered —
      five Fsm factories, dragging, versioning, the collection vector. The check
      earned its keep on that alone.

      Where an atom would take a name an existing curated example answers to, the
      factory gets an `_atom` suffix rather than overwriting it (the existing ones
      are multi-state showcases, and `ProjecturedExample` re-exports those names).
      The three bare text spans are registered `bare_*` rather than reusing
      `string`/`newline`/`line`: an atom's `domain/name` is what the catalog
      filters on and what the known-broken registries match by prefix, so two
      atoms under one name would make both ambiguous.

- [x] **One `@compile_workload`, driven by the registry** —
      `package/projectured/example/Precompile.jl`, walking every atom through
      `NaturalToGraphics` and forcing the output.

      **One workload, not one per example package.** `ProjecturedVisualExample`
      cannot name `NaturalToGraphics` (it lives in domain), and its own atoms are
      8 against 59 widget printers that have no atom at all, so a second workload
      there would buy nothing until those atoms exist. `ProjecturedDomainExample`
      depends on `ProjecturedVisualExample`, so it walks both registries.
      Revisit when the widget atoms land.

      **`NaturalToGraphics` rather than a per-domain chain**, because it is the
      one projection that dispatches on document type across every domain,
      collection, layout and widget — the renderer an editor actually puts on
      screen. A domain→chain table would have been a second registry to keep in
      step with the first.

      Forcing is not optional: printing alone builds thunks. Atoms are minimal by
      construction, so forcing an atom completely is cheap — the "walking the
      whole output is too expensive" problem belongs to real documents and does
      not arise here.

- [x] **Add the parsers, round-tripped off the same atoms.**
      `precompile_atom_parsers` in the same file.

      **No domain→parser table was needed.** The plan called for one of seven
      entries; the natural format turned out to be a registry already.
      `natural_extension(doc)` names the format, `document_to_text(doc)` renders
      it — its own documentation says the text is the editor's rendered form,
      "which the domain parser re-reads" — and `parse_natural(Val(:ext), text)`
      is what a domain registered. A domain with no natural format has no method
      and drops out. That is the registry answering rather than a list going
      stale, and it deletes the "assert every exported `*parse` is in the table"
      step along with the table.

- [x] **The file round-trip, driven by the file-type registry.** Superseded
      rather than built as separately specified: the standing gap here (a
      workload that only prints, never reads, so the read half of the first
      click stays uncompiled) is exactly what
      [plan/done/recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
      closed, by recording a real driven editor session — which exercises the
      file load/save path along with everything else — instead of adding a
      second, narrower registry-driven workload. `_FILE_DOCUMENT_TYPES` /
      `register_file_document_type!` were not found in the current tree under
      those names; do not assume they still exist verbatim if this item is
      revisited.

- [x] **`OmnetppPresentationExample`'s 13 pairs**, in omnetpp-julia. Done in the
      `omnetpp-julia` repository:
      `package/presentation/example/src/Precompile.jl` walks
      `omnetpp_atomic_documents` through the package's own renderer (the same
      `NaturalToGraphics`, with the simulation-embed entry and workbench dispatch
      spliced in).

### What the parser half is worth

Secondary, and worth saying so rather than discovering it later. Measured cold:
`juliaparse` on a twelve-line snippet costs 0.44 s, and in the demo's
`open_page!` phase `_convert_head` accounted for 218 ms across 12 instances
against 4.3 s total — the bulk of that phase is the document walk, not parsing.
Expect a few hundred milliseconds per parser.

Two things not to assume. The parser's coverage unit is **not** the document
type: `_convert_head` dispatches on the `Expr` head (`Val{:function}`,
`Val{:macrocall}`, …), so coverage follows the constructs present in the text.
And not every atom's printed text parses back — measured, 80 of the 105 eligible
atoms round-trip. A throw still compiles everything up to the throw, so a
tolerant workload is fine, but it must not become the place failures go to hide.

Which is why both workloads have a test standing behind them:
`test_natural_renders_every_atom` (132 of 132) and
`test_natural_round_trips_every_atom`, whose `_NO_ROUND_TRIP` names the 25 that
do not. Nearly all are atoms smaller than a file — a column name is not a
statement, an XML attribute is not a root element, `"key": value` is not a JSON
document — which is correct behaviour, not a defect. Two are not:
`sql/insert_statement` and `sql/update_statement` are whole statements that the
SQL parser rejects with "not a parseable statement". That is a parser gap this
check happened to find, and it is recorded here rather than fixed in passing.

### Layering: decided — the example packages, and only those

The atoms live in each domain's own `example/` package (`package/json/example/`,
`package/markdown/example/`, …, aggregated by the umbrella
`package/projectured/example/`) and stay there. The main packages cannot depend
on them, so **a consumer that loads only a domain's `main/` package gets no
benefit**; only consumers of the example packages do. That is accepted rather
than worked around: moving the atoms down into the main packages would be a
larger change for a case nobody is currently in.

The reach is what matters in practice, and it is already there (in
omnetpp-julia, outside this repository): `OmnetppPresentationExample` depends on
`ProjecturedExample` directly (`package/presentation/example/Project.toml`), so
the demo — the thing that motivated this — picks up the workload without any new
dependency.

### If a runtime dry run is ever wanted anyway

For document types no build-time workload could know about, a dry run before the
window comes up is still possible, and the "the document may be huge" objection
has an answer: **prune by (printer, node type) pair.** Walk the output, and stop
descending into any subtree whose pair has already been walked. The traversal is
then bounded by the number of distinct pairs — ~309 — not by the document size.
This is worth building only if the build-time workloads leave a real gap, because
nothing it compiles survives the process.

## Constraints found while prototyping

- `__init__` does not run during precompilation. Any registration the workload
  depends on must be repeated inside `@setup_workload`.
- A workload can only open documents whose file types are registered by packages
  it depends on.
- Cost of the throwaway prototype (a demo-specific workload in
  `OmnetppPresentationExample`, kept on omnetpp-julia branch
  `omnetpp-julia-precompile`, commit 652044d): package precompile 4.2 s → 27 s,
  package image 0.8 MB → 38.9 MB, load time unchanged at 2.3 s, startup 5.4 s →
  0.2 s, first click 12.9 s → 0.04 s, `test_demo_catalog()` 172/172. It proves
  the ceiling; it is not the design, and it should be dropped once the
  registry-driven workloads land.

## What it bought, measured

In a fresh session, rendering through `NaturalToGraphics`. The baseline column is
the same worktree with the workload body removed, so nothing else differs.

| | no workload | atoms only | + Julia atoms | + parsers | all 237 atoms |
|---|---|---|---|---|---|
| render a real Julia source file | 12.57 s | 3.48 s | 0.92 s | 0.93 s | **0.84 s** |
| parse that file (`juliaparse_file`) | 0.77 s | 0.74 s | 0.74 s | 0.39 s | **0.36 s** |
| render a markdown page | 1.86 s | 0.10 s | 0.10 s | 0.10 s | **0.10 s** |
| render a json atom | 2.33 s | 0.55 s | 0.54 s | 0.55 s | **0.49 s** |

Cost, `ProjecturedDomainExample`: precompile **7.7 s → 58 s**, package image
**→ 97 MB**, `using` **0.82 s**. Paid once per source change, not per session.

The Julia-atoms column is the point of the exercise: the workload alone left a
source file at 3.48 s, because 22 of the node types in it had no atom to be
compiled from. Coverage is what makes a workload worth having, which is why the
exhaustiveness check came first.

## What the atoms found

Adding an atom for every document type made 2133 assertions fail across 17
catalog entries — every one of them a projection nothing had ever exercised
standalone, and none of them a regression:

- **layouts, the widget composite, the graph layout** — printed through their own
  single-step projection there is no `recursion`, so a child cannot be printed
  and the child's type has no `print_document` method. Nested under a parent,
  which is how they are always used, they are fine.
- **the bare text spans** — `WordWrapping` is block-level and has no method for a
  lone span, so the derived `:graphics` variant cannot be forced. The `:text`
  variant, which is what those atoms exist for, prints fine.
- **`embed/stub`** — `ReferenceStub` is a plain `mutable struct <: Document`
  rather than a `@document`, so it has no `selection` field for a reader to write.

Each is registered with its reason. That left 19 in `test_printer`, the one
tester with no broken hatch; it now takes the same message predicate
`test_reader` and `test_repl` take.

Two real bugs fixed on the way. `LayoutConstraintToGraphicsCanvas` built its
child context by splicing `ctx.reference` into an `@reference` literal, which is
under-typed whenever the root reference is — and it always is, including from a
bare `PrinterContext()`; every other layout in that file uses the
document-carrying `make_child_context`, and now so does this one. And the shared
forcing walk referred to `ProjecturedKernel.CellModule.AbstractCell` in a module
that binds `CellModule` flat and never binds `ProjecturedKernel`, so every call
threw — invisible, because both callers guard the walk with a `catch`.

### One fix attempted and backed out

The catalog derives a `:graphics` variant for the bare text spans that cannot be
forced, because `_step` accepts a bridge on the strength of its `output` alone —
and printing is lazy, so a bridge that cannot render the document at all still
returns an output and only throws when read. Forcing before accepting looked like
the general fix for that class. It is not: it collapsed the catalog from 427
entries to 81, because legitimate bridges fail that walk too. Reverted. The
laziness gap in `_step` is real and still open.

## Verification

- [x] `test_catalog_coverage` — 4 pass, nothing owed
- [x] `test_natural_renders_every_atom` — every atom but the three bare text
      spans, which are named in `_NO_NATURAL_RENDER` with the reason
- [x] `test_natural_round_trips_every_atom` — the eligible set round-trips
      except the 27 named in `_NO_ROUND_TRIP`, nearly all of them atoms smaller
      than a file
- [x] `test_catalog()` over every domain — **254267 pass, 2166 broken, 0 fail, 0
      error**, against 238841 / 33 before the atoms landed. Every one of the new
      broken entries is registered with its cause.
- [x] `test_demo_catalog()` in omnetpp-julia — landed on `main`, so
      omnetpp-julia's `[sources]` now see it.
- [x] startup and first click re-measured, superseded by the recorded-workload
      plan's own table rather than the exact 5.4 s / 12.9 s baseline figures:
      [plan/done/recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
      reports first click 4105 ms (`:none`) → 61 ms (`:recorded`) on the demo
      catalog's line-chart page.

## Status

**DONE.** The projectured-julia half landed on `main` (not left on the
`projectured-julia-precompile` branch this section used to name — that branch is
gone and the commits are on `main` under different hashes, the same pattern as
[printer-locality-session-log.md](printer-locality-session-log.md)). The
omnetpp-julia half also landed:
`package/presentation/example/src/Precompile.jl` (in the `omnetpp-julia`
repository) compiles `OmnetppPresentationExample`'s own atoms, and
[plan/done/recorded-precompile-workload.md](../done/recorded-precompile-workload.md)
went further, adding a recorded (not just atom-walked) workload across all three
repositories (`projectured-julia`, `omnetpp-julia`, `inet-julia`) — the read half
of the first click, which an atom-only workload does not reach because atoms are
printed, not read. The laziness gap in the catalog's `_step` (see "One fix
attempted and backed out" above) is still open; it was not part of either plan's
scope.
