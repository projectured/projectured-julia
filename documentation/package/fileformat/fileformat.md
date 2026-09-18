# File format

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [natural.md](../natural/natural.md)

Reading and writing a document **as a file**: `import_document` and
`export_document` choose a domain's parser and printer by the extension of a
path, and `write_document_file` / `read_document_file` extend that choice to
the binary snapshot format and to a registered file type. It is the file half
of a document's natural text; what a natural notation is, and how a domain
registers one, is [natural.md](../natural/natural.md).

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/fileformat/FileFormatModule.jl` | the module, and what it exports |
| `source/fileformat/NaturalFormat.jl` | `import_document` / `export_document`, and the two editor operations that call them |
| `source/fileformat/DocumentFile.jl` | `write_document_file` / `read_document_file`, the extension-to-format dispatch, and `make_document_seed` |

## Choosing a format by extension

A path routes to one of three formats:

| extension | write | read (file exists) | read (file missing) |
| --- | --- | --- | --- |
| `.pdoc` | binary `save_document` | `load_document` | `DocumentNothing` |
| a domain's natural extension (`.json`, `.xml`, `.md`, …) | `export_document` | `import_document` | the domain's insertion seed |
| a registered file type with no natural format (`.pred`, `.txt`, none) | `save_file!` | `load_file` | the extension's seed |

`write_document_file(document, path)` and `read_document_file(path)` are the
single entry points a caller uses; they choose the row above by `path`'s
extension. `import_document` reads and parses a path with the domain's
registered parser, and raises for an extension no domain registered.
`export_document` writes a document's natural text, and raises if the path's
extension names a *different* registered format than the document's own — so
a later `import_document` on the same path never picks the wrong parser.
Opening a path that does not exist yields `make_document_seed`: the domain's
insertion placeholder for a registered natural extension (`.json` →
`JsonInsertion`), an empty `PrimitiveString` for `.txt` or no extension, or a
`DocumentNothing` otherwise — so a new file starts as an editable seed.

`ExportDocumentOperation(path)` and `ImportDocumentOperation(path)` are the
editor operations behind a save and an open gesture; import is a whole-root
swap, replacing `editor.document` and dropping the cached `editor.iomap` so
the next print rebuilds on the new root.

## How it fits

The binary row and the registered-file-type row both call down to
[serialization.md](../serialization/serialization.md); the natural row calls
the text printers that [natural.md](../natural/natural.md) dispatches to by
registered domain. This slice adds no format of its own — it is the seam
that picks among the ones `ProjecturedSerialization` and each domain already
provide. The `WorkbenchEditor` save/reload keybindings and the file-editor
registry are what calls `write_document_file` / `read_document_file` in the
running editor.

## What a reader must know before changing this

The natural format is lossy with respect to editor-only state: a document's
selection and its collapsed/expanded state are not represented in natural
text, and a document carrying an *insertion placeholder* has no valid natural
text form, so exporting one does not re-parse. Round-tripping through
`export_document` / `import_document` holds for a real data document, not for
editor scaffolding. There is no `test/fileformat/` folder; the seam is
exercised through `test/projectured/editor/ApplicationTest.jl`,
`test/projectured/editor/WorkbenchFileTest.jl` and
`test/projectured/serializer/SerializationTest.jl`.
