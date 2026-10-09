# Serialization

> **Kind:** design · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md), [document.md](../../kernel/document.md), [domain-anatomy.md](../../../design/domain-anatomy.md)

The serialization slice of `ProjecturedPlatform` writes documents to disk in two ways: as an exact binary snapshot of one document, and as a set of text files with references between them. It also holds the contract that each file type implements and the `.pred` format, which writes any document as its own constructor call. This document says how each way works, what a file type must give, and why a marker never runs code.

## How it works

### The binary snapshot

`save_document(document, path)` writes the text `PROJECTURED-DOC`, the format version `_VERSION` and the document, with the `Serialization` standard library. `load_document(path)` rejects a file with another header or another version, and returns a document whose cells are new and have no dependencies.

**A reactive cell writes only its type and its value.** Its dependencies, its dependents and its thunk are state of the running session, not data. So a write stops at every cell and never follows a dependent into the output of a projection. The selection is a `Reference` made of cells, so it is saved and loaded with the document.

The format depends on the layout of the structs in memory. It is for one version of the program, not for an exchange between versions; the file-format slice holds the portable text form. A document that holds a live resource, such as a database adapter or an open socket, can not be saved this way.

`SaveDocumentOperation(path)` and `LoadDocumentOperation(path)` are the two operations of the editor. The inverse of a save is `DoNothingOperation()`, because the file changes and the document does not. A load replaces the root document and drops the cached IO map of the editor, so the next print builds the projection again.

### The multi-file project

A document graph can also be saved as text files that a version control system compares line by line. A **file document** has a `filename` and a `content`. It is a subtype of `FileDocument`, or a type with another supertype that returns `true` from `is_file_document`.

`get_file_content(file)` answers the value of the `content` field: the parsed tree, for most formats. An application that keeps a history of each file holds that history in the field instead, so `get_file_content` then answers the history and not the tree; [`get_edited_document`](../../kernel/reference.md#a-document-together-with-its-reference) reaches the document itself, through the history and every other such layer. `get_edited_field` of a `FileDocument` answers `:content`, unless the file's own node is its content, where it answers `nothing`. `get_file_content` also takes a `ReferencedDocument` in place of the file.

`FileProject(base_dir, files)` holds the files, because a reference from one file into another needs the other file.

**A file reference is a fact about storage, so it is never a node of the document.** In memory the graph is the real graph. A JSON object can hold an XML element, a shared subtree is one object, and a cycle is a cycle. Only the save writes references:

1. Each node gets an owner: the first file of its own domain that reaches it through nodes of that domain. A node that no file reaches is an orphan.
2. Each file copies its content until it reaches a node that another file owns. There it writes a reference leaf in its own notation.
3. `emit_text` prints the copy, and the file is written only when its bytes change.

`save_project!(project)` writes every file. If a node is an orphan, it logs the reason, writes nothing and returns `false`. `save_file!(file, base_dir)` writes one file with no project, so its content must be a tree of its own domain with no cut. `cut_file_text(file, base_dir)` answers the text that `save_file!` writes, and writes nothing.

`load_project(base_dir, filenames)` parses every file with its own format first; a reference leaf is then an ordinary leaf, such as a `JsonString` that holds a marker. It then walks each tree and replaces each reference leaf with the node that the marker names. Every tree exists before the first replacement, so two markers of one node get the same object and a cycle across files becomes a cycle in memory. A marker that names a file outside the set stays a leaf, so one file can be opened alone and saved back unchanged. `follow = true` also opens the files that the set names, and `tolerant = true` logs a file that does not open and keeps its markers as text.

### The marker language

A marker is `<<expr>>`, where `expr` is a call:

```
<<file("child.json")>>                             the root of a file
<<node(file("child.json"), "entries[2].value")>>   one node in it, as a reference path
<<section(file("page.md"), "Title")>>              the part of a page under a heading
<<definition(file("steps.jl"), "queue_step")>>     one definition in a Julia file
<<UdpHeader(source_port = 5000)>>                  a document of a loaded type
```

**The Julia parser reads a marker, and a small interpreter runs it. Nothing calls `eval`.** The interpreter accepts only a call to a plain name whose arguments are literals, keyword arguments, vectors, tuples, named tuples or such calls. An operator, an assignment, a bare name other than `nothing` or the name of a type that a file may build, and any control flow are not markers. So opening a project can not run code, and a marker stays data that a program can analyse. `file` and `node` belong to the load. A name with a capital letter constructs the loaded document type of that name. Any other name must be registered with `register_marker_function!(:name, f)`, and the interpreter calls `f(project, args...)`.

The first registration of a name wins. A second, different function logs a warning and is not used, because otherwise the order of the `__init__` calls would choose the winner. Two formats that need one name share a generic function instead: `section` calls `get_document_section`, and Markdown and RST each add a method for their own root type.

### The contract of a file type

A file type implements five functions, one line each:

| Function | What it returns | Default |
| --- | --- | --- |
| `get_file_domain(::Type{T})` | the document type of the content; a node of any other type is a cut | none |
| `parse_file_content(::Type{T}, text)` | the content that the text parses to, with no marker replaced | none |
| `emit_text(file)` | the exact text of the file, through the natural notation of the format | raises an error that names the type |
| `make_reference_leaf(file, marker)` | the spelling of a reference in the format, for a marker body without `<<` and `>>` | none |
| `find_reference_marker(node)` | the marker body that a leaf holds, or `nothing` | `nothing` |

Two more have a default that fits most formats:

| Function | Default | Override when |
| --- | --- | --- |
| `is_file_domain_node(file, node)` | `node isa get_file_domain(typeof(file))` | the domain of the file is not one type |
| `is_written_in_file(file, node, name)` | `true` | the notation writes only part of a node, so the save must not walk the other fields |
| `is_editable_file_type(::Type{T})` | `true` | a program writes the file and a person only reads it, such as a result file of a simulation |
| `read_file_content(::Type{T}, path)` | the text of the file through `parse_file_content` | the type does not edit, and its file is too large to read whole, so it reads only what it needs |

A file of a type that a person does not edit is read through `read_file_content`
when it opens and when it is read again, and a save writes nothing of it.

The JSON file type is the smallest full example:

```julia
@document struct JsonFile <: FileDocument
    filename::String
    content::JsonDocument = JsonNothing()
end
get_file_domain(::Type{<:JsonFile}) = JsonDocument
make_reference_leaf(::JsonFile, marker::AbstractString) = JsonString(make_marker_text(marker))
find_reference_marker(leaf::JsonString) = parse_marker_text(leaf.value)
parse_file_content(::Type{<:JsonFile}, text::AbstractString) = parse_json(text)
emit_text(f::JsonFile) = print_natural_text(get_file_content(f))
```

`parse_marker_text` returns `nothing` for a string that is not a marker, so an ordinary string stays a string. Each format spells a reference with its own opaque unit: a JSON string, an XML `pred:ref` element, a Markdown fence, an RST directive. A file whose node is itself the content returns `true` from `is_own_content`, defines `get_file_content(f) = f` and builds itself in `make_file`.

`register_file_document_type!(extension, T)` connects an extension to a file type, and `get_file_document_type(path)` finds it, without regard to case.

### The `.pred` format

A `PredFile` holds one document of any type, written as its constructor call:

```julia
TestRun(
    name = "aloha",
    options = ["a", "b"],
    parameters = (lambda = 1.3, capacity = 8),
)
```

It is the marker language at the scale of a file, read by the same interpreter. A file can build any loaded subtype of `Document`, by its schema name or by `nameof(T)`, and a type that is data but not a document when its package adds a method of the seam `is_pred_constructible(::Type)`, as a wire format does. The reader reads the names from the loaded modules when a name is not known yet, so a package loaded later brings its types, and a name that two loaded types have is an error that names both. `pred_arguments(document)` gives the arguments that the file writes, by default every field as a keyword. A document writes one argument on each line; a value that is not a document writes its call on one line, such as `size = Point2D(x = 800, y = 600)`, because it is one value in a diff. `make_pred_document(T, positional, keywords)` is its inverse, by default the constructor; a type with no keyword constructor is built from its fields in their declared order, and a type that a file must not build raises an error in its own method. A document that holds state of the session, such as a drag in progress or an API key, writes a reduced form with a method of each. A call in the file that names no type becomes a `PredReference`, which the load replaces.

**A type is a value too, written by its bare name.** A field that limits what a document can become holds types, such as `allowed_types = (PrimitiveNumber,)` of a type-in. The writer prints a type that a file may build as its name, and refuses any other type; the reader looks a bare name that starts with a capital up among the same types as the name of a call, and a name that no such type has is an error that names it. A bare name that starts with a small letter is no marker, so a file still can not name a function.

`TextFile` holds a raw `String` and has no parser; its domain is `Union{}`, so it holds no document.

## How it fits

The serialization slice depends only on the kernel and the `Serialization` standard library, and on no domain. The file-format slice uses it for the binary half of `write_document_file` and `read_document_file`. Each domain with a file type depends on `ProjecturedPlatform` for it; [domain-anatomy.md](../../../design/domain-anatomy.md) shows where the file type sits in a domain.

Its `__init__` registers the `section` marker, `TextFile` for a path with no extension and for `.txt`, and `PredFile` for `.pred`. The domains register `.json`, `.xml`, `.md`, `.markdown`, `.rst`, `.yaml`, `.yml`, `.math`, `.sql` and `.jl`. `ProjecturedJulia` also registers the marker `definition`.

## Design decisions

- **A cell saves only its value.** The reactive graph is state of the session, and a save that follows it reaches the whole output of every projection. The module docstring of `SerializationModule` states the rule.
- **The binary format is not an exchange format.** It is exact because it follows the structs in memory, so a change of the format must change `_VERSION`.
- **A reference is written only where the save cuts.** The document holds no storage node, so a projection, an edit and a copy see the real graph. The reason is at the head of `source/platform/serialization/FileCut.jl`.
- **A marker is data, not code.** The restricted interpreter keeps a project from running code when it opens.
- **Any loaded document type can be built, and a type that its package calls data.** A file names data: a subtype of `Document`, or a type for which `is_pred_constructible` is `true`, never a function. The owner chose this over a list of offered types (plan/pending/packages-compose-by-seams.md, C16), so no package lists its types and a file can hold any document of the session.
- **The first registration of a marker name wins.** A silent overwrite would let the load order choose the function, and the loser would fail only when a file loads.

## Usage

```julia
save_document(document, "state.pdoc")
loaded = load_document("state.pdoc")

register_file_document_type!(".json", JsonFile)          # in the __init__ of a domain
register_marker_function!(:definition, (project, file, name) -> find_julia_definition(file, name))

project = FileProject("data", Any[JsonFile("a.json", object), XmlFile("b.xml", element)])
save_project!(project)                                   # false, with a logged reason, on an orphan
project = load_project("data", ["a.json"]; follow = true)
text    = print_pred_text(document)
```

- Tests: `test_marker_language()` and `test_text_file()` in `test/platform/serialization/`; `test_file_project()`, `test_marker_vocabulary()` and `test_serialization()` in `test/projectured/serializer/`. The fixtures of `FileProjectTest.jl` show a project across several formats.

## Limits

- `get_file_document_type` raises an error for an extension that no format registered. `TextFile` covers only a path with no extension and `.txt`, although the comment in `source/platform/serialization/TextFile.jl` calls it the fallback for any extension.
- A file written by an older `_VERSION` does not load. No migration exists.
- A save that can not cut the graph writes no file of the project, and `save_project!` only logs the reason.
