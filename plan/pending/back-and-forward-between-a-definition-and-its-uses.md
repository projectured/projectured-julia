# A person goes back and forward between a definition and its uses

> **Kind:** plan · **Status:** deferred, 2026-10-11. The owner asked for the
> plan and deferred it on the same day. Nothing is implemented. The questions
> of §8 are open. · **Stands on:**
> [navigator.md](../../documentation/package/platform/navigator/navigator.md),
> [filesystem.md](../../documentation/package/platform/filesystem/filesystem.md),
> [pane.md](../../documentation/package/platform/pane/pane.md),
> [julia.md](../../documentation/package/domain/julia/julia.md),
> [selection.md](../../documentation/package/kernel/selection.md),
> [a-navigator-with-back-forward-parent-and-links.md](../done/a-navigator-with-back-forward-parent-and-links.md)

Every file tab holds a navigator, and the navigator shows no bar until the first
visit. A jump to a definition is a visit that keeps the page and moves the
selection, so Back and Forward go between a definition and its uses. A Julia
file stays a file that a person edits.

## 1. The request

On 2026-10-09 the owner asked where the navigator is used, and whether every
pane must have one. Then the owner wrote:

> a Julia file is not for browsing, the user should be able to absolutely edit
> it but navigating backward/forward to and from deifnitions and use/call sites
> is useful

> what if a navigator would be there dormant and would not appear unless the
> first navigation is done and may disapper if you go back to the original
> document?

On 2026-10-11 the owner asked for this plan.

So:

- A file tab shows the whole file, and a person edits it as now.
- A person goes from a use of a name to its definition, and from a definition
  to its uses.
- Back and Forward go along these jumps.
- The navigator of a file tab shows no bar until the first visit. The bar hides
  again when the person goes back to the start.

## 2. The words of this plan

| Word | What it is |
| --- | --- |
| jump | a visit that keeps the page, or goes up only as far as needed, and moves the selection to a part |
| start | the first visit of a navigator: the back list is empty and the page is the root of the content |
| hidden bar | the view of a navigator at the start: the page and no bar |
| definition | a top-level statement that gives a name: a function, a struct, an abstract type, an assignment, a `const` |
| use | a `JuliaIdentifier` with the name of a definition, which is not the name in the definition itself |

This plan does not use the word "dormant" of the request for the hidden bar.
"Dormant" already names a selection that a document keeps while the live
selection is elsewhere ([selection.md](../../documentation/package/kernel/selection.md)),
and the find bar uses it so (`_find_dormant_caret` in
[FindBarViewGestures.jl](../../source/platform/widget/FindBarViewGestures.jl)).

## 3. What exists

- **A navigator opens only on demand.** The editor makes a navigator tab for an
  `OpenPageOperation` that no navigator takes
  ([OpenPageOperation.jl:79](../../source/platform/navigator/OpenPageOperation.jl#L79)).
  A link to a file opens `OpenFileOperation(path; file_wrap = Navigator)`, and the
  tab is `WidgetScrollPane(history(Navigator(file)))`
  ([FileSystemDocument.jl:103](../../source/platform/filesystem/FileSystemDocument.jl#L103)).
- **A plain file tab has no navigator.** The tabs at the start of the
  application ([Application.jl:102](../../source/platform/application/Application.jl#L102)),
  the Files pane and the menu Open
  ([FileDialog.jl:38](../../source/platform/shell/FileDialog.jl#L38)) make
  `WidgetScrollPane(file)`. The history is inside the file, around its content
  ([DocumentFile.jl:149](../../source/platform/fileformat/DocumentFile.jl#L149)).
- **A history around a navigator records the edits of every page.** A history
  inside the content does not record an edit on a page below the root (the
  limits of navigator.md). The tab of a linked file has the history around the
  navigator for this reason (Q10 of the navigator plan, option (a)).
- **A navigator records no move inside its page.**
  `make_navigator_open_operation` answers `nothing` when the new address has the
  steps of the page address
  ([NavigatorVisits.jl:111](../../source/platform/navigator/NavigatorVisits.jl#L111)).
  Back puts back the selection that a visit holds, when it still reaches a node
  of the page (`_find_visit_selection`).
- **A key of the navigator with nothing to do goes on.** `fire_gesture_bindings`
  goes to the next rule when a rule answers `nothing`, and answers `nothing` at
  the end ([GestureBinding.jl:108](../../source/kernel/binding/GestureBinding.jl#L108)).
  Back with an empty list answers `nothing`, so Ctrl+[ then reaches the next
  reader.
- **A link answers the target form of `OpenPageOperation`.** A markdown link
  answers `OpenPageOperation(nothing, EmptyReference(), place; target = link.url)`
  to Ctrl+click in the source view, as an `override` rule
  ([MarkdownLinkTarget.jl:22](../../source/domain/markdown/MarkdownLinkTarget.jl#L22)).
  The nearest navigator asks `find_navigator_target(content, target)`, whose
  default answers `nothing`
  ([OpenPageOperation.jl:74](../../source/platform/navigator/OpenPageOperation.jl#L74)).
  A navigator answers a target that names nothing with `DoNothingOperation`.
- **The Julia domain finds a definition by its name.**
  `find_julia_definition(document, name)` answers the one top-level definition
  called `name`, and throws an error when there is none or more than one
  ([JuliaFile.jl:111](../../source/domain/julia/JuliaFile.jl#L111)). The `definition`
  verb of the marker language uses it. `get_julia_definition_name` gives the name
  of a definition ([JuliaFile.jl:72](../../source/domain/julia/JuliaFile.jl#L72)).
- **A view that shows and hides a bar exists.** `FindBarViewToWidget` prints a
  `FindBarView` as a vertical layout whose list of children has no bar while the
  bar is hidden. The content is at `children[1].<rest>` then, and at
  `children[2].<rest>` while the bar is above it
  ([FindBarViewToWidget.jl](../../source/platform/widget/FindBarViewToWidget.jl)).
- **The navigator view is a grid.** `NavigatorToWidget` prints a `GridLayout` of
  the bar and a `VerticalLayout` that holds the page
  ([NavigatorToWidget.jl:69](../../source/platform/navigator/NavigatorToWidget.jl#L69)).
- **The slices load in an order.** `filesystem` and `shell` load before
  `navigator`, and `application` loads after it. The guard in
  [PlatformSuite.jl:102](../../test/platform/PlatformSuite.jl#L102) lists the
  slices that each slice can use. The list of `application` has no `navigator`.
- **A save finds the file through the layers.** `_find_tab_file` follows
  `get_edited_field` from the content of a tab to the file
  ([PaneFile.jl:38](../../source/platform/pane/PaneFile.jl#L38)). A scroll pane, a
  history and a navigator each answer `:content`.
- **I found no code that moves a scroll pane to the selection.** A data frame
  view moves its own `top_row`, and a scroll pane can follow its end. So a jump
  to a definition below the visible part of a file can leave the view where it
  is. Step 1 checks this in the live application.
- **Ctrl+click and F12 are free in a Julia view.** No rule of the Julia domain,
  of the syntax slice or of the text slice takes Ctrl+click or F12. The keyboard
  guide gives Ctrl+click to a link in a markdown or rst source view.

## 4. The design

### 4.1 Every file tab holds a navigator

A file tab is `WidgetScrollPane(history(Navigator(file)))`, the arrangement of a
linked file. With no settings, it is `WidgetScrollPane(Navigator(file))`. Q7 can
move the scroll pane into the navigator view. Q1 asks where this rule lives.

A tool tab gets no navigator. The Files pane, the assistant, the evaluator and
the logs show no pages that a person goes between.

For a person:

- Ctrl+Return and the menu items "Open as a page" and "Open in a new tab" work
  in every file tab.
- The history of the file records the edits on every page.
- Nothing shows until the first visit (§4.2).

For a program, a path into a file tab has one more step: `content` of the
navigator, after the history. A test, an example and a verb of the assistant
that write such a path change. About 20 test files of this repository and four
of omnet-julia name the shape of a file tab (step 4).

### 4.2 The bar shows after the first visit

`is_navigator_bar_shown(navigator)` is `true` when the back list holds a visit,
or when the page is not the root of the content. The value comes from fields
that exist, so the navigator gets no new field. Q2 asks about the forward list.

The view arranges the bar and the page as `FindBarViewToWidget` arranges the
find bar: a vertical layout whose list of children has the bar only while it
shows.

```
bar shown    children[1].<rest>                 the bar
             children[2].children[1].<rest>     the page
bar hidden   children[1].children[1].<rest>     the page
```

The maps put these steps before a path in the page and take them off, as they
do now. A vertical layout prints its children again when its list changes, so
the change of the list shows or hides the bar. A navigator that an open makes
at an address below the root shows its bar from the start, because Parent is
useful there.

### 4.3 A jump keeps the page

`make_navigator_jump_operation(navigator, selection)` makes a visit whose
selection is `selection`, a path from the content. The page of the visit is the
longest prefix of the current page address that `selection` starts with. That is
the current page when it holds the part, and otherwise the nearest page above it
that holds the part. The current visit goes on the back list, and the forward
list is cleared, as for an open. The builder answers `nothing` when `selection`
is the selection that the navigator has now.

Back returns to the visit before, with the selection that the visit holds. The
code of the visits does this now.

An `OpenPageOperation` asks for a jump with a new place, `:in_page` (Q3). The
nearest navigator makes the jump. With no navigator, the editor selects the part
and records no visit, so a jump also works in a tab with no navigator.

### 4.4 A use goes to its definition

The Julia domain answers `find_navigator_target` for `JuliaFile` and
`JuliaDocument`. The target is a name. The answer is the path to the name of the
top-level definition with that name, or `nothing` when the file has no such
definition. It throws no error, which `find_julia_definition` does.

A `JuliaIdentifier` answers two gestures with
`OpenPageOperation(nothing, EmptyReference(), :in_page; target = name)`:

- Ctrl+click, an `override` rule, which takes the click from the caret of the
  text, as a markdown link does in its source view;
- F12, with the selection on the name.

A name that the file does not define, such as a local variable or a function of
`Base`, gets `DoNothingOperation` from the navigator, as a link to an unknown
target does now. Q4 asks about a name with several definitions.

### 4.5 A definition goes to its uses

The uses of a name are the `JuliaIdentifier`s of the file with that name, less
the name of the definition. A search by name also finds a local variable of the
same name. The bound code of
[bound-julia-code-stores-each-name-once.md](bound-julia-code-stores-each-name-once.md)
removes this error, because each use holds its binder there.

Shift+F12, and Ctrl+click on the name of a definition, open a list of the uses
at the name. The list opens in the window of the context menu, as the list of
choices of the address does. A press on a row, or Return, makes the jump to that
use. The list of choices of the address holds steps of one place, and a use is a
whole path, so the list needs a form that holds paths. Q5 asks about the list.

### 4.6 The bar stays in view

The scroll pane of a file tab is outside the navigator, so the bar scrolls away
with the page. After a jump far down a file, the bar is not in view. Q7 asks how
to keep it in view.

### 4.7 The view follows the selection

After a jump, the part must be in view. §3 found no code that moves a scroll
pane to the selection. Q8 asks where this belongs.

## 5. Steps

Each step is one commit in a worktree. The plan records each fact that a step
finds, and marks the step done.

- [ ] **1. Check the facts in the live application**, in a fresh process. Open a
  markdown file with a link to another file, and follow the link:
  - Does the bar scroll away with the page?
  - Does a caret move below the visible part scroll the view?
  - Does Ctrl+Z take back an edit on a page below the root?
  Record the answers in §3.
- [ ] **2. The hidden bar** (§4.2), after Q2. `is_navigator_bar_shown`, and the
  view as a vertical layout. Tests: `test_navigator_to_widget()`,
  `test_navigator_gestures()`, `test_open_page_operation()`. Document:
  navigator.md.
- [ ] **3. The jump** (§4.3), after Q3. `make_navigator_jump_operation`, the place
  `:in_page`, and the jump with no navigator. Tests: `test_navigator_visits()`,
  `test_open_page_operation()`. Document: navigator.md.
- [ ] **4. Every file tab holds a navigator** (§4.1), after Q1. Tests:
  `test_application()`, and each test that names the shape of a file tab:
  `ApplicationTest.jl`, `WindowShellTest.jl`, `PaneGestureTest.jl`,
  `PaneReaderTest.jl`, `TabsWrapperTest.jl` and the others that
  `grep -rln "OpenFileOperation\|make_file_tab_content\|tabs\[[0-9]*\]\.content" test`
  lists. In omnet-julia: `IdeNavigatorTest.jl`, `IdeTextClipboardTest.jl`,
  `IdeSelectAndPasteTest.jl`, `PaneProgramTest.jl`. Documents: filesystem.md,
  navigator.md, pane.md, keyboard-and-mouse-guide.md.
- [ ] **5. The bar stays in view** (§4.6), after Q7.
- [ ] **6. A use goes to its definition** (§4.4), after Q4. Tests: a new test in
  `ProjecturedJuliaTest`, on the model of `test_markdown_link_target()` and
  `test_markdown_link_gestures()`. Documents: julia.md,
  keyboard-and-mouse-guide.md.
- [ ] **7. The view follows the selection** (§4.7), after Q8, if Q8 keeps it in
  this plan.
- [ ] **8. A definition goes to its uses** (§4.5), after Q5.

Steps 2 and 3 change only the navigator. Step 4 changes every file tab, so it
comes after the bar can hide.

**The test of the whole chain.** One test drives an `Editor` with a Julia file
tab:

1. Ctrl+click on a use. The selection is on the name of the definition, and the
   bar shows.
2. Ctrl+[. The selection is on the use again, and the bar is hidden.
3. Ctrl+]. The selection is on the definition again.
4. An edit, then Ctrl+Z. The history of the file takes back the edit, and the
   visits stay.

A test of one stage does not find an error in the chain of the stages, so this
test drives the editor and reads what the view shows.

## 6. Limits of this plan

- One file. A definition in another file is Q6.
- Top-level definitions only. A local variable and an argument have no
  definition here until the bound code exists.
- The uses are found by their name.

## 7. What a step must not change

- Undo records no visit and no jump: the writes of a visit are view state
  (`ReplaceViewStateOperation`).
- The navigator names no domain. The Julia domain answers
  `find_navigator_target` and the gestures of a name.
- The address stays apart from the selection. A caret move makes no visit. Only
  a jump that a person asks for makes one.

## 8. Questions for the owner

Each question gives my recommendation. It is mine, not a decision.

- **Q1. Where the rule "every file tab holds a navigator" lives.** The
  `filesystem` and `shell` slices load before the `navigator` slice, so they
  cannot name `Navigator`. The Files pane belongs to `filesystem`, and the menu
  Open to `shell`.
  - (a) The `filesystem` slice keeps a list of wraps for an opened file, and the
    `navigator` slice adds `Navigator` to it when it loads, as
    `register_natural_syntax!` fills the natural registry. Every program that
    loads the platform gets a navigator in each file tab, and no opener names
    it.
  - (b) Each opener passes `file_wrap = Navigator`. The application can do it
    for its start tabs when its guard lists `navigator`. The Files pane and the
    menu Open each need a parameter that the application fills. A program that
    opens a file with no such parameter gets a tab with no navigator.
  - (c) The `navigator` slice loads before the `filesystem` slice. A link to a
    file then cannot answer `OpenFileOperation` from the navigator, so it needs
    another way.

  My recommendation: (a). A file tab gets the capability with no flag, and no
  opener can forget it. It is a new registration point, so it needs your word.
- **Q2. Forward after Back to the start.**
  - (a) The bar hides. Ctrl+] and the side button of the mouse still go forward.
  - (b) The bar stays while the forward list holds a visit.

  My recommendation: (a), as the request says: "may disapper if you go back to
  the original document".
- **Q3. How an open asks for a jump.**
  - (a) A new place of `OpenPageOperation`, `:in_page`, beside `:here` and
    `:new_tab`. The flow, the target and the registration stay.
  - (b) A new operation type with the same flow.

  My recommendation: (a). Q4 of the navigator plan chose the target form of
  `OpenPageOperation` over a new type for the same reason.
- **Q4. A name with several definitions**, such as the methods of one function.
  - (a) The first definition in the file.
  - (b) The list of §4.5, with the definitions.
  - (c) Each Ctrl+click goes to the next definition.

  My recommendation: (a) in step 6, and (b) when the list of step 8 exists.
- **Q5. The list of uses.** The gestures: Shift+F12, and Ctrl+click on the name
  of a definition. A row shows the statement that holds the use. The list is a
  new form beside the list of choices of the address, because it holds paths.

  My recommendation: as written.
- **Q6. A definition in another file.**
  - (a) The navigator takes the other file as a new content, as a visit can do
    now. The tab then shows a file that its name does not give, and
    `_find_tab_file` answers the other file, so Ctrl+S saves that file.
  - (b) The tab of that file opens or takes the focus, and a list for the whole
    window holds the jumps between tabs.

  My recommendation: decide later. `find_julia_definition` finds nothing in
  another file now, and the bound code reaches the files of one module at its
  stage 2.
- **Q7. The bar stays in view.**
  - (a) The navigator view puts its page in a `WidgetScrollPane`, and a file tab
    with a navigator has no scroll pane outside it. The scroll is then made
    where the page is made. The rule of 2026-09-25 asks for that: a content
    scrolls where it is made, and a tab page has no scroll by default. A page
    with a scroll pane of its own, such as the form of a data frame row, then
    has one scroll pane in another.
  - (b) The file tab keeps its scroll pane, and the bar scrolls away. The keys
    and the side buttons of the mouse still work.

  My recommendation: (a). It changes the limit "The navigator puts no scroll
  pane around its page" of navigator.md.
- **Q8. The view follows the selection.** Every scroll pane needs this, also for
  an arrow key below the visible part.
  - (a) A step of this plan.
  - (b) A plan of its own, which step 7 waits for.

  My recommendation: (b), if step 1 shows that a caret move does not scroll
  the view now, because then every file has the problem.

## 9. Considered and not proposed

- **A navigator in every pane, tool panes too.** The Files pane, the assistant
  and the evaluator show no pages that a person goes between.
- **A list of jumps for the whole window, now.** An IDE keeps one list for the
  window, because a jump often goes to another file. For one file, the navigator
  of the tab holds the jumps with the code of the visits that exists. Q6 can
  bring the list for the window.
- **The grid with an empty bar.** The page keeps the same path in both states.
  But the hidden bar keeps the gap of the grid, and the find bar view already
  shows the form of a list that changes.
- **A jump with no visit, and a list of selections beside the navigator.** It
  repeats the back and the forward list of the navigator.
- **The definition alone as a page**, as "Open as a page" shows it. The owner
  wants a Julia file to stay a file that a person edits. "Open as a page" stays
  for a person who wants the function alone.
