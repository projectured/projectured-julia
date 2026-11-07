# File format

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [natural.md](../natural/natural.md), [serialization.md](../serialization/serialization.md), [roster.md](../roster/roster.md)

The file-format slice of `ProjecturedPlatform` reads and writes a document as a file, and opens a file as a tab. It adds no format of its own: it selects one of the formats that the serialization slice and the domains give, by the extension of the path. This document says how the choice is made, what a file that does not exist opens as, how a tab saves and reloads its file, and how the open files of an editor show as a table.

## How it works

### The choice by extension

`write_document_file(document, path)` and `read_document_file(path)` are the two entry points. They route a path to one of three formats, in this order:

| Extension | Write | Read, file exists | Read, file missing |
| --- | --- | --- | --- |
| `.pdoc` | binary `save_document` | `load_document` | `DocumentNothing()` |
| a registered file type with no natural parser: `.pred`, `.txt`, none | `save_file!` | `load_file` | the seed of the extension |
| any other extension | `export_document` | `import_document` | the seed of the extension |

The natural formats are the ones for which a domain registered a parser in the natural slice: `.json`, `.xml`, `.yaml`, `.yml`, `.md`, `.rst`, `.math`, `.jl` and `.sql`. The format is the extension without its dot. The file types are the ones that `register_file_document_type!` names. That function is part of the serialization slice, and each domain calls it in its own `__init__`. This package only reads the table with `has_file_document_type` and `get_file_document_type`.

A text file holds a `String`, and the editor edits a `PrimitiveString`. So `read_document_file` gives a `PrimitiveString` for a `.txt` file, and `write_document_file` takes the string back out of one.

### Natural text

`import_document(path)` reads the text and calls `parse_natural_text` with the format that the extension names. It raises an error for an extension that no domain registered. `export_document(document, path)` writes `print_natural_text(document)`. It raises an error when the parser registered for the extension is not the parser of the format of the document, so a later `import_document` of the same path can not select the wrong parser. `find_natural_parser` gives the two parsers. A second name of one format has the same parser, so a YAML document exports to `.yaml` and to `.yml`.

`write_document_file`, `export_document` and `print_natural_text` (of the natural slice) each also take a `ReferencedDocument` in place of the document, and write or render the document it holds, so a document that `get_edited_document` answered reaches a file with no unwrapping step of its own.

Natural text holds no editor state. The selection and the collapse state are lost, and a document that holds an insertion placeholder has no valid text form, so its export does not parse again. A round trip holds for a data document, not for a document that you are still building.

`ExportDocumentOperation(path)` and `ImportDocumentOperation(path)` run the two functions on `editor.document`. The import replaces the whole root and sets `editor.iomap` to `nothing`, so the next print builds on the new root. No gesture makes these two operations.

### The seed of a new file

A path that does not exist opens as `make_document_seed(Val(extension))`. A domain adds a method for its own extension, for example `make_document_seed(::Val{:json}) = JsonInsertion()`, so a new file starts as a placeholder that you can type into and then save. This package defines the seed of `.txt` and of a path with no extension, an empty `PrimitiveString`, and the default, `DocumentNothing()`. `make_document_for(path)` computes the seed of a path.

### A file in a tab

`make_file_tab(path, wrap = identity)` makes the file document of a tab: the type that the extension is registered under, with the absolute path and the content of `read_document_file`. `wrap` applies to the content first. An application gives every file an overlay with it, for example `make_file_tab(path, UndoBuffer)` for an undo history, and this package does not name the overlay. A file that is its own content (`is_own_content`) has no content apart from itself: the tab holds the file that `make_file` builds under the absolute path, and `wrap` applies to the file.

`make_file_tab_content(path, wrap = identity)` makes the content of a tab that shows the file: the view (`FileView`, see the next section) of the file document of `make_file_tab`. The view keeps the scroll pane, so a file longer than its tab scrolls. The scroll is made where the file tab is made, and not by the tab, because a tab page gets no scroll of its own: a page can hold two parts that each scroll. The application and `OpenFileOperation` open each file tab with it, and `open_file!` opens a tab with the view of an open file, so each tab keeps its own place in a file that another place shows too.

`FileToContent` is the projection of a `FileDocument` in the general renderer. It prints `content` through the recursion, so a tab with a `JsonFile` shows the JSON document exactly as a bare `JsonDocument` would show. The forward map passes the path below `content` to the child. The backward map puts the `content` step in front with `concat_references`. The `^` splice of `@reference` would move the type checkpoints of the path, and the selection would then match no document. `FileToContent(; content, accepts)` prints and reads a content that `accepts` answers `true` for with the projection `content` in place of the recursion: the view of a file of a domain, which a document of that domain inside another document does not have. Any other content, such as one that an opener wraps in a document of its own, prints through the recursion. The Julia domain gives `JuliaFile` such a view through `make_graphics_projection`, whose rows come before the row of `FileDocument`.

Its reader gives a gesture to the content first, so a click puts the caret in the JSON and a key edits it, and it puts the `content` step in front of the answer. Only when the content does not answer do the file's own keys answer, Ctrl+S and F5. An Alt+click therefore selects the object under the pointer inside the file, and Alt+Up walks out to the file as a whole. A collection of gestures, for the command palette and the help window, takes the content's and the file's.

The `@gestures` table of `FileDocument` has two keys. Ctrl+O is not one of them: it opens the Open dialog ([shell.md](../shell/shell.md#the-menu-bar)).

| Key | Operation | What it does |
| --- | --- | --- |
| Ctrl+S | `SaveFileOperation` | writes the content to the file name of the document; the file checks the disk first (see the next section) |
| F5 | `ReloadFileOperation` | reads the file again into `content`; the key answers it together with a selection of the whole file; the file keeps the hash of the text that it read |

The save calls `save_file!`, which uses the `emit_text` of the file type, and not `write_document_file`. The content of a `TextFile` is a plain `String`, and `write_document_file` takes only a `Document`. The save writes the document inside a wrapper, found with `get_wrapped_document`, not the wrapper. A file that holds no document, such as a text file, is edited as a `PrimitiveString`, and the save takes the string back out. `compute_file_text(file)` answers the text that the save writes now, and writes nothing. In an editor, the reload first gives each `file("…")` of the new document the file document that the editor holds for that file, with `splice_held_files!` and `open_file_document!`, against the folder of the file; it reads no held file. With no editor, each reference stays a leaf. The reload gives the new document to the wrapper with `replace_wrapped_document!`, so a history keeps its place. Both operations pass every reader unchanged, because `is_self_contained_operation` returns `true` for them.

### The file against the disk

Every file document keeps its state against the disk in one field, `disk`, of type `FileDiskState`, as it keeps `filename` and `content`. `get_file_disk_state(file)` reads it. The state holds `file_hash`, the hash of the text of the last load or save, `band`, the `FileBand` while the file changed on disk under edits that no save wrote, `file_stamp`, the time and the size of the file at the last read, load or save, the counts `read_count` and `loaded_count`, and `text`, the background cell that reads the text of the file. The field is view state (`get_view_state_fields`), so a save writes none of it and a walk does not enter it. The constructor of each file type makes a new state, so two new files have two states. The history keeps only `saved_entry` and `has_unsaved_edits`, and it holds no hash. `make_file_tab` sets `file_hash` to `compute_file_text_hash` of the file as it was just read, and `file_stamp` to `compute_file_stamp` of it. A file of a type that a person does not edit is not read for a hash.

**A file reads its text when it is drawn.** Each change that the watch reports adds one to `read_count`. `text` is a background cell of the path and `read_count`: the view of a file reads it (`demand_file_text`) while `read_count` is past `loaded_count`, a task waits until the file is whole, hashes it and parses it after the frame, and `ApplyFileTextOperation` stores the answer. The cell is made where the file enters the window (`ensure_file_text_cell!`) and by `make_unread_file`. The watch reads no text, and no print, reader or computation reads the disk. A file that is held again after a change counts it at its acquire (`is_file_stale`: another time or size than `file_stamp`).

`make_unread_file(path, wrap)` makes a file that reads nothing: it holds the seed of its extension with `wrap` applied, `loaded_count` is `-1`, and it knows no hash. It reads the file at its first draw, and until then `SaveFileOperation` refuses to write it. The view of such a file draws a row above the scroll pane that says "<name> · reading", in the words of the heading of a folder that reads, and the scroll pane below it shows the seed. The row goes when the read ends. It takes the place of the band, so the scroll pane is the second child of the layout while the row or the band shows, and the first otherwise.

The file document watches its file while a place holds it, and is the receiver of what the watcher reports ([filechange.md](../filechange/filechange.md)). A tab, a card of a dashboard and a navigator all show the file document itself, each through its own view.

Each place that shows a file shows a view of it. `make_document_view(file)` makes a `FileView(file, scroll)`: the `file` and the `scroll` pane of this place, which keeps where this place is scrolled to. `make_file_view(file)` makes it for a new place, with the selection of the view following the selection of the file. A tab keeps a view, a card of a dashboard keeps a view in its slot, and a navigator keeps the view of its page, so a scroll in the tab leaves the card where it is. The view names the file with `get_edited_field`, so a walk and a tab reach the file through the view, and not through the scroll pane, which a walk does not enter (`is_field_walked`). A view says the title and the decoration of its file. A holder holds the view, and the view holds the file. `find_held_file(view)` answers the file, so a document that holds a view saves it as `file("…")` and writes none of the band, the hash or the scroll pane. When the history of a file sits inside the file, around its content, the file reads it with `has_unsaved_edits(get_file_content(file))`; the open of a file gives it so, also when a link of a navigator opens it.

`SaveFileOperation` reads the file on disk and compares its hash with `file_hash`. A file that is not read yet writes nothing.

- If the hashes are equal, or the file knows no hash, it writes the file and keeps the hash of the written text.
- If they differ, it writes nothing and shows the band.
- With `force = true`, it writes with no check.

"Save as" (`save_file_dialog!`) writes with `force = true`. A history inside the file adds no step for a save or for `KeepFileEditsOperation`, because their way back is `DoNothingOperation`. `ReloadFileOperation` keeps the hash of the text that it read (its `file_hash`, or the hash of the file on disk now) and takes the band away.

`FileBand` holds a `message` and `choices`, each a label with an operation. `FileViewToWidget` draws the band of the file of a view above the scroll pane of the view, so the band stays at the top while a long file scrolls, in each view of the file. After a change on disk, the band says "<name> changed on disk." and offers two choices:

| Choice | Operation | What it does |
| --- | --- | --- |
| Load it | `ReloadFileOperation` | loads the document that the read found, or reads the file now when it carries none |
| Keep mine | `KeepFileEditsOperation` | takes the hash of the disk as the hash of the file, so the next save writes |

The decoration of a file says, while its band shows, that the file changed on disk, and a conflict when the file has edits that no save wrote.

The [file-change slice](../filechange/filechange.md) reports each change with `receive_file_change!(editor, receiver)`, which this slice declares. A file adds one to its `read_count`, and reads its text when a view of it is drawn. The answer of the read is stored by `ApplyFileTextOperation`: a file with the same hash does nothing and logs nothing. A file that a person does not edit, with no edits (`has_unsaved_edits` false), or not read yet loads the new document. Any other file keeps its content, and shows the band.

### The open files

`OpenFileList` holds the files that an editor holds open. Its field `files` holds one item for each file: the file document that a tab or a page shows. `get_session_open_file_list(; editor)` gives the one list of a session. `find_open_file_document(path; editor)` finds the file document of a path, so an open of a file that the list holds reaches that document. `open_file_document!(path; editor)` answers the file document that a held file gets in an editor: the one that the list holds, else a new one that reads nothing (`make_unread_file`), with the history of the settings around its content, which it adds to the list at once. The function is generic: the default answers `nothing`, so a load with no editor keeps each leaf, and the file-system slice adds the method for an `Editor`. A call that no holder follows leaves the new file in the list, not watched, until a holder takes it. It carries the mark `For the assistant.`, so the assistant gets the editor's one document of a file with it and places the file in a card with `insert_elements!`, with no tab. The acquire of a file adds it (`add_open_file!`), and the release of its last holder takes it away (`remove_open_file!`). The explorer shows the list as the entry "Open files", with a count of the files that have unsaved edits.

The field `table` holds the table of the files: an `ArrangementDocument` with no entry, around a `Roster` of `CollectionItems` at `files`, with the columns `name`, `folder` and `state`. The list of a session has it. A list that `OpenFileList()` makes has `nothing`. `OpenFileListToWidget` draws the page of the list: a line such as "2 open files · 1 unsaved", or "No file is open.", and under it the table. A person filters and sorts the table in its bar. The name of a file is a link: a click on it opens the file, as a double click on its row does ([roster.md](../roster/roster.md)).

The removal of the last entry of an arrangement normally puts the roster in the place of the arrangement. The page keeps the arrangement with no entry instead, through `keep_held_arrangement` of the arrangement slice, so the next filter of the table has an arrangement to go to.

The reader of the page opens the file of a row at its place in the list, `files[j]`, through `retarget_held_row_open` of the roster slice ([roster.md](../roster/roster.md)). So a click on the name of a file opens it with the address "Explorer › Open files › todo.txt", and Parent goes back to the list. A selected row stays selected at the path of the row, which the table shows.

A file has the facets that a roster of files shows, filters and sorts by:

| Facet | `FileDocument` |
| --- | --- |
| `name` | the name of the file, without its folder |
| `folder` | the folder of the file, as its file name gives it |
| `has_edits` | whether the history of the file has a step that the file does not hold |
| `state` | the words of its conditions, such as "unsaved edits", "changed on disk" or "read only", and the conflict |

The words of `state` are the `words` of the `ConditionLook` of each condition, in the order that a tooltip says them, with commas between them. A file with no condition has an empty `state`.

### The tool set

The file verbs that a language model can call carry the mark `For the assistant.` in their docstrings: `make_file_tab`, `read_document_file`, `write_document_file`, `save_file_to_disk!`, `reload_file_from_disk!`, `open_file_document!`, `import_document` and `export_document`. `save_file_to_disk!` and `reload_file_from_disk!` do what Ctrl+S and F5 do: they take the tab of a file or the file, and the save checks the disk first. `open_file!` of the file system slice opens a file in a tab. It does not say where a file comes from. A workspace, a file list or a dialog belongs to the host application.

## How it fits

The code is in `source/platform/fileformat/`. The file-format slice depends on the natural slice for the formats and on the serialization slice for the binary format and the file types. It also depends on the domain, layout, widget, syntax and text slices, on the tree slice for the node of the open files, and on the roster and arrangement slices for their table. The domains `json`, `xml`, `sql` and `julia` import it to add a `make_document_seed` method. The file-system slice calls `make_file_tab` to open a file in a new tab, and the [application slice](../application/application.md) offers its marked names to the assistant.

It registers three natural rows with `register_natural_graphics!(:fileformat, …)`: `FileDocument => FileToContent()`, so every file type draws as its content in a tab; `FileView` with `FileViewToWidget`, so a file shows through its view; and `OpenFileList` with `OpenFileListToWidget`. [natural.md](../natural/natural.md) describes the table.

## Design decisions

- **This slice selects a format and adds none.** Each domain owns its text form, and the serialization slice owns the binary form and the file types. A new domain gets file input and output from its registrations alone.
- **The export raises an error on a wrong registered extension.** A `JsonObject` written to `a.xml` would be read back with the XML parser. An extension that no domain registered is allowed.
- **A save goes through the file type.** `save_file!` dispatches on the file object, so a `TextFile` and a `JsonFile` save the same way.
- **The file verbs of the tool set end at the path.** The host application owns the source of a path, so this package does not depend on a file list.

## Usage

```julia
doc  = read_document_file("example.json")      # parsed by the registered .json parser
path = write_document_file(doc, "example.json")
doc  = import_document("page.md")
export_document(doc, "copy.md")
tab  = make_file_tab("example.json")           # a JsonFile for a tab
tab  = make_file_tab("example.json", UndoBuffer)
```

- Examples: no example of its own. The [application slice](../application/application.md) opens its files with `make_file_tab_content`.
- Tests: no `test/fileformat/` folder exists. `test_file_tab()` in `test/projectured/projection/FileTabTest.jl` covers `FileToContent`, `test/projectured/editor/ApplicationTest.jl` covers the tool set, and `test/projectured/serializer/SerializationTest.jl` covers the binary format, the natural round trip of each domain and the export guard. `test_roster_facets()` covers the facets of a file and of a page, and `test_explorer()` covers the open files and their page.

## Limits

- Only `.json`, `.xml`, `.jl` and `.sql` define a seed. A missing `.md`, `.yaml`, `.rst` or `.math` file opens as `DocumentNothing()`.
- `write_document_file` writes natural text for an extension that no domain registered, but `read_document_file` raises an error for the same path.
- A file document with no file name has no save and no reload: the two gestures return `nothing`. `save_file_dialog!` of the shell slice gives it a name and writes it.
