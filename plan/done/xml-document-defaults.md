# Eliminate Xml.jl boilerplate constructors via `@document` defaults

Mirror the `refactor(julia): eliminate boilerplate constructors via @document defaults`
(commit `f400ef0`) for the XML domain: give every XML document type `@kwdef`-style
field defaults so the `@document` macro regenerates the
`Foo(...) = Foo(Cell(...), Cell(nothing))` boilerplate (Rule Y), and drop the
now-redundant conversion constructors.

File: `package/domain/src/document/Xml.jl`.

## Macro facts this relies on

- **Rule Y** (positional-defaults): for a trailing run of defaulted fields with
  ≥1 leading required field, the macro emits `Foo(f₁..f_k)` filling the omitted
  suffix with defaults. Fully-defaulted structs get none (keyword ctor only).
- **Auto-wrapping inner ctor**: every field arg is `x isa Cell ? x : Cell(x)`.
  - For a `String`/`Symbol`/`Bool` value → primitive cell.
  - For a **`Function`** value → `Cell(f)` is a **computed thunk** cell. So a
    single generated positional ctor covers *both* the string form and the
    `f::Function` reactive form — the two hand-written ctors collapse into one.
  - For a **`CellVector`** value → `Cell(cv)`; read back via `getproperty` as the
    CellVector (a CellVector is `<: Document`, not `<: Cell`, so it is wrapped and
    unwrapped transparently — same as the existing hand-written ctors already do).
- All XML construction call sites pass `String` (literals, or `_name!` /
  `_attr_value!` / `_text_until_lt!`, all of which return `String`), so dropping the
  explicit `String(...)` conversions keeps the `a.value::String` / `t.content::String`
  assertions in `getindex` valid.

## Per-type plan

### `XmlInsertion` — already done
Already `value::Any = nothing`, `selection::Reference = nothing`, no hand-written
ctors. No change.

### `XmlAttribute` — [x] drop both ctors + `xmlattr`
- Add `selection::Reference = nothing`.
- Rule Y (req=2 name/value, trailing=1) emits `XmlAttribute(name, value)`.
  Auto-wrap covers `value::AbstractString` **and** `value::Function` (thunk).
- Drop `XmlAttribute(name, value::AbstractString)` and
  `XmlAttribute(name, f::Function)`.
- Simplify `xmlattr(name, value) = XmlAttribute(name, value)`.

### `XmlText` — [x] drop both ctors
- Add `selection::Reference = nothing`.
- Rule Y (req=1 content, trailing=1) emits `XmlText(content)`; auto-wrap covers
  `AbstractString` and `Function`.
- Drop `XmlText(v::AbstractString)` and `XmlText(f::Function)`.

### `XmlElement` — [x] drop empty ctor, keep+simplify the three disambiguators
Two `CellVector` fields (`attrs`, `children`), so the macro's single-CellVector
Rule C does **not** apply and cannot disambiguate attrs-vs-children (both are
`Vector`s distinguished only by element type). Keep the type-dispatched ctors.

- Default all trailing fields:
  `attrs::CellVector = CellVector()`, `children::CellVector = CellVector()`,
  `collapsed::Bool = false`, `selection::Reference = nothing`.
- Rule Y (req=1 tag) now emits `XmlElement(tag)` → drop the hand-written empty ctor.
- Keep three typed ctors; they are strictly more specific than Rule Y's untyped
  positional forms, so no ambiguity:
  - `XmlElement(tag, attrs::Vector{XmlAttribute}) = XmlElement(tag, attrs, XmlDocument[])`
  - `XmlElement(tag, children::Vector{<:XmlDocument}) = XmlElement(tag, XmlAttribute[], children)`
  - `XmlElement(tag, attrs::Vector{XmlAttribute}, children::Vector{<:XmlDocument}) =`
    `XmlElement(tag, CellVector(attrs), CellVector(children))`
    — the 3-arg CellVector call lands on Rule Y's generated untyped 3-arg, which
    fills `collapsed`/`selection`. `CellVector(vec)` replaces the verbose
    `CellVector(Cell[Cell(x) for x in vec])`.

## Verification — DONE

Ran (worktree, cached precompile):
`test_xml_to_syntax()`, `test_xml_to_syntax_reader()`, `test_xml_parser()`,
`test_printer(xml_example)`, `test_reader(xml_example)`, `test_example(xml_example)`.

`test_example` bundles printer + reader + repl + text_navigation + typein. Result:

- printer **7318 pass**, reader **225 pass**, repl **225 pass**, text_navigation
  **1015 pass** — all green (these are the construction-sensitive layers).
- typein **0/51** — the *pre-existing* wholesale "no cursor in Graphics image"
  baseline (see memory `typein-json-xml-baseline`: `test_typein(xml_example)=0/51`,
  `repl 225/225 green`). Not a regression: constructor changes cannot leave
  printer/reader/repl/navigation green while breaking only the interactive
  cursor-render path.
- `test_xml_to_syntax` / `_reader` / `test_xml_parser` — green.

Net regression-free. Constructors eliminated: both `XmlAttribute` ctors, both
`XmlText` ctors, the empty `XmlElement(tag)` ctor, and the verbose bodies of the
three kept `XmlElement` disambiguators (now use `CellVector(vec)` + Rule Y tail).
</content>
</invoke>
