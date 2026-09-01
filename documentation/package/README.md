# Per-slice reference guides

One folder per slice, holding the guides that describe that slice's code. They
lived beside the code as `package/<slice>/doc/` until the repository tree moved
prose out of `package/`, which now holds a name and an include list and nothing
else — see [plan/done/repository-tree.md](../../plan/done/repository-tree.md).

The cross-cutting guides stay one level up, in [documentation/](../). Read those
first: [concepts.md](../concepts.md) explains what a document, a projection and
an editor are, and [architecture.md](../architecture.md) explains how the pieces
stack.

A guide here is named `<slice>/<file>` when the editor's documentation tool lists
it, so `kernel/cell` and `widget/widget` do not collide. The bare names belong to
the guides one level up.
