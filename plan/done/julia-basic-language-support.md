# Basic Julia language support — read-only printer subset

## Context

The current Julia domain ([program/src/document/Julia.jl](../program/src/document/Julia.jl)) is the bare minimum needed for the factorial example: `JuliaIdentifier`, `JuliaInteger`, `JuliaBinaryOp`, `JuliaCall`, `JuliaIf`, `JuliaFunction`, `JuliaBlock`. The matching projection ([program/src/projection/primitive/JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl)) prints those seven types.

The goal is to expand this into a **reasonable subset** of Julia for read-only display — comparable in ambition to the existing Math domain, but for Julia source. No editing, no reader (`projection_read`), no insert/delete operations. Just types + printers so a richer set of Julia programs can be projected through the pipeline.

## Scope decisions (resolved with the user)

- **Read-only printer only.** No `projection_read`, no insert/delete operations.
- **No example, no tests.** Just the new types and their printer projections.
- **Definitions out of scope:** no struct, no anonymous/short-form function, no const, no import/using/export, no macros, no module.
- **Strings:** plain text only, no interpolation.
- **Compound assignment (+=, ..):** modeled as an `operator::Symbol` field on a single `JuliaAssignment` type.
- **For loop:** multi-iterator form (`for v1 in i1, v2 in i2 ... end`).
- **Try/catch:** full shape — try body, optional catch with optional variable, optional finally.
- **Optional sub-trees:** use **nullable** fields (`nothing` for absent), not empty-block sentinels.

## Types to add — [program/src/document/Julia.jl](../program/src/document/Julia.jl)

All new types subtype `JuliaDocument`, use `@document`, and carry `selection::Reference` per the Document contract ([guide/design.md §11.2](../guide/design.md)). All fields wrapped in `Cell`s.

### Literals
- `JuliaFloat(value::Float64)`
- `JuliaString(value::String)` — plain text only
- `JuliaBool(value::Bool)`
- `JuliaNothing()`
- `JuliaSymbol(name::String)` — represents `:foo`
- `JuliaChar(value::Char)`

### Expressions
- `JuliaUnaryOp(operator::Symbol, operand::Document)`
- `JuliaTernary(condition::Document, then_branch::Document, else_branch::Document)`
- `JuliaIndex(collection::Document, indices::CellVector)` — `a[i, j, ...]`
- `JuliaFieldAccess(object::Document, field::Document)` — `a.b`; `field` is typically a `JuliaIdentifier`
- `JuliaTuple(elements::CellVector)` — `(a, b, c)`
- `JuliaArray(elements::CellVector)` — `[a, b, c]`
- `JuliaRange(start::Document, step::Union{Document,Nothing}, stop::Document)` — `a:b` or `a:s:b`; `step` nullable
- `JuliaTypeAnnotation(value::Document, type::Document)` — `x::T`

### Statements
- `JuliaAssignment(operator::Symbol, target::Document, value::Document)` — operator is `:(=)`, `:(+=)`, `:(-=)`, `:(*=)`, `:(/=)`
- `JuliaFor(iterators::CellVector, body::Document)` — `iterators` holds `JuliaForIterator` nodes
- `JuliaForIterator(variable::Document, iterable::Document)` — pair-document used inside `JuliaFor.iterators` (must be a Document so selection paths can reach `variable`/`iterable`)
- `JuliaWhile(condition::Document, body::Document)`
- `JuliaReturn(value::Union{Document,Nothing})` — `value` nullable for bare `return`
- `JuliaBreak()`
- `JuliaContinue()`
- `JuliaTry(body::Document, catch_var::Union{Document,Nothing}, catch_branch::Union{Document,Nothing}, finally_branch::Union{Document,Nothing})`
- `JuliaBegin(body::Document)` — `begin ... end` block

### Operator string utility
Extend `_julia_operator_string` to cover any new operators referenced (unary `-`, `!`, `~`; compound `+=`, `-=`, `*=`, `/=`; range `:`). Add `Base.show` for each new type, matching the existing one-line style.

## Printer projections to add — [program/src/projection/primitive/JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl)

One `Projection` struct per new document type, each implementing `projection_print(::Proj, ::DocType, recursion, reference)` and returning a `ChildrenIoMap` (for compounds) or `SimpleIoMap` (for leaves). Wire all of them into the `TypeDispatchingProjection` returned by `JuliaToSyntax()`.

### Existing patterns to reuse

- **Leaves** — follow `JuliaIdentifierToSyntaxLeaf` / `JuliaIntegerToSyntaxLeaf` (lines 36–66 of [JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl)): `SimpleIoMap` returning a `SyntaxLeaf` with empty open/close, value = colored `TextString`, selection passed through with `getfield(v, :selection)`.
- **Compound nodes** — follow `JuliaBinaryOpToSyntaxNode` / `JuliaCallToSyntaxNode` (lines 70–138): build child `iomap` `Cell`s with extended `reference` paths via `append_reference(reference, FieldReference("..."), ElementReference(i))`; produce a `SyntaxNode` whose `children` is a `CellVector` over the child outputs; return `ChildrenIoMap` with the child iomaps cell.
- **Indented blocks** — follow `JuliaBlockToSyntaxNode` (lines 142–163) for `JuliaFor.body`, `JuliaWhile.body`, `JuliaTry.body`, `JuliaBegin.body`, etc. (these can wrap an existing `JuliaBlock`, so the projection just recurses into the body field).
- **Keyword header + indented body + end** — follow `JuliaIfToSyntaxNode` / `JuliaFunctionToSyntaxNode` (lines 167–306) for `JuliaFor`, `JuliaWhile`, `JuliaTry`, `JuliaBegin`.
- **Nullable child** — guard with `iomap !== nothing && ...` when building the children vector. For `JuliaRange.step`, `JuliaReturn.value`, and `JuliaTry.{catch_var, catch_branch, finally_branch}`, emit only the present branches into the children `CellVector`.

### Coloring (extend existing palette)

- Strings, chars: `color_solarized_green` (treat like integer literals — both are values) — or pick a distinct color if preferred, but reuse the existing `color_solarized_*` palette imported at the top of `JuliaToSyntax.jl`.
- `true`, `false`, `nothing`, symbols: `color_solarized_magenta` (keyword-like).
- New keywords (`for`, `while`, `return`, `break`, `continue`, `try`, `catch`, `finally`, `begin`, `end`, `in`): `color_solarized_magenta` + `font_ubuntu_monospace_bold_24`, matching the existing `if`/`else`/`function`/`end` treatment.
- New operators (unary `-` `!` `~`, compound `+=` etc., `::`, `:`, `.`, `?` `:` for ternary): `color_solarized_cyan` matching existing binary-op color.
- Delimiters (`(`, `)`, `[`, `]`, `,`): `color_solarized_gray` matching existing `JuliaCallToSyntaxNode`.

### Wiring

Extend the dispatch table at the bottom of `JuliaToSyntax()` to add every new `JuliaDocument` subtype paired with its projection. Order of entries does not matter (dispatch is on `typeof(input)`).

## Files to modify

- [program/src/document/Julia.jl](../program/src/document/Julia.jl) — add types, constructors, `Base.show` methods, extend `_julia_operator_string`, extend the `export` list.
- [program/src/projection/primitive/JuliaToSyntax.jl](../program/src/projection/primitive/JuliaToSyntax.jl) — add projection structs and `projection_print` methods, extend imports from `JuliaModule`, extend `JuliaToSyntax()` dispatch table, extend the `export` list.

No changes outside these two files are needed: both modules are already loaded by [program/src/Projectured.jl](../program/src/Projectured.jl), and the existing `RecursiveProjection`/`TypeDispatchingProjection` wrapping at `JuliaToSyntax()` already handles arbitrary new dispatch entries.

## What is explicitly NOT in scope

- No `projection_read` methods — no reader, no cursor movement support for new types.
- No insert/delete operations.
- No tests, no example programs.
- No anonymous/short-form functions, structs, modules, imports, macros, comments, docstrings, string interpolation.

## Verification

Since no tests or example are added, verify by:

1. `julia --project=program -e 'using Projectured'` — confirms the module loads without errors.
2. In the REPL, construct an instance of each new type (e.g. `JuliaFor([JuliaForIterator(JuliaIdentifier("i"), JuliaRange(JuliaInteger(1), nothing, JuliaInteger(10)))], JuliaBlock([JuliaReturn(JuliaIdentifier("i"))]))`) and run it through `projection_print(JuliaToSyntax(), instance, JuliaToSyntax(), EmptyReferencePath())` — confirms the dispatch table reaches each new projection and produces a `SyntaxNode`/`SyntaxLeaf` output.
3. Chain through the existing `SyntaxToText`/`TextToGraphics` pipeline (per [guide/debugging.md](../guide/debugging.md)'s `print_example`) to confirm the printed output is well-formed text — no need for visual inspection, just no exceptions.
