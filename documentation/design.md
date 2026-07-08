# Design Overview

This document was previously a single 810-line architecture + reference guide.
It has been split into three focused documents so each can be read independently:

- **[Architecture](architecture.md)** — package/layer/slice structure, module inventory,
  projection pipeline status, and mapping to the original Common Lisp
  ProjecturEd. Read this for *what the code is*.

- **[Design decisions](design-decisions.md)** — rationale for pull-based
  reactivity, every-field-is-a-Cell, multiple dispatch for projections, shared
  selection cells, `ProjectionReference`, and the `KeyPress` abstraction.
  Read this for *why the code is the way it is*.

- **[Selection deep dive](selection-deep-dive.md)** — the full
  reference/selection mechanism: reference step types, the document contract,
  `set_selection!`, how the printer projects the selection reactively, how the
  reader translates it backward, and the three-step algorithm required for
  compound projections. Read this when working on selection, references, or any
  new projection that recurses into children.

For a gentler entry point, start with
[Concepts](concepts.md) (plain English) and
[Architecture](architecture.md) (module inventory).
