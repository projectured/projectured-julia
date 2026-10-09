# File format

> **Kind:** design · **Status:** current · **Stands on:** [natural.md](../natural/natural.md), [serialization.md](../serialization/serialization.md)

The file-format slice of `ProjecturedPlatform` reads and writes a document as a file, and opens a file as a tab. It adds no format of its own: it selects one of the formats that the serialization slice and the domains give, by the extension of the path. This document says how the choice is made, what a file that does not exist opens as, and how a tab saves and reloads its file.

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

`make_file_tab_content(path, wrap = identity)` makes the content of a tab that shows the file: the file document of `make_file_tab` in a `WidgetScrollPane`, so a file longer than its tab scrolls. The scroll is made where the file tab is made, and not by the tab, because a tab page gets no scroll of its own: a page can hold two parts that each scroll. The application and `OpenFileOperation` open each file tab with it.

`FileToContent` is the projection of a `FileDocument` in the general renderer. It prints `content` through the recursion, so a tab with a `JsonFile` shows the JSON document exactly as a bare `JsonDocument` would show. The forward map passes the path below `content` to the child. The backward map puts the `content` step in front with `concat_references`. The `^` splice of `@reference` would move the type checkpoints of the path, and the selection would then match no document. `FileToContent(; content, accepts)` prints and reads a content that `accepts` answers `true` for with the projection `content` in place of the recursion: the view of a file of a domain, which a document of that domain inside another document does not have. Any other content, such as one that an opener wraps in a document of its own, prints through the recursion. The Julia domain gives `JuliaFile` such a view through `make_graphics_projection`, whose rows come before the row of `FileDocument`.

Its reader gives a gesture to the content first, so a click puts the caret in the JSON and a key edits it, and it puts the `content` step in front of the answer. Only when the content does not answer do the file's own keys answer, Ctrl+S and Ctrl+O. An Alt+click therefore selects the object under the pointer inside the file, and Alt+Up walks out to the file as a whole. A collection of gestures, for the command palette and the help window, takes the content's and the file's.

The `@gestures` table of `FileDocument` has two keys:

| Key | Operation | What it does |
| --- | --- | --- |
| Ctrl+S | `SaveFileOperation` | writes the content to the file name of the document |
| Ctrl+O | `ReloadFileOperation` | reads the file again into `content`; the key answers it together with a selection of the whole file |

The save calls `save_file!`, which uses the `emit_text` of the file type, and not `write_document_file`. The content of a `TextFile` is a plain `String`, and `write_document_file` takes only a `Document`. The save writes the document inside a wrapper, found with `get_wrapped_document`, not the wrapper. A file that holds no document, such as a text file, is edited as a `PrimitiveString`, and the save takes the string back out. `compute_file_text(file)` answers the text that the save writes now, and writes nothing; the [file-change slice](../filechange/filechange.md) compares it with the file on disk. The reload gives the new document to the wrapper with `replace_wrapped_document!`, so a history keeps its place. Both operations pass every reader unchanged, because `is_self_contained_operation` returns `true` for them.

### The tool set

`make_file_api()` lists the file verbs that a language model can call: `make_file_tab`, `read_document_file`, `write_document_file`, `SaveFileOperation`, `ReloadFileOperation`, `import_document` and `export_document`. It does not say where a file comes from. A workspace, a file list or a dialog belongs to the host application.

## How it fits

The code is in `source/platform/fileformat/`. The file-format slice depends on the natural slice for the formats and on the serialization slice for the binary format and the file types. It also depends on the domain, layout, widget, syntax and text slices. The domains `json`, `xml`, `sql` and `julia` import it to add a `make_document_seed` method. The file-system slice calls `make_file_tab` to open a file in a new tab, and the [application slice](../application/application.md) adds `make_file_api()` to its tool set.

It registers one natural row: `register_natural_graphics!(:fileformat, …)` with `FileDocument => FileToContent()`. Every file type then draws as its content in a tab. [natural.md](../natural/natural.md) describes the table.

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
- Tests: no `test/fileformat/` folder exists. `test_file_tab()` in `test/projectured/projection/FileTabTest.jl` covers `FileToContent`, `test/projectured/editor/ApplicationTest.jl` covers the tool set, and `test/projectured/serializer/SerializationTest.jl` covers the binary format, the natural round trip of each domain and the export guard.

## Limits

- Only `.json`, `.xml`, `.jl` and `.sql` define a seed. A missing `.md`, `.yaml`, `.rst` or `.math` file opens as `DocumentNothing()`.
- `write_document_file` writes natural text for an extension that no domain registered, but `read_document_file` raises an error for the same path.
- A file document with no file name has no save and no reload: the two gestures return `nothing`. No "save as" exists.
