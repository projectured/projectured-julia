# File format

> **Kind:** design · **Status:** current · **Stands on:** [natural.md](../natural/natural.md), [serialization.md](../serialization/serialization.md)

`ProjecturedFileFormat` reads and writes a document as a file, and opens a file as a tab. It adds no format of its own: it selects one of the formats that `ProjecturedSerialization` and the domains give, by the extension of the path. This document says how the choice is made, what a file that does not exist opens as, and how a tab saves and reloads its file.

## How it works

### The choice by extension

`write_document_file(document, path)` and `read_document_file(path)` are the two entry points. They route a path to one of three formats, in this order:

| Extension | Write | Read, file exists | Read, file missing |
| --- | --- | --- | --- |
| `.pdoc` | binary `save_document` | `load_document` | `DocumentNothing()` |
| a registered file type with no natural parser: `.pred`, `.txt`, none | `save_file!` | `load_file` | the seed of the extension |
| any other extension | `export_document` | `import_document` | the seed of the extension |

The natural formats are the ones for which a domain registered a parser in `ProjecturedNatural`: `.json`, `.xml`, `.yaml`, `.yml`, `.md`, `.rst`, `.math`, `.jl` and `.sql`. The format is the extension without its dot. The file types are the ones that `register_file_document_type!` names. That function is part of `ProjecturedSerialization`, and each domain calls it in its own `__init__`. This package only reads the table with `has_file_document_type` and `get_file_document_type`.

A text file holds a `String`, and the editor edits a `PrimitiveString`. So `read_document_file` gives a `PrimitiveString` for a `.txt` file, and `write_document_file` takes the string back out of one.

### Natural text

`import_document(path)` reads the text and calls `parse_natural_text` with the format that the extension names. It raises an error for an extension that no domain registered. `export_document(document, path)` writes `print_natural_text(document)`. It raises an error when the parser registered for the extension is not the parser of the format of the document, so a later `import_document` of the same path can not select the wrong parser. `find_natural_parser` gives the two parsers. A second name of one format has the same parser, so a YAML document exports to `.yaml` and to `.yml`.

Natural text holds no editor state. The selection and the collapse state are lost, and a document that holds an insertion placeholder has no valid text form, so its export does not parse again. A round trip holds for a data document, not for a document that you are still building.

`ExportDocumentOperation(path)` and `ImportDocumentOperation(path)` run the two functions on `editor.document`. The import replaces the whole root and sets `editor.iomap` to `nothing`, so the next print builds on the new root. No gesture makes these two operations.

### The seed of a new file

A path that does not exist opens as `make_document_seed(Val(extension))`. A domain adds a method for its own extension, for example `make_document_seed(::Val{:json}) = JsonInsertion()`, so a new file starts as a placeholder that you can type into and then save. This package defines the seed of `.txt` and of a path with no extension, an empty `PrimitiveString`, and the default, `DocumentNothing()`. `make_document_for(path)` computes the seed of a path.

### A file in a tab

`make_file_tab(path, wrap = identity)` makes the file document of a tab: the type that the extension is registered under, with the absolute path and the content of `read_document_file`. `wrap` applies to the content first. An application gives every file an overlay with it, for example `make_file_tab(path, UndoBuffer)` for an undo history, and this package does not name the overlay.

`FileToContent` is the projection of a `FileDocument` in the general renderer. It prints `content` through the recursion, so a tab with a `JsonFile` shows the JSON document exactly as a bare `JsonDocument` would show. The forward map passes the path below `content` to the child. The backward map puts the `content` step in front with `concat_references`. The `^` splice of `@reference` would move the type checkpoints of the path, and the selection would then match no document.

The `@gestures` table of `FileDocument` has two keys:

| Key | Operation | What it does |
| --- | --- | --- |
| Ctrl+S | `SaveFileOperation` | writes the content to the file name of the document |
| Ctrl+O | `ReloadFileOperation` | reads the file again into `content`; the key answers it together with a selection of the whole file |

The save calls `save_file!`, which uses the `emit_text` of the file type, and not `write_document_file`. The content of a `TextFile` is a plain `String`, and `write_document_file` takes only a `Document`. The save writes the document inside a wrapper, found with `get_wrapped_document`, not the wrapper. The reload gives the new document to the wrapper with `replace_wrapped_document!`, so a history keeps its place. Both operations pass every reader unchanged, because `operation_travels_unchanged` returns `true` for them.

### The tool set

`make_file_api()` lists the file verbs that a language model can call: `make_file_tab`, `read_document_file`, `write_document_file`, `SaveFileOperation`, `ReloadFileOperation`, `import_document` and `export_document`. It does not say where a file comes from. A workspace, a file navigator or a dialog belongs to the host application.

## How it fits

The code is in `source/fileformat/`. `ProjecturedFileFormat` depends on `ProjecturedNatural` for the formats and on `ProjecturedSerialization` for the binary format and the file types. It also depends on `ProjecturedDomain`, `ProjecturedLayout`, `ProjecturedWidget`, `ProjecturedSyntax` and `ProjecturedText`. The domains `json`, `xml`, `sql` and `julia` import it to add a `make_document_seed` method. `ProjecturedFileSystem` calls `make_file_tab` to open a file in a new tab, and the application of `example/projectured/Application.jl` adds `make_file_api()` to its tool set.

The package registers one natural row: `register_natural_graphics!(:fileformat, …)` with `FileDocument => FileToContent()`. Every file type then draws as its content in a tab. [natural.md](../natural/natural.md) describes the table.

## Design decisions

- **The package selects a format and adds none.** Each domain owns its text form, and `ProjecturedSerialization` owns the binary form and the file types. A new domain gets file input and output from its registrations alone.
- **The export raises an error on a wrong registered extension.** A `JsonObject` written to `a.xml` would be read back with the XML parser. An extension that no domain registered is allowed.
- **A save goes through the file type.** `save_file!` dispatches on the file object, so a `TextFile` and a `JsonFile` save the same way.
- **The file verbs of the tool set end at the path.** The host application owns the source of a path, so this package does not depend on a file navigator.

## Usage

```julia
doc  = read_document_file("example.json")      # parsed by the registered .json parser
path = write_document_file(doc, "example.json")
doc  = import_document("page.md")
export_document(doc, "copy.md")
tab  = make_file_tab("example.json")           # a JsonFile for a tab
tab  = make_file_tab("example.json", UndoBuffer)
```

- Examples: no example of its own. `example/projectured/Application.jl` opens its files with `make_file_tab`.
- Tests: no `test/fileformat/` folder exists. `test_file_tab()` in `test/projectured/projection/FileTabTest.jl` covers `FileToContent`, `test/projectured/editor/ApplicationTest.jl` covers the tool set, and `test/projectured/serializer/SerializationTest.jl` covers the binary format, the natural round trip of each domain and the export guard.

## Limits

- Only `.json`, `.xml`, `.jl` and `.sql` define a seed. A missing `.md`, `.yaml`, `.rst` or `.math` file opens as `DocumentNothing()`.
- `write_document_file` writes natural text for an extension that no domain registered, but `read_document_file` raises an error for the same path.
- A file document with no file name has no save and no reload: the two gestures return `nothing`. No "save as" exists.
