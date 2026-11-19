# Content and view for the whole project: the picture for the decision

Status 2026-11-17: the owner said that the rules are complete. The design is
`documentation/design/content-and-view.md`, and section 13 holds the decisions of
2026-11-16 and 2026-11-17 behind it and the order of the work. Section 13
replaces decisions 1, 3 and 6 of section 11.1, the rules of section 11.6, the
open points of section 11.7 and the order of section 12. The inventory and the
other facts of section 11 stay. The owner approved the order of section 10 on
2026-11-15, and point 1 of it is done and on `main`. This document has no steps:
the steps of each point come in a plan of their own.

The pilot is `plan/done/views-compose-as-content-composes.md`. It was on the
branch `views-compose`, and it is on `main` since 2026-11-15 (`adea9d83f`). Its
steps 1 to 7 and 9 are done. This document says only what differed from `main` on
2026-11-15, before point 1 of the order in section 10.

## 1. The answer in short

- **The idea holds.** The pilot separates what a person edits from the state of the
  edit, for the text chain: a domain, then the syntax, then the text, then graphics.
  Two views of one content keep two carets and two folds. One view shows at two
  places. Views of two domains compose with no code that names the other domain.
- **The content projections do not change.** A stage of views wraps the table of
  the stage. No row of JSON, of Markdown, of the syntax or of the text was written
  again. The paths of a document do not change.
- **The cost is small in time and large in memory.** A chain of views takes about
  20 % more time for the first print and about 55 % more memory than the same chain
  with no view. A caret move and a typed character take 4 % to 11 % more.
- **The pilot covers one of the two kinds of chains.** It does not cover the chains
  that print to widgets, which hold most of the user interface. It does not cover
  lazy lists, the tabs that open a file, the undo, the search and the assistant.
- **The size is the whole project.** 554 document types here and 188 in the two
  other repositories keep a caret now. 13 domains print to the syntax, and 38 key
  tables read a caret.
- **`main` has the first half of the text view.** Since 2026-11-05, `main` has a
  `TextView` of its own, which keeps the look of a text, and whose caret stays in
  the text. Its plan made it as the smallest form of the type of the pilot. The
  two become one type before the pilot can land
  (`plan/done/one-text-view-keeps-the-look-and-the-caret.md`, done and landed on
  2026-11-15).
- **My recommendation** is in section 10: go on, one domain at a time, but first
  build the three parts that every domain needs and that the pilot does not have.

## 2. The one idea

On `main`, a document says what it is, and it also keeps the state of its edit:
its part of the caret, the part under the pointer, and for some types a fold. So
one document has one caret and one fold.

```julia
# main: one document, one caret
array = JsonArray([JsonString("a"), JsonString("b")])
array.selection                    # the caret, stored in the array and in the string below it

# pilot: the content holds no state; each view holds the state of one view
array  = JsonArray([JsonString("a"), JsonString("b")])
view_a = JsonArrayView(array)      # a caret and a fold
view_b = JsonArrayView(array)      # another caret and another fold, the same array
```

`main` has a rule for view documents already (`architecture-rules.md`, "Content
documents and view documents"). There, a view document is one document over its
content, such as `DataFrameView` or `ChartPlot`, and the caret stays in the content.
The pilot goes further in two ways: the caret and the fold move into the view, and
a view is a tree with one node for each node of its content.

`main` also got a view of a text after the pilot started (commit `a055cf397`,
2026-11-05). `TextView(content, wrap, line_spacing)` of `main` keeps the look of
one showing of a text. Its caret stays in the `TextBlock`, and a path of the view
reaches the text through the step `content`. The pilot has a type of the same name
in the same file, with the other rule for the caret. The plan of `main` records
that its type is the smallest form of the type of the pilot, and that the pilot
moves the caret into it and adds the folds.

## 3. The rules of the pilot

### 3.1 Nesting

1. **Each content type that a person edits has a view type.**
   `make_content_view(content)` gives the view. A type with no method has no view.
2. **A view keeps what it shows in the field `viewed`.** No content type that has a
   view can have a field with this name.
3. **A view of a compound holds the views of the children, under the name of the
   child field of its content.** `JsonArrayView.elements` holds the views of
   `JsonArray.elements`. `make_child_views` makes them when they are read, and a
   child keeps its view while it stays in the collection, at any index.
4. **A view answers the paths of its content.** A step that the view does not have
   as a field reads the content. So `.elements[2].value{3}` is a path of the array
   and of its view, and no path of `main` changes.
5. **A child takes the view of its own type.** So a JSON array among the blocks of
   a Markdown document gets a `JsonArrayView`, and neither domain names the other.
6. **A child whose type has no view has `nothing` in the view.** It prints as
   content, and the caret of the view above it names it only as a whole.
7. **A container holds a view.** No type stands for a place. A part at a place of
   its own is the child view itself, such as `view.elements[3]`.
8. **A field of a view hides a field of the content with the same name**, such as
   `collapsed`. The view type chooses names that its content does not use.

```
MarkdownRoot [ MarkdownHeading, MarkdownParagraph, JsonArray ]        the content, held once

MarkdownRootView      { viewed = root,      elements = [heading view, paragraph view, JsonArrayView] }
MarkdownParagraphView { viewed = paragraph, content  = [MarkdownTextView] }
JsonArrayView         { viewed = array,     elements = [JsonStringView, JsonNumberView], collapsed }
```

### 3.2 Selection

| | `main` | Pilot |
| --- | --- | --- |
| Where the caret of a JSON string is stored | In the `JsonString`, its `SyntaxLeaf` and its `TextBlock` | In the `JsonStringView`, the `SyntaxLeafView` and the `TextView` |
| Two tabs of one document | One caret | Two views, two carets |
| One document at two places | One caret, and each place draws it live | One view, one caret; one place draws it live, the other dormant |
| A caret when the focus leaves | Kept only by a document that asks for it | Kept by each view, as a dormant caret |

1. **The selection is one path from the root**, as on `main`. It goes through the
   views and not through the content. Its steps are the same.
2. **No content stores a part of the path.** The selection walk enters a child
   view by the name of its field, and it stops at the view where the next step is
   a field of the content, such as `.value{3}`.
3. **Each view keeps its caret when the focus leaves it**, as a dormant caret. A
   path that comes back to the view makes the caret live again.
4. **Only one place is live.** The print context carries a live flag of the place.
   A parent gives it to each child: the place of the parent is live, and the live
   path of the parent goes on into this child. A print draws a caret as live when
   the stored state and the place both say live.
5. **A write of the stored path gives its part to a new document on the path.** This
   is a repair of the storage of `main`: each document keeps its part, and a paste
   puts a document that has none.
6. **A text view keeps a flat caret**, such as `{k}`, and not a path into its text.
   The text types still have their selection fields, and a path into the text would
   write into the text that two views share.

### 3.3 Printer

1. **Each stage is wrapped, and no row changes.**

   ```julia
   # main
   ChainingProjection(RecursiveProjection(JsonToSyntax()),
                      RecursiveProjection(SyntaxToText()),
                      TextToGraphics(; measure))

   # pilot
   ChainingProjection(RecursiveProjection(ViewingProjection(JsonToSyntax())),
                      RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
                      TextFolding(),
                      RecursiveProjection(TypeDispatchingProjection(
                          TextView  => TextViewToGraphicsCanvas(),
                          TextBlock => TextBlockToGraphicsCanvas(; measure))))
   ```

2. **A step prints the content of the view with the row of the content**, as `main`
   does, and gives the row a recursion of the view. When the row prints a child,
   the recursion takes the steps that the context of the child adds, such as
   `.elements[2]`, applies them to the view, and prints the child view. The row gets
   the content IO map of the child, so it builds its output as on `main`.
3. **The output of a step is the view of the next domain** over the printed
   content. A compound view gives a compound view, and a leaf view gives a leaf
   view. The caret maps through the reference maps of the row.
4. **Where the shape changes, the step has code of its own.** Syntax to text joins
   the carets of the child views into the flat caret of one text view. Text to
   graphics draws the band, the drawing of the text and the caret.
5. **A content with no view prints as on `main`**, through the same table.
6. **A content is printed once for each place of each view.** `main` prints it once
   for each place. No print is shared.
7. **Printing gets one new thing:** the live flag, a property of the print context.

```
JsonArrayView ── ViewingProjection(JsonToSyntax()) ──► SyntaxNodeView ── ViewingProjection(SyntaxToText()) ──► TextView ──► [band, drawing, caret]

ViewingIoMap                              input = JsonArrayView     output = SyntaxNodeView
├ the IO map of JsonArrayToSyntaxNode      input = JsonArray         output = SyntaxNode      (the row of main)
└ the IO maps of the child views          input = view of element   output = SyntaxLeafView
```

### 3.4 Reader

1. **An operation from the next stage goes back through the reader of the row**, as
   on `main`. A path of the view is a path of its content, so the reader gives an
   operation at a path of the view.
2. **An evaluation at a path of a view** reads through the view. A write of a field
   that the view does not have goes to the content. The caret stays on the view.
3. **A key goes down along the live caret.** Each view on the path of the caret
   reads it with the key table of its type, the deepest first. It is the rule that
   documents have on `main`, and the same kernel function.
4. **A key table belongs to a view type.** A row that edits the tree, such as a
   comma that appends an element, makes the edit with the helper of the content and
   sends it through the view (`make_content_edit`).
5. **State of a view that is not a path has two hooks.** One carries it forward,
   such as the fold of a node to the hidden lines of its text. One reads its
   operation back, such as a click on a fold mark.

Now each key table exists twice, such as `@gestures JsonDocument` and
`@gestures JsonView`, because the chains with no view need the first.

### 3.5 Folds

On `main`, a fold is a cell of the syntax node that a print makes. A new print of
the part loses the fold. Five domains declare a `collapsed` field that no code
reads. In the pilot, a fold is a field of a compound view. It maps forward to the
view of the node and then to the hidden lines of the text view. A toggle goes back
as an operation at the path of the view. Two views fold apart, and a fold lives as
long as its view.

### 3.6 Copies and pastes

| Keys | The content | The view |
| --- | --- | --- |
| Copy, Paste | a copy | a new view |
| Note, Paste | the same | a new view |
| Note, "Paste the same view" (Ctrl+Alt+V, new) | the same | the same view at a second place |

On `main`, Note and Paste put the same document at a second place, with its caret.

### 3.7 Combinations

| Case | Result | Tested |
| --- | --- | --- |
| A view over a content, alone | A chain of views | Yes |
| Two views of one content | Two carets and two folds; an edit shows in both | Yes |
| One view at two places | One caret, live at one place and dormant at the other | Yes |
| A part of a view at a place of its own | The child view itself; it shares the caret and the fold with the whole view | Yes |
| A view of one domain inside a view of another | The inner view prints, edits and reads its keys | Yes, JSON in Markdown |
| A child with no view inside a view | It prints as content; the caret names it only as a whole | Yes |
| A content with no view at all | The chain of `main`, not changed | Yes, the suites of `main` |
| A view inside a content with no view | Only a container, such as a layout, holds a view | Yes |
| A paste of a part into a view | Refused; a paste replaces a whole view at its place | Yes |
| A view in a tab, with a file | Not built | No |
| A view of a lazy list | Not built | No |
| A view of a widget tree | Not built | No |

## 4. The changes of the architecture

**New in the platform** (975 lines in five files):

- `Viewing.jl`: `ContentView`, `ViewingProjection`, the recursion of a view,
  `make_content_view`, `make_child_views`, `make_content_edit`, `make_sibling_view`,
  `ToggleFoldOperation`, and the two hooks of the state of a view.
- `TextView.jl`: `TextView` and `TextViewToGraphicsCanvas`. `TextToGraphics` is
  split into the drawing of the lines and the marks of the caret, so the two share
  code.
- `SyntaxView.jl`, `JsonView.jl`, `MarkdownView.jl`: 11 view types and their key
  tables. With `TextView`, the pilot has 12 view types.

**Changed in the kernel** (two slices, no sealed file):

- Selection: the image of a selection takes the live flag of the place; a query
  says whether the live path of a document goes through given steps; a write of
  the stored path repairs the chain below it.
- Printing: the print context has the property of the live place, and
  `make_child_context` and `make_element_context` compute it for a child.
- The output paths take the context, so an output is dormant at a place that is
  not live.

**Changed in the platform:** the evaluation of an edit of a string and of a number
writes to the document that its target shows. The clipboard has an eighth gesture
and makes a second view for a pasted view. `TextFolding` folds a text view. The
compound print of the syntax keeps the fold that it made in its IO map.

**Not changed:** every projection of a content, every IO map of a content, the
references, the operations except the toggle of a fold, the editor loop, the
backends.

The pilot is 1569 added lines of source in 29 files, 1387 lines of tests and 241
lines of examples.

## 5. What is better

- **Two views of one content.** `main` can not give two tabs of one file two
  carets or two folds.
- **Content is only content.** It can be shared, saved, compared and shown at many
  places, and no view writes into it.
- **One live caret, and dormant carets that show.** On `main`, each place of one
  document draws a live caret.
- **A fold has an owner.** It does not go when a part prints again, and no content
  type declares a dead field for it.
- **The state of an edit has one home.** A later kind of state, such as a scroll or
  a mark, has a place to go with no new field in 554 types.
- **Composition needs no code.** A new domain composes with each domain that has
  views.
- **The move of a domain is additive.** The view types come beside the content
  types, and the chains with no view work as before.

## 6. What is worse

- **A second tree.** Each view keeps a node for each content node that it reached,
  at each stage. The memory grows by about half.
- **A view type for each content type**, by hand: a struct, a constructor and a
  method of `make_content_view`. JSON took 149 lines for five types, and Markdown
  87 lines for four.
- **Two key tables for each type** while chains with no view remain.
- **Two systems side by side for a long time.** A person who reads the code must
  know which chain has views.
- **A mixed tree is weaker than `main`.** Inside a view, a child with no view takes
  no caret in its text. By the code, it reads no key; I did not test that. So a
  domain is useful with views only when each of its types that a person edits has
  one.
- **The name space of a view and of its content is one.** `viewed` is reserved, and
  a field of a view hides a field of the content.
- **A place draws one caret.** It draws the caret that the path of its own view
  names, and not the caret of a part that is live at another place.

## 7. The costs that I measured

One JSON array of N strings at one place, with a fixed measure, on the branch. The
first chain is the chain of `main`.

| N | Chain | First print | Memory kept | Caret move | Typed character |
| --- | --- | --- | --- | --- | --- |
| 100 | no view | 12.6 ms | 2.9 MB | 27.2 ms | 57.0 ms |
| 100 | views | 15.3 ms | 4.4 MB | 28.5 ms | 62.0 ms |
| 1000 | no view | 134 ms | 27.9 MB | 2.69 s | 5.32 s |
| 1000 | views | 160 ms | 43.2 MB | 2.80 s | 5.90 s |
| 4000 | no view | 785 ms | 111 MB | 51.2 s | 110.6 s |
| 4000 | views | 1204 ms | 172 MB | 56.8 s | 109.3 s |

- The first print costs about 20 % more at 100 and at 1000. The 53 % at 4000 is one
  sample.
- The memory kept is 52 % to 55 % more.
- A caret move costs 4 % to 11 % more, and a typed character from 1 % less to 11 %
  more.
- The text folds of a view add about 4 % to the print.
- One child context costs 146 ns and 624 bytes more for the live flag. That is
  below 0.1 % of the print of four examples.

A second fact of this table is not about views. A caret move from one element to
the next takes 2.7 s at 1000 elements and 51 s at 4000, with no view too. The time
grows with the square of N. The measure reads the whole drawing with no viewport
and no lazy list of lines, so a real window can differ. I did not find the cause,
and I did not check it on `main`.

## 8. What the pilot does not show

1. **The chains that print to widgets.** Nine domains print to widgets, to a
   layout or to graphics, and the widget slice has 78 document types. A widget is
   an output and also keeps state, such as the rows in view of a table. The pilot
   has no rule for the caret of a cell of a table or of a text of a card.
2. **Lazy lists.** `make_child_views` reads the whole collection of the children,
   and makes the whole vector again when the collection changes. A view of a lazy
   list needs another form. `TextToGraphics` prints a lazy list of lines, and the
   chain of a text view does not.
3. **Who makes a view.** In the pilot, an example makes each view by hand. In the
   editor, a tab of a file, a page of the navigator and a card must make the view
   of what they show, and must hold it while they show it.
4. **The tools that read a caret.** The undo, the search, the assistant, the drag,
   the focusing projection and the versioning projection ran on no view. The caret
   sweeps of the tests skip the examples of views, because a layout sends a key
   only by the selection.
5. **A paste of a part into a view**, and an edit through a view beside an inline
   image.
6. **The gutter of a text.** A chain of views draws no fold triangle.
7. **The live flag in the chains with no view.** 126 calls in 64 files wire the
   selection of an output with no context.

## 9. The size and the risks

### 9.1 The size

| What | Count |
| --- | --- |
| Document types that keep a caret now | 554: platform 248, domains 294, kernel 5, adapters 7 |
| The same in `omnet-julia` and `inet-julia` | 179 and 9 |
| Domains | 19; 13 print to the syntax, 9 print to widgets, a layout or graphics |
| Key tables with no view | 38: domains 18, platform 19, adapters 1 |
| Chains of `SyntaxToText` with no view | 133 of 147 |
| Chains of `TextToGraphics` | 181, none with views |
| View types that the pilot made | 12: the text, 2 of the syntax, 5 of the 8 JSON types, 4 of the 18 Markdown types |

The domains that print to the syntax, by the count of their document types: julia
61, rst 44, sql 40, math 22, markdown 18, process 13, fsm 8, json 8, yaml 8, book
6, dbcatalog 5, xml 4, formula 3.

The work for one domain of the syntax is: a view type for each type, the key
tables again on the view types, the wrap of its stages, and the tests that read a
caret of the content. The projections stay. A macro can make the view type from
the content type; this is my idea, and it is not built.

The selection fields go from a type only when its last chain with no view is gone
(decision 21 of the pilot). For the text and the syntax types, that is the last of
the 13 domains.

### 9.2 The risks

1. **The widget chains have no design.** They are most of the user interface. The
   rule of the text chain can fail there, or can need a second form.
2. **Large documents.** The mirror is not lazy, and the memory grows by half. A
   log, a roster or a data frame with many rows can not take that.
3. **The branch is 1227 commits behind `main`, and the text of a widget must
   change.** A trial merge gives 13 files in conflict, among them
   `TextToGraphics`, `TextDocument`, `TextFolding`, `SyntaxDocument` and the
   clipboard. `main` has its own `TextView`, in the same file, which the text of
   each widget prints through. Its caret stays in the text; the caret of the pilot
   is in the view. The plan of `main` made that type as the first half of the type
   of the pilot, so the design is one `TextView` that keeps the look and the caret.
   The work is the move of the caret of the text of each widget into the view. The
   recorded precompile statements are stale too.
4. **A long time with two systems.** Each new feature of `main` must work in both
   until the last chain moves.
5. **The other repositories follow.** `omnet-julia` has 179 document types and
   follows each change of a name and of a signature.
6. **Behavior that changes with no notice.** A key now goes to the deepest view
   first. A paste gives a new view. A view keeps a dormant caret where a document
   kept none.
7. **The parts that the pilot did not run**, in section 8.4. Each can hold a fault
   of the kind that step 6 found in the selection walk.

## 10. The ways to go on

- **Stop.** The branch stays as a study, and `main` keeps the view documents that
  it has. Nothing is lost on `main`.
- **Land the pilot, and decide later.** The rebase and the landing put the
  mechanism on `main` with three domains of examples. No chain of the editor uses
  it. It costs the rebase now and keeps the code alive.
- **Go on, in this order.** This is my recommendation. The owner approved the
  order on 2026-11-15 ("Yes, that's good plan").
  1. Make the one `TextView`, bring the branch up to `main` and land the pilot, so
     the work is not lost to the distance from `main`. The plan is
     `plan/done/one-text-view-keeps-the-look-and-the-caret.md`. Its four steps
     are done, and the pilot is on `main` since 2026-11-15 (`adea9d83f`).
  2. Design and build the three parts that each domain needs: who makes and holds a
     view in the editor, the view of a lazy list, and the tools that read a caret.
  3. Move JSON whole, with a file in a tab. This is way A of step 8, and it is the
     first real use.
  4. Decide the widget chains with a pilot of their own, before any domain that
     prints to widgets.
  5. Move the other domains of the syntax, one for each plan.

  The decisions of 2026-11-16 (section 11.1) change points 2 to 5. Section 12
  holds the order after them, which the owner approved on 2026-11-16.

I do not know the time of the whole move. The pilot gives the size of one small
domain of the syntax: about 150 lines of views and tables for five types, and about
300 lines of tests. The parts of point 2 and the widget chains are not measured.

## 11. What gets a view

The analysis of 2026-11-15 and 2026-11-16, on `main` at `107fe8fc0`, with the
decisions of the owner.

### 11.1 The decisions

1. **The test** (the owner, 2026-11-16: "Yes, I agree with that"). A type gets a
   view only when both are true: one instance can show at two places, and one
   showing keeps state in it, such as a caret in its text, a fold, a scroll or a
   filter.
2. **A widget and a layout are views** (the owner, 2026-11-16: "They are more like
   views already, no?", then "Yes"). They get no view of their own. One widget at
   two places shares its state, as one view at two places shares its caret.
3. **One generic view** (the owner, 2026-11-16: "Yes", to "Do you want the views of
   the pilot and the arrangement to become one generic view?"; before it: "I tend
   to lean towards option 2 to avoid having so many views" and "Perhaps we should
   switch to reusing the same view if they are structurally and behaviourally
   equivalent"). A type with no state of its own has no view type of its own. The
   generic view keeps its part of the caret and the views of its parts. This is
   option 2 of section 11.5.
4. **An arrangement is a view in the document tree** (the owner, 2026-11-16: "the
   arrangement should really be a view in the document tree and I think we can
   avoid passing it down in the context"). The filter, the sort, the find and the
   group of a collection are state of the view of that collection. No view gives
   its state to the printer of a part through the printer context: the printer of
   a part reads the view of that part.
5. **The view documents of the older rule follow the naming convention and the
   rules for views** (the owner, 2026-11-16: "other old views should follow the
   naming convention and the rules we have for views"). Section 11.6 holds the
   rules and the work for each of them.
6. **A key table belongs to the content type, and the view gives it the caret**
   (the owner, 2026-11-16: "I agree with option 1"). A view type has a key table
   of its own only for state of its own. This replaces decision 7 of the pilot
   plan, "Keys belong to the views"; a key still goes down along the caret of the
   views, the deepest first.

The plan of point 2 of the order was
`plan/pending/one-generic-view-for-a-content-with-no-state-of-its-own.md`. The
owner rejected it on 2026-11-16, and it is in `plan/obsolete/`. Section 13
replaces decisions 1, 3 and 6 above.

### 11.2 The inventory

A scan of `source/` finds 607 `@document` types. A few are examples in docstrings.

| Group | Types | Result |
| --- | --- | --- |
| Views of the pilot | 12 | Are views |
| View documents of the older rule, with their parts | about 40 | Are views, but not by the rules of the pilot |
| Widgets, layouts, graphics, tooltips | about 110 | No view (decision 2) |
| Content of the 13 domains that print as code | 240 | Get a view; 9 have one |
| Text and syntax types | 19 more | No more views; one `TextView` covers a text |
| Primitives | 4 | Get a view |
| Content of the domains that print as widgets | about 70 | Not decided |
| Documents of the session and the rest of the platform | about 110 | Not decided |

- **Printers make the widgets.** 691 of the 1289 calls that make a widget or a
  layout are in the 54 `…ToWidget` files, and most of the rest are in helpers of
  printers and in the widget slice. No content type declares a field of a widget
  or layout type.
- **A widget is the face of a view document.** The printer gives the widget the
  state of the view document: the `WidgetTable` of a data frame uses the cells
  `scroll_position` and `top_row` of the `DataFrameView`; the `WidgetTree` follows
  and writes `expanded` and `shown` of the `DocumentTree`; the `WidgetSplitPane`
  shows the weights of the `PaneSplit`; a `FileView` keeps a `WidgetScrollPane` as
  its scroll.
- **A widget tree that a person or a program makes by hand** has no view document
  behind it, so the widget is the only home of its state.
- **One widget at two places** exists in two cases: a widget in content, such as
  the `WidgetTable` in a vertex of the graph example, and a widget tree made by
  hand that shows in a tab and in a card.
- **About 45 content types keep state of one showing now.** About 32 have a field
  `collapsed`; the others have fields such as `Roster.anchor`,
  `TaskGroupDocument.shown` and `GraphGraph.highlight_vertex`.

### 11.3 The views that exist, against the rules of the pilot

No view document of the older rule has the field `viewed` or the supertype
`ContentView`. No view of the pilot holds its content with `hold_documents!`, which
the older rule asks for.

| View document | Names its content | Holds its content | Notes |
| --- | --- | --- | --- |
| `DataFrameView` | `frame`, no `get_edited_field` | The frame is no document | The caret, the filter, the sort and the scroll are in the view. It keeps what the last read of the frame saw, so two views read the frame two times. Its rows are made from their index when a path reaches them. |
| `ChartPlot`, `SequenceChartPlot` | `chart`, no `get_edited_field` | No | |
| `GraphLayout` | `graph`, no `get_edited_field` | No | One node for each vertex and edge, so it is a mirror tree. `GraphGraph` keeps the highlight too. |
| `WorkspaceExplorer`, `DocumentTree` | `workspace`, `root`, no `get_edited_field` | Yes | |
| `Navigator`, `FileView`, `UrlView` | `get_edited_field` | Not checked | |

Two functions make a view: `make_document_view`, which the navigator and the
dashboard card call and whose default answers the document itself, and
`make_content_view` of the pilot.

### 11.4 `PrimitiveString`

It is a string in a box, plus a caret. It has two uses.

- **A slot that takes any document**, such as `ResearchQuestion.statement`. The box
  is the content, and it keeps the caret too, as `TextBlock` did before the pilot.
- **A cell of a data frame that a person opens** (`make_data_frame_cell`). The
  string lives in the frame; the box holds a copy, the caret and the text before
  the commit. This use is a view in disguise, but it holds a copy and not the
  place of the string.

`ObjectField` names the place of a value, holds no copy and keeps the caret. 313
document fields are a plain `String`, and the caret in them is a step in the view
of the owner, such as `.value{3}`, so they need no view of a string.

### 11.5 How the path of the caret is kept

A caret is a path, and each view on the path keeps its part. So a type with no
state of its own, such as a Markdown paragraph, has a view only because a path
goes through it. Three options were named on 2026-11-16:

1. A view type for each type on a path, by hand or by a macro: 300 to 400 types.
2. One generic view type for a type with no state of its own, and a view type of
   its own only for a type with state of its own.
3. No view for a type with no state of its own; the nearest view above keeps the
   rest of the path, and a printer of a part below gets the caret from it.

The owner decided option 2 (decision 3 of section 11.1), and decided against the
mechanism of option 3 (decision 4). The facts below gave the reasons.

**The 12 views of the pilot are 4 shapes.**

| Shape | View types |
| --- | --- |
| `viewed` only | `JsonNullView`, `JsonBoolView`, `JsonNumberView`, `JsonStringView`, `MarkdownTextView`, `SyntaxLeafView` |
| `viewed` and the views of the children | `MarkdownParagraphView`, `MarkdownHeadingView`, `MarkdownRootView` |
| `viewed`, the views of the children and a fold | `JsonArrayView`, `SyntaxNodeView` |
| `viewed`, the look and the closed folds | `TextView` |

- Nine have no state of their own. The four Markdown views have no behaviour of
  their own. The four JSON leaf views have none of their own either: they share
  the key table of `JsonView`.
- The key tables of the views repeat the tables of their content with another
  helper: `@gestures JsonView` repeats 7 of the 8 rows of `@gestures JsonDocument`,
  `@gestures JsonArrayView` the row of `JsonArray`, and the tables of the two
  syntax views the rows of `SyntaxLeaf` and `SyntaxNode`.
- Only `SyntaxNodeView`, which maps its folds to the text, and `TextView` have
  behaviour of their own.
- No source file outside the three view files names a view type of the pilot. The
  machinery of `Viewing.jl` works on `ContentView`.

**The same kinds of state repeat in the view documents of the older rule.**

| State | Where it is kept |
| --- | --- |
| Open nodes | `DocumentTree.expanded`, `WorkspaceExplorer.open`, `FileSystemChooser.open`, `WidgetTree.expanded`, `ThemeGroup.open_names` |
| Rows in view of a long list | `DataFrameView`, `Roster.anchor`, `TaskGroupDocument`, `FrameStatistics`, `TaskStreamLines.top_row`, `McpLog.shown` |
| Filter, sort and find | The arrangement, `DataFrameQuery`, `ExplorerFilter`, `TaskGroupDocument.row_filter`, `TaskStreamLines` |
| A window on a drawing, a cursor and a drag | `ChartPlot` and `SequenceChartPlot` share six fields; `GraphLayout` has a zoom and a drag |

**An arrangement is a generic view document.** `ArrangementDocument(document,
entries)` goes around the document that a place shows. Each entry names a part by
its path and keeps the filter, the sort, the find and the group that a person set
there. A save of the document saves no entry, and `get_edited_field` names the
document. It differs from the rules of the pilot: the field is `document`, it has
no `ContentView`, it keeps its state by path and not in a node for each part, the
caret is not in it, and it does not hold its document. A stored path does not move
when an insert moves the items (`plan/pending/an-insert-moves-the-paths-after-it.md`);
this is not tested for an entry.

`ArrangingProjection` prints the document with the arrangement in the printer
context, and a dispatch finds the entry of each place. So `main` has the mechanism
of option 3 for a filter and a sort: a view above gives its state to the printer of
a part below through the context.

### 11.6 The rules for a view, and the work for each view that exists

The rules, from `architecture-rules.md` ("Content documents and view documents",
"A type that has views"), from `naming-rules.md` and from the decisions above:

1. **A view names its content in the field `viewed`**, and its type is a
   `ContentView`.
2. **The state of one showing is in the view**, and the content holds none: the
   caret, the part under the pointer, a fold, a look, a filter, a sort, a find, the
   rows in view, a window on a drawing.
3. **`make_content_view(content)` makes the view.**
4. **A view holds the content that it shows**, with `hold_documents!` in its
   `acquire_document!`, and something holds the view only while it shows.
5. **A view with parts keeps the views of the parts** under the name of the child
   field of its content, and follows each part by identity.
6. **A save of content writes no state of a view.**
7. **A view owns no place that takes a pasted value.**
8. **A view of one kind of content takes the suffix `View`.** A view that is a tool
   of its own keeps its own name.
9. **A type has a view type of its own only for state of its own or for its own
   way to print.** Any other type on the path of a caret has the generic view
   (decision 3).

The work for each view that exists. A name in the column "Name" is proposed by the
session and not decided.

| View | Name | Content field now | Other work |
| --- | --- | --- | --- |
| `TextView` | Stays | `viewed` | Holds its content (rule 4) |
| The 11 other views of the pilot | The generic view | `viewed` | Their key tables go when the table of the content reads the caret of the view. The fold code of `SyntaxNodeView` stays as behaviour of the view of a syntax node. |
| `DataFrameView` | Stays | `frame` | The frame is no document, so rule 4 holds nothing. What the last read of the frame saw is content by rule 2, and it is in the view. |
| `ChartPlot` | `ChartView` | `chart` | Holds its content. It has a field `view`, the window on the drawing. |
| `SequenceChartPlot` | `SequenceChartView` | `chart` | Holds its content. The same field `view`. |
| `GraphLayout` | Open | `graph` | It is also the output of the layout stage. The highlight of `GraphGraph` is state of a view. |
| `WorkspaceExplorer`, `DocumentTree`, `Navigator` | Stay, each is a tool of its own | `workspace`, `root`, `content` | `Navigator.page_view` comes from `make_content_view`. |
| `FileView`, `UrlView`, `FindBarView` | Stay | `file`, `url`, `content` | Their methods of `make_document_view` become methods of `make_content_view`. |
| `ArrangementDocument` | Goes | `document` | Its entries become state of the view of their part (decision 4), and `ArrangingProjection` puts nothing in the printer context. |

The filter, the sort and the find exist five times: the arrangement,
`DataFrameQuery`, `ExplorerFilter`, `TaskGroupDocument.row_filter` and
`TaskStreamLines`. Whether they become one is open.

### 11.7 Open

For the generic view:

- How a generic view finds the key table of its content type. Now a key table
  belongs to a view type.
- How a generic view names the views of its parts. Rule 5 asks for a field with
  the name of the child field of the content, and one generic type has no such
  fields.
- Whether a node of a generic view is made only when a caret or a state reaches
  it. The view of a lazy list needs that.
- Whether a fold is state of the generic view. Then 11 of the 12 view types of the
  pilot go; else 9.

For the views of the older rule:

- `ContentView` as their supertype. `ChartPlot`, `GraphLayout` and
  `WorkspaceExplorer` have a supertype of their domain, and a type has one
  supertype.
- The released names. A rename of a field or of a type of a released package gives
  the package a minor step (decision R36 of the release plan), and `omnet-julia`
  follows each rename.
- Whether `make_document_view` goes when its methods are methods of
  `make_content_view`. Its default answers the document itself.
- Which documents that name their content with `get_edited_field` are views:
  `PaneTab`, `ClipboardSlice`, `ClipboardCollection`, `UndoBuffer`, `FileDocument`,
  `WidgetScrollPane` and `WidgetTransformPane` are not on the list above.

Other:

- What `PrimitiveString` becomes.
- Which of the about 180 types that are not decided have state of their own. With
  decision 3, each of them has the generic view where a path of a caret goes
  through it.
- State of a widget that has no view document behind it can go when the printer
  makes the widget again. This is not tested.

## 12. The order after the decisions of 2026-11-16

Replaced on 2026-11-17 by the order of section 13.3.

Proposed by the session, and approved by the owner on 2026-11-16 ("yes", to "Do
you approve this order?"). It replaces points 2 to 5 of the order of section 10;
point 1 is done.

1. **Done.** One `TextView`, and the pilot on `main`.
2. **The generic view** (decision 3). Its design starts with the four open points
   of section 11.7. Then the view types of the pilot that have no behaviour of
   their own go, and the key tables of the views with them.
3. **The rules for each view that exists** (decision 5): the field `viewed`, the
   type `ContentView`, the names, one function that makes a view, and the hold of
   the content. This point takes "who makes and holds a view in the editor" of the
   old point 2, because the navigator, the dashboard card and the tab are the
   holders, and they call `make_document_view` now.
4. **The view of a collection** (decision 4): the filter, the sort, the find and
   the group of an arrangement become state of the view of the collection, and the
   rows in view with them. This point takes "the view of a lazy list" of the old
   point 2.
5. **The tools that read a caret**: the undo, the search, the assistant and the
   drag. This is the rest of the old point 2.
6. **JSON whole, with a file in a tab.** The old point 3.
7. **The widget chains**, with a pilot of their own. The old point 4.
8. **The other domains that print as code**, one for each plan. The old point 5.
   With the generic view, a domain needs a view type only for state of its own.

The reason for the place of point 2: each later point makes or changes views, so
the form of a view comes first. The reason for the place of point 3 before point
4: the arrangement becomes state of a view by the rules, so the rules are one set
first.

## 13. The design of 2026-11-17, and the order after it

The owner and the session worked out the rules on 2026-11-16 and 2026-11-17, for
all the domains of this repository and for `omnet-julia`. On 2026-11-17 the owner
said that the rules are complete ("yes", to "Are the rules complete for you now,
so that I write the plans from this design document?"). The design is
`documentation/design/content-and-view.md`. That document is public, so it names
no private repository. This section holds what that document cannot hold: the
words of the owner, the facts of `omnet-julia`, and the order of the work.

### 13.1 The decisions of the owner

Each line gives the decision, and the words of the owner where they are short.

1. **Content has two forms, and a view has one** (2026-11-16): "content can come
   from an external library such as DataFrames.jl or it can be provided by
   projectured such as the JSON domain documents. For both cases the view
   documents are always provided by projectured and they are reactive."
2. **A content keeps no selection** (2026-11-16 and 2026-11-17): "there should be
   no selection on content documents", "no mouse target on content documents",
   and "The editing/viewing state is always added by the view parts".
3. **A reference step means what it says** (2026-11-16): "the reference step
   should not lie and should not have a document specific hack, that should be a
   rule."
4. **No generic view** (2026-11-16): "I don't like the merged view types and this
   change." This replaces decision 3 of section 11.1.
5. **The view of a list** (2026-11-16): "how about having a view for the
   CellVector as well? we could put there the arrangement parameters", and "each
   kind of list get its own view type".
6. **The tree of views mirrors the tree of content** (2026-11-17): "VectorView of
   StringViews shadowing the Vector of Strings". A view for each node, and a field
   of a fixed plain type is a part of its node: "kinda arbitrary but it's fine".
   This replaces the test of decision 1 of section 11.1.
7. **A gesture at the caret belongs to the key table of the view** (2026-11-17):
   "why isn't the caret specific operations belong to the gesture table of the
   view?" This replaces decision 6 of section 11.1.
8. **A state that must be kept is in the view** (2026-11-17): "The width should
   stay, so it really depends on what we want to store, because we only store the
   document." The printer gives the widget the cell of the view.
9. **The store of the editor writes the views with their state**; a content save,
   a search and the undo steps leave it out (2026-11-17: "Yes").
10. **`View` is the supertype of every view, with `ContentView` below it**
    (2026-11-17: "B, View for every view with ContentView below it").
11. **The supertype decides who has a selection field**, through one kernel hook
    (2026-11-17: "I agree with recommendation").
12. **`@content_view` declares a view type** (2026-11-17: "I like @content_view
    more").
13. **The view of a value element follows its index**, and it stays there when
    another library changes the collection (2026-11-17: "I agree with the first
    way").
14. **One description and one user interface for the arrangement**, kept by the
    view of each kind of collection (2026-11-17: "Yes, I agree").
15. **A view goes when nothing reaches it and its state is the default**
    (2026-11-17: "Yes, I agree").
16. **The word "shadow" names only the reactive variant of a document type with
    two variants**, and no type has the suffix `Shadow`. The content document of a
    frame is `DataFrameDocument` (2026-11-17: "Then maybe DataFrameDocument is
    better and you can store old version there if needed").
17. **A summary** is a small document of computed values, declared with
    `@native_document`, with the suffix `Summary` (2026-11-17: "the summary types
    are looking good", and "yes" to the suffix).
18. **The names**: `ChartPlot` to `ChartView` and the struct `ChartView` to
    `ChartRange`, the same for the sequence chart, and a new `GraphView` beside
    `GraphLayout` (2026-11-17: "I mostly agree").

### 13.2 The facts of `omnet-julia`

- About 186 `@document` types. 20 view kinds are below `SimulationView <:
  Document`, and they name their content in the field `subject`. The header of
  `source/presentation/view/View.jl` states the rule that a view owns nothing of
  its subject.
- `@native_document` is `@document_preset native_document [M, C]`. 22 types use
  it, and `sync_document!` keeps the reactive variant in step, for example in
  `SimulatorMonitor.refresh_monitor!`.
- Three summaries have a name that ends in `View`: `SimulationExecutionView`,
  `SimulationSessionView` and `CaptureView`. A function writes each field by hand
  when it changed. They become `SimulationExecutionSummary`,
  `SimulationSessionSummary` and `CaptureSummary`, each a `@native_document`.
  `ExecutionView` and `SessionView` are real views with almost the same names.
- Types that mix content and state of a view: `SimulationEmbed` keeps the focus,
  its history and the playback; `IniSection`, a NED node, `LegacyTestFileEntry`,
  `LegacyTestRoot` and three result types have a field `collapsed`; `ExpandStage`
  has `selected`.
- Five methods of `make_document_view`: a NED file entry, a test case, an INI
  configuration, a baseline entry and a result file entry.
- No source file of `omnet-julia` calls `@selected`.

### 13.3 The order of the work

Proposed by the session on 2026-11-17, and approved by the owner on the same day
with one condition: "Yes, I mostly agree. I would like to review the JSON domain
when it's done before the whole plan is applied to all parts of the editor." So
points 1 to 4 run first. After point 4 the session shows the JSON domain to the
owner and stops. No point from 5 to 11 starts before the owner says so, and the
review can change the design and the points after it.

Each point is a plan of its own in `plan/pending/`, with steps that are fixed
when the plan is written. Each plan leaves the tests of `main` as they are, and
each plan ends with a request to land.

Two rules make this order possible:

- **The kernel hook starts with the answer `true` for each document type**, which
  is the behaviour of today. A content family answers `false` when its domain has
  its views. The default becomes `false` in the last plan. So no domain loses its
  caret before it has views.
- **Each plan that changes an exported name or a rule has a last step for
  `omnet-julia`**: the follow of each rename, and `Pkg.precompile` with a count
  of the compiled packages.

1. **`View` is the type of every view.** The type `View`, with `ContentView` and
   the widget, layout, graphics and pane families below it. The plan is
   `plan/done/view-is-the-type-of-every-view.md`, done on 2026-11-17 on the
   branch `view-steps`. Its first form also had the
   step `.viewed` in each path of a view. That part moved to points 4 and 11 on
   2026-11-17, when the owner chose way A ("I agree with A"): the step `.viewed`
   comes for each content family together with the loss of its selection field.
   With the field still there, the selection walk of the kernel goes through
   `viewed` and writes the caret into the shared content.
2. **The declaration of a view type, and the view of a list.** `@content_view`,
   `CellVectorView`, a view that is made when something reaches it and that goes
   with its default state, and the view of an element that follows its element.
   The twelve view types of the pilot take the declaration. The plan is
   `plan/done/a-view-type-is-declared-and-a-list-has-a-view.md`, done on
   2026-11-17 on the branch `list-view`. The owner decided on 2026-11-17 that
   the memory of the views gets a general solution later, with no second time
   for the drop: "The printer is not a good place to drop stuff." The drop went
   whole on the same day (the owner: "Yes"): a list view keeps each view that it
   made.
3. **The keys at the caret.** In the domains that have views, the rows for a
   caret stay only in the key table of the view. An operation of a content takes a
   path. An edit that makes a new content gives the place of the caret.
   **This point has no plan of its own** (the owner on 2026-11-18: "Yes"). Its
   three rules are steps of point 4 for JSON, and of point 11 for the text and
   the syntax. The reason is in the code: the editor shows a text, a syntax tree
   and a JSON file as content with no view, so the key table of a content must
   keep its caret rows until its domain shows through views. The count of
   2026-11-18: 38 rows are written two times, in the table of a content and in
   the table of its view: 22 of the text, 8 of the syntax and 8 of JSON. The
   helpers of the text and of the syntax take the caret as an argument already.
4. **The first content family with no selection: JSON, whole.** The kernel hook
   with its first use. The object and its entry get views, a JSON file shows in a
   tab through its view, and the 43 calls of `@selected` start to go. The paths
   of the JSON views take the step `.viewed`, with the two functions that change
   a path between a view and its content. A view of a content that still keeps a
   selection, such as a syntax view or a text view, keeps the form of today. The
   two selection walks of the kernel get one answer for a document with no
   selection field. **This point ends with the review of the JSON domain by the
   owner.**
   **This point is three plans** (the owner on 2026-11-18: "Yes"). The reason is
   in the code: a content can lose its caret only when the editor shows it
   through views, and the editor uses no JSON view now. A tab holds a JSON file
   through a file and an undo buffer, and these have no view.
   - **4a. Each JSON node has a view.** Views for the object, the entry, the
     place for a new value and the empty place. The rule of `@content_view` for
     a field that takes any document. The keys of JSON in the key tables of the
     views. The editor does not change. The plan is
     `plan/done/each-json-node-has-a-view.md`, done on 2026-11-18 and on
     `main`. It found two places where a print reads the caret of its
     content, which plan 4c and point 11 must take: the reader of a node in
     `SyntaxToText.jl`, and the Tab of the printer of the place for a new value.
   - **4b. A file tab shows a content through its views.** The views of the
     file, of the undo buffer, and of the place for a new value of every
     domain. The JSON content keeps its selection field, with no use in a tab.
     **This plan is two plans** (the owner on 2026-11-18: "yes", with the plan
     of 4b1). The reason: about a dozen features of the editor name a place by
     a path through the content, and about 20 test files outside the JSON
     suite open a JSON file.
     - **4b1. A file and its undo steps have views.** The views and their
       printers, with no change of the editor: the rows of the general
       renderer for a view, the view of the undo buffer as a link with no
       state (the owner on 2026-11-18: "yes"), the write of the root value, a
       caret in a part that has no view, the field `content` of `FileView`,
       and the views of the place of every domain. The plan is
       `plan/done/a-file-and-its-undo-steps-have-views.md`. It is done on
       the branch `file-views` on 2026-11-19, and it waits for the landing.
     - **A measurement.** In a copy of the repository, each file view of a
       JSON file is made with views, and the suites of the editor run there.
       The list of the failures gives the steps of 4b2. The copy lands
       nowhere.
     - **4b2. The editor shows a JSON file through its views.** The JSON
       domain turns the views on for its files, and each feature that names a
       place by a path through the content takes the path through the views.
   - **4c. The JSON content keeps no selection.** The kernel hook, the step
     `.viewed`, the caret place in an operation, the key tables of the content,
     and the tests that put a caret into a JSON content. Then the review of the
     owner.
5. **The state to keep, and the store of the editor.** The store writes the views.
   A printer gives a widget the cell of the view for each state to keep. The
   eighteen types with `get_view_state_fields` move that state to a view.
6. **The arrangement in the view of a collection.** One description and one user
   interface. `ArrangementDocument` and the printer context of
   `ArrangingProjection` go. `row_filter`, the filter of the explorer, the query
   of a data frame and the lines of a task stream take the one description.
7. **The view documents of the older rule.** `viewed`, `ContentView` and
   `make_content_view` for `DataFrameView` with `DataFrameDocument`, `ChartView`
   with `ChartRange`, `SequenceChartView`, `GraphView`, `WorkspaceExplorer`,
   `DocumentTree`, `Navigator`, `FileView`, `UrlView` and `FindBarView`.
   `make_document_view` and `follow_content_selection!` go.
8. **The boxes.** `PrimitiveString`, `PrimitiveNumber`, `PrimitiveBool` and
   `ObjectField` keep no selection, and each gets its view.
9. **The other domains that print as code**, one plan for each domain. The view
   types come from `@content_view`, the content family answers `false` to the
   hook, and each fold moves to its view.
10. **The widget domains and the documents of the session**, about 180 types. One
    plan sorts them into content and view, and one plan for each group converts
    it.
11. **The end.** The text and the syntax keep no selection, and the paths of
    their views and of the text of a widget take the step `.viewed`. The field
    step of a `ContentView` to its content goes. The default of the kernel hook
    becomes `false`. A guard checks that only a `View` has a selection. The
    section "Content documents and view documents" of `architecture-rules.md`
    takes the rules of the design document.

The work of `omnet-julia` itself has plans in that repository after point 4: the
summaries, `SimulationView` below `ContentView`, the field `viewed`, and the types
that mix content and state of a view.

The reason for the order. Point 1 gives each later point the type that it
declares a view below. Point 2 gives the form in which each later point declares
a view. Point 3 comes before point 4 because a content can lose its
caret only when no row of its key table reads it. Point 4 proves the whole design
on one domain before the other domains follow.
