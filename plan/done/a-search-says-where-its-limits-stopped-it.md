# A search says where its limits stopped it

Status: DONE, 2026-10-19, on branch `search-limits` (from main `0d211e89f`).

## The ask

The owner, 2026-10-18, on the walk of the documents: "A search in a potentially
large data should be bounded by default but the user should be able to override.
So these are parameters, depth of search, do background work, number of items to
find, etc." The depth (`maxdepth = 64`) and the background work (`background =
false`) are keywords of the walk already. The number of matches is not.

The owner, 2026-10-19, chose option B: a limit of 100 matches by default, the
number of the search of the explorer, and each caller inside the editor that
needs every match asks for all. And: "the limits should be visible, either at the
search or at the result. The user should know that it's limited".

## The model

1. **A limit of matches.** `walk_document`, `search_documents` and
   `search_references` take `limit = 100`; `limit = nothing` finds every match.
   The walk stops when it found one match more than the limit, so it knows that
   the limit cut the answer, and it drops that match.
2. **The answer says which limit stopped the walk.** The answer is a
   `DocumentMatches`, a vector of the matches that also holds the limits and what
   each one left out:
   - the limit of matches, and whether it cut the answer;
   - the depth, and how many parts below it the walk did not enter;
   - the values that a task still computes, which a walk with no background
     work takes as they are, and how many it read.
   A value still to come is counted where the walk reads a cell: in a field of a
   document. An element of a collection is read through the collection, which
   answers its value and not its cell, so the walk neither counts nor waits for
   an element still to come; a background cell is a field today, such as the
   record of a result file.
   Its summary line, which the display of a vector prints first, names each limit
   that stopped the walk and the keyword that lifts it. An answer that no limit
   stopped prints as a vector does. The assistant sees a value through that
   display, so it reads the limits too.
3. **The callers that need every match** pass `limit = nothing`: the save of a
   binary file, the undo, the rows of a roster of the documents within items, the
   files of a window file, the code of a process, the paths of a layout, and the
   tools that collect the parts of a window. A caller that looks for one object,
   or asks whether any matches, keeps the default.

## Steps

1. [x] **The limits in the kernel and their callers.** `DocumentMatches` in
   `DocumentWalk.jl`, the keyword `limit`, the counts of the depth and of the
   values still to come; the docstrings of the three searches and the text that
   the assistant gets; `limit = nothing` at the callers of § The model, 3. Tests:
   `test_document_walk()` with a test of each limit and of the summary,
   `test_kernel()`, `test_platform()`, the assistant tests that read the docstrings
   (`test_referenced_document_editor()`), and the omnet campaign and IDE builds
   that walk in their precompile.
2. [x] **The guides:** `document.md` of the kernel and the guide of the assistant
   that names the search; the plan moves to `plan/done/`.

## As built

- `WalkLimits` holds the limits of one walk and what each one left out:
  `limit` and `is_limit_reached`, `maxdepth` and `depth_stop_count`, `background`
  and `provisional_count`. `DocumentMatches(matches, limits)` is an
  `AbstractVector`, so `==`, `isempty`, `first`, `only` and iteration work as for
  a vector; `setindex!` works, and a change of its length does not. Its
  `summary` names each limit that stopped the walk, and the plain-text display of
  a vector prints the summary first, which is the display that the tools of the
  assistant answer with. `is_search_complete(found)` answers whether no limit left
  a match out.
- A depth stop is counted at a node at the depth that has a part to enter: an
  element, an entry, or a field other than `selection` and `mouse_target`.
- The callers that pass `limit = nothing`: the undo (`UndoDocument.jl`), the
  roster of documents within items (`RosterSource.jl`), the files of a window
  file (`UserInterfaceFile.jl`), the save of a binary file
  (`BinarySerialization.jl`), the code of a process (`ProcessToJuliaCode.jl`),
  `show_layout` (`PaneProgram.jl`), the close of the tabs of a work item
  (`TaskVerbs.jl`), and the tools `rehearsal.jl` and `record_assistant_window.jl`.
  The text that the assistant gets says the default and how to lift it.
- omnet needs no change: its searches take the first path, ask whether any
  path exists, or answer nothing in a precompile workload.
- Tests (2026-10-19): `test_document_walk()` 56, `test_kernel()` 4,863,
  `test_platform()` 165,612 with 7 broken and no failure,
  `test_referenced_document_editor()` 111, `test_assistant_verbs()` 49.
