# A view type is declared, and a list has a view

**Status:** in work since 2026-11-17, in the worktree
`projectured-julia-list-view` on the branch `list-view`. The owner approved the
plan on 2026-11-17 ("Yes").

This plan is point 2 of the order in section 13.3 of
`plan/tentative/content-and-view-for-the-whole-project.md`. The design is
`documentation/design/content-and-view.md`. Point 1, the type `View`, is on
`main`. The plan lands nothing and pushes nothing: it ends with a request to
land.

## The problem

**A person writes each view type in full.**

```julia
# now
@document struct JsonArrayView <: JsonView
    viewed::JsonArray
    elements::CellVector
    collapsed::Bool = false
end
JsonArrayView(content::JsonArray) = JsonArrayView(content, make_child_views(content, :elements))
make_content_view(content::JsonArray) = JsonArrayView(content)

# after this plan
@content_view JsonArray struct JsonArrayView <: JsonView
    collapsed::Bool = false
end
```

**A list of views makes a view for each element, and keeps each one.**

```julia
view = JsonArrayView(array)       # the array has a million elements

# now: `elements` is a plain CellVector with one computation
view.elements[3]                  # makes a million views, and each one stays

# after this plan: `elements` is a CellVectorView
length(view.elements)             # 1000000, and no view of an element exists
view.elements[3]                  # makes the view of element 3, and no other
```

## The decisions of the owner that this plan builds

They are in section 13.1 of the order document.

- **Each kind of list has its own view type** (decision 5: "each kind of list get
  its own view type").
- **The tree of views mirrors the tree of content** (decision 6).
- **`@content_view` declares a view type** (decision 12: "I like @content_view
  more").
- **The view of a value element follows its index** (decision 13).
- **A view goes when nothing reaches it and its state is the default** (decision
  15: "Yes, I agree").

## Proposed decisions

They are approved with this plan.

1. **`CellVectorView` is the view of a `CellVector`.** It is a `ContentView` with
   the field `viewed`, and it acts as a list: its length is the length of its
   content, and its element 3 is the view of element 3 of its content. So the
   step `[3]` on it is the plain index step, and no type changes the meaning of
   a step. It lives in the projection slice beside `Viewing.jl`, which uses
   `CellVector` already. `make_content_view(list::CellVector)` answers it.
2. **The list view makes the view of an element at the first read of that
   element.** A read of the length makes no view. An element that has no view
   type has `nothing` at its place, as now.
3. **The view of an element that is a document follows the identity of the
   element**, as now: after an insert before it, the same view is at the next
   index. No element that is a plain value has a view type yet. The rule that
   such a view follows its index comes with the first view type of a value.
4. **A view of an element goes when all of these are true:**
   - it holds no caret, live or dormant;
   - each field of its state has the default value;
   - no computation reads one of its cells (`has_dependent_cells`), so no print
     shows it;
   - each list view below it keeps no view;
   - nothing asked the list for it after the last time that the list dropped
     views.

   The last condition protects code that gets a view and then writes its state.
5. **The list view drops such views at the start of each print of the view that
   holds the list.** At that time no operation is in work. So the memory of the
   views is what a person changed and what a print shows, with no cap and no
   global walk.
6. **An element that leaves its list takes its view with it**, as now. The list
   view drops that view at the same time as the others.
7. **The output view of a viewing step holds the views that the steps of its
   children gave.** The list view has a second field, `given`, for that list. A
   list view with a `given` list makes and drops no view. Today
   `_make_output_children` builds that list, and it stays.
8. **`@content_view` writes four things**: the field `viewed`, one child field
   for each list of the content, the constructor that takes the content, and
   the method of `make_content_view`. It also writes a method that says if a
   view has its default state, from the defaults in the declaration. A view
   type that a person writes with no declaration has no such method, and a view
   of that type never goes.
9. **In this plan, the macro makes a child field for each field of the content
   type that is declared as a `CellVector`.** The macro reads the declared type
   with `find_declared_field_type`, through one function that answers the view
   type of a kind of list. Three other kinds of field wait for the point of the
   order that needs them:
   - a field that takes any document, such as `JsonObjectEntry.value`: point 4;
   - a field of a document type, such as `SyntaxLeaf.value`: point 11;
   - the lines of a text. `TextBlock.elements` is declared as a union of four
     kinds of collection, so the macro makes no field for it, and `TextView`
     stays one view of the whole text: point 11.

   This closes one part of open point 2 of the design document.
10. **All twelve view types take the declaration.** No type gets a new field,
    loses a field, or changes the order of its fields.
11. **`make_child_views` goes.** It came on 2026-10-20, after the release 0.1.0,
    so no released name changes and no package takes a version step for it.

## Facts of the code

- The twelve view types and what the macro reads:

  | View type | Content type | Child field | State fields |
  | --- | --- | --- | --- |
  | `TextView` | `TextBlock` | none | `wrap`, `line_spacing`, `closed_folds` |
  | `SyntaxLeafView` | `SyntaxLeaf` | none | none |
  | `SyntaxNodeView` | `SyntaxNode` | `children` | `collapsed` |
  | `JsonNullView`, `JsonBoolView`, `JsonNumberView`, `JsonStringView` | the JSON leaf of the same name | none | none |
  | `JsonArrayView` | `JsonArray` | `elements` | `collapsed` |
  | `MarkdownTextView` | `MarkdownText` | none | none |
  | `MarkdownParagraphView`, `MarkdownHeadingView` | the Markdown node of the same name | `content` | none |
  | `MarkdownRootView` | `MarkdownRoot` | `elements` | none |

- `make_child_views` is in `source/platform/projection/higherorder/Viewing.jl`,
  lines 106 to 116. It has five callers: `SyntaxView.jl`, line 40;
  `JsonView.jl`, line 74; `MarkdownView.jl`, lines 43, 57 and 81.
- In `Viewing.jl`, four places read the list of child views:
  `_copy_view_state!` (line 146, a test for `CellVector`),
  `_make_output_children` (lines 335 to 345), `_find_child_view` (line 359) and
  `_find_caret_view_steps` (line 409, a test for a vector). `SyntaxView.jl`
  reads it in `_zip_child_views` and `_find_fold_path`, and `JsonView.jl` in
  `_find_innermost_array`.
- One method of `make_content_view` takes a list of children:
  `SyntaxView.jl`, line 48. It stays, as one line that a person writes.
- The kernel reads an index step with `document[index]` and `length(document)`:
  `evaluate_reference_step` in `source/kernel/reference/ReferenceStep.jl`, line
  218, and `_find_indexed_child` in
  `source/kernel/selection/SelectionDefaults.jl`, line 371. A document type that
  has these two functions and answers `true` to `is_element_collection` is a
  list for the kernel. So no file of the kernel changes.
- `has_dependent_cells` is in `source/kernel/cell/CellInterface.jl`, line 255.
  Three parts of the platform use it already to know if something shows a
  document: the frame statistics, the background work and the system processes. A reader that nothing holds counts until the collector removes it,
  so a view can stay for a short time after the last print of it goes.
- `find_declared_field_type` is in `source/kernel/document/DeclaredType.jl`,
  line 204. `CellVector` is in `source/platform/collection/CellVector.jl`, line
  57. `TextBlock.elements` is declared as `CollectionDocument`
  (`source/platform/text/TextDocument.jl`, line 226), the union of `CellVector`,
  `CellMatrix`, `CellTable` and `ListNode`.
- The tests read the child fields of the views in about 100 lines of four test
  files, mostly as `view.elements[3]` and as paths. They keep their form. One
  test helper walks each field of each view (`_text_view_collect` in
  `TextViewTest.jl`), and it takes the new list type by name.
- Two recorded precompile calls name a view type, one in `ProjecturedJSON` and
  one in `ProjecturedPlatform`. None names `make_child_views`.
- `omnet-julia` uses no view type, no `make_content_view` and no
  `make_child_views`.
- Two documents name `make_child_views`:
  `documentation/design/content-and-view.md` and
  `documentation/design/engineer-tour.md`.

## Steps

- [x] **1. The view of a list.** `CellVectorView` in a file of its own in the
  projection slice: the field `viewed`, the field `given`, the length, the read
  of an element, the loop, `is_element_collection`, and
  `make_content_view(list::CellVector)`. No view type uses it yet.
  Tests, new: the length makes no view; a read makes one view; the same read
  gives the same view; a view follows its element after an insert and after a
  removal of another element; an element with no view type gives `nothing`; a
  path with an index step reaches the view; a list view with a `given` list
  answers that list.
  **Done on 2026-11-17.** The file is
  `source/platform/projection/higherorder/CellVectorView.jl`, and the test is
  `test_cell_vector_view` in `test/platform/projection/CellVectorViewTest.jl`:
  36 of 36 pass. The run that tested step 1 had steps 2 and 3 in it too, because
  each run waits a long time for memory.
- [x] **2. The five child fields hold a list view.** `SyntaxNodeView.children`,
  `JsonArrayView.elements`, `MarkdownParagraphView.content`,
  `MarkdownHeadingView.content` and `MarkdownRootView.elements`. The output view
  of a viewing step gets a list view with its `given` list. `_copy_view_state!`
  copies the state of the views that the source list keeps, and makes no other
  view. `make_child_views` goes.
  Tests: the eleven narrow tests of the views and of the text of a widget,
  against their result on the branch before the change.
  **Done on 2026-11-17.** The eleven narrow tests pass with the counts of the
  branch before the change: 29, 34, 25, 31, 48, 35, 49, 36, 17, 97 and 111.
  `test_platform_layering()` has the two failures of `main` and no other.
- [x] **3. The declaration.** `@content_view`, with the function that answers
  the view type of a kind of list. The twelve view types take it.
  Tests, new: the fields of each of the twelve types, in their order, are the
  fields of today; the constructor and `make_content_view` answer the type; the
  method of the default state answers `true` for a new view and `false` after a
  change of a state field. The eleven narrow tests again.
  **Done on 2026-11-17.** The file is
  `source/platform/projection/higherorder/ContentViewDeclaration.jl`. The new
  test `test_content_view_declaration` has 34 of 34. The tests of the JSON types
  and of the Markdown types are new test sets in `test_json_string_view` (now 47)
  and in `test_markdown_view` (now 50). The nine other narrow tests keep their
  counts, and the layering guard has the two failures of `main` and no other.
- [ ] **4. A view goes.** The drop of the views that nothing reaches, at the
  start of each print of the view that holds the list.
  Tests, new: a view with a caret stays; a view with a closed fold stays; a view
  that a print shows stays; a view that nothing reaches goes at the next print,
  and the next read gives a new view with the default state; the view of an
  element that left the list goes; a view that code got and then changed stays.
  The step starts with a test of one fact: each print of a view reads a cell of
  that view.
- [ ] **5. The wide check and the guides.** `test_platform()` and the suites of
  the JSON and the Markdown domains against the same runs at the base commit.
  The recorded precompile calls, if a list goes above its limit of calls that do
  not resolve. `Pkg.precompile` of `omnet-julia` against the branch, with a
  count of the compiled packages. In
  `documentation/design/content-and-view.md`: the lines of "The code now" about
  `make_child_views`, about the view types that a person writes in full and
  about the view of a list, and open point 2. In
  `documentation/design/engineer-tour.md`: the line about `make_child_views`.
  A rule for `@content_view` in `documentation/rule/architecture-rules.md`. The
  plan moves to `plan/done/`. Then the session asks for the landing, and for
  the push apart.

## Found during the work

1. **`@document` takes a list as one item.** A type whose first field is a list
   gets a constructor that takes documents as the items of that list. A
   `CellVector` is a document, so `CellVectorView(list)` made a view of a new
   list with one item. The list view has two constructors of its own that take a
   list as the content.
2. **The list view of a child field follows the field of the content.** Its
   field `viewed` is a computed cell that reads the field, as `make_child_views`
   read the field at each run. So the list view shows the list that the content
   holds now, also after a write of a new list into the field.
3. **The child documents of a list view are the views that exist.**
   `child_reference_steps` of a list view names them with their index steps and
   makes no view. `find_document_path` and the copy of the state of a view use
   it.
4. **A reflection walk reads each index of a list view**, because the walk of
   the kernel reads each element of a document that answers `true` to
   `is_element_collection` (`source/kernel/document/DocumentWalk.jl`, line 510).
   So a search through a view makes the view of each element, and the next drop
   removes the views that nothing reaches. A walk that enters only the views
   that exist needs a new hook of the kernel. This plan does not add one.
5. **The list view is not on the route of a key.** `_find_caret_view_steps`
   passes through it as through a list, so the keys go to the same views as
   before. The list view gets its place on the route when it gets keys of its
   own, in point 6 of the order.
6. **The macro also writes the method that takes the views of a viewing step**,
   `make_content_view(content, children)`, for a content type with one list.
   Before, only `SyntaxNode` had that method, and a step with a JSON or a
   Markdown output lost the views of its children.
7. **The macro writes each method with the name of the module of the
   function.** So the modules of JSON, Markdown and the text no longer import
   `make_content_view`, which the layering guard asks for when a module extends
   nothing by hand.
8. **The fact that step 4 needs is true.** A print makes nothing until something
   reads its drawing. After a read of the drawing, each view that the print
   shows has a reader on its cell `viewed`: the view of the root, the view of
   each child, and the views below a child. After the print goes and the
   collector runs, no cell of these views has a reader. A probe on the syntax
   pipeline showed it, and step 4 makes it a test.

## Risks

1. **The drop needs a cell that each print of a view reads.** If a print can
   show a view and read none of its cells, the drop removes a view that shows.
   Step 4 starts with the test of that fact. If the fact is false, the step
   stops and the session reports it.
2. **The collector decides when a reader goes**, so a test of the drop must run
   the collector, and a view can stay longer than the rule says. It never goes
   sooner.
3. **A list view is a `ContentView`, so it keeps a dormant caret**, and a plain
   `CellVector` does not. The tests of the dormant carets of the views are the
   guard.
4. **Another plan changes the readers.** `a-reader-is-split-by-its-jobs.md` is
   in work on the branch `reader-split`. Its steps 2, 3 and 3a are on `main`
   since 2026-11-17, and they changed none of the files that this plan names.
   Its later steps will change `read_intent` in `Viewing.jl`. This plan changes
   other functions of that file, so a merge can need work by hand.
5. **A loop over a list view makes the view of each element.** Code that needs
   only the views that exist must ask the list view for them. The search of
   2026-11-17 found no such loop over a long list.

## Not in this plan

- The step `.viewed` in a path, and the loss of the selection field of a content
  (points 4 and 11 of the order).
- A view for a field that takes any document, for a field of a document type,
  and for the lines of a text (points 4 and 11).
- A view of a plain `Vector`, of a data frame or of another kind of collection,
  and the arrangement in the view of a collection (point 6).
- The view of an element that is a plain value, with the rule of the index.
- The key tables (point 3), and the kernel hook (point 4).
- A change of any key, click or look.
