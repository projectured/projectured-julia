# One design document for each package

**Status (2026-09-22): IN PROGRESS.** Step 1, the survey, runs.

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

- [ ] Nine Sonnet subagents read the code, the guides and the plans of their
      slices. At most three run at the same time, and none starts a Julia
      process. Each writes one notes file for each slice into the session
      scratchpad. The notes are facts with a `file:line` or a plan name.

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

- [ ] Collect the shared mechanisms from the notes. Write each one once, in the
      guide that owns it, or add a short section on how a domain works to
      [domain-inventory.md](../../documentation/design/domain-inventory.md).

### Step 3: the documents, one commit for each group

- [ ] G1 · [ ] G2 · [ ] G3 · [ ] G4 · [ ] G5 · [ ] G6 · [ ] G7 · [ ] G8 · [ ] G9

### Step 4: the indexes and the check

- [ ] `documentation/README.md`, `documentation/package/README.md` and
      `domain-inventory.md` list the new documents.
- [ ] `julia test/suite/documentation.jl` reports no violation.
- [ ] Land on `main` with `git merge --ff-only`, and move this plan to
      `plan/done/`.

## 5. Decisions

- **One document for each package, in the folder of its slice.** A second
  design file next to the reference guide would repeat it, and the two copies
  would drift. (Proposed; waits for the owner.)

## 6. Facts found on the way

- `plan/pending/documentation-rewrite.md` says in Step 7 that every slice has a
  guide. 28 slices have no guide folder. The guard in
  `test/suite/documentation.jl` counts a slice as covered when any document
  names it, so a one-line mention passes it.
