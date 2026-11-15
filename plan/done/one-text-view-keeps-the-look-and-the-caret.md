# One text view keeps the look and the caret

**Status:** done on 2026-11-15, and not landed. The owner approved the plan on 2026-11-15 ("Üres", then "That is yes on a
Hungarian keyboard"). Steps 1 to 4 are done on the branch `views-compose`, which
holds `main` at `6a24a6db6`. The landing and the push each wait for the owner.

This plan is point 1 of the order in
`plan/tentative/content-and-view-for-the-whole-project.md`. The owner approved
that order on 2026-11-15 ("Yes, that's good plan"). The plan brings the branch
`views-compose` up to `main`, makes one `TextView` from the two that exist, and
ends with a request to land. It lands nothing and pushes nothing.

## The problem

Two types have the name `TextView`. Both are in
`source/platform/text/TextView.jl`.

| | `main` (`a055cf397`, 2026-11-05) | Branch `views-compose` |
| --- | --- | --- |
| Fields | `content`, `wrap`, `line_spacing` | `viewed`, `closed_folds` |
| State of one view | The look | The caret, the part under the pointer, the folds |
| Caret | In the `TextBlock`. The view names it through the step `content`. | In the view, as a flat place |
| Printer | `TextViewToGraphics`: puts the look in the context; `TextToGraphics` draws the caret of the block | `TextViewToGraphicsCanvas`: draws the caret of the view over the lines |
| Who makes one | A widget, for its text: a text field, a text area, the name of a tab | `make_content_view`, and a viewing step for its output |

```julia
block = TextBlock(TextLine(TextString("alpha beta")))

# main now
view = make_text_view(block; wrap = true)
block.selection     # {3}           the caret is in the block
view.selection      # .content{3}   the view names the caret of the block

# branch now
view = TextView(block)
view.selection      # {3}           the caret is in the view
block.selection     # nothing
```

## The decision that exists

The two types are two halves of one design, on purpose. The plan that made the
type of `main` (`plan/done/the-window-has-one-system-for-space.md` on `main`)
records it:

- "The user asked for the smallest form now: the selection still goes down into
  the `TextBlock`, and the plan `views-compose-as-content-composes.md` gives the
  view its own caret later."
- "It has the name and the field `content` of the `TextView` of the branch
  `views-compose`, so that plan only moves the caret into it and adds the folds."

Decision 19 of the pilot (the owner, 2026-11-14) gives the name of the field: a
view keeps what it shows in the field `viewed`.

So the question "which `TextView`" has an answer: one type, with the look of
`main`, the caret and the folds of the branch, and the field `viewed`.

```julia
# after this plan
@document struct TextView <: ContentView
    viewed::TextBlock
    wrap::Bool = false
    line_spacing::Any = SingleSpacing()
    closed_folds::Any = nothing
end

view = TextView(block; wrap = true)
view.selection      # {3}           the caret of this view
block.selection     # nothing       a block under a view holds no caret
```

## Proposed decisions

These are proposals of the session, not answers of the owner. The approval of
the plan approves them.

1. **The caret is in the view for every `TextView`, the text of a widget too.**
   A widget keeps its own caret as on `main`. It computes the caret of the view
   from its own caret, where it computes the caret of the block now. The block
   that a widget makes for its text holds no caret. The widgets get no view
   types in this plan.
2. **One printer, `TextViewToGraphicsCanvas`.** It puts the look of the view in
   the context of its content, as `TextViewToGraphics` of `main` does. It draws
   the band and the caret of the view over the lines, and it reads the keys of
   the view, as the printer of the branch does. `TextViewToGraphics`,
   `TextViewToGraphicsIoMap` and `make_text_view` of `main` go.
3. **The lines under a view print with no caret, and they can wrap.** The row
   of the widget table becomes
   `TextView => NestingProjection(TextViewToGraphicsCanvas(), ChainingProjection(WordWrapping(; measure), TextBlockToGraphicsCanvas(; measure)))`.
   The printer maps the caret of the view through each IO map of its content to
   the marks. The printer of the branch accepts only a content that
   `TextBlockToGraphicsCanvas` prints with no stage before it.
4. **`TextToGraphics` stays** for a text with no view. 181 chains use it. The
   split of its file into the drawing of the lines and the marks of the caret
   is made again on the file of `main`.
5. **The branch takes `main` by a merge, not by a rebase.** A rebase writes 22
   commits again, and 6 of them change `TextView.jl`. No commit between the
   first and the last would load with the widget code of `main`. A merge keeps
   the commits that the tests passed, and it resolves each conflict once.
   `main` has a merge of this kind (`660b68779`, "merge: main into
   one-system-for-space"). The landing is then a fast-forward of `main`.
6. **The guides of the pilot are step 4 of this plan.** Step 9 of
   `views-compose-as-content-composes.md` must describe the one `TextView`, so
   it runs after the merge.

## Facts of the trial merge

A merge in memory (`git merge-tree`, no branch changed), `main` at `8541a3592`,
`views-compose` at `c5f9be2a6`:

- The branch has 23 commits that `main` does not have. `main` has 1227 that the
  branch does not have.
- One commit of the branch, `7f9ee4c52` (the names of the checkouts), is on
  `main` as `d2ab6c2cb`. The side of `main` wins in its files: the build guide,
  `mcp.md`, `BuildCommand.jl`, `ClaudeCodeAcpProgram.jl` and the manifest.
- 13 more files conflict:

  | File | Hunks | Lines |
  | --- | --- | --- |
  | `source/platform/text/TextToGraphics.jl` | 14 | 326 |
  | `source/platform/text/TextView.jl` | 1 (both files whole) | 324 |
  | `source/platform/text/TextDocument.jl` | 4 | 78 |
  | `source/platform/syntax/SyntaxDocument.jl` | 2 | 56 |
  | `source/platform/clipboard/ClipboardSliceToAny.jl` | 3 | 48 |
  | `source/platform/text/TextFolding.jl` | 2 | 29 |
  | `source/platform/text/TextModule.jl`, `source/domain/markdown/MarkdownModule.jl`, `package/ProjecturedExample/src/ProjecturedExample.jl` | 4 | 22 |
  | Four test suite files | 5 | 45 |

- `main` changed 918 lines of `TextToGraphics.jl` since the base; the branch
  changed 150.
- The merge shows no conflict in the widget code, but that code must change:
  `source/platform/widget/WidgetToGraphics.jl` names the type of `main` at three
  places (the text of a field, the name of a tab, the row of the table) and
  reads the step `content` in four helpers.
- `omnet-julia` and `inet-julia` do not name `TextView`, `make_text_view` or
  `TextViewToGraphics`.
- No other open branch of this repository changes the text slice or
  `WidgetToGraphics.jl`.

## Steps

- [x] **1. Merge `main` into `views-compose`.** Done 2026-11-15; the record is below. The merge commit has one
  `TextView` type with the four fields. For this step only, the two printers
  stay, each with its caret rule: the printer of `main` for the text of a
  widget, with the step `viewed`, and the printer of the branch for the views.
  The split of `TextToGraphics.jl` is made again.
  Tests: the view tests of the pilot (`TextViewTest.jl`, `SyntaxLeafViewTest.jl`,
  `SyntaxNodeViewTest.jl`, `JsonViewTest.jl`, `MarkdownViewTest.jl`,
  `MarkdownJsonViewTest.jl`, the selection test, the clipboard test), the text
  tests of the widgets of `main` (`WidgetTextEditTest.jl`, `WidgetTextWrapTest.jl`,
  `WidgetTextFitTest.jl`, `SlotSpaceTest.jl`), the layer guards and the naming
  guard.
- [x] **2. One printer and one caret rule** (proposed decisions 1, 2 and 3). The
  text of a widget keeps its caret in the view. The printer and the helper of
  `main` go.
  Tests: the tests of step 1, and a real editor: a text field and a text area
  that take typed text, a caret move, a range by the mouse, a wrap, a cut text
  with the caret at its end, and a caret that stays in view; the name of a tab.
- [x] **3. The wide check.** Done 2026-11-15; the record is below. `test_platform()`, `test_json()`, `test_markdown()`,
  the umbrella suites that the pilot touched, and the sweep of the examples,
  against the known failures of `main`. A new record of the precompile
  statements. `Pkg.precompile` of `omnet-julia` against the branch. If a
  released version exports a name that goes, the version takes a minor step.
- [x] **4. The guides.** Done 2026-11-15; the record is below. Step 9 of the pilot plan, with the one `TextView`: the
  guides of the text, the widgets, the syntax, JSON and Markdown, and the rule
  "Content documents and view documents". Both plans move to `plan/done/`. Then
  the session asks for the landing, and for the push apart.

## Step 1: what the merge made

- **The files of the setup commit** take the side of `main`: the build guide,
  `mcp.md`, `BuildCommand.jl`, the manifest, and `ClaudeCodeAcpProgram.jl`, which
  `main` removed.
- **`TextView.jl`** has the one type, `TextView(viewed, wrap, line_spacing,
  closed_folds) <: ContentView`, and the two printers of this step.
  `make_text_view` and `TextViewToGraphics` name the step `viewed`. The key table
  of a view has each row of the key table of a `TextBlock`, also the rows that
  `main` added: Tab, Shift+Tab, Ctrl+Backspace, Ctrl+Delete and Ctrl+A. The key
  helpers of `main` take the caret as an argument, as the helpers of the pilot do.
- **`TextToGraphics.jl`** is the file of `main` with the split made again.
  `_print_text_lines(p, spacing, styled, space)` lays out the lines and reads no
  selection. `_make_selection_marks(p, overlay, is_live, space)` makes the band and
  the caret. The readers that `main` added are shared too: the press, the drag, the
  word and the line at a point, and the page keys take the layout of either
  printer, and `_find_pointer_selection` takes the caret as an argument.
- **`TextBlockToGraphicsCanvas`** has the fields that the layout of `main` reads:
  the color of plain text, and in its IO map the line spacing, the places of the
  lines, the space around the text and the height that shows.
- **`TextFolding.jl`**: `_fold_text` gives the places of the lines that `main`
  added, so the fold of a view and the fold of a block share them.
- **`SyntaxDocument.jl`**: the key helpers of the pilot stay, with the rule of
  `main` for a plain Left and Right in `_navigate_selected_syntax_node`, and the
  row Ctrl+A of `main`.
- **The clipboard**: a paste of the same view is a placed edit, which
  `_read_paste` reads down to its place, as each paste of `main` is.
- **A view answers `has_reference_step_child`.** `main` added this question to
  the reference layer: does a step have a child in a document. A view answers it
  as it answers the evaluation of a step: for a field that it does not have, its
  content answers. Without it, each path of a view that names a field of the
  content failed the check of a selection.
- **A name clash that the merge did not show.** Both sides had an example
  function `make_text_view_document_example`. The example of the pilot, one text
  in two views at three places, is now `text_view_places`:
  `make_text_view_places_document_example`, `make_text_view_places_projection_example`
  and `text_view_places_example`, in `TextViewPlacesDocumentExample.jl` and
  `TextViewPlacesProjectionExample.jl`.
- **Tests that followed `main`.** A layout of `main` draws its children in a
  canvas of their own, with the ring of the selection beside it, so four tests
  find a place at `output.elements[1].elements[k]`. The helper that collects IO
  maps skips a dictionary: the layout of the lines of `main` keeps cells in one,
  and a cell of a line that is gone throws when it is read.

- **The key tables of the syntax views** have the row Ctrl+A of `main`, and
  their plain arrows use `_navigate_selected_syntax_node`, as the tables of the
  content do.
- **A paste selects a pasted view as a whole.** This is a change that a person
  sees. Before the merge, a view that a paste put in kept a live caret. That was
  an accident: the last selection write of a paste used the path object of the
  stored selection, so it wrote nothing. On `main`, a paste goes down to its place
  with a new path, so that write has its effect, and the tests of `main` fix the
  form of the operation: a paste selects what it puts in as a whole. The merge
  keeps the rule of `main` for a view too. The copy of the caret waits in the new
  view as a dormant one. The other way, a paste that keeps the caret of a view
  live, needs a rule for views only in the clipboard, and it is not built.
- **A cut asks the owner of a list.** The cut of `main` took an element out of a
  list with no question to the owner of the list, so a cut inside a view took a
  child view out of the list of the view, which must follow the content.
  `_make_whole_delete` now asks `_is_slot_accepting` for the slot, as a paste
  does. A view owns no place, so a cut inside a view does nothing, as before the
  merge. A cut of a view that is an element of a layout takes the element out of
  the list, which is the rule of `main`; before the merge it left an empty
  document.
- **Tests, 2026-11-15, Julia 1.13.1, in a process for each set.**
  - The text of both sides (`test_platform_layering`, `test_text_to_graphics`,
    `test_word_wrapping`, `test_text_folding`, `test_text_view`,
    `test_syntax_leaf_view`, `test_syntax_node_view`, `test_widget_text_editing`,
    `test_widget_text_wrap`, `test_widget_text_fit`, `test_slot_space`,
    `test_clipboard`): 922 pass, 5 fail. The 5 are known failures of `main`: the
    two sets of the layer guard, with the same 10 entries as on `main`, and the
    cut of a range in `ClipboardTest.jl` (lines 502 to 504).
  - The domains and the umbrella (`test_selection`, `test_json`, `test_markdown`,
    `test_markdown_json_view`, and `test_printer` of the seven view examples):
    16160 pass, 0 fail.
  - The naming guard passes.
- **Left for step 3:** 186 of the 737 recorded precompile calls of
  `ProjecturedJSON` do not resolve after the merge, so the package compiles more
  while it runs until the record is made again.

## Step 2: what the one printer made

- **`TextViewToGraphicsCanvas` is the one printer of a text view.** It prints the
  content of the view through the recursion, in a context that holds the look: the
  line spacing of the view where it sets one, and a free width when the view does
  not wrap. It draws the band and the caret of the view over the drawing. Its
  readers are those of `main` for a text: the keys of the table of the view, the
  keys that read the layout (Up, Down, Home, End and the page keys), the press
  that puts the caret and starts a drag, the drag, and the word and the line of a
  double and a triple click. The print of the content is in a cell, so a change of
  the look prints the content again, as on `main`.
- **The content of a view can have stages before the lines.** The last stage is
  `TextBlockToGraphicsCanvas`. The printer maps a place of the view forward
  through each stage before it to the lines, and reads an answer back through
  those stages (`_find_text_layout`, `_map_to_layout`, `_read_from_layout`).
  `WordWrapping` moves no place, so its maps give each place as it is.
- **`line_spacing` of a view is `nothing` when the view sets none.** Then the
  printer of the lines gives its own spacing, or the context does. A view that a
  stage of the pilot makes for a text of code must not force single spacing. The
  text of a widget sets its spacing as on `main`.
- **The text of a widget keeps its caret in its view.** `_make_widget_text_view`
  sets the caret and the part under the pointer of the view from those of the
  widget, and the block that the widget makes holds none. The name of a tab does
  the same. A widget reads a flat place of the view where it read a place of the
  block behind the step of the view; `_strip_text_view_step` is gone.
- **Removed:** `make_text_view`, `TextViewToGraphics` and `TextViewToGraphicsIoMap`.
  The row of the widget table is
  `TextView => NestingProjection(TextViewToGraphicsCanvas(; theme = text_theme), ChainingProjection(WordWrapping(; measure), TextBlockToGraphicsCanvas(; measure, theme = text_theme)))`.
- **Tests, 2026-11-15.**
  - The text of both sides, the set of step 1: 922 pass, 5 fail, the same 5 known
    failures of `main`.
  - The whole suite of the platform (`test_platform()`): 235562 pass, 13 fail, 22
    broken. Each of the 13 is in code of `main` that this plan does not change:
    the two sets of the layer guard (the same 10 entries); three edges between
    slices that the files of `main` have (`ConversationModule` to `SettingsModule`,
    `SyntaxModule` to `FocusModule`, `UndoModule` to `LayoutModule`); four
    assertions of `NavigatorChoicesTest.jl` (lines 174, 178, 208, 211); the cut of a
    range in `ClipboardTest.jl` (lines 502 to 504); and `FileDialogTest.jl` line
    138. They are named by their entry, and not by a run of the suite on `main`.
  - A real editor with a headless backend and real mouse and key events: 21 of 21.
    A press puts the caret in the view and the block holds none; typed text, Right,
    End, Shift+Left, Backspace; a double click selects a word; a press and a drag
    make a range; in a text area, Down goes to the next line and Return makes a
    line; a field of 120 pixels with a text of 187 draws the text 69 pixels to the
    left so the caret at its end shows; a text wider than the window wraps to two
    rows. The name of a tab has no real editor check; `WidgetTabLabelTest.jl` and
    `PaneRenameTest.jl` of the platform suite cover it.
  - The domains and the umbrella, the set of step 1: 16202 pass, 0 fail.
  - The naming guard passes.

## Step 3: what the wide check found

- **`main` moved two times while the plan ran, so the branch has three merges.**
  The merge of step 1 took `main` at `8541a3592`. The second merge took `main` at
  `3a9b4fae4`, 12 commits that give each file of the editor one document, with one
  conflict in the import lines of `MarkdownModule.jl`. The third merge took `main`
  at `6a24a6db6`, 4 commits that make an image hold its picture file, with two
  conflicts: the same import lines, and the guide of Markdown, which keeps the
  section on images of `main` and the section on views of the pilot. After the
  third merge, `main` has no commit that the branch lacks.
- **The wide check ran on the branch after the second merge**, as four jobs:
  - The suites of the kernel, of JSON, of Markdown and of the data frames, the view
    test of the umbrella and the print of the seven view examples, in one process:
    21944 pass, 2 fail, 2 broken. The first failure is `BuildEditorTest.jl` line
    257, which fails only when other test packages are in the process: the kernel
    suite in a process of its own gives 5179 pass, 0 fail, 2 broken. The second is
    the layer guard of Markdown, for the line
    `using ..NavigatorModule: find_edited_document_target`. `main` had that line at
    `3a9b4fae4` and has none at `6a24a6db6`, and the third merge takes that.
  - `test_platform()`: 236250 pass, 14 fail, 22 broken. They are the 13 failures of
    step 2 and one more edge between slices, which a file of `main` has since the
    second merge: `FileSystemModule` to `SettingsModule`.
  - The sweeps of every example of the umbrella: the printers 1108671 pass; the
    readers 32660 pass; the position navigation 9418 pass, 5 broken; the REPL walk
    31881 pass, 313 fail, 8 broken.
  - The real editor check of step 2: 21 of 21.
- **The 313 failures of the REPL walk are failures of `main`.** They are in two
  examples: YAML, 107 of 230 events, and the graph, 206 of 230. The same walk on a
  clean worktree of `main` at `6a24a6db6`, with the same Julia, gives the same
  counts and the same first events. In the YAML example a typed `0` replaces an
  entry of a mapping by a number, when the caret is on a part that the printer of
  the entry introduced. In the graph example a plain Insert reaches the XML vertex,
  which does not hold the caret, and adds an insertion that the example prints
  with no row. The registry of the known REPL failures (`repl_broken`) does not
  name them, and this plan does not change that.
- **The check of the third merge.** `test_markdown()`, `test_rst()`, `test_book()`,
  the view test of the umbrella and the print of its example, `test_image()` and
  `test_file_change_store()`: 3424 pass, 0 fail.
- **The recorded precompile calls of five packages are recorded again.** A load of
  every package on the branch gave the warning of a stale list for five packages:
  `ProjecturedJSON` (183 of 737 calls did not resolve), `ProjecturedJulia` (587 of
  2930), `ProjecturedMarkdown` (104 of 846), `ProjecturedChart` (65 of 613) and
  `ProjecturedLanguageServer` (2 of 17). `main` gives it for `ProjecturedChart`
  only (62 of 613). Most of those calls name a generated keyword function of a
  module of the platform by its number, such as `var"##TextGutterToGraphics#289"`,
  and the number moves when the module gets code before that function. The JSON
  types of the pilot also have other type parameters, because the field
  `collapsed` is in the view. `record_package_calls!` wrote the `workload.txt` of
  each of the five again. After it, a load of every package gives no such warning.
- **No package takes a minor step for a removed name.** The branch removes three
  exported names of `ProjecturedPlatform`: `make_text_view`, `TextViewToGraphics`
  and `TextViewToGraphicsIoMap`. They came to `main` on 2026-11-05, after the last
  release of the platform (0.3.0, 2026-10-22), so no released version exports
  them.
- **Found, and not decided: the field `collapsed` of the JSON types.** The pilot
  takes the field `collapsed` from `JsonArray`, `JsonObjectEntry` and `JsonObject`,
  because a fold is state of a view (decision 14 of the pilot plan). The released
  `ProjecturedJSON` 0.1.2 has that field and the keyword of the constructors. The
  release generator compares the exported names and finds no lost name there, so
  it gives `ProjecturedJSON` a patch step. A recommendation of the session, which
  the owner did not decide: `ProjecturedJSON` takes a minor step at its next
  release, as a renamed theme field gave one in decision R36 of the release plan.
  The versions are given at release time, so the landing does not wait for it.
- **The repositories that use the platform.** `omnet-julia` at `6b6375c93` and
  `inet-julia` name none of the three removed names, `TextView`, or the field
  `collapsed` of a JSON type. `Pkg.precompile()` of the environment
  `environment/all` of a copy of `omnet-julia`, in which each path of
  `projectured-julia` leads to the branch, compiles the 75 packages of
  `omnet-julia` with no error: no import of a name that is not there, and no
  method that a package writes over. It took two runs, because a memory cap of
  6.3G stopped the workload of `OmnetPresentationExample` in the first, and
  `Pkg.precompile()` then ended with no error and without the 12 packages after
  it. A cap of 13G was enough (peak 9.8G). Two recorded lists of `omnet-julia`
  give the warning of a stale list against the branch: `OmnetLegacyFormat` (427 of
  3675 calls) and `OmnetPresentationExample` (2231 of 8411). The second is stale
  on `main` too (1822 calls at `5f2bdab54`, by the record of another session). The
  count of the first on `main` was not measured. `inet-julia` was scanned for the
  names and not compiled.

## Step 4: what the guides say

- **Eleven guides follow the views and the one `TextView`:** `concepts.md`,
  `engineer-tour.md`, the rule "A type that has views" in `architecture-rules.md`,
  `selection.md` ("A selection through views"), `projection-system.md` ("Views in
  a chain"), and the guides of the text, the widgets, the syntax, JSON, Markdown
  and the clipboard. This is step 9 of the pilot plan, with the guides of the
  widgets and of the clipboard added, because step 2 of this plan and the rule of
  a paste change them.
- **Each statement was read against the source.** Five were corrected: two
  sentences that told what the code was before, one sentence that the source does
  not show, one example with a chain too many, and the statement on the fold of a
  chain with no view. One word that made a mechanism a person was replaced.
- **The static guards on the result.** The naming guard passes. The documentation
  guard reports 10 findings, all in three guides of `main` that this plan does not
  change (`git.md`, `testing-guide.md`, `task.md`). The exports guard reports 36
  and the arguments guard 5, none in a module or a file that this plan changes.
  The list of the lines that the documentation guard gives a person to read named
  one sentence of the branch, in `selection.md`, which made a parent a person; it
  names the printer context now.
- **Both plans are in `plan/done/`.** The pilot plan
  `views-compose-as-content-composes.md` has its step 9 done by this step; its step
  8 is no step of it (decision 21).

## What a person sees after the landing

- A paste of a view selects the pasted view as a whole, as `main` selects each
  pasted document. Before the merge of step 1, the caret of the pasted view was
  live.
- A cut of a view that is an element of a layout takes the element out of the
  list. Before the merge it left an empty document in its place.
- A fold of a JSON array or object in a chain with no view is a cell of the syntax
  node that the print makes, and a new print of that part loses it. On `main` the
  JSON document keeps it in `collapsed`. No pipeline of the editor makes a view
  yet; that is point 2 of the order.

## Risks

1. **The text of a widget is the newest code of `main`.** The last five commits
   of `main` change it. Step 2 changes where its caret is. A fault shows as a
   caret that does not move or keys that do nothing in a text field. So step 2
   has a check in a real editor.
2. **`TextToGraphics.jl` is merged by hand.** 14 hunks, and the two sides changed
   the same functions for different reasons.
3. **`main` moves while the plan runs.** A second, small merge can be necessary
   before the landing.
4. **Step 1 can fail to hold two printers.** If the type of the branch can not
   keep the caret rule of `main` for one step, steps 1 and 2 become one commit.
   The plan gets no new step.

## Not in this plan

- View types for the widgets. A widget keeps its own caret.
- Who makes and holds a view in the editor, the view of a lazy list, and the
  tools that read a caret. They are point 2 of the order.
- A text whose lines are a lazy list under a view. `TextBlockToGraphicsCanvas`
  does not print it, as now.
