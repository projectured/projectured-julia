# A document at several places is printed once

Status: TENTATIVE. The first question is whether this can be done reliably. The
answer can be no.

## The ask

The owner, 2026-10-19, while step 1 of `views-compose-as-content-composes.md` printed
the text of three places three times:

- "I feel like there should be some higher order projection perhaps which solves the
  problem of reusing the output and iomap of applying a projection to a document in
  muiltiple other projections, no? This is just an idea"
- "btw, this issue of printing only once is not new, it has nothing to do with the
  view and content separation. it was already present before, since one document
  could be present in multiple location"
- "besides, due to the reference being part of the context and thus the input of the
  projection, just because the same input is used, it doesn't imply that the output
  is the same"
- On whether this is a topic of its own: "yes, I think it should be, and it may be
  that the answer will be that it cannot be done reliably"

## What is known

- **The recursion prints a document each time it reaches it.** `RecursiveProjection`
  passes itself down, and `print_child` prints again. A document at n places gives n
  prints: n IO maps, n output trees and n sets of cells. This is so for a document in
  two tabs, and for a text that the views of step 1 show at three places.
- **A print reads three things:** the projection, the document and the context. The
  context (`PrinterContext`) holds the path of the place (`reference`), the range of
  the size on each axis, the properties that a parent sets, and the clock.
- **The path is different at each place, and it is a part of the input.** 19 reads of
  the path are in 7 files of `source/`: the context itself, the fault store, fault
  catching, reference dispatching, which chooses a projection by the path, arranging,
  the grid list, and the insertion of the syntax. A print gives its context to its
  children (`make_child_context`), so a print depends on its place when any print in
  its subtree reads the path.
- **The output stays live after the print.** A computed list of children captures the
  recursion to print a child again later; 15 computations in `source/` capture
  `print_child(recursion, …)`.
- **One graphic can be drawn at several places.** The SDL backend keys its records by
  the placement of a graphic, the graphic with the container that holds it, so the
  regions of a table share its rules and its bands.
- **A throwaway prototype, 2026-10-19,** not committed: a recursion that holds a
  table from a document to the IO map of its one print, and a row that asks the table
  first. On the example `text_view`, a vertical layout of view A, view B and view A
  over one `TextBlock`:
  - The text was printed once, and the three views drew the one drawing.
  - Right, Down and a click gave the same operations as with three prints.
  - A typed character made 10 cells of the one drawing stale, where three prints make
    10 stale in each.
  - The SDL render was right.

  It was right only because `TextBlockToGraphicsCanvas` reads no path and no size of
  its place.

## Potential benefits

- **Less work for each place after the first:** no second print, no second set of
  cells, no second output tree in memory.
- **An edit recomputes one print, not n.** In the prototype, a typed character
  recomputed 10 cells and not 3 × 10.
- **The output of a document is one object.** A second place adds only what is its
  own, such as the caret of a view, and a reader of the second place maps through the
  same IO map as the first.
- **It is general.** It is not a feature of the views: every document at several
  places has it, a document in two tabs too.

## Potential traps

- **The same document is not the same input.** The path is a part of the input. A
  print whose subtree reads its path gives another output at each place, and a shared
  print gives the output of the first place at all of them.
- **The other parts of the context differ too.** A place can offer another width, and
  a wrap reads the width. A container can set a property, such as the spacing of its
  lines. A shared print gets the context of the first place that printed it.
- **Nothing can check what a print reads.** A print does not say which parts of its
  context it reads. A promise that a print reads no part of its place, in the
  composite or in the projection, gives wrong output with no error when it is wrong.
- **The state has no natural owner.** A projection serves every print and every
  editor and holds no state, and a print is not a part of a document. A table of
  prints can live only in an object of one print, which the output keeps alive.
- **An entry stays too long.** A document that no place prints any more keeps its
  print in the table while the whole print lives.
- **One IO map answers for several places.** A part of a print that keeps the path of
  its first place, such as a cell that follows the path of its context, answers that
  place for every place.
- **One output object is at several places.** Code that keeps state for each output
  node and not for each placement sees one node where there are several. The SDL
  backend keys by placement; for the other backends this is not known.
- **A fault is shared.** A fault in a shared print shows at every place, and the fault
  store records the place of the first.
- **It is close to a cache.** It is a table of prints keyed by the identity of a
  document. The owner rejected a cache to find the content of a view (2026-10-18), so a
  table of prints needs a reason of its own.

## The first question

Can a document at several places be printed once reliably, so that the sharing
follows from the shape of the composite and not from a promise that nothing checks?
If it cannot, a document at several places stays printed once for each place, and
this plan records why.

## What a step must measure first

How often a document is at several places in practice, and what each print after the
first costs: the time, the cells and the memory. If the cost is small, no is a good
answer.

## Related

`plan/pending/views-compose-as-content-composes.md`: step 1 prints the content of a
view once for each place that shows the view.
