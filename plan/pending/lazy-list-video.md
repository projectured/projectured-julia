# A count of what a lazy list computed, for the video S11

**Status: in progress, on the branch `s11-lazy-video`.** The owner said on
2026-09-27: "yes, agreed, do it and take the video", and chose design 2a. The screenplay is S11 in
[feature-video-screenplays.md](feature-video-screenplays.md), which the owner
accepted on 2026-09-27.

## Problem

S11 shows that a list with no end computes only what its view shows. The program
has the lazy list and the view that it needs, and it has none of the things that
make the laziness visible or easy to type:

1. **No observer that does not force.** Every view that shows a node computes it.
   The performance counters (`PROJECTURED_PERFORMANCE_COUNTERS`) count every cell
   of a frame, not the nodes of one list, and nothing shows a count in a pane.
2. **No natural list that is infinite in both directions.** The two-way example,
   `make_lazy_bidirectional_document_example`, mirrors the primes as `-2, -3, -5, …`
   above `2`. That means nothing to a viewer, and
   `test/substrate/document/CollectionDocumentTest.jl` says that its node chaining
   has faults.
3. **The sieve is not in the scope of the evaluator.** The evaluator binds the
   exports of the umbrella `Projectured` (`_scratch_sources` in
   `source/kernel/tool/CodeExecution.jl`). `sieve`, `integers_from` and
   `lazy_filter` are exports of `ProjecturedSubstrateExample`, which the umbrella
   does not export.
4. **Not tested: an infinite result in the evaluator.** A form whose value is a
   `ListNode` with no end, with no `;` after it, draws in a result row. The
   layout of the evaluator has no case for a canvas with no end, so the row can try
   to lay out without end.
5. **Not tested: a form that opens a list beside the evaluator.** `open_pane!`
   takes `target` and `side`, but no take has used them from the evaluator.

## What exists

- `ListNode` (`source/collection/ListNode.jl`) is a node with a `value` and two
  lazy tails, `prev` and `next`. Index 1 is the node itself, 2 is `next`, 0 is
  `prev`.
- The lazy sieve (`example/substrate/LazyDocumentExample.jl`): each prime adds one
  `lazy_filter` to the rest of the stream. It is the classic lazy sieve, which
  tests each number against every earlier prime.
- `WidgetScrollPane` scrolls a canvas with no end in both directions, measured from
  the head of its list, and clamps nothing (`_pane_scroll_y` and `_scroll_room` in
  `source/widget/WidgetToGraphics.jl`).
- `is_cell_up_to_date` (exported by the kernel) says whether a cell holds a
  computed value, without computing it.

## Design

1. **`count_computed_nodes(list::ListNode) -> Int`**, in
   `source/collection/ListNode.jl`, next to `take_first`. It walks from the node
   along `next` while the cell is up to date and holds a `ListNode`, then along
   `prev` in the same way, and counts the nodes. It never reads a cell that is not
   up to date, so it never computes a node.
2. **The count in a label that stays current.** The label must count again when
   the list grows. There are two ways, and the choice is the owner's:
   - a. The label reads the reactive clock of the editor, so it counts again on
     each frame. It needs no change to the kernel. The cost is one walk over the
     computed nodes each frame, a few hundred steps in the video.
   - b. The count depends on the first cell that is not computed yet, without
     computing it, so it counts again exactly when the list grows. That needs a
     read of the kernel that records a dependency and does not evaluate. The cell
     files are sealed (`SEALING.md`), so it needs the owner's permission for the
     file that it changes.

   My recommendation is a, because it changes no sealed file and the cost is small.
3. **The card of a lazy list**, a helper of the example:
   `make_lazy_list_card(list, title)` answers a `WidgetCard` whose title reads
   "<title>, computed: N" and whose content is a `WidgetScrollPane` of the list,
   drawn by the chain of `make_lazy_projection_example`.
4. **`make_primes_around(n) -> ListNode`**, in `example/substrate/LazyDocumentExample.jl`.
   The node is the first prime that is not less than `n`. Each `next` is the next
   prime, and each `prev` is the prime before it, down to 2, whose `prev` is
   `nothing`. Each prime is found by a test of that number alone, trial division by
   the odd numbers up to its square root, so a node costs the same near one
   trillion as near ten.
5. **The sieve in the evaluator.** If the application can load
   `ProjecturedSubstrateExample`, the first form of the video is
   `using ProjecturedSubstrateExample`, which says honestly where the sieve comes
   from. If it can not, the step finds how the application gets the example
   functions, and the owner chooses.
6. **An infinite result.** A test evaluates a form whose value is an infinite
   `ListNode`, with no `;`, and checks that the evaluator draws a bounded window
   and does not hang. If it hangs, that is a fault of the evaluator to fix: a
   result with no end is drawn in a scroll pane of a fixed height.
7. **A list beside the evaluator.** The forms call
   `open_pane!(editor, card; target = …, side = :right)` for the first list and
   `side = :below` for the next ones. `open_pane!` moves the focus to the new tab,
   so the take clicks the prompt of the evaluator after each one. If the forms are
   too long to type, the example gives a short helper, and the owner chooses.

## Steps

- [x] 1. `count_computed_nodes`, with a test: a count before and after four links
  are read, a `next` that the count leaves not run, and a link held as a value.
- [x] 2. The owner chose design 2a, the label that reads the clock. The view is
  `make_lazy_list_view(list, title; clock)`: a `GridLayout` of one column, as the
  evaluator lays out its own rows, with the label in a `Content` row and the
  `WidgetScrollPane` of the list in a `Fill` row, because a `WidgetCard` with no
  height takes the height of its content and gives a scroll pane nothing to scroll
  against. `show_lazy_list!(editor, list, title; below)` opens it to the right of
  the evaluator, or under an earlier list, and gives the focus back to the
  evaluator, which it finds again by its title because the split moves it.
- [x] 3. `make_primes_around`, named with a verb as the naming rules ask, with a
  test of twenty primes each way around 1000 against a test that shares no code,
  the end at 2, and a start at one trillion that computes two links.
  `test_collection()`: 155 pass.
- [x] 4. The sieve in the scope of the evaluator (design 5): the form
  `using ProjecturedSubstrateExample;` works in the application window, so the
  video starts with it.
- [x] 5. The test of an infinite result (design 6). The evaluator does not hang,
  but it draws the result wrong: a bare `primes` gets a result row one line high,
  and the rest of the list draws over the next prompt and below it. The take does
  not meet this, because every form ends with `;`. The fix is not made; it is the
  owner's call, see "Open" below.
- [x] 6. The rehearsal, in a warm session, and the take script
  `tool/video/record_lazy_primes.jl`. What the rehearsal settled:
  - The count reads what the view read: 30 or 31 when the pane shows about 28
    rows, the rows on the screen and about one row past each edge. Five steps of
    the wheel add about 15.5, and a scroll back adds nothing.
  - The filter pulls from the sieve: while Sevens scrolls, the count of Primes
    grows, from 126 to 251 in the take.
  - The window starts with the Files pane closed (`prepare`, as the S2 take
    does, which sets the selection again after the close), and with no status
    bar, so each form fits on its line in the half of the window that the
    evaluator keeps.
  - With no `below`, `show_lazy_list!` places the lists by their order: the first
    to the right of the evaluator, the second under it, the third under the
    evaluator. The forms stay short, and the window is a grid of two by two.
  - The primes around one trillion are drawn from their first node, so the take
    scrolls up three steps, which shows the crossing of one trillion
    (999999999989, then 1000000000039), and then down.
- [ ] 7. The take is done: 92.2 s, `build/video/s11/s11_lazy_primes.mp4` of the
  worktree. The web page waits for the owner.

## Open

- **An infinite result in a result row.** A result whose graphics have no end
  needs a bounded window, such as a scroll pane of a fixed height. The result
  row passes the rest of a `result` path through to the document, so a wrapper
  there changes the mapping of the selection, and it needs the rules of
  `documentation/package/kernel/reference.md` and `selection.md`. The owner
  decides whether it is made, and when.

## Limits

- The sieve scrolls a few hundred primes at most in the video. Each prime adds one
  filter to the chain of the stream, so a far scroll makes the chain deep and slow.
- The faults of `make_lazy_bidirectional_document_example` stay as they are. S11
  does not use it.
