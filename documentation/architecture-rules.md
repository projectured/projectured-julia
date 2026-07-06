# Architecture rules — how the code is divided and where things belong

The decision rules behind the package/layer/module/file structure. They apply to the
codebase as it exists today (the opt-in packages already obey them) and govern the
target structure being implemented by
[plan/pending/kernel-layered-architecture.md](../plan/pending/kernel-layered-architecture.md)
and
[plan/pending/domain-layered-architecture.md](../plan/pending/domain-layered-architecture.md).
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

Every package carries a static guard (`test/runtests.jl`) that parses the real
`import ..Module` headers and asserts: the include list is a valid topological order,
every file belongs to a declared layer/slice, every edge points to the same or a
lower layer, slice→slice edges are acyclic, and per-layer tests reference only their
layer and below. The guards run without loading the package (~1s) and are the reason
the rules stay true after the refactor that established them.
