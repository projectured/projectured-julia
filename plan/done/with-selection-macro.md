# `@with_selection` — construct-and-select in one expression

## Problem

Every insertion factory repeats the same shape:

```julia
make_insertion_document(::Type{<:JsonString}) =
    let d = JsonString(""); with_selection(d, @reference(d, value{0})) end
```

The `let d = …` exists for exactly one reason: `@reference(d, path)` expands to
`annotate_reference_types(d, <plain path>)`, so the document is needed **at
runtime** to type the path — it must be bound twice, once to select into and once
to type against. The one-arg `@reference(path)` cannot stand in: it runs
`_strict_check` and demands every type hand-spelled
(`::JsonString.value::String{0}::Position`).

The whole-node factories are the *same* pattern with an empty path, because
`annotate_reference_types(doc, EmptyReferencePath())` returns
`EmptyReferencePath(typeof(doc))`:

```julia
make_insertion_document(::Type{<:JsonBool}) =
    with_selection(JsonBool(false), EmptyReferencePath(JsonBool))
```

14 sites: JSON 6, XML 2, YAML 6.

## Design

A `@with_selection` macro that evaluates the document once and selects into it,
with an optional path:

```julia
@with_selection JsonBool(false)                 # select the whole node
@with_selection JsonString("") value{0}         # caret at the path
```

```julia
macro with_selection(document, path...)
    length(path) <= 1 ||
        throw(ArgumentError("@with_selection takes a document and at most one path"))
    d = gensym("document")
    selection = isempty(path) ?
        :($annotate_reference_types($d, $EmptyReferencePath())) :
        Expr(:macrocall, Expr(:., ReferenceModule, QuoteNode(Symbol("@reference"))),
             __source__, d, path[1])
    esc(:(let $d = $document
              $with_selection($d, $selection)
          end))
end
```

### Home

`SelectionModule` (kernel layer 4): it owns `with_selection` and already sits
above `ReferenceModule` (layer 3), which owns `@reference`. The macro goes in
`selection/Selection.jl` next to `with_selection`; the export goes in
`selection/SelectionModule.jl`. Both files are unsealed (⬜).

`ReferenceBuilder.jl` — where an unchecked plain-path builder would otherwise be
the cleaner fix — is 🔒 and is **not** touched.

### The one wrinkle

To emit a *qualified* `@reference` call (so callers need not import it),
the macro needs the `ReferenceModule` **module name** bound, and
`import ..ReferenceModule: syms` binds only the symbols. `SelectionModule.jl`
therefore gains one plain `import ..ReferenceModule` alongside its symbol import.
The layering guard reads that as the edge it already records, so nothing changes
structurally.

### Hygiene (validated in a scratch module tower before implementing)

- a caller-local variable inside the path (`elements[n + 1]`) resolves correctly;
- a caller-local `d` is not captured (the binding is a `gensym`);
- the calling module needs **only** `@with_selection` in scope — not `@reference`,
  not `with_selection`.

## Rejected alternatives

- **Closure form** — `with_selection(JsonString("")) do d; @reference(d, value{0}) end`
  needs no new macro but is *more* lines than the `let`.
- **Declarative per-domain table** (`@insertion_documents Json begin … end`) hides
  more than it saves and would have to re-invent the path DSL.

## Steps

- [x] 1. **Done.** Add `@with_selection` to `selection/Selection.jl` with a docstring; export
  `var"@with_selection"` and add the plain `import ..ReferenceModule` in
  `selection/SelectionModule.jl`.
- [x] 2. **Done.** Convert Json.jl's 6 factories (plus the three gesture sites, incl. the
  last hand-spelled `::JsonNumber.value::Int{1}::Position` path, now `value{1}`). Verify: `test_json()`, `test_example(json_example)`.
- [x] 3. **Done.** Convert Xml.jl (2) and Yaml.jl (6, plus `_replace_number`'s
  hand-spelled path and two gesture sites). Verify: `test_example(xml_example)`,
  `test_example(yaml_example)`.
- [x] 4. **Done.** Documented in `package/kernel/doc/document.md` ("The selection
  generics"), which is where the construct-and-select idiom is described —
  there is no `selection.md` section covering it.

## Baselines (pre-existing, not regressions) — all re-measured on clean main

| suite | baseline | after |
|---|---|---|
| `test_example(json_example)` | 5028 pass / 23 fail | 5028 / 23 |
| `test_example(xml_example)` | 12482 pass / 52 fail | 12482 / 52 |
| `test_example(yaml_example)` | 4520 pass / 79 fail | 4520 / 79 |
| `test_json_to_syntax_reader()` | 48 / 0 | 48 / 0 |
| `test_kernel_layering()` | 7 / 0 | 7 / 0 |
| `test_json()` | 24 / 0 | 24 / 0 |

The failures above are the pre-existing wholesale typein "no cursor" failures.
The `NothingToSyntaxLeaf` conflicting-import warning at precompile is also
pre-existing.
