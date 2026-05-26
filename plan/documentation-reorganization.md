# Documentation Reorganization Plan

## Newcomer's Review

### What works well

- **README.md** is well-structured: it has a clear one-paragraph pitch, an ASCII
  diagram, a quick-start snippet, a repo layout table, and a curated reading
  order. A newcomer landing on the GitHub page gets a solid first impression.
- **guide/design.md** is a genuinely impressive deep-dive. The module inventory,
  the projection pipeline status, the mapping table from Common Lisp to Julia,
  and the selection mechanism walkthrough are exactly what a contributor needs.
- The per-domain guides (json, xml, text, syntax, graphics, widget, workbench,
  collection) are consistently shaped: types, examples, selection, key features.
- The macro, reactive-cell, and projection-system guides are well-scoped and
  self-contained.

### What doesn't work

1. **No "why should I care?" page.** The README says "generic-purpose
   projectional editor" and shows a pipeline diagram, but never explains *what
   problem this solves for a user*. A newcomer who doesn't already know what
   projectional editing is will bounce. There are no screenshots, no GIFs, no
   "here's what it looks like" section.

2. **The pitch is buried in implementation details.** The most inspiring content
   — "the same framework edits JSON, XML, Java, styled documents, graphics, and
   anything else" — is a subordinate clause in a paragraph about architecture.
   The vision ("a text editor is just a degenerate case") appears only deep in
   `design.md` §1, not on the front page.

3. **No conceptual on-ramp.** The recommended reading order sends the newcomer
   straight to `design.md` (811 lines of architecture) or `reactive-cells.md`
   (the reactive engine internals). There is nothing between "here's a
   `run_example()` snippet" and "here's how `Cell` invalidation propagates."
   A conceptual guide that walks through *one concrete example end-to-end*
   — "you type a key, here's what happens" — is missing.

4. **design.md is overloaded.** It serves four roles simultaneously:
   architecture overview, design rationale, module inventory, and selection
   mechanism reference. At 811 lines it is too long for a first read and too
   tangled to use as a reference. Its section numbering skips from §9 to §11.

5. **Duplicate reading orders.** The README, CLAUDE.md, and getting-started.md
   each propose a slightly different reading order with different numbering. A
   newcomer who follows one will be confused when another contradicts it.

6. **No visual material.** There are zero screenshots, diagrams (beyond ASCII),
   or recordings showing the editor in action. For a *visual* editor, this is a
   critical gap. The `image/` directory exists but is empty.

7. **No "use case" or "what can you build?" section.** The example catalogue
   (`example/src/`) contains ~20 examples spanning JSON, XML, widgets, math,
   Julia AST, filesystem, book, table — but no guide explains what each one
   demonstrates or why it matters. A newcomer has to run them blind.

8. **The potential is undersold.** The documentation focuses almost entirely on
   how the current implementation works, not on what the architecture *enables*.
   MCP integration, AI-driven editing, multi-backend rendering, live
   collaboration — these are mentioned in passing but never highlighted as the
   project's unique strengths.

9. **No contributor guide.** There is no CONTRIBUTING.md or "how to add a new
   domain" walkthrough. The closest is a four-step recipe in
   `projection-system.md` §"Writing a custom projection", but it assumes you
   already understand everything else.

10. **Plan docs are invisible.** The `plan/` directory contains substantial
    roadmap thinking (further-development.md alone is 843 lines), but nothing
    links to it from the main documentation except a one-line mention in the
    README table.

---

## Reorganization Plan

### Phase 1 — Front door (make the first 60 seconds count)

**Goal:** A newcomer should understand what this project is, what it looks
like, and why it's interesting within one minute of landing on the repo.

| # | Action | File(s) |
|---|--------|---------|
| 1.1 | **Rewrite the README intro** to lead with the problem, not the solution. Open with "What if your editor understood the *structure* of what you're editing?" followed by 3–4 concrete before/after scenarios (edit JSON and see the tree update; switch a projection and see the same data as XML; zoom into a sub-document). | `README.md` |
| 1.2 | **Add screenshots/GIFs** to the README. Capture the SDL window showing at least: the JSON example, the workbench, the widget example, and one mixed-domain example. Place in `image/`. | `README.md`, `image/` |
| 1.3 | **Add a "What can it do today?" section** to the README listing the implemented domains with one-sentence descriptions and linking to the matching example. Replace the current bare list of guide links with a curated "Start here → Go deeper → Reference" hierarchy. | `README.md` |
| 1.4 | **Add a "Vision" section** that explicitly states the long-term potential: universal structured editing, AI-assisted editing via MCP, multiple backends (terminal, web, IDE plugin), live collaboration, and user-extensible domains. Keep it to one paragraph plus a bullet list. | `README.md` |

### Phase 2 — Conceptual bridge (close the gap between "run it" and "understand it")

**Goal:** A newcomer who has run `run_example()` should be able to understand
what happened and start forming a mental model, before reading any implementation
guide.

| # | Action | File(s) |
|---|--------|---------|
| 2.1 | **Create `guide/concepts.md`** — a plain-English conceptual guide (~300 lines). Structure: What is projectional editing? → Why it matters → The five core ideas (domain, document, projection, selection, operation) explained with analogies → One end-to-end walkthrough: "You press → and here's what happens, step by step" with diagrams. No code, no Cell internals. | `guide/concepts.md` (new) |
| 2.2 | **Create `guide/examples-tour.md`** — a guided tour of 5–6 examples from simple to complex. For each: what it demonstrates, a screenshot, what to try, and what concepts it illustrates. Link to the deeper guides for each concept. | `guide/examples-tour.md` (new) |
| 2.3 | **Trim getting-started.md** to focus on setup and first run. Move the concept table to `concepts.md`. Move the reading-order list to a single canonical version in the README. Remove the duplicate reading orders from CLAUDE.md and getting-started.md (replace with a link to the README). | `guide/getting-started.md`, `README.md`, `CLAUDE.md` |

### Phase 3 — Restructure the deep-dive material

**Goal:** The existing excellent technical content becomes easier to navigate
by splitting overloaded documents and establishing a clear hierarchy.

| # | Action | File(s) |
|---|--------|---------|
| 3.1 | **Split `design.md`** into three focused documents: | |
| | — `guide/architecture.md`: layers 0–3, the pipeline diagram, the module dependency graph. (~200 lines) | `guide/architecture.md` (new) |
| | — `guide/design-decisions.md`: §6 (pull-based reactivity, every-field-is-a-cell, shared selection, ProjectionReference, etc.) + §10 (differences from original). (~200 lines) | `guide/design-decisions.md` (new) |
| | — `guide/selection-deep-dive.md`: §11 (the full reference/selection mechanism, recursive storage, selection under recursion). (~250 lines) | `guide/selection-deep-dive.md` (new) |
| | Leave `design.md` as a short redirecting index that points to the three new files, so existing links don't break. | `guide/design.md` |
| 3.2 | **Fix the section numbering** in the original design.md (§10 missing, §11 should be §10). | `guide/design.md` |
| 3.3 | **Create a single canonical reading-order page** (`guide/README.md` or a section at the top of the guide index) with three tracks: | `guide/README.md` (new) |
| | — **User track**: concepts → examples-tour → getting-started → debugging | |
| | — **Contributor track**: architecture → reactive-cells → macros → projection-system → the domain you're touching | |
| | — **AI-agent track**: CLAUDE.md already works; just link it | |

### Phase 4 — Highlight the potential

**Goal:** Make the documentation communicate not just what the project *is* but
what it *could become*, so that potential contributors and users understand the
vision.

| # | Action | File(s) |
|---|--------|---------|
| 4.1 | **Create `guide/vision.md`** — a standalone page expanding on the README's "Vision" bullet list. Sections: Why structured editing matters (with concrete pain points of text-based editing); What bidirectional projections enable (domain-crossing, mixed-media documents, computed views); The MCP bridge (AI assistants as first-class editors); Multi-backend future (terminal, web, embedded); Extensibility story (add a domain in ~100 lines). | `guide/vision.md` (new) |
| 4.2 | **Surface the roadmap.** Create `guide/roadmap.md` that distills `plan/further-development.md` into a prioritized, public-facing roadmap with three horizons: Near-term (editing ops, mouse input, undo), Medium-term (more domains, terminal backend, collaboration), Long-term (web backend, plugin system, package-manager-style domain distribution). Link from README. | `guide/roadmap.md` (new) |
| 4.3 | **Add a "Compared to…" section** to `vision.md` or the README. Briefly position ProjecturEd relative to JetBrains MPS, Lamdu, Hazel, Tree-sitter, and traditional text editors. Not a feature matrix — just "here's the design space, here's where we sit." | `guide/vision.md` |

### Phase 5 — Contributor experience

**Goal:** Lower the barrier for someone who wants to contribute a new domain,
projection, or backend.

| # | Action | File(s) |
|---|--------|---------|
| 5.1 | **Create `CONTRIBUTING.md`** — repo conventions, PR process, how to run tests, code style (1-based indexing, bidirectional projections, Cell wrapping). | `CONTRIBUTING.md` (new) |
| 5.2 | **Create `guide/tutorial-new-domain.md`** — a step-by-step tutorial that walks through adding a toy domain (e.g. a "counter" or "todo list" domain): define the document types, write the projection to Syntax, implement the reader, add an example, write a test. Each step links to the relevant guide. | `guide/tutorial-new-domain.md` (new) |
| 5.3 | **Expand `projection-system.md` §"Writing a custom projection"** with a second, more complex example (a node-shaped projection with children and recursion, not just a leaf). | `guide/projection-system.md` |

---

## Proposed Documentation Tree (after all phases)

```
README.md                          ← rewritten intro, screenshots, vision summary, reading order
CONTRIBUTING.md                    ← new
CLAUDE.md                          ← trimmed, links to README for reading order

guide/
  README.md                        ← new — the index with three reading tracks
  concepts.md                      ← new — plain-English conceptual guide
  examples-tour.md                 ← new — guided walkthrough of examples
  vision.md                        ← new — potential, comparisons, why it matters
  roadmap.md                       ← new — public-facing roadmap

  getting-started.md               ← trimmed to setup + first run
  architecture.md                  ← new — split from design.md
  design-decisions.md              ← new — split from design.md
  selection-deep-dive.md           ← new — split from design.md
  design.md                        ← becomes a short index pointing to the above three

  reactive-cells.md                ← unchanged
  macros.md                        ← unchanged
  projection-system.md             ← expanded with compound-projection example
  higher-order-projections.md      ← unchanged
  generic-projections.md           ← unchanged
  operations.md                    ← unchanged

  editor.md                        ← unchanged
  editor/
    reference.md                   ← unchanged
    selection.md                   ← unchanged
  devices-and-backends.md          ← unchanged
  debugging.md                     ← unchanged
  testing.md                       ← unchanged

  document/                        ← all unchanged
    json.md, xml.md, text.md, syntax.md,
    graphics.md, widget.md, workbench.md, collection.md

  tutorial-new-domain.md           ← new — hands-on contributor tutorial

image/
  json-example.png                 ← new screenshots
  workbench-example.png
  widget-example.png
  mixed-domain-example.png

plan/                              ← unchanged (internal)
```

## Priority Order

1. **Phase 1** (front door) — highest impact, lowest effort. A rewritten
   README intro + screenshots will change the first impression completely.
2. **Phase 2** (conceptual bridge) — `concepts.md` is the single highest-value
   new document. Without it, every newcomer hits a wall.
3. **Phase 4** (potential) — `vision.md` and `roadmap.md` are what turn a
   curious visitor into a contributor or user.
4. **Phase 3** (restructure) — improves navigation for people already reading;
   important but less urgent than getting people *to* read.
5. **Phase 5** (contributor) — matters once there are contributors; the
   tutorial is also useful as a teaching document.
