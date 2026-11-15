# One text view keeps the look and the caret

**Status:** pending. Not started. The steps wait for the approval of the owner.

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

- [ ] **1. Merge `main` into `views-compose`.** The merge commit has one
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
- [ ] **2. One printer and one caret rule** (proposed decisions 1, 2 and 3). The
  text of a widget keeps its caret in the view. The printer and the helper of
  `main` go.
  Tests: the tests of step 1, and a real editor: a text field and a text area
  that take typed text, a caret move, a range by the mouse, a wrap, a cut text
  with the caret at its end, and a caret that stays in view; the name of a tab.
- [ ] **3. The wide check.** `test_platform()`, `test_json()`, `test_markdown()`,
  the umbrella suites that the pilot touched, and the sweep of the examples,
  against the known failures of `main`. A new record of the precompile
  statements. `Pkg.precompile` of `omnet-julia` against the branch. If a
  released version exports a name that goes, the version takes a minor step.
- [ ] **4. The guides.** Step 9 of the pilot plan, with the one `TextView`: the
  guides of the text, the widgets, the syntax, JSON and Markdown, and the rule
  "Content documents and view documents". Both plans move to `plan/done/`. Then
  the session asks for the landing, and for the push apart.

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
