# Precompile workloads: compile every (printer, node type) pair at build time

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

- [ ] **Make exhaustiveness an assertion, not a directive.** A test that every
      `print_document` method has an atom for its document type, failing with the
      list of gaps. This is the piece that makes everything below stay true.
      Existing known gaps go in the `@catalog-broken` registry that
      `CatalogTest.jl` already has, so the suite stays green while the list stays
      visible.

- [ ] **Close the 150 gaps.** Mechanical, and each one is independently
      valuable — a bare atom exercises paths the curated examples do not, which
      is the argument the catalog plan already makes. Start with the domains that
      have printers but few atoms (Julia 33/54 is the worst offender and the one
      the demo hits).

- [ ] **One `@compile_workload` per example package, driven by the registry.**
      Each workload prints the atoms *its own package registers*, through the
      printers those documents dispatch to, and forces the output. No sample, no
      demo, no catalog of pages — the workload is the method table, and the atoms
      are what make it runnable.

      | workload lives in | atoms it walks | pairs it compiles |
      |---|---|---|
      | `ProjecturedDomainExample` | `domain_atomic_documents` | `ProjecturedDomain`'s 192 |
      | `ProjecturedVisualExample` | `visual_atomic_documents` | `ProjecturedVisual`'s 94 |
      | `OmnetppPresentationExample` | its own (to be written) | `OmnetppPresentation`'s 13 |

      `ProjecturedBase`'s 9 pairs have no example package of their own — there is
      no `package/base/example` — so they ride along in
      `ProjecturedDomainExample`, which already depends on base. `ProjecturedSdl`
      has a single pair and can wait.

      Forcing is not optional: printing alone builds thunks. Atoms are minimal by
      construction, so forcing an atom completely is cheap — the "walking the
      whole output is too expensive" problem belongs to real documents and does
      not arise here.

- [ ] **Add the parsers, round-tripped off the same atoms.** Printing an atom
      already produces its text; feeding that text back through the domain's
      parser costs one more line and compiles the reading half of the stack,
      which is otherwise JIT'd the first time anyone opens a file.

      `document_to_text(doc)` (`visual/main/fileformat/NaturalFormat.jl`) is the
      generic document→String side. The reading side is one function per domain —
      `juliaparse`, `jsonparse`, `xmlparse`, `yamlparse`, `markdownparse`,
      `sqlparse`, plus `parse_natural` in the visual layer — so the workload
      needs a domain→parser table of seven entries. That table is small enough to
      be honest, and the same exhaustiveness test should assert every exported
      `*parse` appears in it, so a new domain's parser cannot be quietly left
      out.

      The text is derived from the atoms rather than written by hand, which is
      what keeps this as non-arbitrary as the printer half: the parser sees
      exactly the constructs the registry holds.

- [ ] **And the file round-trip, driven by the file-type registry.**
      `_FILE_DOCUMENT_TYPES` (extension → concrete type, populated by
      `register_file_document_type!`) is a second registry that makes a second
      workload non-accidental: for each registered extension, run `emit_text` and
      `populate_file!`. That pair *is* the editor's save/load path and is what
      the demo's `definition(file(…))` marker runs on every page.

      Note the ordering trap already recorded below: these types register
      themselves in their package's `__init__`, which does not run during
      precompilation, so the workload's `@setup_workload` has to do the
      registrations itself.

### What the parser half is worth

Secondary, and worth saying so rather than discovering it later. Measured cold:
`juliaparse` on a twelve-line snippet costs 0.44 s, and in the demo's
`open_page!` phase `_convert_head` accounted for 218 ms across 12 instances
against 4.3 s total — the bulk of that phase is the document walk, not parsing.
Expect a few hundred milliseconds per parser.

Two things not to assume. The parser's coverage unit is **not** the document
type: `_convert_head` dispatches on the `Expr` head (`Val{:function}`,
`Val{:macrocall}`, …), so coverage follows the constructs present in the text.
And not every atom's printed text will parse back — a bare leaf need not be
standalone-parseable. A throw still compiles everything up to the throw, so a
tolerant workload is fine, but it must not become the place round-trip failures
go to hide: that is what `JuliaParserTest.jl` and `SqlParserTest.jl` are for, and
a `try` in the workload should not be read as the round trip being tested.

### Layering: decided — the example packages, and only those

The atoms live in the example packages and stay there. The main packages cannot
depend on them, so **a consumer that loads only `ProjecturedDomain` gets no
benefit**; only consumers of the example packages do. That is accepted rather
than worked around: moving the atoms down into the main packages would be a
larger change for a case nobody is currently in.

The reach is what matters in practice, and it is already there:
`OmnetppPresentationExample` depends on `ProjecturedDomainExample` and
`ProjecturedVisualExample` directly (`package/presentation/example/Project.toml`),
so the demo — the thing that motivated this — picks both workloads up without
any new dependency.

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

## Verification

- [ ] the exhaustiveness test lists zero unexplained gaps, for the printer table
      and for the domain→parser table
- [ ] `test_demo_catalog()` and the per-package suites stay green
- [ ] startup and first click re-measured against the 5.4 s / 12.9 s baseline
- [ ] the cost side re-measured too: precompile time and package image size per
      example package, and `using` time, which the prototype left unchanged

## Status

Not started. Measurements and design from the investigation on 2026-08-04.
