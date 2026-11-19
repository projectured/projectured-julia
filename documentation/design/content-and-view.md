# Content and view

> **Kind:** design · **For:** developer · **Status:** in design, built in part · **Stands on:** [concepts.md](concepts.md), [architecture-rules.md](../rule/architecture-rules.md)

This document is the design of content and view, in three layers: a value, a
content document and a view. It gives the rules that each domain and each
downstream program must follow, with the reason for each rule. The code does
not follow all of it yet: the last sections say where the code differs, which
names change and which points are open.

The rule that the code follows today is "Content documents and view documents"
in [architecture-rules.md](../rule/architecture-rules.md). When this design is
built, that section takes these rules.

## Three problems

Take a sequence of characters that a person edits on the screen. Three problems
come one after the other.

1. **Identity.** A Julia `String` cannot change. Each edit makes a new string,
   so the string has no identity. A number such as `42` has none either. A thing
   with an identity can be at many places, and a program can remember it.
2. **The state of editing.** A caret must be somewhere. A `String` has no place
   for it.
3. **The state of viewing.** A long text can be folded. A list can be filtered
   and sorted. A table has a row at the top of its window.

A person can edit a bare `String` with no solution to any of the three. An
operation that names a range of the string replaces that range, and the place
that holds the string takes the new string. A number changes by an increment
operation in the same way. So an edit needs no caret and no identity.

## Three layers

**A content** is what a thing is. It is a value or a content document. **A
view** keeps the state of one showing of a content. Each layer solves one of the
problems and adds nothing else.

| | Value | Content document | View |
| --- | --- | --- | --- |
| What it is | a content that is a plain Julia value | a content that is a document | the state of one showing of a content |
| It adds | nothing | an identity, and changes that a reader of its cells sees | the caret and each other state of a showing |
| Examples | `"abc"`, `42`, a `DataFrame`, a `Vector{String}` | `PrimitiveString`, `JsonString`, `JsonArray` | `JsonArrayView`, `DataFrameView`, `TextView` |
| Identity | none for an immutable value | yes | yes |
| Reactive | no | yes | yes |
| Caret, fold, filter | none | none | yes |
| Where it is saved | in the content document that holds it | in its file | in the store of the editor |

- **A value** comes from Julia or from another library. A mutable value, such
  as a `DataFrame`, has an identity, and it changes with no notice to a reader.
- **A content document** is a document of this program. **A box** is a content
  document with one field, which holds one value: `PrimitiveString` gives a
  `String` an identity. A domain document such as `JsonArray` says what a thing
  is in its domain.
- **A view** is a document of this program too. It names the content that it
  shows, and it keeps the state of one showing.

A person can edit each layer with operations. A view adds the gestures that act
at a caret.

## The tree of views

**The tree of views mirrors the tree of content.** Each node of the content has
a view, and the view of a node holds the views of the nodes below it.

**A node** is one of these: a document, a collection, an element of a
collection, or the value in a slot that takes any value.

**A field of a fixed plain type is a part of its node.** `JsonString.value` is a
`String`, and the view of the `JsonString` keeps the path into it. That field
gets no view of its own. The choice is a convention: it keeps one view for one
JSON string.

**A view is made when something reaches it**: a caret, a state, or the window of
a list. A list of a million elements does not make a million views.

**A node that has no state of its own has a view too.** An undo buffer prints
nothing of its own, and no caret stops at it. Its view keeps no state: it is the
link between the view of the file above it and the view of the document below
it. So the path of a caret has a way down through the views, the printer of the
undo buffer stays on the path of a key, and the write of the document of the
buffer has a place.

**A view goes when nothing reaches it and each of its fields has its default
value.** A new view is then equal to it, so no state is lost. Something reaches
a view when a caret path goes through it, when it is in the window of its list,
or when a place such as a tab shows it. So the memory of the views is what a
person changed and what is in view, with no cap. A print can be thrown away and
made again at any time, because each state to keep is in a view.

A JSON array with a nested array:

```
JsonArrayView                 viewed = array          selection = .elements[3].elements[1].viewed.value{2}
  elements: CellVectorView    viewed = array.elements selection = [3].elements[1].viewed.value{2}
    [3] JsonArrayView         viewed = nested         selection = .elements[1].viewed.value{2}
          elements: CellVectorView                    selection = [1].viewed.value{2}
            [1] JsonStringView  viewed = JsonString   selection = .viewed.value{2}
```

A vector of strings of another library:

```
strings: Vector{String}       the content
VectorView                    viewed = strings        selection = [42].viewed{3}
  [42] StringView             viewed = strings[42]    selection = .viewed{3}
```

The `StringView` of element 42 reads `strings[42]`, and an edit writes that
element. It holds no copy of the string. The vector has the identity, and the
index names the place.

**The view of an element follows its element.** An element that is a document
has an identity, and its view follows it by identity. An element that is a value
has none, and its view follows its index. An operation of the editor that
inserts or removes an element moves the views after that place by one index.
When another library changes the collection, each view stays at its index.

## The rules of a content

1. **A content keeps no state of a showing.** It has no selection, no part under
   the pointer, no fold, no filter and no scroll. A box, a domain document, a
   shadow and a summary follow this rule. So one content can be at many places,
   and each place can have its own caret.
2. **An operation belongs to the content.** It is a function that takes the
   content and a path or a range, and it makes the edit. It needs no caret.
3. **The key table of a content type holds only the gestures that need no
   caret**, such as the save of a file.
4. **An edit that makes a new content gives the place of the caret in its
   operation.** The new content does not keep a caret.
5. **A save of a content writes only the content.**

## The rules of a view

1. **Each view is a `View`, and a view of one content is a `ContentView` below
   it.** A `ContentView` names its content in the field `viewed`. A family of
   views has an abstract type below `ContentView`. A view type never has the
   supertype of a content type.
2. **A widget and a layout are views of a second kind, and their families are
   below `View` too.** Each keeps the state of its own showing in fields of its
   own, and it keeps the path of the caret into what it holds. It has no field
   `viewed`.
3. **A view shows a content that a program can find again**: a content
   document, a mutable value, or a place in one of these. A view never holds an immutable
   value in a cell of its own, because that view is then a box with a caret.
4. **The caret is in the view of its node.** Its path is the step `.viewed` and
   then the path inside the node. Each view above keeps the rest of the path
   from itself.
5. **A reference step means what it says, on every value.** No type gives a step
   another meaning. A step to a field that a view does not have fails, as it
   does on any document.
6. **A gesture that acts at the caret belongs to the key table of the view.**
   Its row reads the caret of the view and calls the operation of the content. A
   view reads a key with its own table first, then with the table of its
   content.
7. **Each kind of list has its own view type.** The view of a list is a list of
   the views of its elements, in the order of the content. So the step `[3]`
   names element 3 of the content.
8. **The view of a collection keeps the arrangement**: the filter, the sort, the
   find and the group. The arrangement changes only which elements show, and in
   which order. It never changes what a path names. Each view of a collection
   keeps its arrangement as the same documents, and the filter language, the bar
   and the keys exist one time. Each kind of collection computes the elements
   that show in its own way: a list of documents reads each item, a data frame
   runs loops over its columns, a tree keeps the rows above a match, and a
   stream of lines reads its index of the file. A change of an arrangement is
   state of a view, so it is no undo step.
9. **Two functions make a view, and each has one job.**
   - `make_content_view(content)` makes the view of one content. Each level of
     the tree of views calls it: each child field of a view, and each element
     of the view of a list. Its default answers `nothing`, and the caller then
     shows the content with no view. It makes nothing that only a place needs,
     so it makes no scroll pane.
   - `make_page_view(content)` makes the document that fills a place: a tab,
     the page of the explorer, or a card of a dashboard. That document is the
     view and what the place needs around it, such as a `WidgetScrollPane` or
     the band of a file. Only the code that opens a place calls it, and only
     for the content that fills the place. Its default answers
     `something(make_content_view(content), content)`, with no pane.

   ```julia
   make_page_view(root::WorkflowStep) =
       WidgetScrollPane(make_content_view(root); grows = (width = false, height = true))
   ```
10. **A view of one kind of content takes the suffix `View`**
    ([naming-rules.md](../rule/naming-rules.md)).
11. **Only a `View` has the fields `selection` and `mouse_target`.** `@document`
    adds them to a type when the hook `keeps_selection` of the kernel answers
    `true` for the supertype of the type. The default is `false`, and the
    platform declares `true` for `View`. So no view type writes the two fields,
    and the kernel has no notion of a view.
12. **`@content_view` declares the view type of a content type.** It reads the
    fields of the content type when it expands. It makes the field `viewed`,
    one field for the view of each child field, the constructor and the method
    of `make_content_view`. A person writes only the state and the key table
    that are specific to the view type.

    ```julia
    @content_view JsonArray struct JsonArrayView <: JsonView
        collapsed::Bool = false
    end
    @content_view JsonString struct JsonStringView <: JsonView end
    ```

## The state of a showing: in the view or in the widget

A printer makes most widgets, and a chain of projections keeps a widget while
the input of its stage is the same object at the same place. A print makes the
widget again in five cases: the input is replaced, the view shows at another
place, a person changes the projection, a lazy print drops a part that is out of
view, and the editor starts again.

**A state that must be kept is a field of a view.** The printer gives the widget
the cell of that field, so the view and the widget share one cell and nothing is
copied. Every other state stays in the widget and lives as long as the print.

**The view writes a state by what it names in the content, where it can.** The
row at the top of a window and the width of the column `name` survive a change
of the projection. A state that names only a part of a print gets a field with a
name of its own, such as the width of the tree of an explorer.

| State | Kept | Home |
| --- | --- | --- |
| The caret, a fold, a filter, a sort, the open folders | yes | view |
| The row or the element at the top of the window | yes | view |
| The width of a column | yes | view |
| The width of a split that a printer makes | yes | view |
| The pixel offset inside the top row | no | widget |
| The highlight under the pointer | no | widget |
| A drag that is in progress | no | widget |

A lazy list is one reason for this rule. The list must read which elements are
in view before it prints them, so that state cannot be in a widget that the
print makes later.

## What is stored

| Job | What it writes or reads |
| --- | --- |
| The save of a content file | the content, and no view |
| The store of the editor at the close of a window | the views with all their state, and each content that is no file |
| A search of the documents | the content, and no state of a view |
| The undo steps | the edits of a content, and no change of the state of a view |

The editor stores only documents and never a print. That is why a state that
must be kept is in a view.

## A content that is not reactive

A mutable value of another library changes with no notice. One view that makes
each edit through the editor can keep a version of its own. Two views of one
value, or a change from outside the editor, need one reactive thing that the
views share.

Three tools give them that thing. Each is a tool for a use that needs it, and
none is a layer of the model.

**A shadow** is the reactive variant of a document type that also has a mutable
variant. `sync_document!(shadow, source)` keeps the shadow in step with the
mutable variant, and it writes a cell only when a value changed. A policy can
stop the walk at a depth or at a count, so a sync need not read the whole tree.
The word names only this variant, and never a view. The two variants keep the
type names that `@document` gives them.

**A content document of a library value** holds a mutable value of another
library in a cell. For a `DataFrame` it is a `DataFrameDocument`. Each view of
the frame names this document in `viewed`. An operation that changes the frame
inside writes the frame into the cell again. A write of a mutable value makes
each reader of the cell compute again, also when the value is the same object,
so all the views see each edit. The document can also hold what the last read
of the frame found, so that a check for a change from outside the editor
compares against it. A `FileDocument` has the same form for a file on a disk.

**A summary** is a small content document of values that a program computes
from a state that is not reactive, such as the count of events of a run. Its
type has a mutable variant and a reactive variant. The program fills the mutable
variant, and `sync_document!` writes the reactive variant, which is its shadow.
The name of a summary type ends in `Summary`.

## Why not otherwise

- **A caret in the content.** Two views of one content cannot have two carets
  then, and one content at two places has one caret by force. Identity exists so
  that a thing can be at many places, so the caret must be in another object.
- **A view that holds a value.** A `StringView` with the string in its own cell
  is a box with a caret. A second view cannot show the same string. The box and
  the view must be two objects.
- **One generic view type for each content type.** A content type can need a
  state that another does not have, such as a fold, and a difference of one view
  type must have a place. So each node type has a view type of its own.
- **No view for a node that has only a caret.** The view above then keeps the
  path into that node. Some nodes then have a view and some do not, and a caret
  has two forms.
- **A view that repeats the state of each widget.** The view must then name each
  widget that a later stage makes, and another projection needs other fields.
- **A field step that a view sends to its content.** Other code reads a step as
  a real step. A step with two meanings breaks that code.
- **One function for the view and for the page.** `make_content_view` runs at
  each level of the tree of views. A scroll pane from it is then around each
  node, for example around each step of a workflow. A place needs things around
  the content that no level of the tree needs.
- **A scroll pane that `open_pane!` adds.** `open_pane!` puts a document at a
  place. What the document is, is not its job.
- **A scroll pane at every place.** A content that needs no scroll then gets a
  pane too.
- **A scroll pane that a printer adds.** The pane is a document, so it must be
  in the tree of documents.

## The code now

The code differs from this design in these places.

- `@document` adds the fields `selection` and `mouse_target` to each document
  type, so each content can keep a caret. `PrimitiveString` and `ObjectField`
  keep one.
- `ContentView` in `source/platform/projection/higherorder/Viewing.jl` sends a
  field step that a view does not have to the field `viewed`.
- Twenty view types have the declaration: `TextView`, three syntax views, the two
  views of the place of every domain, the view of an undo buffer, nine JSON views
  and four Markdown views. `@content_view` makes a child field for a
  list that is declared as a `CellVector`, and for a field that is declared as
  `Document`. A field that takes any value, a field of one document type and the
  lines of a text get no view of their own.
- Each node of a JSON document has a view. A file view can hold the view of what
  its file holds (`make_file_view(file; views = true)`), with the view of the undo
  buffer of the file between the two. The general renderer prints these views.
  The editor shows each JSON file through them: in a tab, on the page of the
  explorer, on a card of a dashboard and on the page of a navigator. Each of
  these places keeps a caret of its own, and the selection of the window is a
  path of the views. The page of a part inside a JSON file shows the part as
  content with no view. Of the other view types, only `TextView` shows in the
  editor, for the text of a widget.
- A place has a path through the views and a path through the content.
  `get_content_path` and `get_view_path` change one into the other at a view, and
  `find_content_path` and `find_view_path` do it for a path from a root. An
  operation, the clipboard and an assistant name content. The path of a view has
  the steps of its content, with no step `viewed`, so the two paths differ only
  where a holder keeps the content and the view in two fields.
- The page of the explorer, a card of a dashboard and a navigator keep the
  content and its view in two fields, under three names: `document_view`,
  `content_view` and `page_view`. A view that keeps a selection of its own takes
  the selection through that field. Any other view copies the selection of its
  content (`follow_content_selection!`).
- A write through a view names its place below `viewed`, as in this design
  (`make_content_edit`). A caret does not: it has the path of the content, with
  no step `.viewed`. One caret has that step already: a caret in a document whose
  type has no view type, which keeps its selection field. Its path is the steps
  to the deepest view, the step `viewed`, and the steps in the content.
- The content that holds a part with no view keeps a piece of the caret, because
  the step `viewed` names it: the list of an array, or the entry of an object.
- `CellVectorView` is the one view of a list. No plain value has a view type, so
  no view follows an index.
- A walk of a document reads each element of the view of a list, and so it makes
  the view of each element.
- No view goes. The view of a list keeps each view that it made, also the view
  of an element that left the list.
- The other view documents name their content in a field of their own:
  `DataFrameView.frame`, `ChartPlot.chart`, `SequenceChartPlot.chart`,
  `GraphLayout.graph`, `WorkspaceExplorer.workspace`, `DocumentTree.root`,
  `Navigator.content`, `FileView.file` and `UrlView.url`. `FileView` has the
  field `content` too, for the view of what its file holds. Four of them have the
  supertype of their content: the two plots, `GraphLayout` and
  `WorkspaceExplorer`.
- The function that makes the document of a place has the name
  `make_document_view`. Its default answers the content itself, and not the view
  of the content. The navigator and the card of a dashboard call it, and the
  open of a file calls `make_file_view`. No other open of a tab calls it, so a
  tab that shows a document that is no file has no scroll pane.
  `follow_content_selection!` makes the selection of a view follow the selection
  of its content.
- Eighteen types declare fields of view state with `get_view_state_fields`.
  About 45 content types keep state of a showing, and most of it is a field
  `collapsed`.
- The key table of a content type and the key table of its view hold the same
  rows for a caret, for example `@gestures TextBlock` and `@gestures TextView`.
- 43 calls of `@selected`, in 12 files, make a content with a caret in it.
- `ArrangementDocument` keeps the filter and the sort of each place of a
  document, and `ArrangingProjection` gives them to a printer through the
  printer context.
- Five parts of the code filter or sort what a person sees: the arrangement,
  `DataFrameQuery`, `ExplorerFilter`, the field `row_filter` of
  `TaskGroupDocument`, and `TaskStreamLines`. They share the filter language and
  the sort by a click on a header. Each has its own state, its own find, and its
  own rule for the undo steps. `row_filter` is a field of a content document.
  `ExplorerFilter` makes a second tree with paths of its own.
- `DataFrameView` keeps the version of its frame and the result of its last read
  in each view, so two views read the frame two times.
- The store of the editor uses the save of a file, which leaves each field of
  view state out.

## The names that change

| Now | In this design | Reason |
| --- | --- | --- |
| `ChartPlot` | `ChartView` | it is the view of a `Chart` |
| the struct `ChartView` | `ChartRange` | it is the range of data that shows, a value of a field of the view |
| `SequenceChartPlot` | `SequenceChartView` | it is the view of a sequence chart |
| the struct `SequenceChartView` | `SequenceChartRange` | the same reason as for the chart |
| `GraphLayout` | `GraphLayout` and a new `GraphView` | the positions are the output of the layout stage; the zoom, the shape of the edges and the highlights are state of a view |
| `DataFrameView.frame` | `viewed`, a `DataFrameDocument` | all the views of one frame read one cell |
| `make_document_view` | `make_page_view` | it makes the document that fills a place, and `make_content_view` makes a view |
| a summary of a downstream program with a name that ends in `View` | a name that ends in `Summary` | it is content, and views read it |

## Open points

1. **The name of the kernel hook.** `keeps_selection` is a working name.
2. **The child fields that `@content_view` reads.** The macro reads the lists
   that are declared as a `CellVector`, and the fields that are declared as
   `Document`. Its form is not written for a field that takes any value, for a
   field of one document type and for the lines of a text.
3. **The sort of each document type that is left.** About 180 document types of
   the widget domains and of the session are not sorted into content and view
   yet. The rules of this document decide each one.
4. **The memory of the views.** The view of a list keeps each view that it made.
   The memory of a lazy structure needs one general solution, which is not
   designed. A printer is not the place that frees memory.
