# One design document for each package

**Status (2026-09-22): IN PROGRESS.** Steps 1 and 2 are done. Step 3 runs.

**Goal:** each package outside the kernel has one document that says how the
package works, how it fits with the other packages, which large design decisions
shaped it and why, and how to use it. The reader is a future developer or an AI
that must change the package. The document covers what is not obvious from the
code. It does not cover every detail.

**Worktree:** `/home/projectured/workspace/projectured-julia-domain-design-docs`,
branch `domain-design-docs`, from `main` at `68b1a458`.

## 1. The request

> I want to document the design decisions and architecture of all projectured
> domains better in markdown files.
>
> So here is the idea, do a survey of each domain, basically the non-test,
> non-example packages other than the kernel, collect knowledge about them from
> the code, from current documentation and from done/pending/etc. plans. We
> should have one document for the design decisions and architecture of each
> domain distilling the current state and the decisions in the plans. You can
> use sub-agents to do this, but avoid using too much resources of this
> computer.
>
> Don't overdo the documentation, it should not cover every minute detail. We
> should focus on the larger and more important design decisions and on how each
> domain works and fit together. You can factor out the common parts into the
> kernel documents if that helps. We should have description for usage examples
> like in json.md too.
>
> This is for future developers and AIs to understand the concepts of each
> domain and how they fit together. The documentation should be technical in
> nature and focus on parts which are not immediately obvious.

## 2. Scope

The 64 slices under `source/` other than `kernel/` and `projectured/`. Each
slice is one package, `Projectured<Slice>`.

Two packages get no document of their own:

- `Projectured`, the umbrella. [system-anatomy.md](../../documentation/design/system-anatomy.md)
  and [package-rules.md](../../documentation/rule/package-rules.md) describe it.
- `ProjecturedBench`, a 39-line benchmark entry. It has no slice.

State on 2026-09-22: 36 slices have a folder under `documentation/package/`,
and 28 have none: yaml, markdown, book, julia, dbcatalog, formula, odbc,
filesystem, log, statistics, anthropic, ollama, layout, dragging, clipboard,
tooltip, style, screen, domain, projection, gesturelog, console, pdf, sdl, web,
video, builder, tulip. Some of these are named in a shared guide:
`llm/llm.md` covers anthropic and ollama, and `database/database.md` covers
dbcatalog and odbc.

## 3. The document

**Place.** `documentation/package/<slice>/<slice>.md`. Where that file exists,
the step revises it in place. It keeps the reference content that a reader
needs, and it drops detail that the code shows at a glance. Other guides in the
same folder stay; the design document links to them.

**Kind.** `design`: what each part is, in the settled form, and why.

**Length.** About 80 to 200 lines. A small package gets less.

**Sections.** A document leaves out a section that has nothing to say.

1. The title, the header line, and a summary of at most three sentences.
2. The screenshot, if `asset/image/example/<name>.png` exists.
3. **How it works.** The documents, the chain of projections, the reader, and
   the mechanisms that are special to the package.
4. **How it fits.** What it takes from each package below it, which packages
   use it, and what it registers: a natural projection, a file format, a
   factory, gestures, tools.
5. **Design decisions.** Each one: the decision, the reason, the alternative
   that was rejected, and the plan under `plan/done/` that holds the history.
   A decision is written in the present tense only when the code has it.
6. **Usage.** A short snippet, as in [json.md](../../documentation/package/json/json.md):
   make a document, show it, parse its text form. The names of the examples,
   and the test function.
7. **Limits.** What does not work yet, and the pending plans. An honest status,
   not a list of wishes.

**Common parts.** A mechanism that many packages use is described once, in the
kernel guide or the substrate guide that owns it. The package documents link to
it. Candidates: `@document`, `@domain`, `@projection_template`,
`register_natural_syntax!`, the file format registration, the `*Nothing`
placeholder, the insert-by-typing leaf, `@gestures`.

**Rules.** [writing-rules.md](../../documentation/rule/writing-rules.md):
Simplified Technical English, no personification, the present state only, no
private name, relative links that resolve. `julia test/suite/documentation.jl`
checks the part that a program can check. It needs no environment.

## 4. Steps

### Step 1: the survey

- [x] Nine Sonnet subagents read the code, the guides and the plans of their
      slices. At most three run at the same time, and none starts a Julia
      process. Each writes one notes file for each slice into the session
      scratchpad. The notes are facts with a `file:line` or a plan name.
      Done: 64 notes files, 60 to 320 lines each.

| Group | Slices |
| --- | --- |
| G1 text data | json, yaml, xml, markdown, rst, book, fileformat, natural |
| G2 code and query | julia, sql, dbcatalog, database, odbc, formula, math |
| G3 diagrams | graph, adaptagrams, tulip, chart, plot, sequencechart, fsm, process |
| G4 AI and application | conversation, assistant, anthropic, ollama, mcp, shell, filesystem, log, statistics |
| G5 widgets | widget, component, focus, reflection |
| G6 layout and panes | layout, pane, dragging, clipboard, tooltip, inspector |
| G7 text rendering | text, syntax, style, graphics, screen |
| G8 vocabulary and algebra | collection, primitive, domain, serialization, projection, versioning, undo |
| G9 features and backends | fault, gesturehelp, gesturelog, console, pdf, sdl, web, video, repl, builder |

### Step 2: the common parts

- [x] Collect the shared mechanisms from the notes. Write each one once, in the
      guide that owns it, or add a short section on how a domain works to
      [domain-inventory.md](../../documentation/design/domain-inventory.md).
      Done as a new design document, `documentation/design/domain-anatomy.md`.

### Step 3: the documents

- [x] The lead writes the documents of the slices with no guide: yaml,
      markdown, book, julia, formula, style, screen, domain, projection,
      filesystem, log, statistics, layout, dragging, clipboard, tooltip, tulip.
- [ ] Six Opus writers revise the guides that exist and write the rest, three
      at a time. Instructions: `writer-instructions.md` in the scratchpad.

| Writer | Documents |
| --- | --- |
| W1 text and code | json, xml, rst, fileformat, natural, sql, math, database (with dbcatalog and odbc) |
| W2 diagrams | graph (new, beside graph-layout), adaptagrams, chart, plot, sequencechart, fsm, process |
| W3 AI and application | conversation (new, beside transcript), assistant, llm (anthropic and ollama), mcp, shell |
| W4 widgets and panes | widget, component, focus, reflection, pane, inspector |
| W5 rendering and vocabulary | text, syntax, graphics, collection, primitive, serialization, versioning, undo |
| W6 features and backends | fault, gesturehelp, repl; new: gesturelog, console, pdf, sdl, web, video, builder |

- [ ] The lead fixes the stale facts in the kernel, rule and design documents
      (section 6).

### Step 4: the indexes and the check

- [ ] `documentation/README.md`, `documentation/package/README.md` and
      `domain-inventory.md` list the new documents.
- [ ] `julia test/suite/documentation.jl` reports no violation.
- [ ] Land on `main` with `git merge --ff-only`, and move this plan to
      `plan/done/`.

## 5. Decisions

- **One document for each package, in the folder of its slice.** A second
  design file next to the reference guide would repeat it, and the two copies
  would drift. The owner did not answer the question by the end of the survey,
  so the work goes on with this option; the owner can still change it.
- **A family keeps one document.** `llm/llm.md` covers `anthropic` and
  `ollama`, and `database/database.md` covers `database`, `dbcatalog` and
  `odbc`. The packages of a family share one seam, and separate documents
  would repeat it.
- **A detail guide stays next to the design document.** `graph/graph.md` is
  new and links to `graph-layout.md`; `conversation/conversation.md` is new and
  links to `transcript.md`; `reflection.md` links to `bounded-sync.md`.
- **The shared parts of a domain are one design document,**
  `documentation/design/domain-anatomy.md`, not a section of the kernel
  guides. Most of them are in substrate packages (syntax, natural, fileformat,
  serialization, domain), not in the kernel.
- **The two projection guides move to `documentation/package/projection/`.**
  Their code is in `ProjecturedProjection`, not in the kernel. No source file
  names them as a guide.
- **The writers are Opus subagents, three at a time.** The survey agents were
  Sonnet; the notes had errors that a writer must catch, so the writer checks
  each claim against the code. The lead reviews each document and runs the
  guard.

## 6. Facts found on the way

Found by the survey and checked against the code. The ones in a document are
fixed there; the ones in code are for the owner.

- `documentation/package/database/database.md:87` says that `dbcatalog`
  depends on `database`. `ProjecturedDbCatalog` has no such dependency;
  `odbc` depends on both.
- `documentation/rule/package-rules.md:173` gives `ProjecturedDomain` the
  third-party dependency `InteractiveUtils`. `source/domain/Domain.jl:26`
  avoids it on purpose.
- `documentation/package/kernel/generic-projections.md` and
  `higher-order-projections.md` describe projections that live in
  `source/projection/` and `source/dragging/`, not in the kernel.
- `documentation/package/kernel/macros.md` names `NothingToSyntaxLeaf()` for the
  placeholder rule. Every domain uses `InsertionNothingToSyntaxLeaf()`;
  `NothingToSyntaxLeaf` prints the Julia value `nothing`.
- `documentation/package/json/json.md` says that `collapsed = true` renders a
  value on one line. No JSON, YAML or XML projection reads `collapsed`;
  `plan/pending/collapse-expand-syntax-nodes.md` tracks it.
- `documentation/package/graphics/graphics.md` shows the eight-argument
  `GraphicsText` and `GraphicsRect` constructors. They take a `StyleColor` now.
- `documentation/design/domain-inventory.md` lists only Julia under the
  dependencies of `ProjecturedFormula`. It also depends on `ProjecturedMath`.
- `higher-order-projections.md` used `prefix(...)` in two `@reference_case`
  examples. `prefix` raises an error now (`source/kernel/reference/ReferenceCase.jl`);
  the examples use `above(...)`, as `HigherOrderCompound.jl` does.
- Code comment: the header of `source/julia/JuliaParser.jl` says that `&&`,
  `||`, `where` and keyword arguments raise an error. The parser has a
  converter for each of them.
- Code: no source file registers a natural row for `FrameStatistics`. The
  toolbar opens a statistics tab, and the general renderer then has no row for
  it; only `example/projectured/FeedExamples.jl` uses `FrameStatisticsToSyntax`.
  `ToolViewTest.jl` checks the rows of the other tools but not this one.
- Code: `FormulaInsertion` has a docstring that says typed text commits to a
  formula. No reader does that (`plan/pending/excel-julia-formulas.md`, Phase 5).

- `plan/pending/documentation-rewrite.md` says in Step 7 that every slice has a
  guide. 28 slices have no guide folder. The guard in
  `test/suite/documentation.jl` counts a slice as covered when any document
  names it, so a one-line mention passes it.
