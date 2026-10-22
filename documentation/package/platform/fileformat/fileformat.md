# File format

> **Kind:** design · **Status:** current · **Stands on:** [natural.md](../natural/natural.md), [serialization.md](../serialization/serialization.md), [roster.md](../roster/roster.md)

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

`make_file_tab_content(path, wrap = identity)` makes the content of a tab that shows the file: a `FilePage` (see the next section) around the file document of `make_file_tab` in a `WidgetScrollPane`, so a file longer than its tab scrolls. The scroll is made where the file tab is made, and not by the tab, because a tab page gets no scroll of its own: a page can hold two parts that each scroll. The application and `OpenFileOperation` open each file tab with it.

`FileToContent` is the projection of a `FileDocument` in the general renderer. It prints `content` through the recursion, so a tab with a `JsonFile` shows the JSON document exactly as a bare `JsonDocument` would show. The forward map passes the path below `content` to the child. The backward map puts the `content` step in front with `concat_references`. The `^` splice of `@reference` would move the type checkpoints of the path, and the selection would then match no document. `FileToContent(; content, accepts)` prints and reads a content that `accepts` answers `true` for with the projection `content` in place of the recursion: the view of a file of a domain, which a document of that domain inside another document does not have. Any other content, such as one that an opener wraps in a document of its own, prints through the recursion. The Julia domain gives `JuliaFile` such a view through `make_graphics_projection`, whose rows come before the row of `FileDocument`.

Its reader gives a gesture to the content first, so a click puts the caret in the JSON and a key edits it, and it puts the `content` step in front of the answer. Only when the content does not answer do the file's own keys answer, Ctrl+S and Ctrl+O. An Alt+click therefore selects the object under the pointer inside the file, and Alt+Up walks out to the file as a whole. A collection of gestures, for the command palette and the help window, takes the content's and the file's.

The `@gestures` table of `FileDocument` has two keys:

| Key | Operation | What it does |
| --- | --- | --- |
| Ctrl+S | `SaveFileOperation` | writes the content to the file name of the document; inside a page, the reader of the page answers `SaveFilePageOperation` in place of it |
| Ctrl+O | `ReloadFileOperation` | reads the file again into `content`; the key answers it together with a selection of the whole file; inside a page, the reader of the page answers `LoadFilePageOperation` in place of it |

The save calls `save_file!`, which uses the `emit_text` of the file type, and not `write_document_file`. The content of a `TextFile` is a plain `String`, and `write_document_file` takes only a `Document`. The save writes the document inside a wrapper, found with `get_wrapped_document`, not the wrapper. A file that holds no document, such as a text file, is edited as a `PrimitiveString`, and the save takes the string back out. `compute_file_text(file)` answers the text that the save writes now, and writes nothing. The reload gives the new document to the wrapper with `replace_wrapped_document!`, so a history keeps its place. Both operations pass every reader unchanged, because `is_self_contained_operation` returns `true` for them.

### The page of a file

`FilePage` is what a tab shows for a file. It holds `content` (the file in its scroll pane), `band` and `file_hash`. `make_file_page(content)` sets `file_hash` to `compute_file_text_hash` of the file as it was just read. A file of a type that a person does not edit is not read for a hash. `find_page_file(page)` gives the file document of the page.

The page holds the state of its file against the disk. `file_hash` is the hash of the text of the last load or save. The history keeps only `saved_entry` and `has_unsaved_edits`, and it holds no hash.

`SaveFilePageOperation` reads the file on disk and compares its hash with `file_hash`.

- If the hashes are equal, it writes the file and keeps the hash of the written text.
- If they differ, it writes nothing and shows the band.
- With `force = true`, it writes with no check.

"Save as" (`save_file_dialog!` with a page) writes with `force = true`. A history above the page adds no step for a save or for `KeepFilePageEditsOperation`, because their way back is `DoNothingOperation`.

`FileBand` holds a `message` and `choices`, each a label with an operation. `FilePageToWidget` draws it above the file. After a change on disk, the band says "<name> changed on disk." and offers two choices:

| Choice | Operation | What it does |
| --- | --- | --- |
| Load it | `LoadFilePageOperation` | loads the document that the watcher read, or reads the file now when it carries none |
| Keep mine | `KeepFilePageEditsOperation` | takes the hash of the disk as the hash of the page, so the next save writes |

The [file-change slice](../filechange/filechange.md) reports each change with `receive_file_change!(editor, receiver, file_hash, content)`, which this slice declares. A page with the same hash does nothing. A file that a person does not edit, or with no edits (`has_unsaved_edits` false), loads the new document. Any other file keeps its content, and the page shows the band. A file document with no page loads a file that a person does not edit. For any other file it logs a warning, because it can not tell its own save from a change.

### The open files

`OpenFileList` holds the files that an editor holds open. Its field `files` holds one item for each file: the `FilePage` that a tab or a page shows, or the file document when no page holds it. `get_session_open_file_list(; editor)` gives the one list of a session. `find_open_file_document(path; editor)` finds the item of a path, so an open of a file that the list holds reaches that document. The acquire of a page or a file adds it (`add_open_file!`), and the release of its last holder takes it away (`remove_open_file!`). The explorer shows the list as the entry "Open files", with a count of the files that have unsaved edits.

The field `table` holds the table of the files: an `ArrangementDocument` with no entry, around a `Roster` of `CollectionItems` at `files`, with the columns `name`, `folder` and `state`. The list of a session has it. A list that `OpenFileList()` makes has `nothing`. `OpenFileListToWidget` draws the page of the list: a line such as "2 open files · 1 unsaved", or "No file is open.", and under it the table. A person filters and sorts the table in its bar. The name of a file is a link: a click on it opens the page of the file, as a double click on its row does ([roster.md](../roster/roster.md)).

The removal of the last entry of an arrangement normally puts the roster in the place of the arrangement. The page keeps the arrangement with no entry instead, through `keep_held_arrangement` of the arrangement slice, so the next filter of the table has an arrangement to go to.

A file and the page of a file have the facets that a roster of files shows, filters and sorts by:

| Facet | `FileDocument` | `FilePage` |
| --- | --- | --- |
| `name` | the name of the file, without its folder | the name of its file |
| `folder` | the folder of the file, as its file name gives it | the folder of its file |
| `has_edits` | whether the history of the file has a step that the file does not hold | the same, of its file |
| `state` | the words of its conditions, such as "unsaved edits" or "read only" | the words of the conditions of the page, which also says "changed on disk" and the conflict |

A page with no file answers `nothing` for `name`, `folder` and `has_edits`. The words of `state` are the `words` of the `ConditionLook` of each condition, in the order that a tooltip says them, with commas between them. A file with no condition has an empty `state`.

### The tool set

`make_file_api()` lists the file verbs that a language model can call: `make_file_tab`, `read_document_file`, `write_document_file`, `SaveFileOperation`, `ReloadFileOperation`, `import_document` and `export_document`. It does not say where a file comes from. A workspace, a file list or a dialog belongs to the host application.

## How it fits

The code is in `source/platform/fileformat/`. The file-format slice depends on the natural slice for the formats and on the serialization slice for the binary format and the file types. It also depends on the domain, layout, widget, syntax and text slices, on the tree slice for the node of the open files, and on the roster and arrangement slices for their table. The domains `json`, `xml`, `sql` and `julia` import it to add a `make_document_seed` method. The file-system slice calls `make_file_tab` to open a file in a new tab, and the [application slice](../application/application.md) adds `make_file_api()` to its tool set.

It registers three natural rows with `register_natural_graphics!(:fileformat, …)`: `FileDocument => FileToContent()`, so every file type draws as its content in a tab; `FilePage` with `FilePageToWidget`; and `OpenFileList` with `OpenFileListToWidget`. [natural.md](../natural/natural.md) describes the table.

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
