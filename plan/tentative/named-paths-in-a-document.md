# Named paths in a document

> **Kind:** idea · **Status:** tentative. Nothing is planned or built. The owner
> asked on 2026-09-29 to write the feature and the idea down, and to build only
> the mouse target now
> ([a-document-knows-the-part-under-the-pointer.md](../done/a-document-knows-the-part-under-the-pointer.md)).

## The feature

A document holds any number of named paths to its own parts, and each
projection draws them:

- **named selections** — "selections are named" (owner 2026-09-29). The live
  selection, which the keys follow, is one of them; a second selection, a
  selection that a search left, or a selection per person are others;
- **named highlights, each with a colour** — "Highlights are named and colour
  coded" (owner 2026-09-29): the results of a search, the parts that an error
  names, the parts that a review marks;
- **the mouse target** — the part under the pointer.

"On the long term we should support any number of colour coded highlights and
any number of selections. So it really feels like there are multiple similar
things like the mouse target and the selection." (Owner 2026-09-28.)

## The idea

All of them have one shape:

- a path from a document to a part, and each document on the path holds its own
  tail, as the selection chain does today;
- written at the root by an operation, or computed for a document that a
  projection introduces, by the forward map of the projection;
- drawn by each projection from its own document, each kind in its own style,
  a highlight in its own colour.

They differ in what they do and how long they live:

| | Selection | Mouse target | Highlight |
| --- | --- | --- | --- |
| **How many** | one live, and any number of named ones | one | any number, each named |
| **What it does** | the keys follow the live one | a move goes to its old part | only drawn |
| **Kept** | can be kept; a dormant part stays in a tab group | never | usually computed, as by a search |

So one model can hold them: every document holds named sets of paths, one
wiring maps all of them forward into the output, and one write operation sets
a named path at the root.

## What exists

- [dormant-selection.md](../done/dormant-selection.md): the stored selection is
  a `SelectionDocument(primary, live)`, and `primary` "reserves the shape for a
  secondary and for named selections, which this plan does not build."
- [annotation.md](annotation.md): annotations, such as comments and highlights,
  as a document of their own, anchored by reference paths. A highlight there is
  an annotation whose content is a colour. A named highlight in a document and
  an annotation next to a document are two ways to show the same kind of mark;
  a plan must choose where each belongs.
- The mouse target is built first as the second kind of this shape: its chain
  write and its forward wiring are written for "a kind of path", and the
  selection keeps its own code until a plan moves it into the model.

## Questions for a plan

- Is the live selection a named selection, or a separate path next to the named
  ones?
- Where does a highlight live: in the document it marks, or in an annotation
  document next to it?
- Which named paths are saved, which are kept in a history, and which are only
  view state?
- How does a person name, switch and clear a selection or a highlight?
