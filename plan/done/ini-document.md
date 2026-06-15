# INI Document Domain — `Ini.jl`

Add an OMNeT++ INI file document domain to ProjecturEd, modelled after `Xml.jl`
and `Json.jl`. The OMNeT++ INI format is defined in the
[Simulation Manual, Chapter 10](https://doc.omnetpp.org/omnetpp/manual/#10-configuring-simulations).

## Source material

The OMNeT++ INI file (usually `omnetpp.ini`) is a line-oriented configuration
format organised into sections, each containing key-value entries. The format
supports comments, file inclusion, line continuation, wildcard parameter paths,
iteration variables for parameter studies, and section inheritance via `extends`.

### Format summary (from manual + samples)

**Structure:**
- Line-oriented text, `#` starts a comment to end-of-line
- Lines grouped into sections: `[General]` and named configs
- Three line types: section headings, key-value entries, `include` directives
- Line continuation via trailing `\` or indented continuation lines
- Key-value lines may not appear before the first section heading (except in
  included files)

**Sections:**
- `[General]` — default fallback section, always implicit base
- `[ConfigName]` or `[Config ConfigName]` — named configurations (the `Config`
  prefix is optional, i.e. `[Foo]` ≡ `[Config Foo]`)
- Section order is not significant
- Inheritance: `extends = Base1, Base2` (C3 linearisation for fallback chain)

**Key classification (by syntax):**
1. **Config options** — keys without dots: `network`, `sim-time-limit`,
   `cpu-time-limit`, `description`, `extends`, `repeat`, `num-rngs`,
   `record-eventlog`, `seed-N-mt`, etc.
2. **Per-object config options** — keys with dots where the last component
   contains a hyphen or equals `typename`: `**.vector-recording`,
   `**.result-recording-modes`, `**.rng-0`, `**.typename`
3. **Parameter assignments** — keys with dots where the last component has no
   hyphen: `Aloha.numHosts`, `**.host[*].iaTime`, `*.queue[*].serviceTime`

**Value features:**
- Iteration variables: `${1, 2, 5, 10..50 step 10}`,
  `${name=val1, val2}`, `${iaMean=1,2,3,4,5..9 step 2}`
- NED expressions as values: `exponential(2s)`, `uniform(0m, 1000m)`,
  `truncnormal(3s,1s)`, `intuniform(0,1) == 0 ? exponential(10) : normal(30,5)`
- String values: `"App"`, `"1 50"`
- Numeric values with units: `100ms`, `9.6kbps`, `952b`, `7MiB`
- Special values: `ask`, `true`, `false`, `default`

**Wildcard patterns in keys:**
- `?` — any character except dot
- `*` — zero or more characters except dot (single path component)
- `**` — zero or more characters including dot (any depth)
- `{a-f}` — character set
- `{38..150}` — numeric range
- `[38..150]` — index range in square brackets

**Include directive:**
- `include <filepath>` — textual inclusion; relative paths resolved from the
  including file's location

## Design decisions

### Separate config options from parameter assignments

The INI format has two semantically distinct entry types (classified by key
syntax — see "Key classification" above). The document model reflects this
with **two concrete types**:

- **`IniConfigOption`** — keys without dots. These control the simulation
  engine: `network`, `sim-time-limit`, `extends`, `description`, `repeat`,
  `num-rngs`, `seed-N-mt`, etc.
- **`IniParamAssignment`** — keys containing dots. These assign values to model
  parameters (`Aloha.numHosts`, `**.host[*].iaTime`) **and** per-object config
  options (`**.vector-recording`, `**.rng-0`, `**.typename`). Both share the
  same structure: a dotted pattern path and a value.

This split matches the manual's primary distinction and enables projections
to render config options and parameter assignments differently (e.g. distinct
colours, separate fold groups). The finer per-object-option vs. parameter
distinction (hyphen in last component) can be derived syntactically from the
key when needed — it does not require a third type.

### Key and value representation

Keys and values are stored as opaque `String` fields. The wildcard patterns,
module path syntax, iteration variables, and NED expressions within values are
all *opaque strings* at the document level. Parsing these into structured
sub-documents (e.g. a wildcard-path AST or NED expression tree) is a future
concern for a projection layer (IniToSyntax), exactly as NED expression strings
are handled in the NED document plan.

### Section naming

The `[General]` section and `[Config Foo]` / `[Foo]` sections are unified into
a single `IniSection` type. A boolean `is_general` field distinguishes the
General section. The `name` field stores `"General"` or the normalised config
name (without the `Config` prefix). `[Foo]` and `[Config Foo]` both produce
`name = "Foo"`.

### Comment handling

Standalone comment lines (lines beginning with `#`) are modelled as `IniComment`
leaf nodes that can appear both at the file level (before/between sections) and
within sections (between entries). Inline comments (trailing `#` on a key-value
line) are stored as a `comment` field on `IniConfigOption` / `IniParamAssignment`.

### Blank lines

Blank lines are ignored. The document model does not preserve them.

### Include directives

`include` lines are modelled as `IniInclude` leaf nodes. They can appear both
at file level and within sections.

### Line continuation

Line continuation (trailing `\` or indentation) is a lexical concern. At the
document level, a continued key-value pair is stored as a single entry with the
full joined key and value. The document model does not preserve the original
line-break positions.

### Iteration variables

Iteration syntax `${...}` in values is kept as part of the opaque value string.
A future projection or analysis layer may parse these into structured
iteration-variable documents.

## Type hierarchy

```
Document
 └── IniDocument (abstract)
      ├── IniFile            # top-level container
      ├── IniSection         # [General] or [Config Name]
      ├── IniConfigOption    # key = value (no dots in key)
      ├── IniParamAssignment # pattern.key = value (dots in key)
      ├── IniComment         # standalone comment line
      ├── IniInclude         # include directive
      └── IniInsertion       # insertion cursor (editor)
```

## Field mapping

### `IniFile`
| Field | Type | Notes |
|---|---|---|
| `children` | `CellVector` | holds `IniComment`, `IniInclude`, `IniSection` |

### `IniSection`
| Field | Type | Notes |
|---|---|---|
| `name` | `String` | `"General"` or config name (e.g. `"PureAloha1"`) |
| `is_general` | `Bool` | `true` for `[General]` |
| `entries` | `CellVector` | holds `IniConfigOption`, `IniParamAssignment`, `IniComment`, `IniInclude` |
| `collapsed` | `Bool` | UI fold state |

### `IniConfigOption`
| Field | Type | Notes |
|---|---|---|
| `key` | `String` | option name, no dots (e.g. `"network"`, `"sim-time-limit"`, `"extends"`) |
| `value` | `String` | value string (e.g. `"Aloha"`, `"100h"`, `"PureAloha1"`) |
| `comment` | `Any` | `Nothing` or trailing inline comment `String` |

### `IniParamAssignment`
| Field | Type | Notes |
|---|---|---|
| `key` | `String` | dotted key with optional wildcards (e.g. `"Aloha.numHosts"`, `"**.host[*].iaTime"`, `"**.vector-recording"`) |
| `value` | `String` | value string (e.g. `"20"`, `"exponential(2s)"`, `"false"`) |
| `comment` | `Any` | `Nothing` or trailing inline comment `String` |

### `IniComment`
| Field | Type | Notes |
|---|---|---|
| `text` | `String` | comment text (the content after `#`, leading `#` excluded) |

### `IniInclude`
| Field | Type | Notes |
|---|---|---|
| `path` | `String` | included file path (e.g. `"omnetpp.ini"`, `"../common/config.ini"`) |

### `IniInsertion`
| Field | Type | Notes |
|---|---|---|
| `value` | `Any` | placeholder for editor insertion cursor |

Every type above also gets the mandatory `selection::Reference` field.

## Example mapping

Given this INI file fragment:

```ini
# This is a comment
[General]
network = Aloha
sim-time-limit = 100h
#debug-on-errors = true
**.animationHoldTimeOnCollision = 0s  # no hold

[PureAloha1]
description = "pure Aloha, overloaded"
Aloha.host[*].iaTime = exponential(2s)

[PureAlohaExperiment]
description = "Channel utilization vs. packet generation frequency"
extends = PureAloha1
repeat = 2
Aloha.numHosts = ${numHosts=10,15,20}
Aloha.host[*].iaTime = exponential(${iaMean=1,2,3,4,5..9 step 2}s)
```

The document model would be:

```julia
IniFile([
    IniComment(" This is a comment"),
    IniSection("General", true, [
        IniConfigOption("network", "Aloha"),
        IniConfigOption("sim-time-limit", "100h"),
        IniComment("debug-on-errors = true"),
        IniParamAssignment("**.animationHoldTimeOnCollision", "0s", " no hold"),
    ]),
    IniSection("PureAloha1", false, [
        IniConfigOption("description", "\"pure Aloha, overloaded\""),
        IniParamAssignment("Aloha.host[*].iaTime", "exponential(2s)"),
    ]),
    IniSection("PureAlohaExperiment", false, [
        IniConfigOption("description", "\"Channel utilization vs. packet generation frequency\""),
        IniConfigOption("extends", "PureAloha1"),
        IniConfigOption("repeat", "2"),
        IniParamAssignment("Aloha.numHosts", "\${numHosts=10,15,20}"),
        IniParamAssignment("Aloha.host[*].iaTime", "exponential(\${iaMean=1,2,3,4,5..9 step 2}s)"),
    ]),
])
```

## Implementation steps

### Step 1 — Scaffold `Ini.jl` (document types only)

Create `program/src/document/Ini.jl` containing:

1. `module IniModule` with the standard imports (`Cell`, `Document`, `@document`,
   `CellVector`, `Reference`).
2. `abstract type IniDocument <: Document end`.
3. All concrete `@document struct` definitions listed above. Start with the
   leaf types (`IniComment`, `IniInclude`, `IniInsertion`), then the entry
   types (`IniConfigOption`, `IniParamAssignment`), then `IniSection`, and
   finally `IniFile`.
4. Convenience constructors following the `Xml.jl` / `Json.jl` patterns:
   - `IniFile()` — empty file
   - `IniSection(name)` — empty section, auto-detects `is_general`
   - `IniConfigOption(key, value)` — config option with no inline comment
   - `IniParamAssignment(key, value)` — param assignment with no inline comment
   - `IniComment(text)` — comment node
   - `IniInclude(path)` — include directive
5. Collection access methods on `IniFile` and `IniSection` (`length`, `getindex`,
   `push!`, `deleteat!`, `insert!`, `iterate`, etc.) following `XmlElement` and
   `JsonArray` patterns.
6. `Base.show` methods for REPL display.
7. Export list.

### Step 2 — Register in `Projectured.jl`

Add `include("document/Ini.jl")` and `using .IniModule` to the main module,
insert the appropriate exports.

### Step 3 — Parser: `iniparse`

Provide an `iniparse(text::AbstractString)::IniFile` function that parses an
INI file string into an `IniFile` document tree. The parser lives inside
`IniModule` and is exported.

#### 3.1 — Preprocessing: line continuation

Before tokenising, join continued lines:

1. **Backslash continuation**: scan for lines ending with `\` (ignoring
   trailing whitespace after `\`). Remove the `\` and newline, concatenate
   with the next line (preserving its leading whitespace).
2. **Indentation continuation**: after backslash joining, any line that starts
   with whitespace (space or tab) and is not a comment or blank is appended
   to the previous logical line (separated by a space).

Result: a `Vector{String}` of logical lines with no continuations.

#### 3.2 — Line classification

For each logical line, classify:

1. **Blank line** → skip (blank lines are not preserved).
2. **Comment line** (first non-whitespace is `#`) → `IniComment`. Store
   the text after `#` (including leading space for readability).
3. **Section heading** (matches `^\s*\[.*\]\s*(#.*)?$`) → start a new
   `IniSection`. Parse the name between brackets:
   - If name is `General` → `is_general = true`, `name = "General"`.
   - If name starts with `Config ` → strip prefix, `is_general = false`.
   - Otherwise → use as-is, `is_general = false`.
   - Trailing `# comment` after `]` is emitted as a separate `IniComment`
     inside the section.
4. **Include directive** (starts with `include `) → `IniInclude`. The path
   is the remainder of the line after `include `, stripped of leading/trailing
   whitespace and optional quotes.
5. **Key-value line** (contains `=`) → split on the **first** `=`. Trim
   whitespace from key and value. Extract trailing inline comment from value
   (scan for unquoted `#`). Classify:
   - Key contains a dot → `IniParamAssignment(key, value, comment)`.
   - Key has no dot → `IniConfigOption(key, value, comment)`.

#### 3.3 — Inline comment extraction

When extracting a trailing `# comment` from a value string, the `#` must not
be inside a quoted string literal. Simple algorithm:

1. Scan left-to-right through the value.
2. Track whether inside double quotes (toggle on unescaped `"`).
3. First `#` found outside quotes splits the value from the comment.
4. If no unquoted `#` is found, comment is `nothing`.

#### 3.4 — Building the tree

- Lines before the first section heading are added to `IniFile.children`
  directly (as `IniComment` or `IniInclude`).
- Once a section heading is encountered, subsequent entries are collected
  into that section's `entries` CellVector until the next heading or EOF.
- Each completed section is pushed into `IniFile.children`.

#### 3.5 — File-based convenience

Also provide `iniparse_file(path::AbstractString)::IniFile` that reads the
file and calls `iniparse`. This does **not** recursively follow `include`
directives — that is a separate concern.

### Step 4 — `_apply_string_replace!` methods

Implement string-replace operations for the editable string fields:
- `IniConfigOption`: fields `key`, `value`
- `IniParamAssignment`: fields `key`, `value`
- `IniComment`: field `text`
- `IniInclude`: field `path`
- `IniSection`: field `name`

Follow `Xml.jl`'s pattern of one method per concrete type dispatching on
`field_name`.

### Step 5 — Tests

- Unit tests: construct each type, verify field access, push/delete children.
- Parse tests:
  - Parse `omnetpp/samples/aloha/omnetpp.ini` → verify 8 sections, correct
    config names, General entries.
  - Parse `omnetpp/samples/routing/omnetpp.ini` → verify per-object options
    like `**.channel.*.result-recording-modes` produce `IniParamAssignment`.
  - Parse `omnetpp/samples/fifo/omnetpp.ini` → verify inline comments and
    config option extraction.
  - Parse `omnetpp/samples/aloha/akaroa.ini` → verify `IniInclude` for the
    `include omnetpp.ini` directive.
- Edge cases: line continuation (backslash, indentation), iteration variables
  `${...}` in values, section names with/without `Config` prefix.
- Round-trip: build an `IniFile`, snapshot via the I-struct, hydrate back,
  and compare.

### Step 6 (future) — `IniToSyntax` projection

A printer/reader pair that renders INI documents as syntax-highlighted text
with section headers, keys, operators (`=`), values, comments in distinct
colours. `IniConfigOption` and `IniParamAssignment` can be styled differently.
This is a separate plan; the document types must exist first.

### Step 7 (future) — Structured key/value sub-documents

If editing needs demand it, introduce:
- `IniKeyPath` — parsed wildcard module path (components, wildcards, indices)
- `IniIteration` — parsed `${...}` iteration variable
- `IniExpression` — parsed NED expression in values

These would be used by a richer projection that allows structured navigation
of keys and values. Defer until projection work starts.

### Step 8 — Example document: `example/src/document/Ini.jl`

Create a `make_ini_document_example()` function that builds a representative
`IniFile` programmatically, similar to `make_xml_document_example()`. The
document should demonstrate the key INI features:

- A `[General]` section with config options (`network`, `sim-time-limit`)
- A named config section with `description`, `extends`, and parameter
  assignments using wildcard paths
- A parameter-study section with iteration variables `${...}` in values
- An `IniInclude` at the file level
- A few `IniComment` nodes (standalone and with inline comments)
- An `IniInsertion` at the end for cursor positioning

This is a static hand-crafted document (not parsed from text), used for
interactive exploration in the editor.

### Step 9 — Example projection: `example/src/projection/Ini.jl`

Create a `make_ini_projection_example()` function that builds the projection
pipeline for INI documents, following the pattern of `make_xml_projection_example()`:

```julia
function make_ini_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(IniToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

This depends on Step 6 (`IniToSyntax` projection) being implemented first.
The projection renders the INI document as syntax-highlighted text with:

- Section headers (`[General]`, `[Config Name]`) as syntax nodes
- Config options and param assignments as key `=` value leaves
- Comments in a distinct colour
- Include directives styled as directives

Both example files need to be registered in `example/src/ProjecturedExample.jl`
and wired into `example/src/Examples.jl`.

## Open questions

1. **Commented-out entries**: Lines like `#debug-on-errors = true` are common.
   They are stored as `IniComment` nodes. A future enhancement could flag them
   as "commented-out entries" with recoverable key/value.
