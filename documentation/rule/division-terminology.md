# Terminology — package, layer, slice, module

> **Kind:** reference · **Status:** current · **Stands on:** nothing; it is the head of the chain

The vocabulary used to describe how the codebase is divided. Four terms, one
per kind of division. Every architecture document in this repository uses them
in exactly this sense; when writing docs, comments, or plans, use these words
and no synonyms.

## The terms

- **Package** — a Julia package with its own `Project.toml`. The project
  consists of packages: the `ProjecturedKernel` engine, `ProjecturedPlatform`,
  the eighteen domain packages, the `Projectured`
  umbrella, `AutoIntegration`, `ProjecturedIntegrations`, the `ProjecturedAll`
  flat-namespace package, their sibling test and example packages, and the
  opt-in packages
  (`sdl`, `web`, `odbc`, `video`, `tulip`, `anthropic`, `ollama`, `mcp`, …). A
  package is one concept and a boundary of dependencies and consumers. The
  packages form an acyclic graph, not a chain.

- **Layer** — a horizontal stratum inside a package, and it holds exactly one
  module. Layers are **ordered**: a layer may depend only on **lower** layers,
  never sideways or up. The kernel is the one layered package, with
  twenty-three layers (`fault` → `performance` → `cell` → `struct` → `clock` →
  `event` → `device` → `gesture` → `backend` → `document` → `reference` →
  `selection` → `operation` → `intent` → `binding` → `iomap` → `projection` →
  `tool` → `llm` → `agent` → `feed` → `editor` → `playback`). Every other
  package is one concept and declares no layer.

- **Slice** — a **vertical** split of a single layer, or of a package that
  has no layers of its own. Where a layer stacks code by dependency height, a
  slice splits it side by side by *feature*: each slice groups everything
  about one feature (a document with its parser, projections, decorators).
  Slices are **not ordered** — a slice may depend on another slice of the
  same layer or package only if the slice→slice edges stay **acyclic** (a
  DAG, not a stack). Slice is not a kernel-only notion: `ProjecturedPlatform`
  is thirty-nine slices in one package, and each source domain, each
  backend, each adapter and each tool is one slice and a package of its own.

- **Module** — a Julia `module`, the namespace/import boundary. One layer
  (or slice) contains one or more modules; module names are de-facto public
  API because `ProjecturedAll` re-exports every one of them, and `Projectured`
  re-exports the twelve names of the platform's essentials slice.

- **Leaf** — a package **nothing depends on and nothing loads after**:
  `ProjecturedREPL`, which the alias loads, and the package that a build writes
  under `build/app/<name>/`, which a binary is compiled from. The word carries a rule rather than a description. A
  package image is built with exactly its own dependencies present, so compiled
  code survives only in a leaf; everything below one has its compiled code
  invalidated as the session finishes loading. That is why a
  `@compile_workload` may appear only in a leaf, and why depending on one makes
  it stop being one. `test_package_graph()` asserts both. See
  [package-rules.md](package-rules.md).

Files are below all of this: a file is a readability boundary only and is
**not** part of the terminology — fragments share their aggregator module's
namespace, and file layout never implies an API boundary the module doesn't
enforce.

## The rules in one picture

```
project
└─ packages                 kernel ← platform ← domains ← ProjecturedAll  (+ umbrella, opt-in)
   │                        an acyclic graph; each package is one concept
   └─ layers                the kernel alone: ordered, depend only on lower layers
      └─ modules            one or more Julia modules per package or layer
```

Whether a layer is materialised as a folder is a code-organisation detail, not
part of the definition. Today each kernel layer happens to be a folder, and the
static layering guard
([CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl)) enforces
both rules: the ordered layers of the kernel, which is the one package that
declares them, and the topological include order of every other package.

## Words to avoid

| Avoid | Because | Say instead |
| --- | --- | --- |
| **tier** | has been used for both "package" and "layer" — ambiguous | **package** (for kernel/base/visual/domain positions in the chain) or **layer** (for strata inside a package) |
| **per-layer** (for `test_kernel()` … `test_domain()`) | those suites are per-*package* | **per-package** |
| **level** (architecturally) | vague; overlaps all four terms | the specific term: package / layer / slice / module |
| **vertical slice** (for MVP / end-to-end scope) | collides with the architectural **slice** | **end-to-end path** |
| **the X layer** (for a pipeline stage, e.g. "the syntax layer") | pipeline stages are domains/slices/modules, not layers | name the thing: the Syntax domain, the `syntax/` slice, the `SyntaxToText` projection |

For the decision rules — *when* to create a package, layer, slice, or module —
see [architecture-rules.md](architecture-rules.md). For what each package
contains, see [system-anatomy.md](../design/system-anatomy.md).
