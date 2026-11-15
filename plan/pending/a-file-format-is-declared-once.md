# A file format is declared once

> **Status:** in progress. Written 2026-11-15. The owner asked for the implementation and the
> landing on 2026-11-15: "I would prefer implement the first decided part, land it and then
> come back to the next question." Branch `file-format`, worktree
> `../projectured-julia-file-format`.

## 1. The request

The architecture review of 2026-11-15 ([architecture-review/README.md](architecture-review/README.md),
theme T6; findings XS-2, AS-2, TD-4 and the notation rows of XS-1) found that a text format
is declared in two tables that disagree. The owner chose it as the first plan ("Yes, number
5") and said:

- "File formats have file extensions, file formats have parsers and conversion to text. Some
  operations may be applicable to the whole document family."
- "We should also write documentation for these."

Decision C7 of [packages-compose-by-seams.md](packages-compose-by-seams.md) promises this
work: "A later plan moves the other eight natural register functions to seams." This plan
moves six of them. The other three are in §8.

## 2. Goal

A format is one thing in the code, apart from the domain and from the file. A package
declares a format one time, with methods. No registry table and no `__init__` registration
hold a format. One function reads a file and one function writes it, and a text with no file
uses the same parser and the same printer as a file.

## 3. What exists

**Two homes for one format.** The YAML domain writes all of these lines:

```julia
register_natural_domain!(YamlDocument; rung = :syntax, make = ..., format = :yaml,
                         extension = ".yaml", parse = parse_yaml)      # the natural slice
register_natural_parser!(:yml, parse_yaml)
register_file_document_type!(".yaml", YamlFile)                        # the serialization slice
register_file_document_type!(".yml",  YamlFile)
get_file_domain(::Type{<:YamlFile}) = YamlDocument
parse_file_content(::Type{<:YamlFile}, text) = parse_yaml(text)
emit_text(f::YamlFile) = print_natural_text(get_file_content(f))
```

- The natural slice keeps five tables in
  [NaturalNotation.jl](../../source/platform/natural/NaturalNotation.jl): `_NOTATIONS`,
  `_FORMATS`, `_PARSERS`, `_EXPRESSIONS`, `_LADDER`, with six register functions.
- The serialization slice keeps `_FILE_DOCUMENT_TYPES` in
  [FileProject.jl](../../source/platform/serialization/FileProject.jl), with
  `register_file_document_type!` (21 calls in the three repositories).
- The file format slice keys the seed of a new file by the extension:
  `make_document_seed(::Val{:json})` in
  [DocumentFile.jl](../../source/platform/fileformat/DocumentFile.jl).

**The homes disagree.**

```julia
document = parse_natural_text(:yaml, "a: 1")
get_natural_extension(document)   # ".yaml"
find_file_extension(document)     # ".yml"

read_document_file("x.math")      # parse_math(text): the natural parser
# Ctrl+S on the same tab          # print_natural_text(content) * "\n": the file type
```

- `.markdown` has a file type and no natural parser.
- The Julia and the math file types add a line break at the end of a file. The natural
  printer does not. So `export_document` and `save_file!` write two different files.
- A new file has two different empty documents: `make_document_seed(Val(:json))` gives
  `JsonInsertion()`, and the default `content` of `JsonFile` is `JsonNothing()`. YAML,
  Markdown, RST and math have no seed method, so their new file is a `DocumentNothing`.

**Eight equal structs.** `JsonFile`, `XmlFile`, `YamlFile`, `MarkdownFile`, `RstFile`,
`MathFile`, `SqlFile` and `JuliaFile` each have the fields `filename`, `content` and `disk`.
Only the default of `content` is different. `TextFile`, `PredFile` and `ImageFile` have the
same three fields. `SourceFile` (language server) and `LegacyResultFile` (omnet-julia) hold
one more field.

**Code that names the file type of one format,** apart from the methods that this plan
moves: 8 rows of `make_workload_file`, one row `make_graphics_projection(::Type{JuliaFile})`,
4 gesture tables for the tooltip of a part (`@gestures JsonFile`), 2 methods of
`find_navigator_target`, 2 constructions of `MarkdownFile` in the research domain, and 2
type checks in omnet-julia.

**The slice order** allows the design: serialization is below style, natural, syntax and
fileformat ([ProjecturedPlatform.jl:38](../../package/ProjecturedPlatform/src/ProjecturedPlatform.jl#L38)).
The natural slice does not import the serialization slice today.

**How a seam is read as a list today:** `collect_graphics_projection_types` reads
`methods(make_graphics_projection)`
([DocumentComposition.jl:37](../../source/platform/widget/DocumentComposition.jl#L37)). Ten
functions of `source/` do the same.

## 4. Decisions

### 4.1 Decisions of the owner (2026-11-15)

- **O1. A format is a thing of its own.** It has extensions, a parser and a conversion to
  text. Some operations are for the whole domain.
- **O2. One domain can have more than one format** ("Yes, I agree with you on that"). So the
  functions that read and write a string take the format, and a domain names its natural
  format.
- **O3. The names** of §5 ("Yes, it's good"). The words: `file_format`, not `format`,
  because `format_` is a verb of the naming rules; `domain`, not family, because "family" is
  the word for the variants of one document type; `string`, not text, as in
  [a-print-writes-and-a-make-answers.md](a-print-writes-and-a-make-answers.md).
- **O4. One file type with the format as its parameter** ("I agree with you"):
  `File{F<:FileFormat}`. A file that holds more than a name, a content and a disk state
  keeps a struct of its own.
- **O5. The plan writes documentation** for the functions and the types (§7).
- **O6. Five points of this plan** that differ from what the assistant told the owner
  before, or that a person sees. The owner accepted them with "Yes": P3, P6, P9, P10, and
  the first line of §8.

### 4.2 Proposed by the assistant

P3, P6, P9 and P10 are accepted by the owner (O6). P1, P2, P4, P5, P7 and P8 are approved
with the plan, 2026-11-15, when the owner asked for the implementation.

- **P1. A format is a type with no field,** a subtype of the abstract `FileFormat`. The
  package of the format declares it and so owns each method (C1). Rejected: `Val{:yaml}` as
  the key, because the name has no owner and one format has two names; a struct with fields,
  because a search finds it only in a registry, which C1 forbids. The owner saw this choice
  and gave no explicit answer.
- **P2. A domain is the abstract type above its documents,** as `@domain` declares it. It
  needs no new type.
- **P3 (accepted, O6). `make_syntax_projection` takes a document type,** as `make_graphics_projection`
  does. It is the natural notation of the type. One general method for a format asks the
  domain of the format. A second format of a domain writes a method of its own. Reason:
  `FaultLog`, `GestureLog` and `MessageLog` have a syntax notation and no format. This
  changes row D5 of the table that the owner accepted, where the format was the key.
- **P4. Where each thing lives.** `FileFormat`, `File{F}`, `make_document_seed` and the
  seams of a format live in the serialization slice, which holds `FileDocument`.
  `make_syntax_projection`, `find_natural_file_format`, `make_document_expression` and the
  general method of `make_document_string` live in the natural slice, which gets an import
  of the serialization slice.
- **P5. A list with no registry.** `collect_file_formats()` reads the methods of
  `get_file_format_extensions`. Rejected: `subtypes(FileFormat)`, which walks each module.
- **P6 (accepted, O6). A file is the string of its content and one line break.** The one write adds one
  line break at the end, and the one read removes one, for each format that goes through
  the text of the file. Rejected: a method for Julia and for math that adds the line break,
  because it keeps two strings for one document. **A person sees this:** a saved JSON, XML,
  YAML, SQL, Markdown, RST or plain text file ends with a line break, as a Julia and a math
  file do today.
- **P7. The empty document of a new file comes from one function,**
  `make_document_seed(domain)`, and each domain writes its method. It is the insertion of the
  domain where a person must type a first element (JSON, XML, YAML, SQL, Julia, math), and
  the empty root where the root takes edits (Markdown, RST, and NED, INI and test files of
  omnet-julia). It is also the default content of a `File{F}`. `@domain` does not write the
  method. Changed on 2026-11-15, see §10: the first form said "the insertion of the domain"
  for each domain.
- **P8. The short names stay,** each in its package: `const JsonFile = File{JsonFileFormat}`.
  About 120 places construct or test such a file. A new format needs no short name.
- **P9 (accepted, O6). The three functions that the assistant calls keep their names in this plan:**
  `parse_natural_text`, `print_natural_text` and `describe_natural_formats`. They call the
  new functions. Their new names (`parse_document_string` with a short name,
  `make_natural_string`, `print_natural_string`, `describe_file_formats`) belong to
  [a-print-writes-and-a-make-answers.md](a-print-writes-and-a-make-answers.md), which waits
  for decision D18 of the owner: the system prompt of the application does not change now.
- **P10 (accepted, O6). The four tooltip tables stay on the file type,** through the short name
  (`@gestures JsonFile`). The note of a part shows the name of the file as its title, so it
  needs the file. A gesture table on a type with a parameter is found since the fix of
  kernel audit L15-1. Rejected: a move to the documents of the domain, which the assistant
  first told the owner; the note would lose the name of the file.

## 5. The functions

A domain declares the first two groups with methods. The examples use YAML.

**A format declares:**

| Function | Answers | Replaces |
| --- | --- | --- |
| `get_file_format_extensions(format)` | `(".yaml", ".yml")`; the first is for a new file | `_FORMATS`, `_FILE_DOCUMENT_TYPES` |
| `parse_document_string(format, string)` | the document | `parse_file_content`, `_PARSERS` |
| `make_document_string(format, document)` | the string; one general method prints the tree | `emit_text` |
| `get_file_format_domain(format)` | `YamlDocument` | `get_file_domain` |
| `is_editable_file_format(format)` | true when a person edits such a file | `is_editable_file_type` |
| `read_file_content(format, path)` | the content; the default parses the text of the file | the same name, on the file type |
| `is_written_in_file(format, node, field)`, `is_written_inline(format, node)` | what the string holds | the same names, on the file |
| `make_reference_leaf(format, marker)`, `find_reference_marker(node)` | the node of a reference to another file, and back | the same names, on the file |
| `is_file_domain_node(format, node)` | true when a file of the format writes the node itself; the default asks the domain of the format | the same name, on the file |
| `get_file_type(format)` | the type of the document of a file of the format; `File{F}` by default | `get_file_document_type(path)` |
| `make_file(format, filename, string)` | the document of a file, from its text | `make_file(type, filename, text)` |

**A domain declares:**

| Function | Answers | Replaces |
| --- | --- | --- |
| `make_syntax_projection(type; appearance)` | the projection of its documents to syntax | `_NOTATIONS`, the `rung` and `make` keywords |
| `find_natural_file_format(document)` | the format that writes the document when nobody names one, or nothing | `get_natural_format`, `get_natural_extension`, `find_file_extension` |
| `make_document_seed(domain)` | the empty document of a new file | `make_document_seed(::Val{extension})` |
| `make_document_expression(document)` | the `Expr` that runs the document | `_EXPRESSIONS`, `make_natural_expression` |
| `find_navigator_target(document, target)` | the part that a link names | the same name, on the file |

**Searches:**

| Function | Answers | Replaces |
| --- | --- | --- |
| `find_file_format(name)` | the format of an extension, a path or a short name, or nothing | `get_file_document_type`, `has_file_document_type`, `has_natural_parser`, `find_natural_parser` |
| `collect_file_formats()` | each format of the session | none |
| `get_file_format(file)` | the format of a file, from its type | none |

**Built from them:**

| Function | Does | Replaces |
| --- | --- | --- |
| `read_document_file(path)` | finds the format, reads the content; a file that does not exist gives the seed | also `import_document` |
| `write_document_file!(document, path)` | finds the format, writes the string and one line break | `write_document_file`, `export_document` |

The syntax to text and the text to graphics steps of `_LADDER` become one plain function of
the natural slice, because the three steps are fixed.

## 6. Steps

Each step is one commit. Each step changes the documents that it makes wrong.

- [ ] **1. The record of today.** For each format and each of its example files, record the
  string that `export_document` writes and the string that `save_file!` writes. The record
  is the reference for step 5. Test: none; the record is a file in the worktree.
- [ ] **2. The format and its seams.** Add `FileFormat` and the functions of the first and
  the third table of §5 to the serialization slice, with no user. Test: a new
  `FileFormatTest.jl` that declares a format in the test.
- [ ] **3. Each format is declared.** The eight domains, plain text, `.pred`, the pictures
  and the source files of the language server each get a format type and its methods. The
  old tables stay for this step. Test: one contract test over `collect_file_formats()`: the
  extensions, the domain, and parse then print of the workload text of each format.
- [ ] **4. The natural slice reads the seams.** Add `make_syntax_projection`,
  `find_natural_file_format`, `make_document_expression` and the general method of
  `make_document_string`. `parse_natural_text`, `print_natural_text`,
  `describe_natural_formats`, `make_prose_document`, `make_natural_projection` and
  `get_natural_entries` read them. Remove the five tables of `NaturalNotation.jl`, the six
  register functions and their calls. Test: `test_natural_notation()`,
  `test_natural_registry()`, `test_natural_round_trips_every_atom()`.
- [ ] **5. One file type, one read, one write.** First prove with a small program that
  `@document struct File{F}` works with a parameter that no field uses, and that a `.pred`
  file writes and reads `File{JsonFileFormat}`. Then add `File{F}`, the short names and
  `make_document_seed(domain)`; move the methods of §3 that name a file type; make
  `read_document_file` and `write_document_file!` the one read and the one write, with P6;
  remove the eleven structs, `_FILE_DOCUMENT_TYPES`, `register_file_document_type!`,
  `import_document` and `export_document`. Compare each string with the record of step 1:
  the only difference is the line break of P6. Test: `test_serialization()`,
  `test_file_project()`, `test_pred_file()`, `test_text_file()`, `test_file_tab()`, and the
  suite of each of the eight domains.
- [ ] **6. omnet-julia and inet-julia follow,** in worktrees of their own and in the same
  landing: the NED, INI, test, result, event log and fingerprint files. Test:
  `Pkg.precompile()` of `environment/all` of omnet-julia with no warning, and its suites
  that open a file.
- [ ] **7. The documentation of §7,** and the record of the compile-ahead lists again,
  because they name the old types. Test: `test_documentation()`, `test_naming()`,
  `test_arguments()`, `test_exports()`, `test_package_graph()`, the layering guards, then
  `test_platform()` as the wide sweep.

## 7. Documentation

| Where | What it says |
| --- | --- |
| The docstring of each function of §5, of `FileFormat` and of `File` | what goes in, what comes out, one example |
| [fileformat.md](../../documentation/package/platform/fileformat/fileformat.md) | what a file format is, what a format declares, how a file is read and written; the home of the subject |
| [domain-anatomy.md](../../documentation/design/domain-anatomy.md), "The text form and the file" and "The registration" | what a domain declares |
| [new-domain-guide.md](../../documentation/guide/new-domain-guide.md), a new step | how to give a new domain a file format, with one complete example |
| [package-rules.md](../../documentation/rule/package-rules.md), the slice table | the new import of the natural slice |
| `natural.md`, `serialization.md`, `orientation.md`, the documents of eight domains | each line that names a function that goes |

## 8. Not in this plan

- The three register functions of the renderer rows, `register_natural_syntax!`,
  `register_natural_graphics!` and `register_natural_fallback!` (30 factories, finding XS-1).
  They need their own questions to the owner. The owner accepted this limit (O6).
- The new names of the three functions that the assistant calls (P9).
- A second format for a domain. The plan makes it possible and builds none.

## 9. Risks

- **Active branch.** `views-compose` changes `DocumentFile.jl`, `OpenFileList.jl` and
  `FileProject.jl` for other work. Start step 5 after it lands, or merge with it. The branch
  `page-pictures`, which changed `MarkdownFile.jl`, `RstFile.jl` and `DocumentFile.jl`,
  landed on main on 2026-11-15 (`6a24a6db6`), after §3 was written. Read the files of §3
  again before step 2.
- **A parameter that no field uses.** `@document` gives each document type one layout
  parameter for each field, and `CellVector{T}` adds a parameter of its own that its fields
  use. Step 5 proves first how `File{F}` joins its own parameter with the layout parameters,
  and which name a method and an `isa` test use for "a file of the format F in any layout".
  If it fails, the plan stops and the owner decides.
- **The name of a type.** `nameof` of each `File{F}` is `:File`, and its module is the
  serialization slice. Code that makes a text from the name of a file type must ask the
  format. Step 5 searches each use.
- **Saved files change** by P6, and a file made with no content holds an insertion and not
  a "nothing" document, by P7. Tests that compare a saved string change with them.
- **Removed exports.** The functions and the tables that go are exported, so the next
  release takes a minor version step.
- **Downstream methods.** omnet-julia adds methods to functions that change, for example
  `get_file_domain`, `parse_file_content`, `emit_text` and `make_reference_leaf`. A landing
  of projectured-julia alone stops its precompile, so step 6 lands with it.
- **Compile ahead.** The workload rows and the recorded lists name `JsonFile` and the other
  types. Follow [compile-ahead.md](../../documentation/design/compile-ahead.md) and record
  again.
- **Sealed files.** Check [SEALING.md](../../SEALING.md) for each kernel file before an
  edit. The plan expects no edit of a sealed file.

## 10. Found during the work

**2026-11-15, from the inventory of omnet-julia** (its plan:
`omnet-julia/plan/pending/a-file-format-is-declared-once.md`, branch `file-format`). The
six file types of omnet-julia show cases that §4 and §5 did not cover. Each change below is
proposed by the assistant, and the owner gets it in the next report.

- **From a format to the type of its file.** `load_project`, `make_file_tab` and the write
  of a file build the file from the type that the extension names. A result file of
  omnet-julia and the source file of the language server keep a struct of their own. So §5
  gets `get_file_type(format)`, with `File{F}` as the default, and `make_file` takes the
  format. A file is built again from another content as
  `get_file_type(get_file_format(file))(filename, content)`, never from
  `typename(typeof(file)).wrapper`, which loses the format.
- **A file uses its own format.** A reload, a save and each other operation on a file that
  exists ask `get_file_format(file)`. Only the open of a path with no file searches by the
  extension. So a format can have no extension: the fingerprint store of omnet-julia is
  `fingerprint.json`, and its opener chooses its format.
- **The seed is not the insertion for each domain** (P7 above). A new NED, INI, test,
  Markdown or RST file starts as an empty root that takes edits. `@domain` emits no method,
  because a domain that wants its root would then define the same method a second time.
- **`is_file_domain_node` takes the format, and keeps its name.** The owner accepted
  `is_domain_node(domain, node)`. That key does not work: `.pred` and four formats of
  omnet-julia have the domain `Document`, and a `.test` file writes nodes of three domains.
  The question is "does a file of this format write this node itself", so the format is the
  key. The math format answers true for a plain number.
- **The text of `describe_natural_formats()` stays equal.** It lists the formats that parse
  a string, as today, and not each format of `collect_file_formats()`. The result files and
  the event log have no parser. The system prompt must not change (P9).
- **Where P6 shows in omnet-julia.** A saved NED or INI file ends with a line break. The
  read removes one line break, so an INI file that ends with an empty line has one node
  less in its tree, and the text that the file writes is equal.

