# Serialization

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

Two ways to write a document to disk: an exact binary snapshot of one
document, and a save that cuts a document graph into several text files with
a reference between them written in a small marker language. Neither depends
on a domain's own notation; the `fileformat` slice is the natural,
domain-text counterpart.

## What is in the slice

| File | What it holds |
| --- | --- |
| `source/serialization/SerializationModule.jl` | the module, and what it exports |
| `source/serialization/BinarySerialization.jl` | `save_document` / `load_document`, the exact binary format |
| `source/serialization/FileProject.jl` | `FileProject`, `FileDocument` and the contract a file type keeps |
| `source/serialization/FileCut.jl` | the save walk: which node writes to which file, and where it cuts to a marker |
| `source/serialization/FileSplice.jl` | the load walk: parsing every file, then splicing each marker for the node it names |
| `source/serialization/TextFile.jl` | `TextFile`, the plain-text file type and the fallback for an unregistered extension |
| `source/serialization/PredFile.jl` | `PredFile`, a `.pred` file: one document written as its own constructor call |

## The binary format

```julia
save_document(document, "state.pdoc")
loaded = load_document("state.pdoc")
```

`save_document` writes a magic header, a format version and the document with
Julia's `Serialization` stdlib; `load_document` checks the header and
rejects a file of the wrong magic or an older version. The one customization
is that a reactive cell serializes as its value alone — its dependency edges
and its thunk are runtime state, not data — so the write never follows a
cell's `dependents` out into unrelated computed values, and the selection
`Reference`, itself built of cells, round-trips with the document. The format
is exact and lossless for a structural document, but it is tied to the
in-memory struct layout: a document holding a live external resource, such as
a database adapter, does not serialize this way, and a file written by one
version is not a portable interchange format for another.

`SaveDocumentOperation` and `LoadDocumentOperation` are the editor operations
that call `save_document` and `load_document` from a gesture.

## The multi-file project

A document graph can also be saved as a set of text files that a version
control system diffs the ordinary way. A **file document** is any type with
a `filename` and a content field — a direct subtype of `FileDocument`, or any
type that opts in with the `is_file_document` trait for a type that already
has an incompatible supertype. `FileProject(base_dir, files)` holds the set
together, because a reference from one file into another must know that the
other file exists.

Saving walks the graph and writes each node into the first file of its own
domain that reaches it; a node no file reaches is an orphan and the save
raises `FileCutException`. Wherever the walk crosses from one file's domain
into another, it writes a **marker** instead of the node: `<<file("b.xml")>>`
names another file's root, and `<<node(file("a.json"),
"entries[1].value")>>` names one node inside it. A marker is `<<expr>>`, a
restricted Julia expression read by the Julia parser and run by a small
interpreter — never `eval` — so opening a project can never execute
arbitrary code. `file` and `node` are built in; a package registers any other
verb with `register_marker_function!(:name, f)`, called as
`f(project, args...)`. Loading parses every file with its own format first,
then walks each tree and replaces every marker leaf with the node it names,
so a cycle across files becomes a cycle in memory, the same as a cycle
inside one file.

`TextFile` is the simplest file document: its content is a raw `String`, no
parser and no projection runs, and it is the fallback for any extension no
registered format claims. `PredFile` is a `.pred` file holding one document
written as a constructor call, `TestRun(name = "aloha", options = ["a",
"b"])`; `register_pred_type!` says which types a `.pred` file may construct,
so a file cannot name a type the session did not offer.

## How it fits

Nothing in this slice depends on a domain package. `ProjecturedFileFormat`
depends on `ProjecturedSerialization` for the binary half of
`write_document_file` / `read_document_file`, and several domains register a
file type against this slice's registry with `register_file_document_type!`
— JSON, XML, Markdown, RST and math each register their own extension, so a
project can cut at a file of any of them. The Julia domain also registers
`:definition` with `register_marker_function!`, so a marker can name one
definition inside a `.jl` file.

## What to check when a change touches this slice

There is no `test/serialization/` folder; the suite runs under
`test/substrate/serialization/` (`MarkerLanguageTest.jl`, `TextFileTest.jl`)
and `test/projectured/serializer/` (`FileProjectTest.jl`,
`MarkerVocabularyTest.jl`, `SerializationTest.jl`). A change to the on-disk
binary format must bump `_VERSION` in `BinarySerialization.jl`, or an old
file loads as the wrong shape instead of failing the version check.
