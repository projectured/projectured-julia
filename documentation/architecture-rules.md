# Architecture rules — how the code is divided and where things belong

The decision rules behind the package/layer/module/file structure. They apply to the
codebase as it exists today (the opt-in packages already obey them); the structure
was established by
[plan/done/kernel-layered-architecture.md](../plan/done/kernel-layered-architecture.md)
and
[plan/done/domain-layered-architecture.md](../plan/done/domain-layered-architecture.md),
and extended to the sibling test/example DAGs by
[plan/done/test-package-split.md](../plan/done/test-package-split.md) and
plan/pending/example-package-split.md.
When a "where does this go?" question comes up, answer it from these rules — and if
the rules don't answer it, extend the rules, don't improvise.

## The four levels of division

Each level answers to a different criterion. "Should X be a package?" is really four
questions, one per level:

| Level | Is a boundary of | Create one when | Cost |
| --- | --- | --- | --- |
| **Package** | dependencies and consumers | a new **external dependency**, or a **distinct consumer set** wants the code *without* the rest | Project.toml, resolver slot, alias plumbing in every dependent — strict criterion, not aesthetic |
| **Layer** (folder in a package) | direction of dependency | code sits at a distinct height: layer N imports only layers ≤ N | a folder + a guard entry — cheap |
| **Module** | namespace / import surface | it is a seam others import or implement against **by name** (module names are de-facto public API via the umbrella re-export) | every import header that names it; merge modules only ever imported together |
| **File** | readability only | a module grows; *fragments* share their aggregator's namespace at zero API cost | none — never let file layout imply an API boundary the module doesn't enforce |

A **feature slice** is a layer that groups by *feature* (a document with its parser,
projections, tests) instead of by *kind*. Slice when the instances are the features
and grow in number (domain, visual); keep by-concept layers where the kind is itself
the feature (the kernel). General form: **organize by the axis along which the code
grows and changes; keep the other axis as a naming convention** (`*Parser.jl`,
`*ToSyntax.jl` make "all parsers" a glob, not a folder).

## The package chain and what belongs to each

```
kernel  →  base  →  visual  →  domain  →  (umbrella)     opt-in: sdl web odbc video tulip llm mcp
```

- **kernel** — machinery and interfaces only: cells, the document/reference/operation
  contracts, devices/gestures, the backend seam, the projection interface + the
  document-free structural combinators, agent seams, the editor loop. **Zero concrete
  documents.** Membership tests: "does the editor loop itself need it?"; a projection
  is kernel-side iff it imports no concrete document.
- **base** — the domain-independent vocabulary and frameworks: the engine's documents
  (Collection, Primitive, the insertion document), the document-shaped generic
  projections, and the persistence frameworks (binary/natural serialization, document
  files). Membership test: **frameworks sink to the lowest package where their types
  make sense; only per-domain methods stay above** (the seam pattern below).
- **visual** — everything about how documents become visible: style atoms, the
  screen/window model, the render-target documents (Graphics, Layout, Text, Widget,
  Syntax) with their projections, and the dependency-free backends (Console, Pdf).
  Membership test: "is this about presenting/arranging/drawing?" Anything
  screen-, window-, or graphics-related lives here — with one deliberate exception:
  the Screen *device* and display-size seam stay in the kernel, because they are the
  interface the editor writes to, not the graphics themselves.
- **domain** — pure feature slices (json, sql, graph, …: each a document + parser +
  projections + tests) plus the application slices (workbench, conversation) on top.
  No shared tiers: anything two slices need is a framework and belongs in base (or
  visual, if it renders).
- **opt-in packages** — exactly one per external dependency or transport (sdl=SDL2,
  web=HTTP, odbc=ODBC, tulip=C++ solver, llm/mcp=protocol clients). They implement
  seams owned below (make_backend, adapters) and bind to the narrowest package that
  has what they render (sdl/web → visual, odbc → domain's sql surface).

## Sibling DAGs — every runtime package has its code, its tests, and its examples

A runtime package is one third of a **triad**. For each `package/<name>` there is a
`package/<name>-test` and (per the example split) a `package/<name>-example`; the
three kinds form **parallel DAGs with identical shape**:

```
runtime:   kernel ← base ← visual ← domain ← Projectured (umbrella) ← {sdl, odbc, tulip, video, llm, mcp, web}
tests:     kernel-test ← base-test ← visual-test ← domain-test ← ProjecturedTest
examples:  kernel-example ← base-example ← visual-example ← domain-example ← ProjecturedExample ← ProjecturedExtrasExample
```

- A **test package** depends on the runtime package it tests, plus the test packages
  below it (for the shared drivers and enumerators). It must never depend on a
  runtime package *above* its own tier.
- An **example package** depends on the runtime package whose vocabulary its
  examples use, plus the example packages below it (for the `Example` harness).
- **Test packages may depend on example packages** of their own tier or below
  (fixtures); never the other way around — examples are runtime artifacts, tests
  observe them.
- The **umbrellas** (`ProjecturedTest`, `ProjecturedExample`) keep only what is
  genuinely cross-cutting (the all-examples registry and sweeps, cross-domain
  discovery) or coupled to an opt-in package (SDL rendering, live DB, LLM, video).
  Everything else sinks.

This is what keeps every tier runnable in a minimal environment: `test_kernel()`
through `test_domain()` (and the per-tier example factories) work in an env with
none of the opt-in native/network dependencies installed.

**The lowest-home rule.** Any piece of code — source, test, example, or harness —
lives in the **lowest package of its DAG whose API it hard-references**. Two
clarifications that decide most disputes:

- **Seam calls don't count as references.** Obtaining a backend via
  `make_backend(:sdl)` or recording via the `record_video` seam creates no
  dependency — the opt-in package registers the method when loaded. Only a `using`
  / `import` of a package, or naming its types/functions directly, anchors code to
  a tier. This is why the example gallery can live in the visual tier while
  rendering through SDL at runtime.
- **The fixture decides, not the machinery.** A test (or example) that exercises
  low-tier machinery *through* a higher-tier fixture belongs to the fixture's tier:
  a Pdf-backend test driven by a JSON pipeline is a domain-tier test, even though
  the Pdf backend is visual. Classification tables in plans are guesses; the
  vocabulary check at move time is the authority.

The generic drivers follow the same rule from the other side: a driver written
against only kernel API (`test_printer(label, document, projection)`,
`walk_repl_loop`) sits at the bottom and is reused by every tier above; tier-typed
overloads (`test_printer(::Example)`) sit wherever their argument type lives.
Open generics declared low and extended high (`collect_text_selections`,
`_text_leaf_length`) bridge the tiers without inverting the DAG.

## Placement rules for individual pieces

- **Projection placement invariant** (machine-checked by the guards):
  `home(projection) ≥ max(tier(input), tier(output), tier(every other import))`.
  Canonical home = the more-specific side: `JsonToSyntax` → json slice,
  `SyntaxToText` → visual, `ObjectToSyntax` → visual (generic input, visual output).
  It works because pipelines flow *specific → generic*; a reverse-direction
  projection (WorkspaceToFileSystem) still obeys it via its input side.
- **Documents own no cross-domain edges.** A document imports only its own slice and
  the packages below. All cross-domain coupling lives in projections (the edges), not
  documents (the nodes) — this is what makes slicing possible; keep it true.
- **The seam pattern** (how frameworks stay below their users): the lower layer
  declares open generics (or a small registry); higher layers add methods **in the
  files they already have** — multiple dispatch *is* the registration; a couple of
  methods never earns a new file. Precedents: operation traversal and rerooting,
  reader defaults, insertion, serialization, the projection template's children
  container, layout focus-paths.
- **Lower layers may *mention* higher concepts only as opaque payloads** — an untyped
  field the lower layer never interprets (`ProjectionReference.projection::Any`,
  `Intent`). If the lower layer needs to *call* it, that's a seam, not a payload.
- **Interfaces live with their concept, not in an api/ tier.** Each layer's interface
  is its first file(s); implementations depend downward onto it.
- **No orphans shape the structure.** A file nothing imports gets wired or deleted
  before it gets a home.

## Enforcement

Every runtime package has a static guard that parses the real `import ..Module`
headers and asserts: the include list is a valid topological order, every file
belongs to a declared layer/slice, every edge points to the same or a lower layer,
and slice→slice edges are acyclic. The guard is implemented **once** — the shared
`check_layering` in
[package/kernel-test/src/layering/CheckLayering.jl](../package/kernel-test/src/layering/CheckLayering.jl)
— and each test package applies it to its runtime package
(`test_kernel_layering()`, `test_base_layering()`, `test_visual_layering()`,
`test_domain_layering()`), running inside `test_<tier>()`. It runs without loading
the package (~1s) and is the reason the rules stay true after the refactors that
established them.
