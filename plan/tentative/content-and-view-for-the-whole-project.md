# Content and view for the whole project: the picture for the decision

Status 2026-11-15: for a decision of the owner. This document has no steps. If the
owner decides to go on, the steps come in a plan of their own.

The pilot is `plan/pending/views-compose-as-content-composes.md`, on the branch
`views-compose`. Its steps 1 to 7 are done. This document says only what differs
from `main`.

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
  (`plan/pending/one-text-view-keeps-the-look-and-the-caret.md`).
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
     `plan/pending/one-text-view-keeps-the-look-and-the-caret.md`.
  2. Design and build the three parts that each domain needs: who makes and holds a
     view in the editor, the view of a lazy list, and the tools that read a caret.
  3. Move JSON whole, with a file in a tab. This is way A of step 8, and it is the
     first real use.
  4. Decide the widget chains with a pilot of their own, before any domain that
     prints to widgets.
  5. Move the other domains of the syntax, one for each plan.

I do not know the time of the whole move. The pilot gives the size of one small
domain of the syntax: about 150 lines of views and tables for five types, and about
300 lines of tests. The parts of point 2 and the widget chains are not measured.
