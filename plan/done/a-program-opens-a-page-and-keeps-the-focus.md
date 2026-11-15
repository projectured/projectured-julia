# A program opens a page and keeps the focus of the person

> Status: done 2026-10-28, landed on `main` as `31416bb2a`..`dad01a5df`. Written 2026-10-28 from
> `main` at `60a915abe`. Branch
> `open-page-places`, worktree `projectured-julia-open-page`. The owner agreed
> on 2026-10-28 to the change of §3 ("yes, let's do these").

## 1. The request

The plan [a-pane-is-placed-shown-and-focused-by-three-verbs.md](../done/a-pane-is-placed-shown-and-focused-by-three-verbs.md)
split the open of a pane into three verbs: `open_pane!` places, `show_pane!`
shows, and `focus_pane!` shows and moves the focus of the person. An agent never
calls `focus_pane!`. The plan left one open item: `open_page!`, the verb of an
agent that opens a part as a page, moves the focus of the person, and it can not
answer its tab.

## 2. Facts (2026-10-28)

- `open_page!(part)` evaluates `OpenPageOperation(nothing, get_reference(part))`,
  the operation of the command "Open as a page" of a person. That evaluation
  posts `make_open_pane_operation(Navigator(content, address); group =
  get_pane_file_group(; editor), focus = true)`, so the tab opens at the next
  frame and takes the focus (`NavigatorPageOpen.jl`).
- `open_page!` answers `Text("The page of … opens in a new tab.")`. It answers
  the same text when `_find_opened_content` finds no content and no tab opens.
- `open_pane!` evaluates its operation at once, with `focus = false`, and
  answers the new tab as a `ReferencedDocument`.
- `run_on_editor_task!` runs a nested call at once on the task that owns the
  editor, so `open_page!` can call `open_pane!` and `get_pane_file_group`.
- omnet has `OmnetPresentation.open_page!(shell, i)`, a different function of
  the catalog shell. This change does not touch it.

## 3. The change

- `open_page!` finds the content and the address with `_find_opened_content`,
  as the command does, makes `Navigator(content, address)`, and calls
  `open_pane!` with `group = get_pane_file_group(; editor)`. The tab is placed
  where the command places it, it does not take the focus, and the verb answers
  it, as `open_pane!` does.
- A part that no content of the window holds: `open_page!` throws an
  `ArgumentError`, and no tab opens.
- `OpenPageOperation` and the command "Open as a page" do not change: a person
  who opens a page gets the focus on it.

## 4. Steps

### Step 1 — the verb

- [x] `NavigatorPageOpen.jl`: the new body of `open_page!` and its docstring.
      The docstring example keeps the answer, `page_tab_1 = open_page!(…)`, and
      shows it with `show_pane!(page_tab_1)`.
- [x] `AssistantVerbsTest.jl`: the answer is a tab whose content is a navigator
      on the part; the page is there with no frame between; the selection of
      the person stays; `show_pane!` shows the tab. A reference that names a
      key the record does not have gives the `ArgumentError`; the test builds it
      with `extend_reference`, because `people[2]["missing"]` throws a
      `KeyError` before the verb runs.

### Step 2 — the guides

- [x] `orientation.md`, `navigator.md` and the system text of the assistant
      (`Application.jl`) say that `open_page!` answers the tab and moves no
      focus.
- [x] The open item of the plan of the three pane verbs names this plan.

### Step 3 — check

- [x] `test_assistant_verbs()` 83/83 (79 before: the old test had 3 checks,
      the new one 7), `test_open_page_operation()` 93/93,
      `test_referenced_document_editor()` 112/112, `test_search_corpus()` 6/6,
      `test_search_ranking()` 27/27, and `test_call_site()` 20/20, which reads
      the examples of the docstrings. One process, 2026-10-28.
