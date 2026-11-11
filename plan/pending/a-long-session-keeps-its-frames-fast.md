# A long session keeps its frames fast

**Status (2026-11-11): done on the branch.** All three steps are done. The
landing on main waits for the owner.

**Goal:** a view whose table builds a new list of rows at each refresh keeps no
row of an old list. So the frame statistics of a long session refresh as fast
as at the start, and the memory of the window does not grow with each refresh.

**Repository:** projectured-julia. The plan changes no file under
`source/kernel/`, and [SEALING.md](../../SEALING.md) seals only kernel files.

**Branch:** `long-session-fast-frames`, in the worktree
`../projectured-julia-long-session-fast-frames`.

## 1. The request

> do you have any idea why every second frame time may increase over a long
> session of the omnet IDE?

The owner showed the table of the frames of the statistics page at frame
55,570: every second or third frame took about 200 ms, of which about 175 ms
were in the part `feed`. At the start of the session these frames took about
30 ms. The owner then asked for the cause to be found and fixed in a branch.

## 2. What was found (main `3fd04ea4b`)

- The slow frames are the flushes of the `FrameStatisticsFeed`, at most one in
  each 0.25 s while the table is on the screen. A flush writes
  `statistics.frames` and `statistics.columns`, and each write visits every
  live reader of the cell.
- Each frame adds 9 readers to both cells, one for each label of its row and
  one for the flag of a slow frame, and no reader ever goes. A headless run of
  the statistics page measured this:

  | flushes | readers of `statistics.frames` | time of a flush | live heap |
  | --- | --- | --- | --- |
  | 1000 | 8,995 | 3.8 ms | 429 MiB |
  | 5000 | 44,995 | 28.4 ms | 2,136 MiB |
  | 10000 | 89,995 | 76.9 ms | 4,243 MiB |

- With a store of 20 frames, 1611 readers of frames that had left the store
  were still alive after 200 flushes. A search of the strong references from
  the editor found the holder: `_follow_output_list!` in
  [OutputSelection.jl](../../source/platform/focus/OutputSelection.jl) keeps
  one `followed` set for each lazy list of the output, for the life of the
  view. The table of the frames builds a new list of rows at each flush, with
  new nodes, so the set grows by the nodes that each flush builds and holds
  each node, its row and the readers of the row.

## 3. Decisions

- **D1 (proposed by the assistant).** The set stays: it stops a walk at a node
  that it followed already, also a node that a new head shares with the head
  before it, as a list does whose links are cells that hold their nodes. A
  `ListNode` is an immutable document, so a set with weak keys can not hold it.
- **D2 (proposed by the assistant).** When the holder of the list builds a new
  head, and the set grew to twice its length after the last sweep, the set
  keeps only the nodes that the new head reaches through links that are built.
  This is the rule of the readers of a cell (`_sweep_dependents!`). The walk of
  the sweep reads no link that is not built, so it builds no row. So the set
  holds at most about twice the nodes that the list links, and a sweep costs
  no more than the follows since the last one.

## 4. Steps

1. ~~The sweep of the followed nodes at a new head, in
   [OutputSelection.jl](../../source/platform/focus/OutputSelection.jl), and
   its rule in [focus.md](../../documentation/package/platform/focus/focus.md).~~
   **Done.** `_FollowedListNodes` holds the set and its length after the last
   sweep, `_follow_built_list_heads!` puts the computation around the holder,
   and `_sweep_followed_list_nodes!` keeps the nodes that the new head reaches.
   The minimum under which no sweep runs is 64 nodes. A table that builds 20 to
   30 rows at each refresh so keeps the nodes of its last few lists, not of two
   as first written.
2. ~~Tests: the walk lets the nodes of a replaced list go
   ([MouseTargetMoveTest.jl](../../test/platform/projection/MouseTargetMoveTest.jl)),
   and the readers of the statistics stay within the frames of the store
   ([FrameStatisticsFeedTest.jl](../../test/projectured/editor/FrameStatisticsFeedTest.jl)).~~
   **Done.** `WidgetTable` takes no `cells = nothing`, so the first test gives
   the table an empty list and puts the computation on its `cells` cell.
   `test_mouse_target_move` passes 88 of 88, and `test_frame_statistics_feed`
   passes 178 of 178 (Julia 1.13.1). The run of section 2 on main had 1795
   readers after 200 flushes with a store of 20 frames, above the bound of 360
   of the new test.
3. ~~The headless run of section 2 again, with the fix.~~ **Done.**

   | flushes | live readers of `statistics.frames` | entries of the list | time of a flush | live heap |
   | --- | --- | --- | --- | --- |
   | 1000 | 8,995 | 8,995 | 5.1 ms | 410 MiB |
   | 2000 | 9,004 | 12,856 | 11.5 ms | 491 MiB |
   | 3000 | 9,004 | 21,856 | 12.5 ms | 493 MiB |
   | 4000 | 9,004 | 18,004 | 9.4 ms | 493 MiB |
   | 5000 | 9,004 | 18,004 | 8.5 ms | 493 MiB |

   The live readers stay at the 1000 frames of the store, and the heap stays
   flat. The list of readers holds up to twice its live entries, because a cell
   sweeps its collected readers only when the list doubles; the time of a flush
   follows the entries of the list, so it stays between 8 and 13 ms.
