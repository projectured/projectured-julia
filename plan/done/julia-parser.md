# Julia source parser — string → JuliaDocument

## Context

The Julia domain ([program/src/document/Julia.jl](../../program/src/document/Julia.jl)) is fully
populated (literals, expressions, statements) and has a read-only printer
([program/src/projection/primitive/JuliaToSyntax.jl](../../program/src/projection/primitive/JuliaToSyntax.jl)).
There is currently **no way to get a `JuliaDocument` from source text** — the only
`JuliaDocument` in the tree is hand-built in
[example/src/document/Julia.jl](../../example/src/document/Julia.jl) (`make_julia_document_example`,
the factorial function).

The goal: a `juliaparse(text)` entry point that turns a Julia source string into a
`JuliaDocument` tree, reusing an existing Julia parser and building the document
**directly** in a single recursive pass (no intermediate AST of our own).

This mirrors the existing parsers — [program/src/parser/IniParser.jl](../../program/src/parser/IniParser.jl)
(`iniparse`) and [program/src/parser/NedParser.jl](../../program/src/parser/NedParser.jl)
(`nedparse`) — which each live in `program/src/parser/`, expose a `*parse(text)` /
`*parse_file(path)` pair, and emit a domain document tree directly. The difference: INI
and NED are hand-written; Julia we get for free.

## Parser choice — Julia's own parser via `Meta.parse`

Use **`Meta.parse`** (Base). Since Julia 1.10 this is backed by `JuliaSyntax.jl`, which
ships in the stdlib (the build here is 1.12.6, see `executable/build/`). It returns Julia's
native AST: nested `Expr` objects with literal leaves (`Int`, `Float64`, `String`, `Bool`,
`Char`, `Symbol`, `QuoteNode`, `nothing`). No extra dependency.

- Parse a whole source string with `Meta.parseall(text)` (wraps top level in
  `Expr(:toplevel, …)` / `Expr(:block, …)`), or `Meta.parse(text)` for a single expression.
  Use `Meta.parseall` and unwrap so multi-statement files work.
- "Built directly, not a separate step": there is no way to make Julia's parser emit our
  types, but we avoid any *intermediate of our own*. A single recursive
  `convert_expr(x)::JuliaDocument` walks the `Expr`/literal tree and constructs
  `JuliaDocument` nodes inline. The `Expr` tree is the parser's native output, not a stage
  we add.
- The high-level `JuliaDocument` constructors (e.g. `JuliaBinaryOp(op, left, right)`) already
  wrap fields in `Cell`s and seed `selection = Cell(nothing)`, so `convert_expr` just calls
  them — no manual `Cell` plumbing.

## New file — `program/src/parser/JuliaParser.jl`

```julia
module JuliaParserModule
import ..JuliaModule: JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool,
    JuliaNothing, JuliaSymbol, JuliaChar, JuliaBinaryOp, JuliaUnaryOp, JuliaCall,
    JuliaTernary, JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange,
    JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile,
    JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin, JuliaIf, JuliaFunction,
    JuliaBlock, JuliaDocument
export juliaparse, juliaparse_file
# juliaparse(text)        -> JuliaDocument
# juliaparse_file(path)   -> JuliaDocument
# convert_expr(x)         -> JuliaDocument   (the single recursive pass)
end
```

`juliaparse(text)` = `convert_expr(Meta.parseall(text))` with the `:toplevel` wrapper
flattened into a `JuliaBlock` (and a lone single expression returned bare).

## `Expr` → `JuliaDocument` mapping (the core of `convert_expr`)

Dispatch on `typeof(x)`, then on `x.head` for `Expr`. Strip `LineNumberNode`s from every
block/body before converting.

### Leaves
| Input | Output |
|---|---|
| `Int` | `JuliaInteger(x)` |
| `Float64` / `Real` | `JuliaFloat(x)` |
| `String` | `JuliaString(x)` |
| `Bool` | `JuliaBool(x)` |
| `Char` | `JuliaChar(x)` |
| `Symbol` `:nothing` | `JuliaNothing()` |
| `Symbol` (other, bare value) | `JuliaIdentifier(string(sym))` |
| `QuoteNode(sym)` | `JuliaSymbol(string(sym))` |

**Discovered during implementation:** `nothing` in source does **not** parse to the
value `nothing` — `Meta.parse("nothing")` returns the *symbol* `:nothing`. So
`JuliaNothing` is keyed off `x === :nothing`, checked before the generic `Symbol`
→ `JuliaIdentifier` arm. `Bool` is also checked before `Integer` (since `Bool <: Integer`).

### `Expr(:call, callee, args...)` — needs operator classification
Julia encodes `a + b` as `Expr(:call, :+, a, b)` and `-x` as `Expr(:call, :-, x)`. Decide in
this order:
1. callee is `:(:)` → `JuliaRange` (`a:b` 2-arg, `a:s:b` 3-arg with `step`).
2. callee ∈ **binary-operator set** and 2 args → `JuliaBinaryOp(op, l, r)`.
3. callee ∈ **unary-operator set** and 1 arg → `JuliaUnaryOp(op, operand)`.
4. otherwise → `JuliaCall(convert_expr(callee), [convert_expr.(args)...])`.

Define the operator sets in the parser module to match what
`_julia_operator_string`/the printer already render:
- binary: `:+ :- :* :/ :(==) :(!=) :(<) :(>) :(<=) :(>=)`
- unary:  `:- :! :~`

Operators that overlap (`:-`) are disambiguated by arity (step 2 vs 3). Operators outside
these sets fall through to `JuliaCall`, which is correct and lossless for display.
Short-circuit `&&`/`||` arrive as `Expr(:&&, …)`/`Expr(:||, …)` (not calls) — out of scope
for now, see Limitations.

### Other heads
| Head | Output |
|---|---|
| `:(=)` | `JuliaAssignment(:(=), target, value)` |
| `:+= :-= :*= :/=` | `JuliaAssignment(head, target, value)` |
| `:block` | `JuliaBlock([convert_expr.(non-LineNumberNode stmts)...])` |
| `:function` | `JuliaFunction(name, params, body)` — sig is `Expr(:call, name, params...)` |
| `:for` | `JuliaFor(iterators, body)` — see for-spec handling below |
| `:while` | `JuliaWhile(cond, body)` |
| `:if` / `:elseif` | `JuliaIf(cond, then, else?)` — `else` optional → `JuliaNothing()` or omit |
| `:return` | `JuliaReturn(value)` / `JuliaReturn()` for bare |
| `:break` | `JuliaBreak()` |
| `:continue` | `JuliaContinue()` |
| `:try` | `JuliaTry(body, catch_var, catch_branch, finally_branch)` (nullable fields) |
| `:ref` | `JuliaIndex(collection, indices)` |
| `:.` with `QuoteNode` field | `JuliaFieldAccess(object, field=JuliaIdentifier)` |
| `:tuple` | `JuliaTuple(elements)` |
| `:vect` | `JuliaArray(elements)` |
| `:(::)` | `JuliaTypeAnnotation(value, type)` |

**For-spec:** `Expr(:for, spec, body)`. A single iterator → `spec = Expr(:(=), var, iter)`.
Multiple (`for a in x, b in y`) → `spec = Expr(:block, Expr(:(=), …), Expr(:(=), …))`.
Convert each `:(=)` clause into a `JuliaForIterator(variable, iterable)`.

**Try-spec:** `Expr(:try, body, catch_var, catch_body[, finally_body])`. `catch_var` is
`false` when absent → map to `nothing`; same for missing catch/finally branches.

## Known ambiguities (Julia AST is lossy vs. our richer domain)

The domain distinguishes a few constructs the `Expr` AST collapses. Document these; pick the
common case:

- **`JuliaTernary` vs `JuliaIf`:** `a ? b : c` parses to the *same* `Expr(:if, …)` as a real
  `if`. Default `Expr(:if, …)` → `JuliaIf`. (A heuristic on `Meta.parseall`'s source ranges
  via `JuliaSyntax` could recover ternaries later; out of scope.)
- **`JuliaBegin` vs `JuliaBlock`:** `begin … end` parses to `Expr(:block, …)`. Default to
  `JuliaBlock`. `JuliaBegin` is unreachable from parsing for now.
- **Short-circuit `&&`/`||`, `where`, keyword args, splat, broadcast, string interpolation,
  structs/macros/modules:** out of scope (the domain has no node for them). `convert_expr`
  throws a clear `error("unsupported Julia construct: $(head)")` rather than silently
  dropping, so gaps are visible.

These mirror the domain's own scope decisions in
[plan/done/julia-basic-language-support.md](../done/julia-basic-language-support.md).

## Wiring

In [program/src/Projectured.jl](../../program/src/Projectured.jl):
- Add `include("parser/JuliaParser.jl")` next to the other parser includes (after line 62).
- Add `using .JuliaParserModule: juliaparse, juliaparse_file` next to the existing
  `using .IniParserModule …` / `using .NedParserModule …` (around lines 316/322).

## Validation

No new test harness needed — validate by **round-tripping against the existing read-only
printer**:
1. `juliaparse` the factorial source and structurally compare against
   `make_julia_document_example()` (same shape, allowing the if-vs-ternary default).
2. Parse → project through `JuliaToSyntax` → confirm it prints. Reuse the debugging helpers
   from [guide/debugging.md](../../guide/debugging.md) (`print_example`) on a parsed document.
3. Smoke-test each supported head with a one-liner (`juliaparse("a + b")`,
   `juliaparse("x[1]")`, `juliaparse("for i in 1:3\n  x\nend")`, etc.) and eyeball the tree.

Optional: add a `make_julia_parsed_example()` in [example/src/document/Julia.jl](../../example/src/document/Julia.jl)
that calls `juliaparse` on a source string, exercising the parser through the normal
example/printer pipeline.

## Out of scope

- A `projection_read` reader (editing text back into the document) — the printer is
  display-only; this plan only adds string→document parsing.
- Recovering ternary / `begin` / short-circuit / macros / structs / interpolation (domain has
  no nodes; would require extending [program/src/document/Julia.jl](../../program/src/document/Julia.jl) first).

## Files

- **New:** `program/src/parser/JuliaParser.jl`
- **Modify:** `program/src/Projectured.jl` (include + using)
- **Optional:** `example/src/document/Julia.jl` (parsed example)

## Steps

- [x] Create `program/src/parser/JuliaParser.jl` with module skeleton, imports, exports.
- [x] Implement leaf conversions in `convert_expr` (incl. `:nothing` special case + `Bool`-before-`Integer` ordering).
- [x] Implement `:call` classification (range / binary / unary / call) + operator sets.
- [x] Implement statement/expression heads via `_convert_head(::Val{head}, x)` dispatch.
- [x] Implement for-spec and try-spec destructuring.
- [x] Implement `juliaparse` / `juliaparse_file` (parseall + toplevel flatten).
- [x] Wire into `Projectured.jl` (include after NedParser + `using`).
- [x] Validate: per-head smoke tests (all 29 cases map correctly); factorial parsed and projected
      cleanly through `make_julia_projection_example()` (no errors, no depth/cap limits);
      multi-statement source flattens to `JuliaBlock`.
- [ ] ~~(Optional) Add `make_julia_parsed_example`~~ — **skipped.** The printer-walk validation
      already proved a parsed document projects identically to a hand-built one; registering a
      second Julia example would only duplicate the display and add test-sweep surface.

## Implementation notes

- Head dispatch is done with `_convert_head(::Val{head}, x::Expr)` methods (one per head) plus a
  catch-all that raises `error("unsupported Julia construct: …")`, rather than a long
  `if/elseif` chain — keeps each construct isolated and makes gaps loud.
- `CellVector` fields on `JuliaDocument` types are **not** wrapped in an outer `Cell` (the
  `CellVector` is itself the reactive container); the high-level constructors take plain
  `Vector`s, so the parser just builds `JuliaDocument[...]` and passes them in.
- Confirmed lossy AST collapses behave as planned: `a ? b : c` → `JuliaIf`,
  `begin … end` → `JuliaBlock`. `JuliaTernary`/`JuliaBegin` remain unreachable from parsing.
```
