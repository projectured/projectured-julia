# Per-slice reference guides

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../design/system-anatomy.md), [package-rules.md](../rule/package-rules.md)

One folder per slice, holding the guides that describe that slice's code. Guides
live in `documentation/package/`, one folder per slice; `package/<slice>/` holds
only a name and an include list.

The cross-cutting guides stay one level up, in [documentation/](../). Read those
first: [concepts.md](../design/concepts.md) explains what a document, a projection and
an editor are, and [architecture.md](../design/system-anatomy.md) explains how the pieces
stack.

A guide here is named `<slice>/<file>` when the editor's documentation tool lists
it, so `kernel/cell` and `widget/widget` do not collide. The bare names belong to
the guides one level up.
