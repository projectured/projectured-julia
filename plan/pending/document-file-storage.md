# Document file storage

Save/load the ProjecturEd document graph as a set of text files that
can be version-controlled with git the ordinary way. The graph knows
its own file layout: every node that should live in its own text file
is a **file document** carrying a `filename`; the saver walks the
graph and each file document's content becomes that file. Cross-file
references (including sub-file fragment references) are expressed as
kernel `ConcreteReference` chains prefixed with a new
`FileReferenceStep`, embedded in the containing file's natural format.

Companion work in `omnetpp-pred` adds a `filename` field to the
existing `NedFile` / `IniFile` types and extends the NED / INI
parsers to preserve line comments so reference markers survive
round-trip. `omnetpp-julia` registers those types as file documents.

## Model

### File documents

One concrete type per format. Each declares two fields:
`filename::String` and `content` (the format-native AST held in a
reactive cell; all reactive cells are `Any`-typed at runtime, so any
`Document` can sit in a slot regardless of declared AST type — see
the marker-walk note below).

Projectured-side (all AST types + parsers **already exist** in the
domain package):

| Type          | AST type          | Parser (existing)                        | Printer (existing)                        |
|---------------|-------------------|------------------------------------------|-------------------------------------------|
| `JsonFile`    | `JsonDocument`    | `jsonparse` (`domain/json/JsonParser.jl`)         | `document_to_text` via `JsonToSyntax`     |
| `XmlFile`     | `XmlDocument`     | `xmlparse` (`domain/xml/XmlParser.jl`)            | `document_to_text` via `XmlToSyntax`      |
| `JuliaFile`   | `JuliaDocument`   | `juliaparse` (`domain/julia/JuliaParser.jl`)      | `document_to_text` via `JuliaToSyntax`    |
| `MarkdownFile`| `MarkdownDocument`| `markdownparse` (`domain/markdown/MarkdownParser.jl`) | `document_to_text` via `MarkdownToSyntax` |
| `TextFile`    | `String`          | identity                                          | identity                                  |

omnetpp side (in omnetpp-pred / omnetpp-julia):

| Type       | AST type            | Parser (existing)          | Printer (existing)                |
|------------|---------------------|----------------------------|-----------------------------------|
| `NedFile`  | omnetpp-pred NED AST| `nedparse` (omnetpp-pred)  | `document_to_text` via `NedToSyntax` |
| `IniFile`  | omnetpp-pred INI AST| `iniparse` (omnetpp-pred)  | `document_to_text` via `IniToSyntax` |

All are `<: FileDocument <: Document`. **`filename` is added to the
existing `@document struct NedFile` / `IniFile`** in omnetpp-pred —
`@document` auto-appends `selection` last, so this is a one-field
addition.

### Root manifest

A saved project has one entry-point file document (the "root"), by
default a `JsonFile` named `root.json`. Every other file document
is reached from it via a reference chain.

### FileReferenceStep (new kernel step type)

```
struct FileReferenceStep <: ReferenceStep
    path::String   # relative to the project's base dir; `../` disallowed
end
```

Slots in beside `FieldReferenceStep`, `RangeReferenceStep`, etc.
Prints and parses through the existing `@reference` /
`parse_reference_path` machinery. Example:

```
@reference file("model/Aloha.ned").networks.Aloha.submodules.host
```

### IdentityDocument + IdentityReferenceStep (new)

Stable, name-based addressing that survives structural moves.

```
struct IdentityDocument <: Document
    identity::String
    content::Any
end

struct IdentityReferenceStep <: ReferenceStep
    identity::String
end
```

**Resolution semantics.** DFS pre-order over the currently-focused
node; returns the `.content` of the first `IdentityDocument` whose
`identity == id`. Duplicate identities within the focused subtree
are an **error** at resolve time (so a duplicate can appear
transiently mid-edit without exploding).

Example fragment reference:

```
@reference file("model/Aloha.ned").identity("host-1").submodules
```

### Marker embedding

Uniform marker text, escaped per format:

| Format    | Escape                                                                   |
|-----------|--------------------------------------------------------------------------|
| JsonFile  | JSON string equal to `<<REF>>` (whole-string match)                      |
| JuliaFile | `@ref file("…").…` macro call                                            |
| Markdown  | `[label](<<REF>>)` link, or fenced block with `pred-ref="…"`             |
| XmlFile   | `<pred:ref>REF</pred:ref>` element                                       |
| NedFile   | `// @pred-ref REF` line comment                                          |
| IniFile   | `# @pred-ref REF` line comment (omnetpp-pred INI uses `#`, not `;`)      |

`REF` is the printed form of a `ConcreteReference` starting with
`FileReferenceStep`. Whole-file: `file("path")`. Fragment:
`file("path").identity("name").a.b.c`.

### Marker walk (per format, load only)

- **Load**: parse text via the existing projectured parser → strict
  AST → walk once, recognizing marker nodes (JSON string,
  `@ref` macro-call, `[label](<<…>>)` / fenced block with `pred-ref`,
  `<pred:ref>`, comment line). Each marker is replaced *in the slot*
  with a `ReferenceStub` (see below). Reactive slot cells are
  `Any`-typed at runtime, so this works even when the AST slot is
  declared narrower (`JsonDocument`, `XmlNode`, …).
- **Save**: no walk. `ReferenceStub` has its own `<Fmt>ToSyntax`
  method per format (see below) so `document_to_text(content)`
  emits the marker directly when it hits a stub. Save just: project
  → compare bytes → write.

### ReferenceStub

```
struct ReferenceStub <: Document
    reference::ConcreteReference   # starts with FileReferenceStep
    resolved::ReactiveCell{Any}    # forced value is the target Document
end
```

Forcing `resolved` looks the reference up in the loader's intern
table; on miss, it loads the target file (which recursively wires
its own stubs) and returns the resolved node.

**Per-format printing.** Each format registers a `<Fmt>ToSyntax`
method on `ReferenceStub` that emits the format's marker (JSON
string, XML element, Julia macro-call, Markdown link, NED / INI
comment line). This is what makes save cheap: no pre-save AST
mutation, no discipline for callers to remember — the projection
pipeline handles stubs uniformly.

### Shared identity across files

The loader keeps an intern table keyed by `(canonical_path,
ConcreteReference)`. Two stubs to the same ref yield the same forced
value (`===`). Cycles: stubs are only forced on demand, so A→B→A
loads fine.

### Lazy loading

Every file document's `content` is a reactive cell whose read
function reads-and-parses the file on first access. Loading the
manifest does NOT force children.

### Save trigger

Explicit `save_project!(root, base_dir)`. Iterates every **loaded**
file document reachable from `root`, projects its content to text via
`document_to_text`, compares byte-for-byte with the current on-disk
contents, and writes only when they differ (or the file is missing
— recreate). Unloaded file documents are left untouched on disk.

## New pieces

### projectured-julia

- `package/kernel/main/reference/FileReferenceStep.jl` — step +
  printer/parser hooks.
- `package/kernel/main/reference/IdentityReferenceStep.jl` — step
  + DFS-pre-order resolver + duplicate detection.
- `package/kernel/main/document/IdentityDocument.jl` — two-field
  document type.
- `package/base/main/document/FileDocument.jl` — abstract
  `FileDocument <: Document` + interface (`filename`, `content`).
- `package/base/main/document/ReferenceStub.jl` — stub type.
- `package/base/main/serialization/FileProject.jl` — driver:
  `save_project!`, `load_project`, intern table, lazy-cell wiring.
  **Parametrised on a per-format `to_text` callable** injected by each
  format's registration (keeps base free of `visual/` dependency).
- `package/domain/main/json/JsonFile.jl`         — `JsonFile` + JSON marker walk.
- `package/domain/main/xml/XmlFile.jl`           — `XmlFile` + XML marker walk.
- `package/domain/main/julia/JuliaFile.jl`       — `JuliaFile` + Julia marker walk.
- `package/domain/main/markdown/MarkdownFile.jl` — `MarkdownFile` + Markdown marker walk.
- `package/domain/main/filesystem/TextFile.jl`   — plain text.
- Format registrations wire each `<Fmt>File` to its `to_text`
  callable at load time (the `visual/`-side projection is the
  callable).

### omnetpp-pred (in the standing worktree)

- Add `filename::String` field to `@document struct NedFile` /
  `IniFile` (`program/src/document/Ned.jl:318` / `Ini.jl:87`).
- **NED parser only**: extend the Lerche grammar in
  `program/src/parser/NedParser.jl` to preserve line + block
  comments. Mirror the INI parser's shape: a standalone `NedComment`
  node in statement position, plus an optional `trailing_comment`
  field on statements where a trailing comment is common (following
  `IniComment` at `IniParser.jl` — comments already work there,
  no INI change needed).

### omnetpp-julia

- `src/file_documents/NedFile.jl` — register NedFile as
  `FileDocument`; NED marker walk (line-comment).
- `src/file_documents/IniFile.jl` — same for INI (marker via `#`
  line comment).
- Round-trip integration test on a mini omnetpp project (README.md +
  omnetpp.ini + model.ned + root.json).

## Stages

**S1 — Reference-step additions in kernel**
`FileReferenceStep`, `IdentityReferenceStep`, `IdentityDocument`.
Printer/parser round-trips; DFS resolver with duplicate-error.

**S2 — FileDocument + TextFile end-to-end**
`abstract FileDocument`, `ReferenceStub`, driver in
`base/serialization/`. `TextFile` concrete. One-file project
round-trip.

**S3 — JsonFile round-trip**
`JsonFile` + JSON marker walk + registration. Two-file project
round-trip (root.json + child.json).

**S4 — Intern table + shared identity + cycles**
Loader intern table; `===` sharing test; A↔B cycle test.

**S5 — Save discipline**
Loaded-only iteration; byte-equality skip; recreate-on-deleted.

**S6 — JuliaFile + MarkdownFile**
Marker walks using existing `juliaparse` / `markdownparse` +
`document_to_text`.

**S7 — XmlFile**
Marker walk using existing `xmlparse` + `XmlToSyntax`.

**S8 — omnetpp-pred + omnetpp-julia integration**
Coordinated `filename` + comment-preservation change in omnetpp-pred.
Register NedFile / IniFile in omnetpp-julia; marker walk via line
comments. Round-trip test on a minimal omnetpp project.

## Open questions

None outstanding — ready to implement pending your go-ahead.

## Out of scope

- Text-diff-aware merges of file-format-native content across git
  branches (git handles it).
- Cross-repository refs (all files under one project root).
- Non-text file contents (images, binary blobs).
- Editor UI for "open project" / "save project".
- Preserving external hand-edits to formatting/whitespace beyond
  what the existing projectured parsers preserve.
