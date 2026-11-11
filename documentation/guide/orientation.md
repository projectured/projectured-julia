# Orientation — read first, then search

> **Kind:** reference · **For:** user · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md), [system-anatomy.md](../design/system-anatomy.md)

What the assistant of a window can do, each capability in code: find a part, read
it, change it, show a result, control the window, work with files, and run long
work. Every example runs in `execute_julia_code`, and every name in it is one that
the window offers. The text of the window lists the names by module, and
`search_api` reads the documentation of each.

## Find a name and a guide

Search before you write code, and never guess a name or a signature:

- `search_api("open a tab")` finds the name to call: a module, a type or a
  function. One clear hit comes back with its whole documentation.
- `search_guides("selection")` finds a section of a guide, with the
  `resource://guide/<name>#<heading>` name that `read_resource` reads it by. It
  searches the guides for users; `audience = "developer"` searches the guides
  about the code of the editor.
- Both take `mode`: `"keywords"` by default (`+word` must match, `-word` must not,
  `a|b` is either, `"a phrase"`), `"regex"`, or `"description"` for a sentence
  that says what you want to do. `detail` is `"names"`, `"summary"` or `"full"`.
- `read_function_documentation` reads the documentation of one function.

## Find a part

A part is a place in the window and what is there: a tab, a document in it, or a
piece of that document. A verb takes a part as it is. Find one with a verb, and do
not walk the tree of the window:

```julia
items_tab_1 = find_pane("items.json")      # the tab of that title
here_1 = find_focused_pane()               # the tab where the person works
this_1 = find_selected_part()              # what the person selected
under_1 = find_part_under_pointer()        # what is under the mouse pointer
```

`search_documents(document, query; places = true)` answers each part of a
document that matches `query`. `query` is a function of a node that answers
`true` or `false`, or a `String` or a `Regex` that the text of a leaf matches. A
search finds each node once, stops at 100 matches and at 100,000 visited nodes,
and the first line of its answer names the limit that stopped it: `limit =
nothing` and `maxvisits = nothing` lift them.

Search inside the data of one tab, not inside the whole window. Two tabs can show
the same value, and a match of a value alone finds both. Match the type of the
domain too:

```julia
items_1 = get_edited_document(items_tab_1)
lamps_1 = search_documents(items_1, node -> node isa JsonString && node.value == "lamp"; places = true)
```

## Reach what a tab holds

`find_pane(title)` answers the tab of that title. `get_edited_document(tab)`
answers the data that the tab shows, through the file and the history that hold
it. A part acts like its data: read a field, index it, iterate it. Every document
or collection that a read answers is a part too; a string, a number or a `Bool`
comes back plain.

Look at the data first, in one call. Here a tab shows `items.json`, a JSON array
of records with a name and a price:

```julia
items_tab_1 = find_pane("items.json")
items_1 = get_edited_document(items_tab_1)
println(print_natural_text(items_1))
```

Then use the same variables in the next call. A `JsonArray` acts as a vector, and
a `JsonObject` as a map from key to value; the field value of a leaf is its plain
value. Build the rows of a table and sort them in one call, with a comprehension
in its brackets: `sort` takes a vector, not a generator.

```julia
rows_1 = sort([[item["name"].value, item["price"].value] for item in items_1]; by = first)
table_tab_1 = open_pane!(WidgetTable(["name", "price"], rows_1); title = "Items by name")
```

To change what a tab shows, give the part and its new value to
`replace_referenced_value!`, so the change is an edit that Ctrl+Z can undo:

```julia
replace_referenced_value!(items_1[2]["price"], parse_natural_text(:json, "12"))
```

To add a record, or to remove one, use `insert_elements!` and `delete_elements!`,
which take the collection and a 1-based index:

```julia
item_1 = parse_natural_text(:json, """{"name": "lamp", "price": 25}""")
insert_elements!(items_1, length(items_1) + 1, [item_1])
```

Each of the three records the edit in the history of the file, so Ctrl+Z in the
tab of the file takes it back.

## Read what the person does and what the window shows

"This" in a message is the part that the person selected. Read it, say what it
is, and print its text:

```julia
part_1 = find_selected_part()
println(describe_document(part_1))
println(print_natural_text(part_1))
```

A part that has no text of its own domain, such as a widget or a chart, prints as
the constructor that builds it, with `print_pred_text(part)`.
`describe_undo_history()` says what changed last, and the logs of the session
print as text:

```julia
println(describe_undo_history())
println(print_natural_text(get_session_gesture_log()))
println(print_natural_text(get_session_message_log()))
```

`read_os_clipboard()` answers the text that the person copied.

## Change a document

Change a document only with a verb. A direct write, such as
`items_1[2]["price"].value = 12`, changes the data outside the edits of the
editor: Ctrl+Z can not take it back, and the editor does not check it.

- `replace_referenced_value!(part, value)` puts a new value at a part.
- `insert_elements!(collection, index, values)` and
  `delete_elements!(collection, index)` add and remove elements.
- Write a new value as the text of its domain: `parse_natural_text(:json, text)`
  reads one JSON value, `:md` reads Markdown and `:jl` reads Julia.
  `describe_natural_formats()` lists the formats.

A part also has the commands that a key or the command palette runs for the
person. List them, and run one by its words:

```julia
println(describe_commands(items_1))
run_command!(items_1, "Insert a new element")
```

Several edits can be one step of the undo. `make_change` makes the change of a
verb as a value and changes nothing; `combine_changes` joins changes, and
`apply_change!` applies the group. Make the changes of one collection from its
last position to its first, so that one change does not move the place of the
next:

```julia
apply_change!(combine_changes(make_change(delete_elements!, items_1, 3),
                              make_change(delete_elements!, items_1, 1)))
```

## Show a result in a tab

**Do the work without a tab.** A value that a call answers shows in the
conversation, and a task that a call starts is a row of the task list. Open a tab
only when the person asks for one, or when the conversation shows that the person
wants to see it now, and then show it.

`open_pane!(document; title)` puts any document in a tab, behind the tab that its
group shows, and answers the new tab. The focus of the person stays where it is.
`show_pane!(tab)` brings the tab to the front when the person must look at it:

```julia
table_tab_2 = open_pane!(WidgetTable(["name", "price"], rows_1); title = "Items")
show_pane!(table_tab_2)
```

To put the tab before another tab, or at the end of a group, give that tab or
group as `target`. To put it in a new pane beside or under the group of the
target, add `side`: `:left`, `:right`, `:above` or `:below`. `get_parent(editor,
tab)` answers the group that holds a tab:

```julia
table_tab_3 = open_pane!(WidgetTable(["name", "price"], rows_1); title = "Items",
                         target = get_parent(editor, items_tab_1), side = :below)
```

To draw, put shapes and text on a canvas. The coordinates are pixels from the top
left of the canvas:

```julia
sketch_1 = GraphicsCanvas([
    GraphicsRect(10, 10, 160, 50; color = StyleColor(0.85, 0.9, 1.0, 1.0)),
    GraphicsText("the queue", 20, 40; font = StyleFont("DejaVu Sans", 14)),
    GraphicsLine(170, 35, 230, 35; color = StyleColor(0.0, 0.0, 0.0, 1.0), width = 2),
    GraphicsCircle(250, 35, 15; color = StyleColor(0.85, 0.2, 0.2, 1.0))]; w = 280, h = 70)
sketch_tab_1 = open_pane!(sketch_1; title = "Sketch")
```

A chart and a graph are documents too:

```julia
chart_1 = Chart("Lamps sold", [ChartLineSeries("2025", collect(1.0:12.0), sales_1)])
open_pane!(chart_1; title = "Sales")
paris_1 = GraphVertex(PrimitiveString("Paris"))
lyon_1 = GraphVertex(PrimitiveString("Lyon"))
open_pane!(GraphGraph([paris_1, lyon_1], [GraphEdge(paris_1, lyon_1)]); title = "Roads")
```

A coordinate of a shape can be a function of no arguments. When it reads the
clock of the editor, the shape moves on each frame, and it stops when its tab
closes:

```julia
orbit_1 = GraphicsCanvas([
    GraphicsCircle(() -> 100 + 60 * cos(get_reactive_clock_time(editor.clock)),
                   () -> 100 + 60 * sin(get_reactive_clock_time(editor.clock)), 10;
                   color = StyleColor(0.2, 0.4, 0.8, 1.0))]; w = 200, h = 200)
open_pane!(orbit_1; title = "Orbit")
```

More ways to show:

- `open_page!(part)` opens one part of a large document as a page of its own, in
  a new tab.
- `select_part!(part)` selects a part to show it to the person. It is the one
  verb that moves the selection of the person.
- `show_roster!(source; title, columns)` shows a table of the members of one kind,
  gathered from the whole window: `TabDocuments(FileDocument)` gives the files of
  the tabs. `describe_roster_sources()` says which sources exist.
- `show_document_tree!(root; title)` shows a document as a tree.
- `write_os_clipboard!(text)` gives the person a text to paste.

## Control the window

`show_layout()` prints each window, split, group and tab, with the path steps
that reach it. `show_pane!`, `move_pane!` and `close_pane!` arrange the tabs.
`focus_pane!` also moves the focus of the person, so do not call it: the person
moves their focus. `describe_settings()` lists the settings of the window, and
`change_setting!` changes one:

```julia
println(show_layout())
println(describe_settings())
change_setting!(:partial_render, false)
```

The tool `undo` takes back the last change, as Ctrl+Z does, and `redo` puts it
back. The tool `take_picture` shows you what the window draws.

## Work with files

`open_file!(path)` opens a file in a tab and answers the tab; a file that is open
keeps its tab. `save_file_to_disk!(tab)` writes it, as Ctrl+S does, and
`reload_file_from_disk!(tab)` reads it again, as F5 does:

```julia
notes_tab_1 = open_file!("notes.json")
notes_1 = get_edited_document(notes_tab_1)
replace_referenced_value!(notes_1["done"], parse_natural_text(:json, "true"))
save_file_to_disk!(notes_tab_1)
```

A picture file is a file document too. Get it with `open_file_document!`, so that a
card, a zoom tab and a file tab share one document of the path, and each of them
shows the new picture after a program writes the file again:

```julia
throughput_1 = open_file_document!("media/throughput-new.png")
delay_1 = open_file_document!("media/delay-new.png")
charts_1 = Dashboard("Charts", [DashboardCard("Throughput", throughput_1),
                                DashboardCard("Delay", delay_1)])
open_pane!(charts_1; title = "Charts")
zoom_tab_1 = open_pane!(WidgetTransformPane(throughput_1); title = "Throughput")
show_pane!(zoom_tab_1)
```

A document that a call returns shows as a live card, so a picture file as the last
value shows its picture in the conversation. The conversation holds no document, so
that picture does not follow its file.

`read_document_file(path)` reads a file into a document without a tab, and
`write_document_file(document, path)` writes a document to a file.

The explorer is a tab of the window: a tree of sections and entries beside the
page of the selected node. `find_explorer_content()` answers its root section,
and `format_tree_node_label` gives the label of an entry as the tree shows it. Add
a document with an insert into the entries, such as a dashboard of cards:

```julia
content_1 = find_explorer_content()
println([format_tree_node_label(entry) for entry in content_1.entries])
study_1 = Dashboard("Queue study", [DashboardCard("Notes", ExplorerSection("Notes"))])
insert_elements!(content_1.entries, length(content_1.entries) + 1, [study_1])
open_explorer_page!(content_1.entries[length(content_1.entries)])
```

## Run long work and tasks

Code that needs no document of the window, such as a long computation or a wait
for a process, runs with the argument `background` of `execute_julia_code` set to
true. The person can use the window while it runs. Code in the background reaches
a document only through the verbs.

A group of tasks is a set of programs that the window runs and shows.
`list_task_groups()` answers one line for each group of the session, with its
identifier and its title. `find_task_group(name)` answers the group of an
identifier or a title. `describe_task_group(group)` says how far a group has come,
and `get_task_output`, `stop_tasks!`, `rerun_tasks!` and `close_task_group!` act
on it:

```julia
println(list_task_groups())
build_1 = find_task_group("T1")
println(describe_task_group(build_1))
```

## Keep what you found

Each call of `execute_julia_code` runs in the same module, so a variable that one
call binds at the top level is still there in every later call. Keep each object
that you find or make in its own variable, named by what it holds and numbered:
`items_tab_1`, `items_1`, `rows_1`. When you make another object of the same kind,
give it the next number, `rows_2`, and do not overwrite the first.

The person edits the window between your turns: a key, an undo or a click can
change what a variable of an earlier turn shows. Read a document again before you
tell the person what it holds.

- A field of a document reads as its value: write `node.field`, not
  `node.field[]`.
- A part is not an instance of the type of its document. `describe_document(part)`
  says what it is, and `print_natural_text(part)` shows its text.
