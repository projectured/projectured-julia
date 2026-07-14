# Terminology — package, layer, slice, module

The vocabulary used to describe how the codebase is divided. Four terms, one
per kind of division. Every architecture document in this repository uses them
in exactly this sense; when writing docs, comments, or plans, use these words
and no synonyms.

## The four terms

- **Package** — a Julia package with its own `Project.toml`. The project
  consists of packages: the four main packages in the dependency chain
  `kernel ← base ← visual ← domain`, the `Projectured` umbrella, their
  sibling test/example packages, and the opt-in packages (`sdl`, `web`,
  `odbc`, `video`, `tulip`, `llm`, `mcp`, …). A package is a boundary of
  dependencies and consumers.

- **Layer** — a horizontal stratum inside a package. Layers are **ordered**:
  a layer may depend only on **lower** layers, never sideways or up. The
  kernel is fifteen layers (`cell` → `event` → `device` → `gesture` → `backend` →
  `document` → `reference` → `selection` → `operation` → `binding` → `projection` →
  `tool` → `llm` → `agent` → `editor`); base is three (`document` → `projection` → `serialization`).

- **Slice** — a **vertical** split of a single layer. Where a layer stacks
  code by dependency height, slices split one layer side by side by
  *feature*: each slice groups everything about one feature (a document with
  its parser, projections, decorators). Slices are **not ordered** — a slice
  may depend on another slice of the same layer only if the slice→slice
  edges stay **acyclic** (a DAG, not a stack). The visual package is split
  into 11 slices (style, screen, graphics, layout, text, widget, syntax,
  clipboard, tooltip, inspector, backend); the domain package into ~16
  source slices (json, xml, sql, graph, …) with the application slices
  (workbench, conversation) in the layer above them.

- **Module** — a Julia `module`, the namespace/import boundary. One layer
  (or slice) contains one or more modules; module names are de-facto public
  API because the umbrella re-exports them.

Files are below all of this: a file is a readability boundary only and is
**not** part of the terminology — fragments share their aggregator module's
namespace, and file layout never implies an API boundary the module doesn't
enforce.

## The rules in one picture

```
project
└─ packages                 kernel ← base ← visual ← domain ← umbrella  (+ opt-in)
   └─ layers                ordered: depend only on lower layers
      └─ slices             vertical splits of one layer; acyclic slice→slice DAG
         └─ modules         one or more Julia modules per layer/slice
```

Whether a layer or slice is materialised as a folder is a code-organisation
detail, not part of the definition. Today each layer and slice happens to be a
folder, and the static layering guard
([CheckLayering.jl](../package/kernel/test/layering/CheckLayering.jl)) enforces
both rules — ordered layers where a package declares them (kernel, base), and
the acyclic slice DAG elsewhere (visual, domain).

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
contains, see [architecture.md](architecture.md).
