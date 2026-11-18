# Architecture rules — how the code is divided and where things belong

> **Kind:** rule · **For:** developer · **Status:** current · **Stands on:** [division-terminology.md](division-terminology.md), [architecture-invariants.md](architecture-invariants.md)

The decision rules behind the package/layer/slice/module structure. The terms
are defined precisely in [division-terminology.md](division-terminology.md). They apply
to the codebase as it exists today, including the opt-in packages. The design
rationale is in
[plan/done/kernel-layered-architecture.md](../../plan/done/kernel-layered-architecture.md),
[plan/done/domain-layered-architecture.md](../../plan/done/domain-layered-architecture.md),
[plan/done/test-package-split.md](../../plan/done/test-package-split.md) and
[plan/done/example-package-split.md](../../plan/done/example-package-split.md).
When a "where does this go?" question comes up, answer it from these rules; if
the rules don't answer it, extend the rules, do not improvise.

These are the *placement* rules (where code lives). For the *invariants and
conventions* every change must respect — reactivity, the projection contract,
references/selection, operations, testing — see
[architecture-invariants.md](architecture-invariants.md) (the `PAR-…`
development requirements).

## The four levels of division

Each level answers to a different criterion. "Should X be a package?" is really four
questions, one per level ([division-terminology.md](division-terminology.md) defines the terms):

| Level | Is a boundary of | Create one when | Cost |
| --- | --- | --- | --- |
| **Package** | dependencies and consumers | a new **external dependency**, or a **distinct consumer set** needs the code *without* the rest | Project.toml, resolver slot, alias plumbing in every dependent — strict criterion, not aesthetic |
| **Layer** | direction of dependency | code sits at a distinct height: layer N imports only layers ≤ N | a folder + a guard entry — cheap |
| **Slice** | feature membership within one layer | the instances of a layer are features that grow in number; slice→slice edges must stay acyclic | a folder + a guard entry — cheap |
| **Module** | namespace / import surface | it is a seam others import or implement against **by name** (module names are de-facto public API via the umbrella re-export) | every import header that names it; merge modules only ever imported together |

(A **file** is below all four levels — a readability boundary only: *fragments*
share their aggregator's namespace at zero API cost, and file layout must never
imply an API boundary the module doesn't enforce.)

A **slice** is a *vertical* split of a single layer: where layers stack code by
dependency height, slices split one layer side by side by feature (a document with
its parser, projections, tests). Slice when the instances are the features
and grow in number (the domains); keep by-concept layers where the kind is itself
the feature (the kernel). General form: **organize by the axis along which the code
grows and changes; keep the other axis as a naming convention** (`*Parser.jl`,
`*ToSyntax.jl` make "all parsers" a glob, not a folder).

A layer holds **exactly one module**, and the package top file includes one
module file per layer, in layer order — so the top file reads as the layer
diagram, and each module file reads as its layer's table of contents through
its fragment include list (the kernel does this: `ProjecturedKernel.jl` is
twenty-three module includes). Two sibling modules in one folder mean either
one concept split in two — merge them — or two layers sharing a folder —
give each its own.

## The package chain and what belongs to each

```
kernel  →  platform  →  domain  →  (ProjecturedAll)     umbrella: kernel + platform     opt-in: sdl web odbc video tulip anthropic ollama mcp
```

- **kernel** — machinery and interfaces only: cells, the document/reference/operation
  contracts, devices/gestures, the backend seam, the projection interface + the
  document-free structural combinators, agent seams, the editor loop. **Zero concrete
  documents.** Membership tests: "does the editor loop itself need it?"; a projection
  is kernel-side iff it imports no concrete document.
- **platform** — one package, `ProjecturedPlatform`, that holds every slice
  between the kernel and the domains, one concept each, in an acyclic graph;
  [package-rules.md](package-rules.md) has their table. The lower slices hold
  the domain-independent vocabulary and frameworks: the engine's documents
  (`collection`, `primitive`, the insertion document of `domain`), the
  document-shaped generic projections (`projection`), and the persistence
  frameworks (`serialization`, `fileformat`). Membership test: **frameworks
  sink to the lowest slice where their types make sense; only per-domain
  methods stay above** (the seam pattern below).
  The upper slices hold everything about how documents become visible: the
  style atoms (`style`), the screen/window model (`screen`), the render-target
  documents with their projections (`graphics`, `layout`, `text`, `widget`,
  `syntax`), and the dependency-free backends (`ProjecturedConsole`,
  `ProjecturedPDF`, packages of their own, not slices of the platform).
  Membership test: "is this about presenting/arranging/drawing?" Anything
  screen-, window-, or graphics-related lives there — with one deliberate exception:
  the Display *device* and display-size seam stay in the kernel, because they are the
  interface the editor writes to, not the graphics themselves.
- **domain** — pure feature slices (json, sql, graph, …: each a document + parser +
  projections + tests). No shared layers between domains: anything two of
  them need is a framework and belongs in the platform. The application
  slices (assistant, conversation, shell, help, log, statistics, undo) are
  slices of the platform too, because the platform may depend on no domain.
- **opt-in packages** — exactly one per external dependency or transport (sdl=SDL2,
  web=HTTP, odbc=ODBC, tulip=linear-programming solver, anthropic/ollama=HTTP clients
  of a model provider, mcp=the MCP server). They implement
  seams owned below (the render/image/record backend generics, database adapters)
  and bind to the narrowest slice that has what they render (sdl/web → the
  platform's style, graphics and screen slices; odbc → the sql,
  database and dbcatalog domains).

## The triad — every main package has its code, its tests, and its examples

A main package is one of three: the code, its tests and its examples. The three
are sibling packages of equal standing, each with its own `Project.toml`, uuid
and module, and `package/` is flat: one directory per package, named for the
package. So `ProjecturedKernel`, `ProjecturedKernelTest` and
`ProjecturedKernelExample` are three directories, and the umbrella's three are
`Projectured`, `ProjecturedTest` and `ProjecturedExample`.

The code of a package is not in its directory. `package/ProjecturedJSON/` holds
a name and an include list; the code it includes is `source/domain/json/`, its suite is
`test/domain/json/` and its documents are `example/domain/json/`. An opt-in package grows a
test or an example package the same way when it earns one.

The three kinds form **parallel DAGs with identical shape** (the module names keep
the `-Test` / `-Example` suffixes even though the directories share one folder):

```
main:      kernel ← the platform ← the 18 domains ← ProjecturedAll
tests:     kernel/test ← platform/test ← <domain>/test ← projectured/test
examples:  kernel/example ← platform/example ← <domain>/example ← projectured/example ← {odbc/example, adaptagrams/example, tulip/example}
```

The platform shares **one** example package and **one** test package
(`package/platform/{example, test}`) rather than one per slice: the files of
both were written against the flat namespace, so a static scan cannot say which
of the thirty-nine slices owns which file.

The example DAG's leaves are the **opt-in example packages** — one per engine,
each under its opt-in package's folder: `package/odbc/example`
(`ProjecturedODBCExample`, the live-DB catalog/SQL examples),
`package/adaptagrams/example` (`ProjecturedAdaptagramsExample`, the native
graph-layout examples), `package/tulip/example` (`ProjecturedTulipExample`, the
LP-solved constraint layout). One example, `dvdrental_relationship`, needs two
engines (its document is DB-derived, its layout native), so
`adaptagrams/example` depends on `odbc/example` for that document. This is the
lowest-home rule applied to a genuinely cross-engine example, keeping each
projection source file whole.

- A **test package** depends on the main package it tests, plus the test packages
  below it (for the shared drivers and enumerators). It must never depend on a
  main package *above* its own position in the chain.
- An **example package** depends on the main package whose vocabulary its
  examples use, plus the example packages below it (for the `Example` harness).
- **Test packages may depend on example packages** at or below their own
  position in the chain
  (fixtures); never the other way around — examples are main-package artifacts, tests
  observe them.
- The **umbrellas** (`ProjecturedTest`, `ProjecturedExample`) keep only what is
  genuinely cross-cutting (the all-examples registry and sweeps, cross-domain
  discovery) or coupled to an opt-in package (SDL rendering, live DB, LLM, video).
  Everything else sinks.

This is what keeps every package runnable in a minimal environment: `test_kernel()`
through `test_domain()` (and the per-package example factories) work in an env with
none of the opt-in native/network dependencies installed.

**The lowest-home rule.** Any piece of code — source, test, example, or harness —
lives in the **lowest package of its DAG whose API it hard-references**. Two
clarifications that decide most disputes:

- **Seam calls don't count as references.** Recording via the `record_video`
  seam, or picking a backend via `default_backend` (which resolves a loaded
  `Backend` subtype by type-name reflection), creates no dependency — the opt-in
  package registers/provides the method when loaded. Only a `using` / `import` of
  a package, or naming its types/functions directly, anchors code to a package.
  This is why the example gallery can live in `ProjecturedExample` while rendering
  through SDL at runtime — it never names `SdlBackend`, it calls `default_backend`.
- **The fixture decides, not the machinery.** A test (or example) that exercises
  a lower package's machinery *through* a higher package's fixture belongs to the
  fixture's package: a Pdf-backend test driven by a JSON pipeline is a domain test,
  even though the Pdf backend is a package of its own, below the domains. Classification tables in plans are
  guesses; the
  vocabulary check at move time is the authority.

The generic drivers follow the same rule from the other side: a driver written
against only kernel API (`test_printer(label, document, projection)`,
`walk_repl_loop`) sits at the bottom and is reused by every package above; overloads
typed on a higher package's types (`test_printer(::Example)`) sit wherever their
argument type lives.
Open generics declared low and extended high (`_text_leaf_length`) bridge the
packages without inverting the DAG. Where a driver needs package-specific behavior
wholesale — the navigation gesture sets and their ground-truth enumerators — it
takes them as arguments instead: the generic `explore_selections` /
`test_navigation` driver sits in the kernel test package, and its presets
(`test_position_navigation`, `test_tree_navigation`) and the enumerators
(`collect_position_selections`, `collect_tree_selections`) sit in the platform
test package, whose readers own those gesture vocabularies and whose document walk
can express them.

## Placement rules for individual pieces

- **Projection placement invariant** (machine-checked by the guards):
  `home(projection) ≥ max(package(input), package(output), package(every other import))`.
  Canonical home = the more-specific side: `JsonToSyntax` → json slice,
  `SyntaxToText` → the syntax slice, `ObjectToSyntax` → the syntax slice
  (generic input, syntax output).
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
  container, the focus walk's `is_focusable_document`.
- **Shared helpers are exported API; internals never cross a module boundary.** No
  module may `import` a name another module does not export — not across layers, and
  not between sibling modules in the same layer. If code outside a module needs a
  symbol, export it. To share a helper without exporting it, the sharers must be
  fragments of one module (the `@gesture_case` / `@gestures` parser, in-namespace by
  construction); otherwise sink the machinery to a module at or below both users and
  export it (the transparent-Cell struct codegen: `@cell_struct` + builders in the
  struct layer, built on by `@document`, `@iomap`, and `@projection`).
- **Lower layers may *mention* higher concepts only as opaque payloads** — an untyped
  field the lower layer never interprets (`ProjectionReferenceStep.projection::Any`,
  `Intent`). If the lower layer needs to *call* it, that's a seam, not a payload.
- **Interfaces live with their concept, not in an api/ layer.** Each layer's interface
  is its first file(s); implementations depend downward onto it.
- **An interface file declares; it never implements.** It holds the abstract types,
  the type aliases, and the open generics as bodiless `function f end` — and no
  method bodies at all, defaults and error fallbacks included (a default is
  behaviour; it belongs beside the concrete methods, as `get_reference_step_kind`'s default belongs
  in `ReferenceStep.jl`). No concrete structs, no state, no algorithms. Everything an
  interface file declares is exported: the export list *is* the layer's API surface.
  See architecture requirement PAR-INTERFACE-DECLARES-ONLY.
- **A projection holds its styles, and its builder fills them.** A projection
  holds one field for each style that it draws, and no theme; nothing in a
  projection scales, or asks whether a theme is scaled, or reads the appearance
  of a theme. A builder gives the styles: the factory of a domain, an outer
  keyword constructor that takes `theme`, or `make_<name>_projection(; theme)`.
  It reads them with `get_<name>_style(theme, :field)`, which `@theme` writes,
  from a theme scaled or not, or the default theme for `nothing`. Only a builder
  that holds an `Appearance` scales (`get_scaled_theme!`), so a user interface
  with no scales passes a theme as it is. A length that a projection draws is a
  field of its theme, of a kind that a scale scales, never a number that the
  projection scales itself. See
  [style.md](../package/platform/style/style.md#themes-and-the-appearance).
- **A printer never makes a copy of its projection for a value of one print.**
  A value that holds for one print, such as the line spacing or the space that a
  slot gives, comes in through the printer context. What a reader needs of that
  value goes out through the IO map. So the projection that a dispatch gives to a
  reader is the projection that the IO map holds. The projection is fixed
  configuration, and a printer builds none inside a print.
  `test_widget_printer_projection()` checks the widget slice. See
  [spacing-rules.md](spacing-rules.md#a-printer-makes-no-copy-of-itself).
- **No orphans shape the structure.** A file nothing imports gets wired or deleted
  before it gets a home.
- **No test doubles in `main`.** A fake, mock, stub, or any canned/scripted
  stand-in for a real seam is test/example scaffolding, so it lives in a `test`
  or `example` package — never in a `main` package, and never named by `main`
  code (not even as a fallback). `main` defines only the real seam the double
  implements; the double subtypes/implements that seam from its `test`/`example`
  home. This keeps a production build free of fakes: a fake may still be *defined*
  in an example package the executable bundles, but no `main` code path ever
  constructs one, so a real user can never be served a faked result. Offline
  or deterministic behaviour belongs in the example that needs it:
  pass an explicit fake `llm`; a `main` path with no real backend fails
  loudly instead. `FakeLlm` / `ScriptedLlm` live in `ProjecturedKernelExample`,
  not in kernel `main`. The one exception is the model of
  `make_workload_llm` in the platform, which only a compile workload makes. See
  architecture requirement PAR-NO-TEST-DOUBLES-IN-MAIN.

## Content documents and view documents

A document is either content or a view of content. The two kinds keep different
state, and the code keeps them apart.

- **A content document says what a thing is**, and what was read about it from
  outside, with the state of that read. An editor has one content document for each
  thing, and every view of the thing shares it. A folder (`FileSystemDirectory`)
  keeps its listing, its read state and its watch. A chart keeps its series and its
  axes.
- **A view document says how one view shows content**: the open nodes, the head of
  a lazy list, the rows in view, a filter, a sort, a fold, the current part. Each
  view has its own, and a view with places has one for each place.
  `WorkspaceExplorer` keeps the open folders, `ChartPlot` the zoom and the cursor,
  `DataFrameView` the anchor, the filter and the sort, `DocumentTree` the open and
  the shown nodes, and `Navigator` the address and the visits.
- **Two views of one thing differ.** Two charts of one series zoom apart, and two
  explorers of one folder open apart. State that every view of a thing shares is
  content.
- **A view document names the content that it shows** with `get_edited_field`, so a
  path into the content goes through the view, as it goes through a `FileView`.
- **A view document holds the content that it shows**, with `hold_documents!` in
  its `acquire_document!`, and something holds the view document only while it
  shows. So a read of outside state follows the views by the count of the holders,
  and the content reads once for all of them. An explorer owns what a person
  controls, and shares what it reads
  ([filesystem.md](../package/platform/filesystem/filesystem.md)).
- **A save of content writes no view state.** A view document can save its own
  state apart.
- **The reader of a gesture still marks a write as view state**
  ([undo.md](../package/platform/undo/undo.md)), not the type of the document: a
  view document can itself be edited as content, as a person edits the folders of a
  workspace.
- **A view document of one kind of content takes the suffix `View`**
  ([naming-rules.md](naming-rules.md)).
- **`View` is the supertype of each view.** `ContentView` is below it, for a view
  of one content. The widget, layout, graphics and pane families are below it
  too: a widget and a layout keep the state of their own showing.

### A type that has views

For a type that has views, the caret and the fold live in the view, and the
content holds neither.

- **A `ContentView` is the supertype of the views of a content.** A view keeps the
  content that it shows in the field `viewed`. Each view type has one child field
  for each list of its content, and that field holds the view of the list, such as
  `JsonArrayView.elements`. It has one child field for each field of its content
  that is declared as `Document`, and that field holds the view of the document
  that the content holds there now, such as `JsonObjectEntryView.value`. A view is
  a tree with one node for each node of its content, so a path of the content is a
  path of the view.
- **`@content_view` declares a view type.** It writes the field `viewed`, the child
  fields, the constructor and the methods of `make_content_view`. A person writes
  only the state of the view type and its key table.
- **A `CellVectorView` is the view of a list.** It is a list of the views of the
  elements of its content, so the step `[3]` names the view of element 3. It makes
  the view of an element at the first read of that element, and that view follows
  its element when the list changes.
- **A list view keeps each view that it made.** No view goes: the memory of a lazy
  structure has no general solution yet, and no printer frees memory.
- **An edit through a view writes below `viewed`.** A row of the key table of a
  view acts for the node of its view, and it answers with a path from that view,
  as a row of a content answers with a path from its document. The step of a view
  turns each write of the answer into a write below the field `viewed` of the
  deepest view above the written place (`make_content_edit`). So a row writes no
  child field of a view, and no row finds the view that holds a place by hand.
- **The state of one view is in the view.** The caret, the part under the pointer,
  the folds (`collapsed` of a `SyntaxNodeView`, of a `JsonArrayView` and of a
  `JsonObjectView`, `closed_folds` of a `TextView`) and the look of a text (`wrap`, `line_spacing`) belong to one
  view. Two views of one content keep two carets and two folds. The content is
  shared, saved and compared with no state of a view.
- **A view type has a method of `make_content_view`** for its content type. A
  content type with no such method has no view, and prints as content.
- **A view can be a link with no state.** A content that prints nothing of its
  own and that no caret stops at has a view too, when a view above it and a view
  below it need the way through it. The view of an undo buffer is such a view: it
  holds the view of the document of the buffer, it keeps the printer of the buffer
  on the path of a key, and it writes the document of the buffer.
- **A path into a part that has no view has the step `viewed`.** A document whose
  type has no view type keeps its caret as a content does. The step `viewed`
  comes before the step that reaches no view, such as
  `.elements.viewed[2].value{3}`, in a caret and in each operation with a path.
  The path of a caret in a view, and in a field of the content of a view, has no
  such step.
- **The printer that holds the place of a view writes the node of that view.** A
  view does not replace its own content. The step of a view passes a write of its
  own node up only when the printer above says that it holds the place
  (`with_view_place_holder`), and that printer writes below `viewed` of its own
  view. A view that no view holds gives no operation for such a write.
- **A content type says which of its fields no view shows.**
  `is_child_view_field(content, field)` answers `false` for such a field, and
  `@content_view` writes no child field for it.
- **A content type that has a view has no field `viewed`.** A view type names the
  content in `viewed`, so a path that names a field of the content must not meet a
  field of that name. A viewing step throws an error for a view whose content has such a field.
- **A field of a view hides the field of its content with the same name.** A view
  type chooses the names of its state, such as `collapsed`, so that its content
  does not use them.
- **A view owns no place that takes a pasted value.** A paste and a cut do not
  write into a view. The container that holds a view owns its place, and a paste
  replaces the whole view there.

These types have views: `TextBlock` (`TextView`); `SyntaxLeaf`, `SyntaxNode` and
`SyntaxDelimitation` (`SyntaxLeafView`, `SyntaxNodeView`,
`SyntaxDelimitationView`); `DocumentInsertion` and `DocumentNothing`
(`DocumentInsertionView`, `DocumentNothingView`); `UndoBuffer` (`UndoBufferView`);
each type of the JSON domain, with the views that
`JsonView.jl` defines; and the four Markdown types that `MarkdownView.jl`
defines: `MarkdownText`, `MarkdownParagraph`, `MarkdownHeading` and
`MarkdownRoot`. A `FileView` can hold the view of what its file holds, in its
field `content` (`make_file_view(file; views = true)`). No tab of the editor makes
such a file view yet. Every other Markdown type prints as content inside a view and
takes no caret in its text there. A document inside a view of the general
renderer whose type has no view prints as content and keeps its caret, below the
step `viewed`.

Every other type and every other chain has no view: the type keeps its caret in
its own selection field. The widgets have no views. A
text of a widget keeps its caret in a `TextView`, and the widget itself keeps its
own caret. The view of a list makes a view only for an element that something
reads.

Only the folds of the syntax, JSON and text views are state of a view. The YAML,
XML, reStructuredText and Markdown types declare a `collapsed` field that no
projection reads: the fold that a person makes is a cell of the syntax node that
each print makes, so two views fold apart, and a new print of a part loses its
fold. The workflow and conversation types keep their fold in the content, which
every view shares and a save writes.

## Enforcement

Every main package has a static guard that parses the real `import ..Module`
headers and asserts: the include list is a valid topological order, every file
belongs to a declared layer/slice, every edge points to the same or a lower layer,
and slice→slice edges are acyclic. Where enabled (the kernel today; the
platform and the domains as they come clean), it also asserts that **imports name only
exported symbols** — a non-exported name is a module-internal detail, so share a
private helper via same-module fragments (the `@gesture_case` / `@gestures` parser
precedent) or sink the seam below both users as exported API (the `@cell_struct`
precedent), never lend it across a module boundary. The guard enforces the
cross-*layer* case today; the same-layer case (a sibling module reaching into a
neighbour's internals) is the next enforcement phase, turned on per package once
its same-layer internal imports are cleaned up. It also parses each file a package
names as an **interface file** and asserts it declares without implementing, and
exports every name it declares (requirement PAR-INTERFACE-DECLARES-ONLY) — the kernel's nine contract files
today. The guard is implemented **once** — the shared
`check_layering` in
[package/kernel/test/layering/CheckLayering.jl](../../test/kernel/layering/CheckLayering.jl)
— and each test package applies it to its main package
(`test_kernel_layering()`, `test_platform_layering()`, and one for each domain
such as `test_json_layering()`), running inside `test_<package>()`. It runs without loading
the package (~1s) and is the reason the rules stay true after the refactors that
established them.
