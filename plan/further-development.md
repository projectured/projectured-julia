# Further Development Directions

> **Note:** This document was generated with AI assistance as a brainstorming
> artifact. It is a collection of raw ideas and directions, not a specification.
> Everything here needs to be critically evaluated, refined, and adapted before
> any of it gets implemented.

Development directions for predj, organized by theme in roughly the order I
intend to tackle them. Each section includes open questions I need to resolve
before committing effort.

The ordering follows a principle: **deepen the vertical slice first** (make
editing actually work), **then widen** (more domains, more layouts, more
backends), **then distribute** (network, collaboration, external data).

---

## 1. Editing Operations

The projection pipeline is bidirectional, cursor movement works across all
major domains, but there is no character editing yet. This is the most
important gap — without it the editor is a viewer.

### Steps

- **1a. `StringReplaceRangeOperation`** — character insert/delete for
  `JsonString`, `XmlText`, and any `PrimitiveString`. The `Primitive` domain
  already declares `StringReplaceRangeOperation` and
  `NumberReplaceRangeOperation` — wire them into `evaluate_operation` and make
  the reader produce them from key events (printable characters, backspace,
  delete).
- **1b. Structural insert/delete** — add/remove elements from `JsonArray`,
  entries from `JsonObject`, children from `SyntaxNode`. Needs a
  `CollectionInsertOperation` / `CollectionDeleteOperation` and reader-side
  logic to detect when the cursor is on structural whitespace and an
  insert/delete key is pressed.
- **1c. Clipboard** — cut/copy/paste. The `Clipboard` domain exists as a stub.
  Define `ClipboardCopyOperation`, `ClipboardPasteOperation`, wire them to
  Ctrl+C/V/X.

### Open questions

- **`Cell{Vector}` under insert/delete** — pushing to a `JsonArray`'s cell
  invalidates every downstream computed cell that read the vector length or
  iterated it. Need to verify `Reactive.jl` handles this correctly, or whether
  fine-grained collection diffing is needed.
- **Selection adjustment after mutation** — if the cursor is at position 5 and
  character 3 is deleted, the cursor should move to 4. Need to decide who is
  responsible: the operation itself, the projection reader, or a post-eval
  fixup. Worth checking how the original ProjecturEd handles this.
- **Reactive graph under structural changes** — if there is a design problem
  (e.g. the cell graph blows up when a vector's length changes, or
  `set_selection!` doesn't handle structural shifts), I want to surface it
  early rather than mid-implementation.

---

## 2. Mouse / Pointer Input

`MouseClick` exists in the device layer, the SDL backend forwards button-down
events, and the `dragging.md` plan adds `MouseRelease`.

### Steps

- **2a. Click-to-select** — `TextToGraphics` reader receives a `MouseClick`,
  uses `char_to_coord` to map `(x, y) → flat position`, produces
  `ReplaceSelectionOperation`. Straightforward, low-hanging fruit — should be
  done soon.
- **2b. Drag selection (text highlight)** — needs a `SelectionRange` concept
  (anchor + cursor). The current selection model is a single path. Extending
  to a range is non-trivial: every reader in the chain must map range
  endpoints, not just a point.
- **2c. Drag-and-drop** — per the existing `dragging.md` plan.
- **2d. Scroll wheel** — `GraphicsViewport` already exists; wire SDL scroll
  events to viewport offset changes.

### Open questions

- **Range selection design** — every `projection_read` currently maps a single
  `ReferencePath`. A range needs two paths, or a single path plus an extent.
  The original ProjecturEd represents selection as a *pair* of references
  (start, end). Need to decide whether to follow that design or find an
  alternative.

---

## 3. Undo/Redo and Object Versioning

Basic undo/redo is the immediate need, but the architecture can generalize to
full object versioning: multiple named timelines, branching, and the ability
to inspect or diff any previous state of a document subtree.

### Steps

- **3a. Operation log** — every `evaluate_operation` call appends the operation
  + its inverse to a bounded log on the `Editor`.
- **3b. Inverse operations** — each operation type defines its inverse.
  `ReplaceSelectionOperation` is trivially invertible (store the old path).
  `StringReplaceRangeOperation` needs the deleted text.
  `CollectionInsertOperation` inverts to delete and vice versa.
- **3c. Group boundaries** — consecutive character inserts should undo as a
  group (word-level or burst-level), not one character at a time. Need a
  grouping policy.
- **3d. Named timelines** — extend the operation log from a single linear
  stack to a tree of named branches. Each branch is a sequence of operations
  from a common ancestor. Switching branches means undoing back to the fork
  point and replaying the target branch. This gives "what-if" exploration:
  try an edit on a branch, compare with the original, keep or discard.
- **3e. Version inspection** — a projection that shows a document at a
  specific version (operation index). This is a read-only projection: the
  printer replays operations up to the requested index and produces the
  corresponding document state. Useful for diffing, reviewing history, or
  presenting a "before/after" view.
- **3f. Persistent data structures (optional)** — if version inspection or
  branching becomes expensive (replaying long operation chains), consider
  switching document collections to persistent/immutable data structures
  where snapshotting is O(1). This is a deep change — only pursue if the
  operation-replay approach proves too slow.

### Open questions

- **Operation vocabulary** — right now `ReplaceSelectionOperation` is the only
  operation. Undo depends on having the full vocabulary from section 1, so it
  makes sense to defer this until after editing operations land.
- **Reactive graph topology under undo** — undoing a structural change (e.g.
  removing an array element that was added) changes the reactive graph
  topology backwards. Need to verify that cells created during the forward
  operation are correctly GC'd / invalidated on undo.
- **Branch granularity** — is a timeline per-document, per-editor, or
  per-subtree? Per-subtree is the most powerful (version one array element
  independently) but also the most complex to manage.
- **Storage** — for long-lived versioning, the operation log needs to be
  serializable. This intersects with the external document persistence
  question (section 13).

---

## 4. Transactional Editing (Uncommitted Change Buffer)

A special projection that accumulates edits in a staging area without
modifying the underlying document, then applies them atomically. This is
analogous to transactional memory: the printer shows the document *as if* the
staged changes were applied, but the real document is untouched until commit.

### Steps

- **4a. `StagingProjection`** — a higher-order projection that wraps an inner
  projection. It maintains a `StagingBuffer`: a list of pending operations.
  The printer applies the pending operations to a *copy* of the input
  document (or overlays them via computed cells) and projects the result
  through the inner projection. The reader collects new operations into the
  buffer instead of forwarding them to the document.
- **4b. Commit / discard** — keybindings or commands that either apply all
  buffered operations to the real document (`commit!`) or clear the buffer
  (`discard!`). Commit replays the operations in order via
  `evaluate_operation`.
- **4c. Visual diff** — the printer can highlight staged changes (inserted
  text in green, deleted in red) by comparing the staged overlay with the
  original document. This is a domain-independent decoration projection that
  wraps the output of any inner projection.
- **4d. Conflict detection** — if the underlying document changes while edits
  are staged (e.g. from another user or an external source), detect conflicts
  at commit time by checking whether the operations' preconditions still hold.

### Open questions

- **Overlay vs. copy** — overlaying pending operations on the original
  document via computed cells is more incremental (only the affected subtrees
  recompute) but harder to implement correctly. A full copy is simpler but
  expensive for large documents. The right answer probably depends on document
  size.
- **Interaction with undo** — if undo is available, is staging redundant?
  Not entirely: staging lets me preview a complex multi-step refactoring
  before committing, whereas undo is post-hoc. But the two features share
  machinery (operation logs, inverse operations), so they should be designed
  together.
- **Nested staging** — can I stage edits within a staged view? This would
  allow hierarchical "drafts" but adds complexity. Probably defer.

---

## 5. Editing Through Searching

A mode where the user types a search query and the editor narrows the visible
document to matching subtrees, with the ability to edit directly within the
filtered view. This combines `FocusingProjection` (already exists) with
incremental text search and a reader that maps edits back through the filter.

### Steps

- **5a. Incremental search projection** — a projection that takes a document
  and a search query (a `Cell{String}`) and produces a filtered document
  containing only subtrees that match the query. The IO map records which
  input elements were kept, enabling the reader to map edits back.
- **5b. Search-as-you-type** — wire a keybinding (e.g. Ctrl+F) that opens a
  search input field. Characters typed into the field update the query cell,
  which invalidates the search projection, which re-filters incrementally.
  The existing `FocusingProjection` already does predicate-based filtering;
  this extends it with a text-match predicate.
- **5c. Replace** — extend the search projection with a replace buffer. When
  the user confirms a replacement, the projection produces
  `StringReplaceRangeOperation`s for each match. Batch replacement is a
  natural fit for the staging projection (section 4): stage all replacements,
  preview them highlighted, then commit.
- **5d. Structural search** — search by document structure, not just text.
  E.g. "find all `JsonObject` entries where the key matches `name`". This is
  a predicate-dispatch search where the predicate operates on the domain
  types rather than their text representation.

### Open questions

- **Reader through a filter** — if the visible document is a subset of the
  real document, the reader must translate operations on the filtered view
  back to the full document. The IO map needs to record the mapping from
  filtered indices to original indices. `FocusingProjection` already has
  some of this, but it needs to be robust enough for editing, not just
  viewing.
- **Highlight without filtering** — sometimes I want to highlight matches
  without hiding non-matches. This is a separate projection (a decorator)
  that annotates the syntax domain with highlight markers. Need to decide
  whether highlighting and filtering are the same projection with a mode
  flag, or two separate projections.

---

## 6. Domain Expansion

~15 domains are declared. Most have printers but incomplete or missing readers.

### Steps

- **6a. Julia domain** — `JuliaToSyntax` printer exists. Add the reader so I
  can navigate Julia ASTs. This is the path to self-hosting.
- **6b. Math domain** — `MathToSyntax` exists. Add the reader. Good demo:
  edit `x + y * z` and see the AST update structurally.
- **6c. XML reader** — listed as missing. Wire it up.
- **6d. Book domain** — `BookToSyntax` exists. Interesting for structured
  document editing (a lightweight alternative to LaTeX/Word).
- **6e. Table domain** — `TableToGraphics` exists. Tables with editable cells
  would be a compelling demo.
- **6f. Graph domain** — a new domain for directed/undirected graphs. Nodes
  and edges are documents; each node holds a sub-document (any domain) as its
  content, plus layout metadata (position, size). Edges reference source and
  target nodes. See section 8 for layout projections.

### Open questions

- **Target use case** — "edit JSON" doesn't justify this architecture. "Edit
  Julia source code projectionally" does. "Edit a mixed document with embedded
  code, math, and tables" does. I need to commit to a primary use case and
  let that drive priority.
- **Stub domains** — `FileSystem`, `Collection`, `Color`, `Font`, `Geometry`,
  `Image` — need to audit which of these are actually used by any projection
  pipeline end-to-end, and whether the unused ones are worth keeping or are
  just dead weight.
- **Self-hosting** — editing predj's own source code would be the strongest
  validation. If that's a goal, the Julia domain is the critical path.

---

## 7. Extended Programming Language Domain

A programming language domain where the data structure is a semantic graph —
functions reference their arguments and callees directly, not by name — and
the traditional textual AST is derived from it by a projection. Combined with
immutable code objects, this gives a programming model where published code
can never break: every edit creates a new version, and dependents keep
referencing the old version until they explicitly upgrade.

### Steps

- **7a. Semantic program graph** — a new domain where the fundamental objects
  are `FunctionDef`, `Parameter`, `CallSite`, `Binding`, `Literal`, etc.
  Unlike the existing Julia domain (which mirrors a textual AST),
  relationships are direct object references stored in cells:
  - A `CallSite` holds a `Cell` pointing to the `FunctionDef` it calls, not a
    name string that must be resolved.
  - A `Parameter` is a document node; every use site holds a `Cell` pointing
    to the same `Parameter` object.
  - A `Binding` (let/variable) holds a `Cell` to its value expression.
  This means renaming is free (the name is a display attribute, not an
  identity), and "find all references" is a cell-dependency query.
- **7b. Graph-to-AST projection** — a projection that expands the semantic
  graph into a traditional AST suitable for the existing `Syntax` domain.
  The printer linearizes the graph: it resolves direct references into
  scoped names (inventing names where needed), orders definitions
  topologically, and produces `SyntaxNode`/`SyntaxLeaf` trees. The reader
  maps AST-level edits back to graph-level operations: renaming a parameter
  in the AST updates the `Parameter` node's name cell, adding a call in
  the AST creates a new `CallSite` with a direct reference.
- **7c. Immutable code objects** — once a `FunctionDef` is *published*
  (marked immutable), it becomes frozen: its body, parameter list, and
  return type cells become read-only. Any edit to a published function
  creates a *new version* — a new `FunctionDef` whose body is initialized
  as a copy of the original. The original is untouched. Call sites that
  referenced the old version continue to work; they see the old behavior.
  Upgrading a call site to the new version is an explicit operation
  (`UpgradeReferenceOperation`) that swaps the `CallSite`'s target cell
  from the old `FunctionDef` to the new one.
- **7d. Version registry** — a mapping from `FunctionDef` identity to its
  version chain (a linked list of versions, newest first). The projection
  can render version indicators (e.g. `foo@v3`) and offer navigation
  between versions. The registry is itself a document, so it can be
  projected and inspected.
- **7e. Upgrade assistant** — a projection or tool that scans all call sites
  referencing an old version and presents them as a list. For each call
  site, it shows the diff between the old and new function signatures and
  lets the user upgrade (update the reference) or pin (keep the old
  version). Batch upgrade applies `UpgradeReferenceOperation` to all
  selected call sites.
- **7f. Compatibility checking** — when creating a new version of a function,
  compare the old and new signatures. If the new version adds a required
  parameter or changes a return type, flag the upgrade as breaking. The
  upgrade assistant can filter by compatibility level (safe / breaking) to
  help the user prioritize.
- **7g. Evaluation / execution** — the semantic graph can be interpreted
  directly (no text generation needed). An interpreter walks `CallSite` →
  `FunctionDef` → body, evaluating expressions. Since references are direct,
  there is no name resolution at runtime. This is a longer-term goal but
  validates the domain: if the graph can run, it is a real programming
  language, not just a visualization.

### Open questions

- **Granularity of immutability** — is immutability per-function, per-module,
  or per-expression? Per-function is the natural unit (it matches how
  libraries version APIs), but per-expression would allow finer-grained
  pinning (e.g. freeze one branch of an `if` while editing the other).
  Per-function is simpler and probably sufficient to start.
- **Garbage collection of old versions** — if no call site references an old
  version, can it be collected? This requires reference counting or
  reachability analysis on the version registry. Without GC, the version
  chain grows unboundedly.
- **Cyclic references** — mutual recursion means two `FunctionDef`s reference
  each other. Immutability of one forces the other to create a new version
  too (since its body references the now-frozen function). Need a policy:
  either publish mutually recursive functions as a group (atomic publish),
  or allow forward references to not-yet-published functions.
- **Integration with the existing Julia domain** — the current `Julia.jl`
  domain is a textual AST. The extended domain is a semantic graph. They
  serve different purposes: the AST domain is for editing existing Julia
  source files (text in, text out); the semantic graph is for a new
  programming model where text is a projection, not the source of truth.
  They should coexist, with a possible bridge projection
  (SemanticGraph → JuliaAST → Syntax → Text) for exporting to .jl files.
- **Name generation** — the graph-to-AST projection needs to assign textual
  names to nodes that may not have user-given names (e.g. intermediate
  bindings). Need a naming strategy: user-assigned names take priority,
  then auto-generated names based on type or role, with disambiguation
  suffixes when needed.

---

## 8. Color Coding Arbitrary Domains

A domain-independent projection that assigns colors to document elements based
on configurable rules, so that any domain gets syntax-highlighting-like
coloring without the projection needing to know the domain's semantics.

### Steps

- **8a. `ColorCodingProjection`** — a domain-preserving projection that walks
  the syntax tree (or any tree-shaped domain) and assigns `StyledString` color
  attributes based on a rule set. Rules are predicates on the document type,
  depth, field name, or content: e.g. "all `JsonString` values are green",
  "all `SyntaxNode` open delimiters are gray", "depth > 3 dims the color".
- **8b. Rule DSL** — a small declarative language for defining color rules,
  stored as a document itself (so it can be edited projectionally). Rules are
  evaluated in priority order; the first matching rule wins.
- **8c. Theme support** — a theme is a named set of color rules. Switching
  themes swaps the rule set cell, which invalidates the color projection for
  the entire document. The reactive system handles the rest.
- **8d. Semantic coloring** — for domains with richer semantics (Julia, Math),
  allow rules that depend on semantic analysis (e.g. "color bound variables
  differently from free variables"). This requires the color projection to
  receive semantic annotations, which could be another projection in the
  pipeline that annotates the document before coloring.

### Open questions

- **Where in the pipeline** — color coding operates on the syntax domain (it
  modifies `StyledString` attributes). It should sit between the domain-to-
  syntax projection and `SyntaxToText`, as a domain-preserving syntax
  transformation. But it could also be a decoration on the text domain. Need
  to decide which is cleaner.
- **Performance** — walking the full syntax tree to apply color rules on every
  frame is wasteful. The reactive system should handle this if each color
  assignment is a computed cell that depends only on the corresponding
  document node, but I need to verify this doesn't explode the cell count
  for large documents.

---

## 9. Graph Editing and Layout

A graph domain with layout projections that position nodes and route edges
automatically, plus interactive editing (add/remove nodes and edges, drag
nodes to reposition).

### Steps

- **9a. Graph domain** — `GraphNode` (holds content document + position cell),
  `GraphEdge` (references source and target nodes), `Graph` (collection of
  nodes and edges). All fields are cells. Selection on a graph means either a
  selected node, a selected edge, or a cursor within a node's content.
- **9b. Force-directed layout** — a projection that computes node positions
  using a simple force-directed algorithm (repulsion between nodes, attraction
  along edges). The layout runs incrementally: when a node is added or
  removed, only the affected neighborhood recomputes. The output is the same
  graph domain with positions filled in.
- **9c. Graph to graphics** — a projection from the positioned graph to
  `GraphicsCanvas`: each node's content is recursively projected (it can be
  any domain — JSON, text, syntax, another graph), then placed at the node's
  computed position. Edges are drawn as lines or curves between node
  rectangles.
- **9d. Interactive graph editing** — the reader maps mouse events to graph
  operations: click a node to select it, drag to reposition, click empty
  space to deselect, keybinding to add/remove nodes and edges. Edge creation
  could work by selecting a source node, pressing a key, then clicking the
  target.
- **9e. Graph serialization** — read/write graph documents to formats like
  DOT, GraphML, or JSON adjacency lists. This is an external-data projection
  (section 14) applied to the graph domain.

### Open questions

- **Layout as projection vs. layout as operation** — the force-directed
  algorithm could be a projection (the printer computes positions from the
  graph structure) or it could be an operation (the layout algorithm writes
  positions into the graph's position cells). The projection approach is more
  consistent with the architecture, but layout algorithms are iterative and
  stateful (they converge over time), which doesn't fit the pure-functional
  projection model. May need a hybrid: the projection delegates to a
  stateful layout engine that caches intermediate state in cells.
- **Nested graphs** — a graph node containing another graph. The recursive
  projection infrastructure (`RecursiveProjection`) handles this in
  principle, but the layout algorithm needs to know the inner graph's
  bounding box, which creates a dependency cycle (inner layout depends on
  outer layout depends on inner bounds). Need to break the cycle with a
  two-pass approach or fixed inner bounds.

---

## 10. Graphical Layout Projections

Beyond the existing vertical text flow and word wrapping, add layout
projections for other arrangements. These are domain-preserving projections on
the graphics domain that take a collection of graphics elements and position
them according to a layout strategy.

### Steps

- **10a. Horizontal layout** — arrange children left-to-right with configurable
  spacing and alignment (top, center, bottom, baseline). This is the dual of
  the existing vertical text layout.
- **10b. Vertical layout** — the existing `SyntaxNodeToText` already does
  vertical layout for syntax nodes, but I want a general-purpose
  `VerticalLayout` projection on the graphics domain that works for any
  collection of graphics elements, not just text.
- **10c. Grid layout** — arrange children in a 2D grid with configurable
  row/column counts, cell sizes, and alignment. Useful for the table domain
  (`TableToGraphics` already exists but uses a custom layout) and for any
  dashboard-like view.
- **10d. Constraint-based layout** — a more powerful layout engine where
  elements declare constraints (e.g. "A is left of B", "C's width equals D's
  width", "E is centered in its parent"). A constraint solver (e.g. Cassowary)
  computes positions that satisfy all constraints. This subsumes horizontal,
  vertical, and grid layouts as special cases.
- **10e. Nested layouts** — layouts compose: a horizontal layout can contain a
  vertical layout inside one of its children. The recursive projection
  infrastructure handles this, but each layout needs to report its bounding
  box as a computed cell so that parent layouts can position it correctly.

### Open questions

- **Constraint solver** — implementing Cassowary or a similar incremental
  constraint solver in Julia is a significant effort. Alternatively, I could
  use a simpler two-pass box model (like CSS flexbox) that covers 90% of use
  cases without a full solver. The question is whether the remaining 10%
  (arbitrary cross-element constraints) is worth the complexity.
- **Layout as domain-preserving projection** — layout projections transform
  `GraphicsCanvas → GraphicsCanvas` (they position children within a canvas).
  This means they live in the graphics domain's projection layer. But some
  layout decisions (like indentation, line breaks) are currently made in
  `SyntaxToText`. Need to decide whether to consolidate all layout into the
  graphics domain or keep domain-specific layout in the domain's own
  projection.

---

## 11. Editing Projections

The projection pipeline itself is data — a tree of projection structs. If that
tree is represented as a document, it can be edited projectionally: the user
sees the projection configuration and modifies it live, with the projected
output updating in real time as the projection changes.

### Steps

- **11a. Projection document domain** — represent the projection pipeline as a
  document: `ProjectionNode` wrapping each projection struct, with children
  for sub-projections (e.g. the inner projections of a
  `SequentialProjection`). Each `ProjectionNode` has a `selection::Cell` so
  it participates in the selection mechanism.
- **11b. Projection-to-syntax printer** — a projection that renders the
  pipeline as a tree: `Sequential [ JsonToSyntax, SyntaxToText,
  TextToGraphics ]`. Each node shows the projection type, its parameters, and
  its input/output domain types.
- **11c. Live editing** — when the user modifies the projection document (e.g.
  removes a projection from a sequence, swaps two projections, changes a
  parameter), the underlying projection pipeline updates, and the document
  being edited re-projects through the new pipeline. This requires the
  editor's `projection` field to be a reactive cell that reads from the
  projection document.
- **11d. Projection palette** — a UI panel listing available projections,
  filterable by input/output domain type. The user drags a projection from
  the palette into the pipeline, or selects an insertion point and picks from
  a list. Type-checking ensures only domain-compatible projections can be
  inserted.

### Open questions

- **Circularity** — editing the projection that is currently projecting the
  projection document is a bootstrapping problem. The simplest solution: the
  projection editor uses a *fixed* projection pipeline (hardcoded to
  ProjectionToSyntax → SyntaxToText → TextToGraphics) that is not itself
  editable.
- **Hot-swap safety** — changing the projection pipeline mid-edit may
  invalidate the current IO map, selection path, or undo history. Need a
  strategy for graceful degradation: clear the selection, discard the IO map,
  and re-project from scratch when the pipeline changes.
- **Scope** — this is a powerful feature but it's also a rabbit hole. The
  minimum viable version is a read-only projection inspector (show the
  pipeline, highlight which projection is active for the current selection).
  Live editing can come later.

---

## 12. Terminal Backend

### Steps

- **12a. `TerminalScreen`** — render `GraphicsText` and `GraphicsRect` to ANSI
  escape sequences. Bounded task: the graphics domain is already abstract
  enough that a terminal renderer just walks the canvas.
- **12b. Terminal input** — translate terminal escape sequences to `KeyPress` /
  `MouseClick`. Libraries like `Crossterm.jl` or raw ANSI parsing.
- **12c. Alternate: text-mode projection** — skip the graphics domain entirely
  and render `Text` directly to the terminal. Avoids pixel-coordinate issues
  but loses the viewport/scrolling model.

### Open questions

- **Coordinate system** — rendering `GraphicsCanvas` to a terminal means
  mapping pixel coordinates to character cells. `TextToGraphics` already works
  in character-cell units (char_width × line_height), so this might be simpler
  than it sounds — but I need to standardize whether graphics coordinates are
  pixels or character cells.

---

## 13. Web Backend

### Steps

- **13a. HTTP + WebSocket server** — serve an HTML page with a `<canvas>` or
  DOM-based renderer. The editor runs server-side in Julia; the frontend is a
  thin event relay.
- **13b. Canvas renderer** — translate `GraphicsCanvas` to Canvas 2D API calls
  sent as JSON messages over the WebSocket.
- **13c. DOM renderer** — alternative: translate `Text` (styled spans) to HTML
  `<span>` elements. Simpler, more accessible, but loses pixel-level layout
  control.
- **13d. MCP integration** — the MCP server already exists. A web frontend
  could share the same protocol.

### Open questions

- **Server-side vs. client-side reactivity** — if the editor runs in Julia and
  the browser is a dumb terminal, every keystroke is a round-trip. At 60fps
  cursor blinking or smooth scrolling, this becomes latency-sensitive. May need
  client-side prediction.
- **MCP scope** — the MCP server currently serves AI agent integration. The
  web backend and MCP serve different audiences and probably shouldn't be
  conflated.

---

## 14. External Data: Databases and Documents

Edit data that lives outside the editor — in a database, a file on disk, or a
remote API — with the projection pipeline bridging between the external
representation and the editor's document model.

### Steps

- **14a. File-backed documents** — a document wrapper that reads from and
  writes to a file. On load, the file's contents are parsed into the
  appropriate domain (JSON file → `JsonValue` tree, XML file → `XmlElement`
  tree). On save, the document is serialized back. The wrapper tracks
  dirty state (has the document been modified since last save?) and watches
  the file for external changes.
- **14b. Database-backed documents** — a document that reflects a database
  table or query result. Each row is a document (e.g. a `JsonObject` or a
  `TableRow`), and the collection of rows is a `CellVector`. Edits to cells
  produce operations that are translated into SQL UPDATE/INSERT/DELETE
  statements. Can use a connection pool with transactions to batch changes.
- **14c. Lazy loading** — for large external data sources, load only the
  visible portion. The document holds a window (offset + limit) and fetches
  more data as the user scrolls. This interacts with `GraphicsViewport` and
  the lazy projection strategy (section 17b): the viewport determines which
  document subtrees are visible, which determines which external data needs
  to be fetched.
- **14d. External document embedding** — a document node that references
  another file or URL. The printer resolves the reference, loads the external
  content, parses it into the appropriate domain, and projects it inline.
  The reader maps edits back to the external source. This enables
  mixed-source documents: a book document where one chapter is a local file
  and another is fetched from a URL.
- **14e. Schema-driven projection** — when editing database-backed data, the
  schema (column types, constraints, foreign keys) can drive the projection:
  a foreign key column renders as a link to the referenced row, a boolean
  column renders as a checkbox, an enum column renders as a dropdown. The
  schema is itself a document that can be projected and (carefully) edited.

### Open questions

- **Consistency model** — when editing a database-backed document, how do I
  handle concurrent modifications by other clients? Options range from
  optimistic locking (detect conflicts at save time) to real-time
  synchronization (section 15). For a single-user editor, optimistic locking
  is probably sufficient.
- **Operation translation** — the editor produces domain-level operations
  (`StringReplaceRangeOperation`, `CollectionInsertOperation`). Translating
  these to SQL or file-write operations requires a mapping layer that
  understands the external schema. This mapping could be a specialized
  projection (external-to-domain), or it could be a separate adapter outside
  the projection system.
- **Reactivity across process boundaries** — a database change notification
  (e.g. PostgreSQL LISTEN/NOTIFY) should invalidate the corresponding cell
  in the editor. This requires wiring external events into the reactive
  system, which currently only handles internal cell writes.

---

## 15. Network Transparency

Make documents and projections location-transparent: a document can live on a
remote machine, a projection can run on a different process, and the editor
stitches them together over the network. The reactive cell system becomes
distributed.

### Steps

- **15a. Remote cells** — a `Cell` variant that proxies reads and writes over
  a network connection. Reading a remote cell sends a request to the owning
  process; the response contains the value. Invalidation notifications are
  pushed from the owner to all subscribers. This is the minimal unit of
  distribution: any cell can be local or remote, and the rest of the system
  doesn't know the difference.
- **15b. Document hosting** — a server process holds a document and exposes
  its cells over the network. Client editors connect and bind remote cells
  into their local projection pipeline. The projection runs locally (for
  latency), but reads document cells remotely.
- **15c. Projection hosting** — alternatively, a server runs the projection
  and sends rendered output (graphics primitives or text spans) to the
  client. This is simpler for thin clients (the web backend from section 13
  is a degenerate case of this), but it means the server must handle all
  projection computation.
- **15d. Mixed local/remote** — the general case: some cells are local, some
  are remote, and the reactive graph spans multiple processes. Invalidation
  notifications propagate across the network. This requires a protocol for
  cell identity (globally unique cell IDs), subscription management, and
  value serialization.

### Open questions

- **Latency** — a remote cell read adds a network round-trip. If the
  projection pipeline reads hundreds of cells per frame, this is unusable.
  Mitigation: batch reads, prefetch visible subtrees, cache remote cell
  values locally with invalidation-based cache coherence.
- **Serialization** — cell values can be arbitrary Julia objects (documents,
  vectors, reference paths). Need a serialization format that handles the
  full type vocabulary. MsgPack or a custom binary format, with a type
  registry.
- **Failure modes** — what happens when a remote cell's host goes down?
  The cell should enter an error state that propagates through the reactive
  graph, and the printer should render a placeholder ("disconnected") rather
  than crashing.

---

## 16. Multi-User Collaboration

Multiple users editing the same document simultaneously, with real-time
visibility of each other's cursors and changes.

### Steps

- **16a. Object ownership and locking** — a lightweight concurrency control
  mechanism. Each document subtree can be *claimed* by a user (advisory lock).
  Other users see the locked region as read-only (grayed out or marked with
  the owner's color). Locks are per-subtree, not per-character: locking a
  `JsonObject` entry locks the entire entry. Locks are advisory — the system
  warns but doesn't hard-block. This is the simplest multi-user scheme and
  doesn't require real-time sync.
- **16b. Cursor sharing** — each user's selection is broadcast to all other
  users. The editor renders remote cursors as colored markers (using the
  color coding projection from section 8, keyed by user identity). This
  requires the network layer from section 15: each user's selection cell is
  a remote cell visible to others.
- **16c. OT or CRDT** — for real-time collaborative editing without locks,
  implement Operational Transformation or a CRDT (Conflict-free Replicated
  Data Type) on the operation layer. Each user's operations are transformed
  against concurrent operations from other users before being applied. The
  document converges to the same state on all clients. This is a major
  undertaking — the operation vocabulary (section 1) must be mature before
  attempting it.
- **16d. Awareness protocol** — beyond cursors, share user presence
  information: who is connected, what document they're viewing, what subtree
  they're focused on. This feeds into the UI (user list in the workbench,
  avatar markers on the document).

### Open questions

- **Granularity of locking** — per-subtree locking is simple but coarse. If
  two users want to edit different fields of the same `JsonObject`, they
  can't both lock the object. Per-field locking is finer but more complex.
  Need to find the right granularity.
- **OT vs. CRDT** — OT is well-understood for text (Google Docs uses it) but
  complex for tree-structured documents. CRDTs are more natural for trees
  (each node has a unique ID, insertions and deletions commute) but have
  known issues with intention preservation. Need to research which approach
  fits the projectional editing model better.
- **Projection divergence** — if two users use different projection pipelines
  on the same document (e.g. one sees JSON, the other sees a table view),
  they're editing the same underlying data through different lenses. This is
  fine architecturally (the projections are independent), but it may be
  confusing for users. Need to think about UX for this case.

---

## 17. Performance and Scalability

### Steps

- **17a. Benchmark suite** — measure frame time, cell recomputation count, and
  memory allocation for documents of increasing size (100, 1K, 10K, 100K
  nodes). `perf_counters()` is already available — use it systematically.
- **17b. Lazy projection** — only project visible subtrees. Laziness is part of
  the design strategy but the current implementation projects everything
  eagerly. `GraphicsViewport` should gate projection.
- **17c. Incremental collection updates** — when one element of a `JsonArray`
  changes, avoid re-projecting all siblings. May require a diff-aware
  `CellVector` or a more granular invalidation strategy.

### Open questions

- **Current performance baseline** — I haven't profiled a 1000-entry JSON
  array or a 10,000-line file. Need to do this before optimizing.
- **Pull-based overhead at scale** — pull-based means every frame re-pulls the
  entire visible tree. If the tree is deep and most cells are valid, the pull
  itself (checking validity flags up the chain) becomes
  O(visible_nodes × depth). Need to measure this.

---

## 18. Testing

### Steps

- **18a. Reader round-trip tests** — for every domain, assert that
  `projection_read(projection_print(doc), move_event)` produces a valid
  operation that, when applied, results in a correct document state. This is
  the most important class of test for a projectional editor.
- **18b. Property-based testing** — generate random documents, random cursor
  positions, random key sequences. Assert that the selection never points to
  an invalid path, that the reactive graph never has stale cells after an
  operation, and that the printer never crashes.
- **18c. Visual regression tests** — snapshot the `GraphicsCanvas` output for
  known documents and diff against a baseline. Catches layout regressions.

### Open questions

- **Edge case coverage** — `test_printers`, `test_readers`, `test_selections`,
  `test_repls` exist but I need to check whether they cover edge cases (empty
  arrays, deeply nested objects, selections on structural characters) or are
  happy-path only.
- **Reactive invalidation tests** — need tests that exercise the invalidation
  graph specifically, e.g. "change a leaf value, assert that exactly N cells
  recompute and no more."

---

## 19. Developer Experience

### Steps

- **19a. Error messages** — when a projection crashes (e.g. selection path
  points to a non-existent child), the error should name *which* projection,
  *which* document node, and *which* selection path. A crash in a computed cell
  thunk currently gives an opaque stack trace.
- **19b. Projection inspector** — a debug mode that renders the IO map
  alongside the document, showing the mapping between input and output
  elements.
- **19c. Hot reload** — `Revise.jl` compatibility. Modify a projection and see
  the change without restarting the editor.

### Open questions

- **Selection debugging cost** — if I miscount an index in a reader and the
  cursor lands in the wrong place, how long does it take to diagnose? If the
  answer is "a long time", tooling here pays for itself quickly.

---

## Prioritized Roadmap

| Phase | Focus | Why |
|---|---|---|
| **Phase 1** | Character insert/delete (1a) + click-to-select (2a) | Without these the editor is a viewer. Minimum to call it an editor. |
| **Phase 2** | Structural insert/delete (1b) + undo/redo (3a–3c) | Makes the editor usable for real editing tasks. |
| **Phase 3** | Color coding (8) + domain readers: Julia (6a), Math (6b), XML (6c) | Visual polish + self-hosting path. |
| **Phase 4** | Search-based editing (5) + transactional editing (4) | Power-user editing workflows. |
| **Phase 5** | Extended language domain (7) + graph domain + layout projections (9, 10) | Semantic programming model + non-textual editing. |
| **Phase 6** | Editing projections (11) + benchmark suite (17a) | Meta-editing + performance baseline. |
| **Phase 7** | Web backend (13) or terminal backend (12) | Make the editor accessible beyond SDL. |
| **Phase 8** | External data (14) + file-backed documents (14a) | Real-world data sources. |
| **Phase 9** | Object versioning + timelines (3d–3f) | History exploration and branching. |
| **Phase 10** | Network transparency (15) + multi-user collaboration (16) | Distributed editing. Goes last because it depends on mature operations, versioning, and external data. |

---

## Guiding Principle

The risk is expanding horizontally (more domains, more projections) while the
vertical slice — can I actually *edit* something end-to-end? — stays shallow.
The original ProjecturEd had this tendency.

The bar I want to hold myself to: **use this editor for a real task** — open a
file, make changes, save it. Everything in this plan should be evaluated
against that.
