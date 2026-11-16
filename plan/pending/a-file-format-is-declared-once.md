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
  `register_file_document_type!` (21 calls in the three repositories outside the tests:
  15 here, two of them loops over the 5 picture and the 8 source extensions, and 6 in
  omnet-julia).
- The file format slice keys the seed of a new file by the extension:
  `make_document_seed(::Val)` and its methods for `.txt` and no extension are in
  [DocumentFile.jl](../../source/platform/fileformat/DocumentFile.jl), and a domain adds
  a method for `.json`, `.xml`, `.sql` and `.jl` (`make_document_seed(::Val{:json})` in
  `JsonToSyntax.jl`); omnet-julia adds `.ned`, `.ini` and `.test`.

**The homes disagree.**

```julia
document = parse_natural_text(:yaml, "a: 1")
get_natural_extension(document)   # ".yaml"
find_file_extension(document)     # ".yml"

read_document_file("x.math")      # parse_math(text): the natural parser
# Ctrl+S on the same tab          # print_natural_text(content) * "\n": the file type
```

- `.markdown` has a file type and no natural parser.
- The Julia and the math file types add a line break at the end of a file, and so does
  the `.pred` file type. The natural printer does not. So `export_document` and `save_file!` write two different files.
- A new file has two different empty documents: `make_document_seed(Val(:json))` gives
  `JsonInsertion()`, and the default `content` of `JsonFile` is `JsonNothing()`. YAML,
  Markdown, RST and math have no seed method, so their new file is a `DocumentNothing`.

**Eight equal structs.** `JsonFile`, `XmlFile`, `YamlFile`, `MarkdownFile`, `RstFile`,
`MathFile`, `SqlFile` and `JuliaFile` each have the fields `filename`, `content` and `disk`.
Only the default of `content` is different. `TextFile`, `PredFile` and `ImageFile` have the
same three fields. `SourceFile` (language server) and `LegacyResultFile` (omnet-julia) hold
one more field.

**Code that names the file type of one format,** apart from the methods that this plan
moves: 9 rows of `make_workload_file` (the eight domains and plain text), one row
`make_graphics_projection(::Type{JuliaFile})`, 4 gesture tables for the tooltip of a part
(`@gestures JsonFile`, `XmlFile` and `YamlFile`, and `IniFile` in omnet-julia), 2 methods of
`find_navigator_target`, 2 constructions of `MarkdownFile` in the research domain, and 2
type checks in omnet-julia. `ImageFile` is named in about 15 places of the platform, the
PDF backend and the book domain (`isa ImageFile`, `ImageFile(filename)`), and `PredFile(…)`
in 5 places; the short names of P8 keep them.

**What `page-pictures` added** (`6a24a6db6`). An image of a Markdown page, a figure and an
image of an RST file, and a picture of a book keep the file of their picture in the
view-state field `picture`, with a method of `splice_named_file!`, and a root holds them
through `acquire_document!`. `BookPicture` asks `isa ImageFile`. These methods name the
nodes and not a file type, and this plan does not move them.

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
- **O7. `@document` stays as it is (2026-11-16).** The owner found it "weird" to put support
  for the file type in `@document`. The kernel gets one new function in its place,
  `get_document_schema_type`: the type of the schema with the parameters that its programmer
  wrote, and no layout. The gesture walk and the explorer kinds call it. The owner answered
  "yes" to "Do I add `get_document_schema_type` to the kernel?". §10 has the details.

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

- [x] **1. The record of today.** For each format and each of its example files, record the
  string that `export_document` writes and the string that `save_file!` writes. The record
  is the reference for step 5. Test: none; the record is a file in the worktree.
  **Done** 2026-11-15: [a-file-format-record/](a-file-format-record/), see §10.
- [x] **2. The format and its seams.** Add `FileFormat` and the functions of the first and
  the third table of §5 to the serialization slice, with no user. Test: a new
  `FileFormatTest.jl` that declares a format in the test.
  **Done** 2026-11-16: `FileFormat.jl` and `test_file_format()` (55 pass). Equal to the
  baseline, with the same failures: `test_serialization()`, `test_file_project()`,
  `test_pred_file()`, `test_text_file()`, `test_naming()`, `test_package_graph()`,
  `test_platform_layering()`, `test_exports()`, `test_arguments()`,
  `test_documentation()`. See §10.
- [x] **3. Each format is declared.** The eight domains, plain text, `.pred`, the pictures
  and the source files of the language server each get a format type and its methods. The
  old tables stay for this step. Test: one contract test over `collect_file_formats()`: the
  extensions, the domain, and parse then print of the workload text of each format.
  **Done** 2026-11-16, with the Julia fix `285f60d1b` before it. `test_file_format_contract()`
  297 pass and 1 fail: the XML assertion of the contract test fails until the owner
  decides the white space of an XML text (§10). Equal to the baseline, with the same
  failures: the eight domain suites, `test_languageserver()`, `test_file_format()`,
  `test_pred_file()`, `test_text_file()`, `test_file_project()`, `test_serialization()`,
  `test_file_tab()`, the three natural tests, and the guards `test_naming()`,
  `test_exports()`, `test_arguments()`, `test_documentation()`, `test_package_graph()` and
  `test_platform_layering()`. `test_julia()` 793 pass, with the 1 failure of the baseline.
- [x] **4. The natural slice reads the seams.** Add `make_syntax_projection`,
  `find_natural_file_format`, `make_document_expression` and the general method of
  `make_document_string`. `parse_natural_text`, `print_natural_text`,
  `describe_natural_formats`, `make_prose_document`, `make_natural_projection` and
  `get_natural_entries` read them. Remove the five tables of `NaturalNotation.jl`, the six
  register functions and their calls. Test: `test_natural_notation()`,
  `test_natural_registry()`, `test_natural_round_trips_every_atom()`.
  **Done** 2026-11-16. The three natural tests 33 pass (21 in the baseline;
  `test_natural_notation()` changes with the step, §10). `test_file_format_contract()` 305
  pass and 1 fail, the XML assertion of step 3 at the same line; 8 assertions more,
  because the general method of `make_document_string` answers for each format of a
  domain. `describe_natural_formats()` and the system text are byte-equal (§10). Equal to
  the baseline, with the same failures: `test_json()`, `test_xml()`, `test_yaml()` and
  `test_sql()` (1072 pass, 2 broken), `test_markdown()` 311, `test_rst()` 140,
  `test_julia()` 793 and 1 fail, `test_math()` 221 and 1 fail, `test_languageserver()` 114,
  `test_file_format()`, `test_file_tab()`, `test_pred_file()`, `test_text_file()`,
  `test_serialization()`, `test_file_project()`, `test_workflow_file()`,
  `test_marker_vocabulary()`, the eleven editor tests of the umbrella with
  `test_assistant_verbs()` and `test_application()`, which test the system text (1241
  pass, 2 fail, 2 broken), and the guards `test_naming()`, `test_exports()`,
  `test_arguments()`, `test_documentation()`, `test_package_graph()`,
  `test_platform_layering()` and `test_platform_slice_edges()`. Equal, testset by testset,
  to a run on `9895e0b46` before the first edit: `test_conversation()` (666 pass, 87 fail,
  65 error), `test_parse_markdown_blocks()`, `test_assistant_mvp()`,
  `test_assistant_composer_panel()`, and the tests of the three logs `test_tool_views()`,
  `test_gesture_log_in_tab()`, `test_message_log()`, `test_gesture_log()`,
  `test_tool_themes()`, `test_message_log_feed()` and `test_fault_catching()`.
- [x] **5. One file type, one read, one write.** First prove with a small program that
  `@document struct File{F}` works with a parameter that no field uses, and that a `.pred`
  file writes and reads `File{JsonFileFormat}`. Then add `File{F}`, the short names and
  `make_document_seed(domain)`; move the methods of §3 that name a file type; make
  `read_document_file` and `write_document_file!` the one read and the one write, with P6;
  remove the eleven structs, `_FILE_DOCUMENT_TYPES`, `register_file_document_type!`,
  `import_document` and `export_document`. Compare each string with the record of step 1:
  the only difference is the line break of P6. Test: `test_serialization()`,
  `test_file_project()`, `test_pred_file()`, `test_text_file()`, `test_file_tab()`, and the
  suite of each of the eight domains.
  **Done** 2026-11-16. The proof passes with no change of the kernel (§10). The record
  differs from step 1 by the line break of P6 and by the inputs that the old export
  refused (§10). Equal to the baseline, with the same failures: `test_serialization()`
  58, `test_file_project()` 169 and 1 broken, `test_pred_file()` 87, `test_text_file()`
  40, `test_file_tab()` 34, `test_workflow_file()` and `test_marker_vocabulary()` 56 and 1
  error, `test_json()` 405, `test_xml()` 86, `test_yaml()` 64 and 2 broken, `test_sql()`
  671, `test_markdown()` 346, `test_rst()` 140, `test_julia()` 793 and 1 fail,
  `test_math()` 221 and 1 fail, `test_languageserver()` 114, the three natural tests 33,
  the eleven editor tests of the umbrella 1241, 2 fail and 2 broken, and the guards
  `test_naming()`, `test_exports()` (37 fail; the line of `LanguageServerModule.jl` is 41
  now), `test_arguments()`, `test_documentation()`, `test_package_graph()` 562,
  `test_platform_layering()` and `test_platform_slice_edges()`. `test_file_format()` 61
  (55) and `test_file_format_contract()` 350 and 1 fail (305 and 1) change with the step
  (§10). Not in the list and equal to the baseline: `test_research()` 386, `test_book()`
  55, `test_workflow()` 314, `test_chart()` 642, `test_image()` 144, `test_file_dialog()`
  28 and 1 fail, `test_roster_program()` 21, `test_open_page_operation()` 103,
  `test_link()` 2109, `test_roster_facets()` 26 and `test_file_change_store()` 242, each
  with the strings of P6 (§10); `test_explorer()` 507, where the baseline fails one
  assertion of a repeat (`ExplorerTest.jl:1908`), which passes now. `test_formula()` 310,
  1 fail and 1 broken: the fail is the time guard `FormulaFrameGuardTest.jl:67`, a ratio
  of 3.7 and 4.5 to the limit 3.0, which fails on main too (4.2 on `3fd04ea4b`, run
  alone).
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

**2026-11-15, the baseline.** The worktree on `6a24a6db6` with Julia 1.13.1 and the private
depot `/var/tmp/projectured-julia-file-format-depot`. The summary of 31 suites, with the
commands, the logs and the failures of each, is
`/var/tmp/projectured-julia-file-format-depot/baseline/summary.md`. The suites of the
serialization slice, the natural slice, the file tab and the eight domains pass, except one
failure each in `test_math()` and `test_julia()`. Main already fails `test_documentation()`
(11), `test_exports()` (37), `test_arguments()` (6), `test_platform_layering()` (2) and
`test_platform()` (108 failures and 66 errors, most of them in the conversation tests). A
step compares its counts with these. `test_platform()` in one call needs a cap of 14 GB and
`-t 2`, and takes 36 minutes.

**2026-11-15, step 1: the record.** The folder
[a-file-format-record/](a-file-format-record/) holds the script `record.jl`, its inputs and
its record.

- **The inputs, 44.** The 14 data files of the repository: the examples and the fixtures
  of `example/` and the RST fixtures of `test/domain/rst/fixture/`. The folder `input/`
  holds 30 more that the first run made: the text of `make_workload_file` for each of its
  14 types (eight domains, plain text, and five `.pred` files), and one file for each
  extension of the registry that no other input has (`.yml`, `.markdown`, no extension,
  the five picture extensions and the eight source extensions of the language server).
- **The record.** `record/export/<input>` is the string that
  `export_document(import_document(input), …)` writes, `record/save/<input>` the string
  that `save_file!` writes for `load_file` of the input, and `record/index.tsv` lists each
  with its size and its last line break, or the first line of the error. Two runs give the
  same bytes.
- **For step 5.** Run `julia --project=environment/all
  plan/pending/a-file-format-record/record.jl <new folder>` and compare with
  `diff -r record <new folder>`. When `import_document` and `export_document` no longer
  exist, the script calls `read_document_file` and `write_document_file!`. It reads the
  folder `input/`, so it needs no registry.
- **What today writes.** The export and the save are equal for each input that both
  write, except Julia and math, where the save adds one line break (§3). The save of a
  `.pred` file ends with a line break too. The SQL printer ends its string with a line
  break of its own (`SELECT\n  name\nFROM\n  people\n`), so by P6 a saved SQL file ends
  with an empty line; step 5 checks this against the record.
- **What today does not write.** `import_document` refuses plain text, no extension,
  `.pred`, `.markdown`, the pictures and the source files, so these have no export
  string. The save of a picture raises an error (`ImageFile` has no `emit_text`), and the
  save of a source file of the language server, loaded alone, answers `false` ("holds a
  MarkedText … that is not of its domain"). The editor saves no picture
  (`is_editable_file_type` is `false`); how it saves a source file is not checked here. A
  change of these in step 5 is no difference of P6, and step 5 names it.

**2026-11-15, before step 2: §3 read again on `6a24a6db6`.** Corrected in §3: the seed
methods of the domains are in the domains and not in `DocumentFile.jl`; the `.pred` file
type also adds a line break; `make_workload_file` has 9 rows that name a file type, with
plain text; the 4 gesture tables are 3 here and `@gestures IniFile` in omnet-julia;
`ImageFile` and `PredFile` are named in about 20 more places, which the short names keep;
and what `page-pictures` added. The rest of §3 holds: the five tables and six register
functions of `NaturalNotation.jl`, 21 calls of `register_file_document_type!` outside the
tests, the eight equal structs, the slice order, and the ten functions that read a method
table.

**2026-11-15, step 2: the format and its seams.**

- **Where it lives.** The new fragment `source/platform/serialization/FileFormat.jl`,
  included after `FileSplice.jl`, holds `FileFormat`, the seams and the searches. Its test
  is `test/platform/serialization/FileFormatTest.jl`, `test_file_format()`.
- **The slice has no suite of its own.** Its tests `test_text_file()`,
  `test_marker_language()` and `test_pred_file()` run in `test_platform()`.
  `test_serialization()` is a test of the umbrella, in `test/projectured/serializer/`, of
  the binary snapshot and of `import_document` and `export_document`. So
  `test_file_format()` runs in `test_platform()` after `test_pred_file()`, and alone.
- **A generic function with no method** where the default comes in a later step or each
  format must answer: `get_file_type` and `get_file_format` (the default for `File{F}`
  comes in step 5), `make_document_string` (its general method comes in the natural slice
  in step 4), `parse_document_string`, `get_file_format_extensions` and
  `get_file_format_domain`. `make_reference_leaf(format, marker)` documents its signature
  and has no default, as the form on a file has none.
- **The defaults.** `is_editable_file_format` is `true`, `is_written_in_file` is `true`,
  `is_written_inline` is `false`, `is_file_domain_node` asks `get_file_format_domain`, and
  `make_file(format, filename, string)` makes `get_file_type(format)(filename, content)`.
  `read_file_content(format, path)` parses the whole string of the file. In step 5 its
  default becomes the one read of P6, which removes one line break before the parse,
  because `load_project` (`FileSplice.jl`) and the file tab (`DocumentFile.jl`) read a file
  through it, and `read_document_file` calls it too. A format that reads its file in a
  method of its own, such as a picture, has no line break to remove.
- **The searches.** `collect_file_formats()` reads `methods(get_file_format_extensions)`
  and gives the value of each concrete type with no field, in the order of the names of
  the types. A format with no extension declares `()`, so that it is in the list. A type
  with a field is not in it (P1). `find_file_format(name)` takes a string that a format
  declares as it is as an extension, any other string as a path, and a symbol as the
  extension without its dot; case does not count. So `".yml"` and `"a.yml"` name the YAML
  format, and `".bashrc"` is a path with no extension.
- **Proposed by the assistant: an extension that two formats declare is an error that
  names both.** The reason is the rule of this slice for a name of two loaded types
  (`get_pred_type`): a file can not say which format it means, and with no registry no
  load order can choose. The registry of today lets the last registration win, with no
  word. The test adds a second format of `.tly` for one testset and removes its method
  with `Base.delete_method` after it.
- **No assistant mark.** No new docstring has the line `For the assistant.`, because the
  system text does not change in this plan (P9). A docstring of a method does not change
  the docstring of its generic function, which is the one that a model reads.
- **For step 3.** The formats that `FileFormatTest.jl` declares, `TallyFileFormat` and
  `TallyLogFileFormat`, are in `collect_file_formats()` in each session that loads
  `ProjecturedPlatformTest`. They have no workload text. The contract test of step 3 over
  `collect_file_formats()` must check them too, or check only the formats of the packages
  of the product.


**2026-11-16, step 3: each format is declared.**

- **Where each lives.** Each format is a type with no field beside the file type of today,
  in the same fragment, and its module exports it: `JsonFileFormat` (`JsonFile.jl`),
  `XmlFileFormat`, `YamlFileFormat`, `SqlFileFormat`, `MarkdownFileFormat`,
  `RstFileFormat`, `JuliaFileFormat` and `MathFileFormat` in their domains,
  `TextFileFormat` (`TextFile.jl`) and `PredFileFormat` (`PredFile.jl`) in the
  serialization slice, `ImageFileFormat` (`Image.jl`) in the style slice, and
  `SourceFileFormat` (`LanguageServerDocument.jl`) in the language server adapter. Each
  module imports the seams that it extends. The old functions on the file types do not
  change and call no new method.
- **The extensions.** The same 26 extensions as the calls of
  `register_file_document_type!`, and no extension that two formats declare, so
  `find_file_format` raises no error. The first is the extension of a new file: `.yaml`
  and `.md`, as `_FORMATS` names them, and not the shorter `.yml` that
  `find_file_extension` answers (§3). Three formats have no default today: plain text
  takes `(".txt", "")`, so a new file has an extension that names its format again; the
  pictures keep the order of the loop of `StyleModule` (`.png` first); the source files
  take the keys of `SOURCE_FILE_LANGUAGES` in the order of their names (`.c` first), so
  the table stays the one place that names them.
- **The domains** are those of `get_file_domain`: `Union{}` for plain text and a source
  file, `Document` for `.pred` and a picture. `is_file_domain_node` has a method for
  `.pred` and math only, as today. The picture declares `is_editable_file_format` false
  and `read_file_content`, and no parser and no string.
- **`make_document_string` in this step** has a method for the three formats whose string
  is not the print of a tree: plain text (the string as it is), `.pred`
  (`print_pred_text`) and a source file (the text of its marked text, also through a
  history, as `emit_text`). The `.pred` method writes no line break at the end, because
  by P6 the write adds it, and it does not add the name of the file to a
  `FileCutException`, which `emit_text` does: a format knows no file name, so that note
  belongs to the write of step 5. No other format writes a string that is not a tree.
- **One body for `is_written_in_file` of `.pred`.** The method on `PredFile` and the
  method on `PredFileFormat` both call the private `_is_written_in_pred_file`. The other
  methods of the formats are one line each and repeat the line of the file type, which
  step 5 removes.
- **A path with no extension names plain text.** `TextFileFormat` declares `""`, so
  `find_file_format("tally")` and `find_file_format(".tally-field")` give
  `TextFileFormat()`. The test of step 2 asserted `nothing` for the second; it now
  asserts plain text, as the rule of step 2 says (a string that no format declares is a
  path).
- **The contract test** is `test_file_format_contract()` in
  `test/projectured/serializer/FileFormatContractTest.jl`, where every domain and the
  language server are loaded; `test_documents()` runs it. A row of `make_workload_file`
  counts for the format of its file name, so the five `.pred` rows (book, chart, graph,
  research, workflow) test the `.pred` format. The formats with no workload text are
  named and asserted: `ImageFileFormat`, `SourceFileFormat`, and the two formats of
  `FileFormatTest.jl`.
- **"The same text" is a fixed point.** The workload text of JSON, XML, YAML, SQL and
  Julia is not in the layout of their printer (the record of step 1), so the first print
  is not the workload text. The test parses the workload text, prints it, parses the
  print, and asserts that the second print equals the first. Where the format declares
  `make_document_string`, the test also asserts that `emit_text` writes the same string,
  or the string and one line break.
- **For step 4.** The methods of `.pred` and of a source file take a document of any
  type. A general method `make_document_string(::FileFormat, ::Document)` would be
  ambiguous with them for a `Document`; the general method takes an untyped document, or
  the two methods take a narrower type.
- **The export guard.** `LanguageServerModule.jl` fails the guard on main ("the names are
  not in the order that `LanguageServerDocument.jl` defines them"). The longer import
  moves that statement from line 39 to line 42; the violation is the same.
- **Two defects of today that step 3 shows.** Each one is on main, and each one breaks the
  promise of `parse_document_string`: the string of a document parses to an equal
  document. The Julia defect is fixed in its own commit, `285f60d1b`. The XML defect waits
  for the owner, and the landing waits for that answer.
  - **The print of XML is not stable.** `parse_xml` keeps the white space around a text
    that is not white space alone (`XmlParser.jl:114` drops only a text of white space
    alone), and the printer writes a text on a line of its own with an indentation. So
    the string that a save writes today, `"<person>\n  <name>\n    Alice\n  </name>\n</person>"`,
    reads and prints as `"<person>\n  <name>\n    \n        Alice\n      \n  </name>\n</person>"`:
    each load and save of an XML file adds white space. The contract test fails at
    this row, and at no other.
  - **The print of Julia drops the comma of a tuple of one element.**
    `JuliaTupleToSyntaxNode` (`JuliaToSyntax.jl:461`) writes the elements between
    `(` and `)` with `, ` between them, so `(".jl",)` prints as `(".jl")`, a string in
    parentheses: the save of a Julia file changes what the code means.
    `JuliaParserTest.jl` reads `JuliaFile.jl` as a fixture, and the new line
    `get_file_format_extensions(::JuliaFileFormat) = (".jl",)` makes its test "a real
    file keeps every comment, in order" fail (line 309): the print of the print is not
    the print. **Fixed** in `285f60d1b`: the close of the tuple is a computed text, `,)`
    for one element and `)` otherwise, as the close of a top level writes its `;`. The
    fixture is not changed. A test prints, parses and navigates `(".jl",)`, and the comma
    follows a `push!` and a `deleteat!` through the same IO map.
- **Question for the owner: is the white space at the start and the end of an XML text
  data or layout?** Two places can fix the XML defect. (1) Layout, the recommendation of
  the assistant: the parser removes the white space around a text, and the printer stays;
  a text whose spaces matter, such as `<code>  x</code>`, loses them. This follows the
  owner's rule of 2026-11-03: no layout in the tree, and the printer makes the layout.
  (2) Data: the parser keeps it, and the printer writes each text as it is, on the line of
  its tags; a text between child elements needs a rule of its own. (3) Later: a known
  failure, and a plan of its own. Until the answer, the XML row of the contract test fails.
- **For step 6.** Today a format of another package can register itself on top of `.txt`
  or of a name with no extension, which plain text declares. With one format for each
  extension, such a format is an error of `find_file_format`. The inventory of omnet-julia
  found none, and step 6 checks it again.
- **A caret does not reach the places inside a Julia string** in the chain
  `JuliaToSyntax → SyntaxToText → TextToGraphics`, with
  `test_position_navigation(...; check_reaches_all = true)`: `".jl"` alone leaves 4 places
  unreached, `[".jl"]` 4, `f(".jl")` 6 (also the 2 places of the name `f`), and
  `(".jl",)` 4. No Julia test asked for every place before. This plan does not fix it,
  and the editor is not checked. The tuple test checks the navigation with no
  `check_reaches_all`.


**2026-11-16, step 4: the natural slice reads the seams.**

- **Where each lives.** `make_syntax_projection`, `make_syntax_to_text_projection`,
  `find_natural_file_format`, `make_document_expression` and the general method of
  `make_document_string` are in `NaturalNotation.jl`, which also holds the steps of the
  ladder as one plain function, `_make_natural_steps`. The natural slice uses the
  serialization slice: a new edge in `PLATFORM_SLICE_EDGES` and in the slice table of
  `package-rules.md`. Each of the eight domains declares
  `make_syntax_projection(::Type{<:XDocument}; appearance)` in `XToSyntax.jl` and
  `find_natural_file_format(::XDocument) = XFileFormat()` in `XFile.jl`, and the Julia
  domain declares `make_document_expression(::JuliaDocument)` in `JuliaExpression.jl`.
  The fault log, the gesture log and the message log declare `make_syntax_projection`
  only, in their `*ToSyntax.jl`; the gesture log has no `__init__` now.
- **What goes.** The five tables, `RUNGS`, the six register functions and their 16
  calls: eight `register_natural_domain!` calls of the domains, `register_natural_parser!(:yml)`,
  three `register_natural_notation!` calls of the logs, the notation of `TextDocument`
  and the two steps from text in `ProjecturedPlatform.__init__`, and the step from syntax
  in `register_syntax_fallback!`. Also the readers of the tables that §5 replaces:
  `get_natural_format`, `get_natural_extension`, `find_natural_parser`,
  `make_natural_expression` and `has_natural_expression`. `find_file_extension` reads
  `_FILE_DOCUMENT_TYPES`, so it stays until step 5.
- **The text of `describe_natural_formats()` is byte-equal.** It lists each format of
  `collect_file_formats()` that natural text reads, with the first extension without
  its dot as the short name, the first extension, and the name of the domain. Before the
  first edit and after it, `describe_natural_formats()`, `make_application_system()` for
  `:anthropic` and for `:ollama`, the docstrings of `parse_natural_text` and
  `describe_natural_formats` and the prints of one document of each domain are equal
  byte for byte (`/var/tmp/projectured-julia-file-format-depot/step4/before` and
  `after`, made by `capture.jl` there). The system text names the module by the first
  sentence of its docstring, which stays. The docstring of `print_natural_text` says
  "the steps of the ladder" in place of "the registered steps"; the system text does not
  hold it.
- **Proposed by the assistant: the step from syntax to text is a seam with no key,**
  `make_syntax_to_text_projection(; appearance)`. §5 says that the steps become one plain
  function of the natural slice. The steps from text are the text slice's, which the
  natural slice uses, so the plain function makes them. `SyntaxToText` is the syntax
  slice's, and the syntax slice uses the natural slice (the renderer tables of §8), so
  the natural slice can not name it. So the natural slice declares the function with no
  method, and the syntax slice adds the one method, as C14 does with
  `make_document_projection`. Rejected: the natural slice imports the syntax slice (a
  cycle); the row of `_LADDER` stays for this step (a table, C1); a method of
  `make_syntax_projection` for a syntax tree (it answers another question). **A new
  generic function, so the owner sees it.**
- **Proposed by the assistant: `has_natural_parser(format::Symbol)` stays, and reads the
  seams.** §5 says that `find_file_format` replaces it. But `find_file_format` also finds
  plain text, `.pred`, the pictures and the source files, which natural text does not
  read: with it alone, a fence `c` in a message of the model would become a source file
  in place of a code block, and a resource `x.png` of an agent would raise an error in
  place of staying text. So a natural format is a format that parses a string and whose domain
  has a syntax notation, and `has_natural_parser`, `parse_natural_text` and
  `describe_natural_formats` read that set. `find_natural_parser` goes, as §5 says. The
  docstring of `parse_natural_text`, which names `has_natural_parser`, stays equal.
- **Proposed by the assistant: `get_natural_entries(; appearance)` has no rung argument.**
  Each row is a syntax row now: no domain declared a `:graphics` notation, and the renderer
  never read the `:text` row of `TextDocument`. It reads the methods of
  `make_syntax_projection`, each type before its supertypes, as
  `collect_graphics_projection_types` does, and calls each with `invokelatest`, as the
  renderer calls `make_graphics_projection`. The rows of the logs now come after the rows
  of the domains; the types do not overlap, so the renderer takes the same row.
- **Proposed by the assistant: `make_document_expression` has a general method,**
  `Expr(:toplevel, QuoteNode(document))`: a document that is no code runs as its own value,
  as `make_julia_expression` makes it for a document that is no Julia. So the evaluator
  makes an `Expr` for each form that is no text, and no longer asks whether a domain has
  an expression (`has_natural_expression(:jl)` went with its table). With the Julia domain
  loaded, each form gives the same `Expr` as before. With no Julia domain, a form whose
  whole code is a pasted object runs as that object, where it did nothing before. C8 says
  that a `make_` seam has no method where it is declared; this one always makes an
  `Expr`, as `make_file` of step 2 does.
- **For step 4 (from step 3): the general method of `make_document_string` takes an
  untyped document,** `make_document_string(format::FileFormat, document)`. The methods of
  `.pred` and of a source file are more specific in the format, so no call is ambiguous,
  and they keep a document of any type: a `.pred` file holds a document of any domain, and
  a source file holds a marked text or a history around one, so a narrower type would name
  types of other slices. The general method prints the document through
  `make_syntax_projection(format)`, then the steps to a string, and raises an error for a
  format whose domain has no syntax notation.
- **Proposed by the assistant: a caller that held a type now holds a document.**
  `find_natural_file_format` takes a document (§5). The composer and the fresh code of the
  evaluator asked `get_natural_format` of an insertion type; they now make the insertion
  document first and ask about it. The conversation slice reads the short name of a
  format (`_find_format_name`, the first extension without its dot), so `FORMAT_LABELS`
  and `CODE_FORMATS` keep their keys `:jl`, `:md`, `:json` and `:xml`. The fence of the
  assistant takes the first extension of the format, and the guard of `export_document`
  compares two formats.
- **What a person sees.** `parse_natural_text` reads each short name of a natural format,
  so `:markdown` and an `x.markdown` read Markdown now; before, only the format names and
  `:yml` had a parser (§3: "`.markdown` has a file type and no natural parser"). So
  `import_document`, `read_document_file` and `write_document_file` take a `.markdown`
  path as natural text, not through `MarkdownFile`; for a file with no reference to
  another file, the document and the string are equal. `parse_natural_text(:math, …)`
  removes the white space around the formula, as the parser of the format does.
- **Tests that change with the step.** `test_natural_notation()` registered rows in two
  tables and put them back; it now adds methods with `@eval` and removes them after,
  also the method of the keyword call, and asserts the order of the rows of the renderer,
  the `Expr` of a document that is no code, and that `make_document_string` of a format
  is `print_natural_text` for five short names: 33 assertions in the three natural tests,
  21 in the baseline. `CatalogCoverageTest.jl` and `precompile_atom_parsers`
  (`example/projectured/Precompile.jl`) read `find_natural_file_format` and
  `parse_document_string`. `PackageGraphTest.jl` counts a method of
  `make_syntax_projection` for a type as a natural row, as `package-rules.md` now says.
  `test_file_format_contract()`: the general method makes `is_declared` true for each
  format of a domain, so the test also asserts for each that `emit_text` writes the
  string of the format, 8 assertions more.
- **§8 holds.** `register_natural_syntax!`, `register_natural_graphics!` and
  `register_natural_fallback!` do not change. One sentence of the docstring of
  `register_natural_syntax!` named `register_natural_notation!` and now names
  `make_syntax_projection`.
- **The documents that the step makes wrong** change with it: `natural.md` (the seams in
  place of the rung table), `conversation.md`, `fileformat.md`, the documents of Markdown,
  RST, YAML, math and book, `domain-anatomy.md` ("The registration"),
  `domain-inventory.md`, `new-domain-guide.md` and `package-rules.md`. The documentation
  of §7 is step 7.
- **For step 6: the calls in omnet-julia and inet-julia.** omnet-julia (`main`,
  `6b6375c93`) has three calls of a removed function, each in an `__init__`, each with
  the keywords `rung = :syntax`, `make`, `format`, `extension` and `parse`:
  - `source/legacy/ned/NedModule.jl:63`, `register_natural_domain!(NedDocument; …)`, format `:ned`, `.ned`;
  - `source/legacy/testfile/LegacyTestModule.jl:64`, `register_natural_domain!(LegacyTestDocument; …)`, format `:test`, `.test`;
  - `source/legacy/ini/IniModule.jl:57`, `register_natural_domain!(IniDocument; …)`, format `:ini`, `.ini`.

  No file of omnet-julia names another removed function or a table
  (`register_natural_notation!`, `_format!`, `_parser!`, `_expression!`, `_rung!`,
  `get_natural_format`, `get_natural_extension`, `find_natural_parser`,
  `make_natural_expression`, `has_natural_expression`, `get_natural_entries`, `_NOTATIONS`,
  `_FORMATS`, `_PARSERS`, `_EXPRESSIONS`, `_LADDER`, `RUNGS`), and no file of inet-julia
  names any of them. Each of the three becomes a method of `make_syntax_projection`, a
  method of `find_natural_file_format` and the format of step 6, so that
  `describe_natural_formats()` of a session of omnet-julia lists `:ini`, `:ned` and `:test`
  again. Until step 6, each of the three `__init__` calls a function that projectured-julia
  no longer defines, so omnet-julia does not load with this branch (§9, "Downstream
  methods"). Not checked here: step 6 runs its precompile.


**2026-11-16, step 5: one file type, one read, one write.**

- **The proof.** `/var/tmp/projectured-julia-file-format-depot/step5/proof.jl` ran on the
  branch before the first edit, 30 assertions pass. It declares
  `@document struct ProofFile{F<:FileFormat} <: FileDocument` in `Main`. The stem is
  `ProofFile{F, C1, …, C5}`: the format comes before the layout parameters, so
  `ProofFile{JsonFileFormat}` is the file of the format in each cell layout, and
  `copy_document` of each cell kind keeps the format. The default of `content` can name
  `F`. The bare name constructs nothing, because nothing binds `F`, and the stem with its
  format has no keyword constructor; no code builds a file with keywords. The native
  layout `MProofFile{F}` exists and is no `ProofFile{F}`; no code of the platform builds
  the native layout of a file. **So a method and an `isa` test use `File{F}` or the short
  name**, and `@document` needs no change of the kernel. A `.pred` file that holds the
  file writes `file("a.json")`, and the splice puts the `ProofFile{JsonFileFormat}` back
  in its place. A file written as its own constructor prints `ProofFile(…)`, and the
  print does not read back, because the name loses the format; no save writes a file in
  that way. Two facts that the plan did not know: the table of `@gestures JsonFile` is
  not found, because `collect_document_gesture_bindings` asks the concrete type and the
  whole stem, not the stem with its format bound (P10 said that it is found); a method on
  `Type{<:JsonFile}` is found for each cell layout.
- **Where each thing lives** (P4). `FileFormat.jl` holds `File{F}`, the generic
  `make_document_seed` with its method for the domain `Union{}` (the empty string), the
  defaults `get_file_type(format) = File{typeof(format)}` and
  `get_file_format(::File{F}) = F()`, the generic `read_file_content` with the docstring
  that the assistant reads, and `make_file`. It is included right after `FileProject.jl`,
  because the cut keeps the format of its file. `FileCut.jl` asks each seam of
  `get_file_format(file)`; `FileSplice.jl` reads the file of a set in the format that its
  extension names. The default seed, `DocumentNothing()` for a domain with no method, is in
  `DocumentFile.jl` of the file-format slice, where the default of
  `make_document_seed(::Val)` was: the serialization slice uses no slice of the platform,
  and `DocumentNothing` is of the domain slice.
- **The short names** (P8): `JsonFile`, `XmlFile`, `YamlFile`, `MarkdownFile`, `RstFile`,
  `MathFile`, `SqlFile` and `JuliaFile` in their domains, `TextFile` and `PredFile` in the
  serialization slice, `ImageFile` in the style slice, each with the docstring of the old
  struct, and each exported by its module: `@document` exports a stem, not a constant.
  `ImageFile(filename)` stays, a method of `File{ImageFileFormat}`. `SourceFile` keeps its
  struct (O4) and declares `get_file_type` and `get_file_format`.
- **The seeds** (P7), each in the fragment of its format, as
  `make_document_seed(::Type{JsonDocument})`: `JsonInsertion`, `XmlInsertion`,
  `YamlInsertion`, `SqlInsertion`, `JuliaInsertion` and `MathInsertion`; `MarkdownRoot()`
  and `RstRoot()`. A `JsonFile` made with no content held `JsonNothing()` and holds
  `JsonInsertion()` now; a `PredFile` held `nothing` and holds `DocumentNothing()`.
- **P6.** The default of `read_file_content(format, path)` and of
  `make_file(format, filename, text)` removes one line break at the end of the text before
  the parse. `cut_file_text`, `save_file!` and `save_project!` write the string and one
  line break. The string with no line break is the private `_cut_file_string`, which a
  `.pred` file writes inline. A format whose file is its own content builds itself in its
  `make_file` from the whole text, so it removes the line break itself, as the `NoteFile`
  of `TextFileTest.jl` does. The emit of `.pred` kept its note of the file name on a
  `FileCutException` (`save: "x.pred" …`); the cut adds it now, for each format.
- **The one read and the one write.** `read_document_file(path)`: `.pdoc` is the binary
  snapshot; any other path finds its format (`find_file_format`), a missing file gives
  `make_document_for(path)`, the seed of the domain, and a file that exists is
  `load_file`, so a marker of a file into itself is spliced for each format; the natural
  read of `import_document` spliced none. `write_document_file!(document, path)`: `.pdoc`,
  or `save_file!` of a file of the format with the document, which keeps the guard of
  `export_document` (a natural format of the path that is not the format of the
  document). `ExportDocumentOperation` and `ImportDocumentOperation` stay and call the two.
  `NaturalFormat.jl` goes; the two operations are in `DocumentFile.jl`.
  `read_file_content_again(format, path)` takes the format of the file that reads again.
- **What goes.** The eleven structs; `_FILE_DOCUMENT_TYPES`,
  `register_file_document_type!` and its 21 calls with their `__init__` lines,
  `get_file_document_type`, `has_file_document_type`, `find_file_extension`,
  `import_document`, `export_document`, `write_document_file`; the forms on a file type
  `emit_text`, `parse_file_content`, `get_file_domain`, `is_editable_file_type`,
  `read_file_content(::Type)`, `make_file(::Type, …)`, `is_file_domain_node(file, …)`,
  `is_written_in_file(file, …)`, `is_written_inline(file, …)`,
  `make_reference_leaf(file, …)` and `make_document_seed(::Val)`; the methods
  `get_file_type` and `get_file_format` of each format that has the default; the two
  methods `find_navigator_target(::MarkdownFile, …)` and `(::RstFile, …)`. No kernel file
  changes.
- **The name of a type** (§9), searched with `nameof(typeof(`, `typename(` and
  `get_document_schema_name` in `source/`. Changed: the three builds of a file from its
  type (`_with_content`, `_make_plain_file`, `_read_file_again` and the background read
  in `DocumentFile.jl`) make `get_file_type(get_file_format(file))`; the error of a save
  of a held file with no name, and the facet `type` of a file in a roster, use the name
  that a reader gives the file (below). Not changed, and they say `File` for a file:
  `describe_document` (the menu entry "Show File in the explorer"), the descriptions of
  `DocumentRelease.jl` in the gesture log ("acquire the File that enters the window"),
  "This File has no command now." of `PartCommands.jl`, the kind of a row in the filter
  of the explorer (one kind `File` for each format), `show` of a document, and the
  `.pred` text of a file written as its own constructor.
- **Proposed by the assistant: a gesture table of the file of one format is a method on
  `Type{<:JsonFile}`.** `@gestures JsonFile` writes a method on `Type{File{JsonFileFormat}}`,
  which the walk of the kernel never asks (the proof). So the tables of JSON, XML and YAML
  are `get_document_gesture_bindings_own(::Type{<:JsonFile}) = _JSON_FILE_BINDINGS`, as
  the table of Julia already was a method. The tables stay on the file type, through the
  short name (P10). Rejected: a change of the walk in `source/kernel/binding/`, which is
  not sealed, because a change of the kernel is the owner's; `@gestures <:JsonFile`,
  because the macro takes a type.
- **Proposed by the assistant: a reader names the file of a format by the name of the
  format without `Format`,** `get_document_schema_name(::Type{<:File{F}})`, so `JsonFile`
  for `File{JsonFileFormat}`. The kernel says that this function gives "the name to show a
  reader". It gives a roster (`compute_item_facet(::FileDocument, ::Val{:type})`, so a
  table of files groups `TextFile` and `JsonFile` apart, as `test_roster_program` asserts),
  the inspector and the error of a save a name for each format, and the reader of a
  `.pred` file builds a file by that name, so the marker `TextFile("page.txt", "hello")`
  of `test_text_file` builds a `TextFile` again. Rejected: a new seam of a format for the
  name, which is a new function; a search of the module of the format for its short name,
  a scan of names at each call that gives no name to a format with no short name; the
  name `File{JsonFileFormat}`, which the grammar of a marker can not write.
- **Proposed by the assistant: one `find_navigator_target(file::FileDocument, target)` in
  the navigator slice.** §5 moves the method from the file to the document. The two
  methods of a file did one thing, after what the document names: a relative path to a
  file beside the file, which only the file knows. So the navigator slice has one method
  for each file document, and Markdown and RST keep the method of their root. **A person
  sees this:** a link in a file of each format to a file beside it opens that file.
- **Proposed by the assistant: the format that a `.pred` file writes inline is read from
  `collect_file_formats()`.** `find_natural_file_format` is of the natural slice, which
  the serialization slice can not use, so the private `_find_domain_format(node)` gives
  the first format of the session whose domain holds the node, other than `Document` and
  `Union{}`, and `is_pred_document` asks it too. The tag of the text is the first
  extension of the format, so a YAML value is tagged `yaml"…"` where
  `find_file_extension` gave the shorter `yml"…"`; a file with `yml"…"` still reads. The
  research domain names a block file by the first extension too (`.yaml`).
- **Proposed by the assistant: the file types of the tests are formats.** `NoteFile`,
  `PredFileLinesFile`, `PredFileViewedLinesFile`, `_ShoutedFile` and `_ReadOnlyProbeFile`
  become `NoteFileFormat` (with its struct, a file that is its own content),
  `PredFileLinesFileFormat`, `PredFileViewedLinesFileFormat`, `_ShoutedFileFormat` and
  `_ReadOnlyProbeFileFormat`, declared at the top of their test files; the last two have
  no extension, `()`. So they are formats of each session that loads
  `ProjecturedPlatformTest`, where a registration in a testset held an extension for the
  rest of the session. The contract test names them in its list. Each format has a file
  type now, so the contract test makes a file of each format: of the workload text, of an
  empty text for a format that a person edits, and of the seed of the domain for one that
  a person does not edit.
- **The record.** `record.jl` into
  `/var/tmp/projectured-julia-file-format-depot/step5/record`, then `diff -r`: of the 88
  strings, 41 are the string of step 1 and one line break (P6), and 12 are equal: the save
  of Julia, math, `.pred`, plain text and no extension, which wrote the line break before.
  The export of Julia and math is now equal to their save. The SQL file ends with an empty
  line, `SELECT\n  name\nFROM\n  people\n\n`, because the printer of SQL ends its string
  with a line break of its own. The other differences are not P6: the export of plain
  text, of a path with no extension, of `.markdown` and of the six `.pred` inputs writes
  now, where `import_document` refused them, and each is the save of step 1 (the save of
  `.markdown` and one line break); the export and the save of a picture raise
  "make_document_string: the documents of ImageFileFormat have no syntax notation", where
  they raised "unsupported extension" and "emit_text: no method"; the export of a source
  file raises "could not write …; the log says why", where it raised "unsupported
  extension", and its save answers `false` as before.
- **What a person sees.** A saved JSON, XML, YAML, SQL, Markdown, RST or plain text file
  ends with a line break (P6), and a saved SQL file with an empty line. A new YAML or math
  file starts as an insertion, and a new Markdown or RST file as an empty page, where all
  four were an empty document (P7). A link in a file of any format to a file beside it
  opens that file. A `.pred` file tags an inline YAML value `yaml"…"`. The texts of the
  list above say `File` for a file. A new source file of the language server holds an
  empty `PrimitiveString`, the seed of `Union{}`, which its format does not write (its
  save raises an error; before, it held a `DocumentNothing`, and its save was refused with
  a log).
- **Tests that change with the step.** The calls of a removed function take the new one.
  A saved string takes the line break of P6: `TextFileTest.jl` (5), `PredFileTest.jl` (1),
  `SerializationTest.jl` (1), `RosterFacetTest.jl` (1) and `FileChangeStoreTest.jl` (8,
  such as `"saved\n\n"` for the save of the text `"saved\n"`, and its hash). A read
  string loses its line break: `FileChangeStoreTest.jl` (19, such as `"one"` for a file
  `"one\n"`, and `"BYE"` for the read of `"bye\n"` in a format of the test) and
  `ExplorerTest.jl` (1). `FileFormatTest.jl` replaces the
  testset of the forms on a file type with one of `File{F}`, the seed and the line break
  of `make_file`: `test_file_format()` 61 pass (55). `test_file_format_contract()` 350
  pass and 1 fail (305 and 1): the five formats of the tests add 43 assertions, and
  `TallyLogFileFormat` has a file type now, 2 more; the fail is the XML row, now at line
  82.
- **For step 6: the calls in omnet-julia and inet-julia** (`main` of each; omnet-julia
  `6b6375c93`), besides the three `register_natural_domain!` calls of step 4. Each of the
  six file types of omnet-julia defines its struct and methods of removed functions.
  - `source/legacy/ned/NedFile.jl` and `NedModule.jl`: `@document struct NedFile`,
    `get_file_domain`, `parse_file_content`, `emit_text`, `make_reference_leaf(::NedFile, …)`,
    `make_document_seed(::Val{:ned})`, `register_file_document_type!(".ned", NedFile)`,
    the imports of `make_document_seed` from `FileFormatModule` and of `emit_text`,
    `get_file_domain`, `parse_file_content` from `SerializationModule`.
  - `source/legacy/ini/IniFile.jl` and `IniModule.jl`: the same for `IniFile` and `.ini`,
    with `make_document_seed(::Val{:ini})` and `@gestures IniFile` (a method on
    `Type{<:IniFile}`, as in step 5).
  - `source/legacy/testfile/LegacyTestFile.jl` and `LegacyTestModule.jl`: the same for
    `LegacyTestFile` and `.test`, with `is_file_domain_node(::LegacyTestFile, node)` and
    `make_document_seed(::Val{:test})`.
  - `source/legacy/result/presentation/LegacyResultFile.jl`: `get_file_domain`,
    `is_editable_file_type`, `read_file_content(::Type{<:LegacyResultFile}, path)`,
    `register_file_document_type!(".sca" / ".vec", …)`, and the calls
    `read_file_content(LegacyResultFile, path)` at lines 232 and 385; the struct keeps its
    own type (O4).
  - `source/legacy/result/presentation/LegacyEventLogFile.jl`: `get_file_domain`,
    `is_editable_file_type`, `read_file_content(::Type)`,
    `register_file_document_type!(".elog", …)`.
  - `source/legacy/simulator/presentation/LegacyFingerprintStore.jl`:
    `is_editable_file_type`, `get_file_domain`, `parse_file_content`, `emit_text`, and
    `parse_file_content(LegacyFingerprintStoreFile, text)` at line 234.
  - `source/ide/StudyVerbs.jl:369`: `get_file_document_type(filename)` and
    `make_file(T, filename, text)`; `source/ide/CampaignVerbs.jl:500`:
    `has_file_document_type(path) && make_file(get_file_document_type(path), …)`;
    `source/ide/IdeWorkload.jl:106, 108, 359`: `make_file(get_file_document_type("Net.ned"), …)`,
    `make_file(get_file_document_type("study.ini"), …)` and
    `type <: FileDocument && !is_editable_file_type(type)`;
    `source/ide/LegacyBaselineFileView.jl:71`: `read_file_content(LegacyResultFile, path)`.
  - Tests: `test/legacy/ini/IniFileNoteTest.jl:27, 49` (`parse_file_content`),
    `test/legacy/result/LegacyResultFileTest.jl:67` (`is_editable_file_type`),
    `test/legacy/simulation/LegacyFingerprintStoreTest.jl:21, 83`,
    `test/legacy/simulation/LegacyResultFolderTest.jl:517` (`read_file_content` of the
    type), `test/legacy/simulation/MiniProjectRoundTripTest.jl:53, 54`
    (`make_file(OmnetLegacy.NedFile, …)`, `make_file(OmnetLegacy.IniFile, …)`).
  - Search corpora that name a removed function as an answer:
    `example/ide/SearchContextCorpus.jl:132` (`write_document_file`) and
    `example/ide/SearchUntunedCodeCorpus.jl:86, 87` (`import_document`).
  - `source/ide/LegacyIniFileEntryToWidget.jl:150` calls `find_navigator_target(file, section)`,
    which the method of step 5 for a file document answers; it needs no change.
  - inet-julia names no removed function. It names `MarkdownFile` and `ImageFile`
    (`package/InetQueuingExample/src/InetQueuingExample.jl:67`,
    `test/model/queuing/tutorial.jl:538`), which the short names keep.
- **For step 7.** The record of the compile-ahead lists: the load warns that 100 of the
  978 recorded calls of `ProjecturedRST`, 358 of the 3297 of `ProjecturedJulia`, 43 of the
  411 of `ProjecturedBook` and 49 of the 488 of `ProjecturedResearch` no longer resolve.
  The system text changes in two lines, by the removed exports: the line of
  `FileFormatModule` has its new first sentence and names `write_document_file!` in place
  of `export_document`, `import_document` and `write_document_file`, and the types of
  `SerializationModule` hold `File`. `describe_natural_formats()`, the docstrings of
  `parse_natural_text` and `describe_natural_formats`, the insertions and the syntax rows
  are byte-equal to step 4; the docstring of `print_natural_text` names
  `write_document_file!` in place of `export_document`
  (`/var/tmp/projectured-julia-file-format-depot/step5/after`, by `step4/capture.jl`).

**2026-11-16, the check of step 5 by the lead.**

- **The places that read the bare type name lose the format.** The type of
  `JsonFile("a.json", JsonInsertion())` is `File{JsonFileFormat, Cell, Cell, Cell, Cell,
  Cell}`: the format is the parameter of the schema and the five cells are the layout, and a
  copy keeps the format (`_apply_schema_parameters`). But `get_document_family` answers
  `AFile` and `get_document_cell_type` `File`, the same for each format, because they name
  no parameter; `get_document_schema_name` answers `JsonFile` by the method of step 5. A
  first reading of this check said that the kernel takes each parameter for a layout; the
  copy shows that it does not. Each place that asks for "the type of a
  document with no layout" through `Base.typename(T).wrapper` or `nameof` loses the format:
  the walk of the gesture tables (`GestureBinding.jl:70`, so `@gestures JsonFile` is not
  found), the kinds of the explorer filter (`ExplorerFilter.jl:77`, one kind `File` for
  each format), `describe_document` (`PaneProgram.jl:164`), the three descriptions of
  `DocumentRelease.jl` and the line of `PartCommands.jl:95`. The rebuilds
  `Copying.jl:118` and `DocumentView.jl:117` would build a bare `File`, which no
  constructor takes; no file reaches them now, and the cut never rebuilds a file node (a
  held file is a reference leaf). None of the kernel files is sealed. The question goes
  to the owner: a kernel that keeps such a parameter bound, or the platform that asks the
  format at each place.
- **The time guard of `test_formula()` is noise.** `FormulaFrameGuardTest.jl:67` failed
  on the branch three times. Five measurements of `time_ratio` on each, alone, on the same
  day: main `107fe8fc0` 3.26, 3.60, 3.59, 4.50, 4.05; the branch 4.02, 3.47, 3.70, 3.00,
  3.12. So it is no regression. The script is
  `/var/tmp/projectured-julia-file-format-depot/check/ratio.jl`.
- **Checked:** the system text differs from step 4 only where step 5 removes
  `import_document`, `export_document` and `write_document_file`, and in the type lists;
  `describe_natural_formats()` is byte-equal. The failure of `FileDialogTest.jl:138` is in
  the baseline. The worktree is clean at `a697a2d93`.

**2026-11-16, the schema type (O7).**

- **The kernel function.** `get_document_schema_type(T)` (`DocumentInterface.jl`,
  `DocumentDefaults.jl`, exported by `DocumentModule`) answers
  `_apply_schema_parameters(get_document_cell_type(T), T)` for a concrete type, and `T`
  itself for a type that is not concrete (a family, a `UnionAll`, an abstract type). So the
  walk does not ask the cell layout again at the level of the family, which would give each
  binding twice. The copy of a cell layout (`DocumentCopy.jl`) calls it in place of the
  same expression. `@document` does not change.
- **The gesture walk** (`GestureBinding.jl`) asks at each concrete level the schema type
  first, then the bare stem when it differs. So `@gestures JsonFile` names
  `File{JsonFileFormat}`, and a table on `File` would apply to each format. The tables of
  JSON, XML and YAML are `@gestures` again, as on main, and the three imports of
  `get_document_gesture_bindings_own` of step 5 are gone.
- **The explorer kinds** (`ExplorerFilter.jl`) key by the schema type, so the files of one
  format are one kind. The name of a kind comes from `get_insertion_names`, which now
  derives the names from `get_document_schema_name(T)` in place of `nameof(T)`: "Text file"
  and "Pred file", not "File". This also changes the names of a schema whose bare name binds
  its native layout (`TaskGroup`, `TaskExecution`), from the coded name to the bare name.
- **The texts** call `get_document_schema_name`: the three descriptions of
  `DocumentRelease.jl`, `PartCommands.jl:95`, `describe_document` and the duplicate error of
  `PaneProgram.jl`.
- **Not changed:** `Copying.jl:118` rebuilds the layout of its source, and the schema type
  would turn a native source into a cell layout; `DocumentView.jl:117` is the code of the
  views pilot. No file reaches either now. Both stay for the plan of theme T6 or a defect.
- **Tests:** `DocumentMacroTest` (the schema type of each layout), `GestureBindingTest` (a
  table on `GestureProbeTagged{Int}` applies to that type only), `FileFormatTest` (the
  schema type and name of `File{TallyLogFileFormat}`), `ExplorerTest` (two formats are two
  kinds).
