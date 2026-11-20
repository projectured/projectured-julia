# File format

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [natural.md](../natural/natural.md), [serialization.md](../serialization/serialization.md), [roster.md](../roster/roster.md)

The file-format slice of `ProjecturedPlatform` reads and writes a document as a file, and opens a file as a tab. It adds no format of its own: it selects one of the formats that the serialization slice and the domains give, by the extension of the path. This document is the home of the subject. It says what a file format is and what a format declares, how a file is read and written, how the choice by extension is made, what a file that does not exist opens as, how a tab saves and reloads its file, and how the open files of an editor show as a table.

## How it works

### What a file format is

A file format is a type of its own, apart from the domain and from the file. It is a concrete subtype of `FileFormat` with no field, such as `struct YamlFileFormat <: FileFormat end`, and the package that declares it owns every method of it. A format says how the string of a file becomes a document, and how a document becomes the string again. Three things stay apart:

| Thing | What it is | Example |
| --- | --- | --- |
| The domain | the abstract type above the documents that the format holds | `YamlDocument` |
| The format | the type that declares the extensions, the parser and the string | `YamlFileFormat` |
| The file | the document of one file: its name, its content and its state on disk | `File{YamlFileFormat}`, short name `YamlFile` |

One domain can have more than one format, and a format can have no domain: plain text holds a `String`, so its domain is `Union{}`. No registry holds a format and no `__init__` registers one. `collect_file_formats()` reads the formats from the method table of `get_file_format_extensions`, so a format is known when its package is loaded. `find_file_format(name)` finds the format of an extension (`".yml"`), a path (`"notes/a.yml"`) or a short name (`:yml`), or answers `nothing`. Case does not count. An extension that two loaded formats declare is an error that names both, because a file can not say which format it means and no load order chooses.

### What a format declares

A format declares four seams. The other seams have a default, and a format overrides a default only when it differs. Each function takes the format as its first argument.

| Function | What it answers | Default |
| --- | --- | --- |
| `get_file_format_extensions(format)` | the extensions with their dot, such as `(".yaml", ".yml")`; the first is for a new file; `""` stands for a name with no extension; `()` stands for no extension at all | none |
| `get_file_format_domain(format)` | the type of the documents that the file holds | none |
| `parse_document_string(format, string)` | the document that the string holds, with a reference to another file left as its leaf | none |
| `make_reference_leaf(format, marker)` | the leaf that spells a reference to another file; the body of the marker has no `<<` and no `>>` | none; a format whose files hold no reference needs none |
| `make_document_string(format, document)` | the string of a document | one general method of the natural slice prints the document in the syntax notation of the domain |
| `is_editable_file_format(format)` | whether a person edits such a file | `true` |
| `read_file_content(format, path)` | the content of the file at `path` | reads the text, removes one line break at its end, and parses it |
| `is_written_in_file(format, node, name)` | whether the string holds the field `name` of `node` | `true` |
| `is_written_inline(format, node)` | whether a file of the format writes a node of another domain in its own string, as a `.pred` file does | `false` |
| `is_file_domain_node(format, node)` | whether a file of the format writes `node` itself | `node isa get_file_format_domain(format)` |
| `get_file_type(format)` | the type of the document of a file of the format | `File{F}` |
| `make_file(format, filename, text)` | a file of `get_file_type(format)` from its text, less one line break | the default |

The domain declares two methods of its own, apart from the format. `make_document_seed(domain)` answers the empty document of a new file. `find_natural_file_format(document)` answers the format that writes a document when nobody names one. [natural.md](../natural/natural.md) describes the second.

The YAML format shows the lines that a text format owes ([YamlFile.jl](../../../../source/domain/yaml/YamlFile.jl)):

```julia
struct YamlFileFormat <: FileFormat end

get_file_format_extensions(::YamlFileFormat) = (".yaml", ".yml")
get_file_format_domain(::YamlFileFormat) = YamlDocument
parse_document_string(::YamlFileFormat, string::AbstractString) = parse_yaml(string)
make_reference_leaf(::YamlFileFormat, marker::AbstractString) = YamlString(make_marker_text(marker))
find_reference_marker(leaf::YamlString) = parse_marker_text(leaf.value)
find_natural_file_format(::YamlDocument) = YamlFileFormat()
make_document_seed(::Type{YamlDocument}) = YamlInsertion()

const YamlFile = File{YamlFileFormat}
```

`find_reference_marker(leaf)` is a method on the leaf, not on the format: it answers the body of the marker that the leaf holds, or `nothing`. [FileFormatTest.jl](../../../../test/platform/serialization/FileFormatTest.jl) declares a complete small format, `TallyFileFormat`, with each seam and a test of each default.

### The file of a format

`File{F<:FileFormat}` is the one document type of a file ([FileFormat.jl](../../../../source/platform/serialization/FileFormat.jl)). It has the fields `filename`, `content` and `disk`, and the format is its type parameter. `get_file_format(file)` answers `F()`. A file made with no content holds `make_document_seed` of the domain of its format.

A package gives the file of its format a short name with a `const`: `JsonFile = File{JsonFileFormat}`, and likewise `XmlFile`, `YamlFile`, `MarkdownFile`, `RstFile`, `MathFile`, `SqlFile`, `JuliaFile`, `TextFile`, `PredFile` and `ImageFile`. The short name constructs a file (`JsonFile("a.json", document)`), takes a method (`make_graphics_projection(::Type{JuliaFile})`) and answers an `isa` test for each cell layout of the file. A new format needs no short name.

The name of a file type in a message, an inspector and a `.pred` file is the name of the format without `Format`, `JsonFile` for `File{JsonFileFormat}` (`get_document_schema_name`).

A table of gestures on a short name, `@gestures JsonFile`, applies to the files of that format only. The gesture walk asks the schema type of the document, `File{JsonFileFormat}`, and a table on `File` would apply to each format ([gesture.md](../../kernel/gesture.md#the-schema-type-in-the-walk)).

### A file type of its own

A file that holds more than a name, a content and a disk state keeps a struct of its own. Its format declares `get_file_type(format)` with that struct, and a method of `get_file_format(file)` gives the format back. The source file of a language server does it ([LanguageServerDocument.jl](../../../../source/adapter/languageserver/LanguageServerDocument.jl)):

```julia
get_file_type(::SourceFileFormat) = SourceFile
get_file_format(::SourceFile) = SourceFileFormat()
```

A file is made again with another content as `get_file_type(get_file_format(file))(filename, content)`. A code that builds a file by the type name of its argument loses the format of a `File{F}`.

### A format with no extension

A format that a person never names by a path declares `get_file_format_extensions(format) = ()`. `collect_file_formats()` still lists it, and `find_file_format` never finds it. Its opener chooses the format and builds the file with `get_file_type(format)`. [FileFormatTest.jl](../../../../test/platform/serialization/FileFormatTest.jl) holds `TallyLogFileFormat`, a format with `()` whose file a program writes and a person only reads (`is_editable_file_format` is `false`). A path with no extension is not the same case: `TextFileFormat` declares `""`, so `find_file_format("README")` finds it.

### How a file is read and written

One read and one write go through the format of a file, so the text of a path and the text of a tab are the same.

- `load_file(base_dir, filename)` finds the format of the file name (`find_file_format`), builds the file with `make_file` from the text of the file (a format that a person does not edit builds it from `read_file_content`), and splices each reference to the file itself.
- `save_file!(file, base_dir)` asks `get_file_format(file)` for the format, cuts the document at the file, prints it with `make_document_string`, and writes the string and one line break. `cut_file_text(file, base_dir)` answers that text and writes nothing.
- `read_document_file(path)` and `write_document_file!(document, path)` take a path and no file. They find the format by the extension and call `load_file` and `save_file!` of a file of `get_file_type(format)`. A path that no format declares is an error.

### The line break

The text of a file is the string of its content and one line break. The write adds one line break at the end, and the read removes one before it parses, for each format that goes through the text of the file. So a saved JSON, XML, YAML, SQL, Markdown, RST, Julia, math or plain text file ends with a line break. A `.pred` file writes a node of another format inline as the string with no line break. A format whose file is its own content builds itself in its `make_file` from the whole text, so it removes the line break itself.

### The choice by extension

`write_document_file!(document, path)` and `read_document_file(path)` are the two entry points, the one write and the one read of a document by its path. They route a path to a format by its extension:

| Extension | Write | Read, file exists | Read, file missing |
| --- | --- | --- | --- |
| `.pdoc` | binary `save_document` | `load_document` | `DocumentInsertion("")` |
| an extension of a format (`find_file_format`) | `save_file!` of a file of the format | `load_file` | the seed of the domain of the format |

The formats are the ones that the serialization slice and the domains declare ([serialization.md](../serialization/serialization.md#the-file-of-a-format)): `.json`, `.xml`, `.yaml`, `.yml`, `.md`, `.markdown`, `.rst`, `.math`, `.jl`, `.sql`, `.pred`, `.txt` and a path with no extension, the pictures `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif`, and the source files of a language server. No registry holds them; this package asks `find_file_format(path)`. The text of a file is the string of the document in the format and one line break, so a saved file of each text format ends with a line break. A picture is read as an `Image` of the path, which reads no byte, and a person does not edit it, so nothing writes it.

A text file holds a `String`, and the editor edits a `PrimitiveString`. So `read_document_file` gives a `PrimitiveString` for a `.txt` file, and `write_document_file!` takes the string back out of one.

### Natural text

The write raises an error when the path names a natural format that is not the format of the document (`find_natural_file_format`), so a later `read_document_file` of the same path can not select the wrong parser. Two extensions of one format name the same format, so a YAML document goes to `.yaml` and to `.yml`. A document that the file can not write alone, such as a node of another domain that needs a reference to another file, is refused with an error, and the log says why.

`write_document_file!` and `print_natural_text` (of the natural slice) each also take a `ReferencedDocument` in place of the document, and write or render the document it holds, so a document that `get_edited_document` answered reaches a file with no unwrapping step of its own.

A text holds no editor state. The selection and the collapse state are lost, and a document that holds an insertion placeholder has no valid text form, so its write does not parse again. A round trip holds for a data document, not for a document that you are still building.

`ExportDocumentOperation(path)` and `ImportDocumentOperation(path)` run the two functions on `editor.document`. The import replaces the whole root and sets `editor.iomap` to `nothing`, so the next print builds on the new root. No gesture makes these two operations.

### The seed of a new file

The empty document of a new file comes from one function, `make_document_seed(domain)`, and it is also the default content of a `File{F}`. A path that does not exist opens as the seed of the domain of its format. A domain adds a method for its own type: the insertion where a person types a first element, `make_document_seed(::Type{JsonDocument}) = JsonInsertion()` for JSON, XML, YAML, SQL, Julia and math, and the empty root that takes edits, `MarkdownRoot()` and `RstRoot()`, for Markdown and RST. So a new file starts as a placeholder that you can type into and then save. The serialization slice gives the empty string for the domain `Union{}` of plain text, which the read gives as an empty `PrimitiveString`, and this package gives the default, `DocumentNothing()`, for a domain with no seed: a picture holds it until its read. A `.pdoc` file that does not exist opens as `DocumentInsertion("")`, where a person types the kind of its document. `make_document_for(path)` computes the seed of a path.

### A file in a tab

`make_file_tab(path, wrap = identity)` makes the file document of a tab: a file of the format that the extension names (`get_file_type`), with the absolute path and the content of `read_document_file`. `wrap` applies to the content first. An application gives every file an overlay with it, for example `make_file_tab(path, UndoBuffer)` for an undo history, and this package does not name the overlay. A file that is its own content (`is_own_content`) has no content apart from itself: the tab holds the file that `make_file` builds under the absolute path, and `wrap` applies to the file. Each call makes a new document, which no other place shares. The editor's one document of a path comes from `open_file_document!` and `open_file!`.

`make_file_tab_content(path, wrap = identity)` makes the content of a tab that shows the file: the view (`FileView`, see the next section) of the file document of `make_file_tab`. The view keeps the scroll pane, so a file longer than its tab scrolls. The scroll is made where the file tab is made, and not by the tab, because a tab page gets no scroll of its own: a page can hold two parts that each scroll. The application and `OpenFileOperation` open each file tab with it, and `open_file!` opens a tab with the view of an open file, so each tab keeps its own place in a file that another place shows too.

`FileToContent` is the projection of a `FileDocument` in the general renderer. It prints `content` through the recursion, so a tab with a `JsonFile` shows the JSON document exactly as a bare `JsonDocument` would show. The forward map passes the path below `content` to the child. The backward map puts the `content` step in front with `concat_references`. The `^` splice of `@reference` would move the type checkpoints of the path, and the selection would then match no document. `FileToContent(; content, accepts)` prints and reads a content that `accepts` answers `true` for with the projection `content` in place of the recursion: the view of a file of a domain, which a document of that domain inside another document does not have. Any other content, such as one that an opener wraps in a document of its own, prints through the recursion. The Julia domain gives `JuliaFile` such a view through `make_graphics_projection`, whose rows come before the row of `FileDocument`.

Its reader gives a gesture to the content first, so a click puts the caret in the JSON and a key edits it, and it puts the `content` step in front of the answer. Only when the content does not answer do the file's own keys answer, Ctrl+S and F5. An Alt+double click therefore selects the object under the pointer inside the file, and Alt+Up walks out to the file as a whole. A collection of gestures, for the command palette and the help window, takes the content's and the file's.

The `@gestures` table of `FileDocument` has two keys. Ctrl+O is not one of them: it opens the Open dialog ([shell.md](../shell/shell.md#the-menu-bar)).

| Key | Operation | What it does |
| --- | --- | --- |
| Ctrl+S | `SaveFileOperation` | writes the content to the file name of the document; the file checks the disk first (see the next section) |
| F5 | `ReloadFileOperation` | reads the file again into `content`; the key answers it together with a selection of the whole file; the file keeps the hash of the text that it read, or for a file that a person does not edit the hash of its time and size |

The save calls `save_file!`, which writes the string of the format of the file, and not `write_document_file!`: a file has a format of its own, and `write_document_file!` chooses the format by a path. The content of a `TextFile` is a plain `String`, and `write_document_file!` takes only a `Document`. The save writes the document inside a wrapper, found with `get_wrapped_document`, not the wrapper. A file that holds no document, such as a text file, is edited as a `PrimitiveString`, and the save takes the string back out. `compute_file_text(file)` answers the text that the save writes now, and writes nothing. In an editor, the reload first gives each `file("…")` of the new document the file document that the editor holds for that file, with `splice_held_files!` and `open_file_document!`, against the folder of the file; it reads no held file. With no editor, each reference stays a leaf. The reload gives the new document to the wrapper with `replace_wrapped_document!`, so a history keeps its place. A held file holds its edited document, so the reload moves that hold to the new document (`ChangeHeldDocumentsOperation`), and what the new document holds, such as the pictures of a page, is held. Both operations pass every reader unchanged, because `is_self_contained_operation` returns `true` for them.

### The file against the disk

Every file document keeps its state against the disk in one field, `disk`, of type `FileDiskState`, as it keeps `filename` and `content`. `get_file_disk_state(file)` reads it. The state holds `file_hash`, the hash of the text of the last load or save, `band`, the `FileBand` while the file changed on disk under edits that no save wrote, `file_stamp`, the time and the size of the file at the last read, load or save, the counts `read_count` and `loaded_count`, and `text`, the background cell that reads the text of the file. The field is view state (`get_view_state_fields`), so a save writes none of it and a walk does not enter it. The constructor of each file type makes a new state, so two new files have two states. The history keeps only `saved_entry` and `has_unsaved_edits`, and it holds no hash. `make_file_tab` sets `file_hash` to `compute_file_text_hash` of the file as it was just read, and `file_stamp` to `compute_file_stamp` of it. A file of a type that a person does not edit is not read for a hash: its read, and F5, take the hash of the time and the size.

**A file reads its text when it is drawn.** Each change that the watch reports adds one to `read_count`. `text` is a background cell of the path and `read_count`: the view of a file reads it (`demand_file_text`) while `read_count` is past `loaded_count`, and so does `FileToContent` where it reads the content of a file, so a place that draws a file with no view, such as a zoom tab or the span of a picture in a page (`make_picture_span`), reads it at its first draw and after a change (a second ask in one frame records no second demand), a task waits until the file is whole, hashes it and parses it after the frame, and `ApplyFileTextOperation` stores the answer. The cell is made where the file enters the window (`ensure_file_text_cell!`) and by `make_unread_file`. The watch reads no text, and no print, reader or computation reads the disk. A file that is held again after a change counts it at its acquire (`is_file_stale`: another time or size than `file_stamp`).

`make_unread_file(path, wrap)` makes a file that reads nothing: it holds the seed of its extension with `wrap` applied, `loaded_count` is `-1`, and it knows no hash. It reads the file at its first draw, and until then `SaveFileOperation` refuses to write it. The view of such a file draws a row above the scroll pane that says "<name> · reading", in the words of the heading of a folder that reads, and the scroll pane below it shows the seed. The row goes when the read ends. It takes the place of the band, so the scroll pane is the second child of the layout while the row or the band shows, and the first otherwise.

The file document watches its file while a place holds it, and is the receiver of what the watcher reports ([filechange.md](../filechange/filechange.md)). A tab, a card of a dashboard and a navigator all show the file document itself, each through its own view.

Each place that shows a file shows a view of it. `make_document_view(file)` makes a `FileView(file, scroll)`: the `file` and the `scroll` pane of this place, which keeps where this place is scrolled to. `make_file_view(file)` makes it for a new place, with the selection of the view following the selection of the file. A tab keeps a view, a card of a dashboard keeps a view in its slot, and a navigator keeps the view of its page, so a scroll in the tab leaves the card where it is. The pane of a view also keeps the choice of Ctrl+1, the natural size of the content (`at_natural_size` of `WidgetScrollPane`, see [widget.md](../widget/widget.md)): a picture file in a tab at its natural size leaves a card of the same file at the fit, and the view has no field for it. The view names the file with `get_edited_field`, so a walk and a tab reach the file through the view, and not through the scroll pane, which a walk does not enter (`is_field_walked`). A view says the title and the decoration of its file. A holder holds the view, and the view holds the file. `find_held_file(view)` answers the file, so a document that holds a view saves it as `file("…")` and writes none of the band, the hash or the scroll pane. When the history of a file sits inside the file, around its content, the file reads it with `has_unsaved_edits(get_file_content(file))`; the open of a file gives it so, also when a link of a navigator opens it.

**A file view can show its file through views.** `make_file_view(file; views = true)` makes a view with the field `content` in use: `content` holds the view of what the file holds now (`make_content_view`), for example the view of the undo buffer of the file, which holds the view of the document. The scroll pane then shows that view, and the selection of the file view is its own, a path such as `.content.content.entries[1].value.value{2}`. The file, the undo buffer and the document hold no caret, so a second place that shows the same file keeps another caret, and the two places share the undo steps. With a view in the pane, the printer of the file is not on the path of a key, so `FileViewToWidget` reads the key table of the file with a method of `read_gesture`, by the rule of a level: Ctrl+S and F5 answer when what the pane shows gives no answer, and a list of rows takes the rows of the file. While what the file holds has no view, the pane shows the file, as with no `views`. The default is `views = false`, and no place of the editor passes `true` yet.

`SaveFileOperation` reads the file on disk and compares its hash with `file_hash`. A file that is not read yet writes nothing.

- If the hashes are equal, or the file knows no hash, it writes the file and keeps the hash of the written text.
- If they differ, it writes nothing and shows the band.
- With `force = true`, it writes with no check.

"Save as" (`save_file_dialog!`) writes with `force = true`. A history inside the file adds no step for a save or for `KeepFileEditsOperation`, because their way back is `DoNothingOperation`. `ReloadFileOperation` keeps the hash of the text that it read (its `file_hash`, or the hash of the file on disk now) and takes the band away. The new document holds no part of the path of the selection, because each document on the path keeps the rest of the path in its own field. So the load writes a live selection that passes through the file again from the root: the path that it names, or the longest start of that path that still names a part. The caret of the new document then draws and takes keys. A dormant selection stays as it is, and its tab writes it again when it takes the focus.

`FileBand` holds a `message` and `choices`, each a label with an operation. `FileViewToWidget` draws the band of the file of a view above the scroll pane of the view, so the band stays at the top while a long file scrolls, in each view of the file. After a change on disk, the band says "<name> changed on disk." and offers two choices:

| Choice | Operation | What it does |
| --- | --- | --- |
| Load it | `ReloadFileOperation` | loads the document that the read found, or reads the file now when it carries none |
| Keep mine | `KeepFileEditsOperation` | takes the hash of the disk as the hash of the file, so the next save writes |

The decoration of a file says, while its band shows, that the file changed on disk, and a conflict when the file has edits that no save wrote.

The [file-change slice](../filechange/filechange.md) reports each change with `receive_file_change!(editor, receiver)`, which this slice declares. A file adds one to its `read_count`, and reads its text when a view of it is drawn. The answer of the read is stored by `ApplyFileTextOperation`: a file with the same hash does nothing and logs nothing. A file that a person does not edit, with no edits (`has_unsaved_edits` false), or not read yet loads the new document. Any other file keeps its content, and shows the band.

### A file that repeats on its own path

Two files can hold each other, so a print that follows the files never ends. `FileToContent` gives everything below a file the property `path_files`, the files from the window to that place, outermost first. A file that is already on that path is a repeat, and the print draws it as a closed, collapsible `WidgetCard` with the title of the file and its path (`_make_repeated_file_card`), and prints no content. Nothing stores which places are closed: the card that the print makes at that one place holds its `collapsed` cell, so the next place of the same file starts closed, and no document holds the state. The card holds its content in a layout whose list is empty while the card is closed, because a card prints its content once, when it is made. An opened card shows the content of the file, which has the file on its path, so a repeat in it is closed again. Two cards of one file side by side, and a chain of files with no cycle, are no repeat. A view of a file draws its file in its scroll pane through `FileToContent`, so a view follows the rule without code of its own. A file type that registers a projection of its own does not follow it. The print of a repeat answers a `RepeatedFileIoMap` whose input is the file and whose inner map is the map of the card. The readers and the maps of `FileToContent` take a repeat by that type, and a press on the chevron folds the card; its baseline is the baseline of the card. The paths of the file are not mapped into an opened repeat, so the caret does not go into it and a key does not edit it; a press by coordinates works in it.

### The open files

`OpenFileList` holds the files that an editor holds open. Its field `files` holds one item for each file: the file document that a tab or a page shows. `get_session_open_file_list(; editor)` gives the one list of a session. `find_open_file_document(path; editor)` finds the file document of a path, so an open of a file that the list holds reaches that document. `open_file_document!(path; editor)` answers the file document that a held file gets in an editor: the one that the list holds, else a new one that reads nothing (`make_unread_file`), with a history around its content, as many steps long as the settings of the editor say, or the default settings when the editor has none, which it adds to the list at once. The function is generic: the default answers `nothing`, so a load with no editor keeps each leaf, and the file-system slice adds the method for an `Editor`. A call that no holder follows leaves the new file in the list, not watched, until a holder takes it. It carries the mark `For the assistant.`, so the assistant gets the editor's one document of a file with it and places the file in a card with `insert_elements!`, with no tab. The acquire of a file adds it (`add_open_file!`), and the release of its last holder takes it away (`remove_open_file!`). The explorer shows the list as the entry "Open files", with a count of the files that have unsaved edits.

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

The file verbs that a language model can call carry the mark `For the assistant.` in their docstrings: `read_document_file`, `write_document_file!`, `save_file_to_disk!`, `reload_file_from_disk!` and `open_file_document!`, and `read_file_content` of the serialization slice. `save_file_to_disk!` and `reload_file_from_disk!` do what Ctrl+S and F5 do: they take the tab of a file or the file, and the save checks the disk first. `open_file!` of the file system slice opens a file in a tab. `make_file_tab` and `make_file_tab_content` carry no mark: each makes a new document that no other place shares, so the assistant gets the editor's one document of a path with `open_file!` or `open_file_document!`, as a person does. It does not say where a file comes from. A workspace, a file list or a dialog belongs to the host application.

## How it fits

The code is in `source/platform/fileformat/`. The file-format slice depends on the serialization slice for the formats, the files and the binary format, and on the natural slice for the natural format of a document. It also depends on the domain, layout, widget, syntax and text slices, on the graphics slice for the baseline of a repeat, on the tree slice for the node of the open files, and on the roster and arrangement slices for their table. It gives the default of `make_document_seed` of the serialization slice, `DocumentNothing()`. The file-system slice calls `make_file_tab` to open a file in a new tab, and the [application slice](../application/application.md) offers its marked names to the assistant.

It registers three natural rows with `register_natural_graphics!(:fileformat, …)`: `FileDocument => FileToContent()`, so every file draws as its content in a tab; `FileView` with `FileViewToWidget`, so a file shows through its view; and `OpenFileList` with `OpenFileListToWidget`. [natural.md](../natural/natural.md) describes the table.

## Design decisions

- **This slice selects a format and adds none.** Each domain declares its format, and the serialization slice owns the binary form, `FileFormat` and `File`. A new domain gets file input and output from the methods of its format alone.
- **The write raises an error on the extension of another natural format.** A `JsonObject` written to `a.xml` would be read back with the XML parser.
- **One read and one write.** `read_document_file` and `write_document_file!` go through `load_file` and `save_file!`, so the text that a path gets is the text that a tab saves, with one line break at the end (plan/done/a-file-format-is-declared-once.md, P6).
- **A save goes through the format of the file.** `save_file!` asks `get_file_format` of the file, so a `TextFile` and a `JsonFile` save the same way.
- **The file verbs of the tool set end at the path.** The host application owns the source of a path, so this package does not depend on a file list.

## Usage

```julia
doc  = read_document_file("example.json")      # parsed by the parser of JsonFileFormat
path = write_document_file!(doc, "example.json")
doc  = read_document_file("page.md")
write_document_file!(doc, "copy.md")
tab  = make_file_tab("example.json")           # a JsonFile for a tab
tab  = make_file_tab("example.json", UndoBuffer)
```

- Examples: no example of its own. The [application slice](../application/application.md) opens its files with `make_file_tab_content`.
- Tests: no `test/fileformat/` folder exists. `test_file_tab()` in `test/projectured/projection/FileTabTest.jl` covers `FileToContent`, `test/projectured/editor/ApplicationTest.jl` covers the tool set, and `test/projectured/serializer/SerializationTest.jl` covers the binary format, the round trip of each domain and the guard of the write. `test_roster_facets()` covers the facets of a file and of a page, and `test_explorer()` covers the open files and their page.

## Limits

- A path of an extension that no format declares raises an error in the read and in the write.
- A new source file of a language server holds an empty `PrimitiveString`, the seed of the domain `Union{}`, which its format does not write.
- A file document with no file name has no save and no reload: the two gestures return `nothing`. `save_file_dialog!` of the shell slice gives it a name and writes it.
