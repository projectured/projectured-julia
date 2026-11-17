# `View` is the type of every view

**Status:** in work since 2026-11-17, in the worktree
`projectured-julia-view-steps` on the branch `view-steps`. The owner approved the
plan with the order of the plans on 2026-11-17 ("Yes, I mostly agree"), and asked
for the start on the same day ("yes").

This plan is point 1 of the order in section 13.3 of
`plan/tentative/content-and-view-for-the-whole-project.md`. The design is
`documentation/design/content-and-view.md`. The plan makes the type `View` and
puts the families of views below it. It lands nothing and pushes nothing: it ends
with a request to land.

The plan had the name "A step into a view names a real field" and a second part:
the step `.viewed` in each path into the content of a view. That part moved to
later points of the order on 2026-11-17. The section "Found during the work"
gives the reason.

## The problem

The types that are views have no common type.

```julia
# now
abstract type ContentView <: Document end
abstract type WidgetDocument <: Document end

# after this plan
abstract type View <: Document end
abstract type ContentView <: View end       # a view of one content: it has `viewed`
abstract type WidgetDocument <: View end    # the same for the layout, graphics and pane families
```

## The decision of the owner

**`View` is the supertype of every view, with `ContentView` below it**
(2026-11-17: "B, View for every view with ContentView below it").

## Proposed decisions

They are approved with this plan.

1. **`View` lives in the projection slice**, in `Viewing.jl`, beside
   `ContentView`. The graphics, layout, widget and pane slices can use that slice
   already (`PLATFORM_SLICE_EDGES` in `test/platform/PlatformSuite.jl`), so the
   table gets no new edge. `ProjecturedPlatform` exports `View`.
2. **Five families go below `View`**: `ContentView`, `WidgetDocument`,
   `LayoutDocument`, `GraphicsDocument` and `PaneDocument`. The other documents
   that show something, such as a tooltip, wait for the plan that sorts the
   document types of the session.
3. **`View` has no method and no field rule in this plan.** It only names the
   family. The rule that only a `View` has a selection field comes with the kernel
   hook in point 4 of the order.

## Facts of the code

- `ContentView` is in `source/platform/projection/higherorder/Viewing.jl`, line
  27. `ProjectionAlgebraModule.jl`, line 51, exports it.
- The four other families: `GraphicsDocument` in
  `source/platform/graphics/GraphicsDocument.jl`, line 30; `LayoutDocument` in
  `source/platform/layout/LayoutDocument.jl`, line 21; `WidgetDocument` in
  `source/platform/widget/WidgetDocument.jl`, line 5; `PaneDocument` in
  `source/platform/pane/PaneDocument.jl`, line 21. No abstract type is below one
  of them.
- Three places read the chain of the supertypes of a type: `_find_supertype` in
  `source/platform/roster/RosterDocument.jl`, the help tree in
  `source/platform/help/HelpTree.jl`, and the subtype table of
  `source/platform/domain/Domain.jl`. The help of a widget type can show one more
  supertype after this plan.
- No file of the kernel changes.
- `omnet-julia` has 20 view kinds below `SimulationView <: Document`. They go
  below `ContentView` in a plan of that repository, after point 4 of the order.

## Steps

- [x] **1. The type `View`.** `abstract type View <: Document` in `Viewing.jl`,
  `ContentView` below it, and the widget, layout, graphics and pane families below
  it. The export of `View`.
  Tests: a new test that each of the five families is below `View`;
  `test_platform_layering()`; the eleven narrow tests of the views and of the text
  of a widget, against their result on the branch before the change.
  **Done on 2026-11-17.** The new test is `test_view_families` in
  `test/platform/projection/ViewingTest.jl`: 11 of 11 pass. The eleven narrow
  tests pass with the same counts as before the change: 29, 34, 25, 31, 48, 35,
  49, 36, 17, 97 and 111. `test_platform_layering()` has 19 passes and 2
  failures. Both failures name files that this plan does not change: a qualified
  name in `assistant/AssistantList.jl`, and the form of an import in six modules.
  Step 2 compares them with the base commit. The naming guard passes.
- [ ] **2. The wide check and the guides.** `test_platform()` against the known
  failures of `main`. A new record of the precompile calls of each package whose
  list goes stale. `Pkg.precompile` of `omnet-julia` against the branch, with a
  count of the compiled packages against the manifest. In
  `documentation/design/content-and-view.md`, the line of "The code now" that
  says that no type `View` exists goes. The plan moves to `plan/done/`. Then the
  session asks for the landing, and for the push apart.

## Risks

1. **A new supertype for four families.** A method of the platform for `View` can
   be ambiguous with a method of a family, here or in `omnet-julia`. Step 1 adds
   no method for `View`, and the precompile of step 2 is the guard.
2. **Code that reads the chain of supertypes** shows one more type. The three
   places are in the facts above, and the wide check is the guard.
3. **The recorded precompile calls go stale**, as in the plans before this one.

## Found during the work

1. **The selection walk enters `viewed` and writes into the content.** Found on
   2026-11-17, before any code changed. With a path such as `.viewed.value{2}`,
   the kernel walk reads the head `.viewed` as a field of the view, finds the
   content there, and writes `.value{2}` into the `selection` field of the
   content (`_selection_child` and `_sync_selection!` in
   `source/kernel/selection/SelectionDefaults.jl`). Each content type still has
   that field: it goes in point 4 of the order for JSON, and for the text and the
   syntax only when each domain prints through views. Two views of one content
   then share one caret in the content, and the tests of the views assert that
   the content keeps none (`JsonViewTest.jl`, lines 62, 92, 184 and 200). Today
   the walk stops at the view, because the view has no field `value`. A view that
   a printer makes gets its caret from a computation and not from the walk: each
   output view of a viewing step, and the `TextView` of the text of a widget. So
   the fault shows only for a view that is in the document of the editor, which
   only the tests and the examples have now.

   The session gave the owner two ways. A: the step `.viewed` comes for each
   content family together with the loss of its selection field. B: a new rule of
   the kernel, that the selection walk does not enter a field for which
   `is_field_walked` answers `false`; twelve document types use that hook now, so
   the rule can move a caret in parts that have no view. **The owner chose A on
   2026-11-17 ("I agree with A").**

   So the second part of this plan moved:
   - **To point 4 of the order**, for the JSON views: the step `.viewed`, the two
     functions `get_content_path` and `get_view_path`, and the caret that a new
     content brings. Until the end of the work, the field step of a `ContentView`
     to its content stays for a view of a content that keeps a selection.
   - **To point 11 of the order**, for the text and the syntax views, with the
     text of a widget. The two methods of `Viewing.jl` go there.

   The search of 2026-11-17 for that part stays valid: about 49 places in 9
   source files, about 134 lines in 7 test files, 14 lines in 5 example files, and
   no place in `omnet-julia`. No source file builds a `ViewingProjection`; ten
   test and example files do. The one view type that the editor uses in each
   window is `TextView`, for each plain text of a widget
   (`_make_widget_text_view` in `WidgetToGraphics.jl`).
2. **The two selection walks differ at a document with no selection field.**
   `_set_selection_walk!` writes nothing there and goes on into its children.
   `_sync_selection!`, which `replace_selection!` uses, stops there. Point 4 of
   the order needs one answer, because a content with no selection field is then
   on the path of a caret.
3. **Another plan changes the readers.** `a-reader-is-split-by-its-jobs.md` is
   approved and in work on the branch `reader-split`. It changes the form of each
   reader, also the readers of the views, the text and the widgets. This plan
   changes no reader now, so the two plans do not meet. Point 4 of the order must
   start from the form of the readers that is on `main` then.

## Not in this plan

- The step `.viewed` in a path, in any view (points 4 and 11 of the order).
- `@content_view`, the view of a list, and a view that is made only when
  something reaches it (point 2).
- The key tables (point 3), and the kernel hook (point 4).
- A change of any key, click or look.
