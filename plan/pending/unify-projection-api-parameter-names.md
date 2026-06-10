# Unify the parameter names of the four projection APIs

## Context

The four generic projection functions —
[`projection_print`, `projection_read`, `map_reference_forward`,
`map_reference_backward`](../../program/src/api/Projection.jl) — are implemented
across **42 files** under [`program/src/projection/`](../../program/src/projection/).
Their parameter names have drifted, so the same slot reads differently from one
file to the next. A survey of every signature shows:

| Slot | Current spread | Verdict |
| --- | --- | --- |
| projection (always 1st) | `p` ×125, `projection` ×2, type-abbrevs `tdp/seq/rp/rdp/pdp/np/ap/proj` ×9 | **inconsistent** |
| recursion (print/read 2nd) | `recursion` ×~135, `_` ×few | consistent word, abbreviating |
| printer input (print 3rd) | `input` ×23 vs single letters `j/w/b/v/m/t/s/f/x/n/c/e…` ×40+ | **most inconsistent** |
| context (print 4th) | `ctx` ×117, 1 stray | already consistent |
| iomap | `iomap` ×100% | already consistent |
| reference (mappers 3rd) | `reference` ×100% | consistent word, abbreviating |
| reader payload (legacy 3-arg) | `op` ×42, `evt` ×30, `operation` ×2, `event` ×2 | **inconsistent** |
| reader change (new 4-arg) | `change::Change` | already consistent |

The goal is readability only — **zero behaviour change**. Note that part of the
codebase already uses the chosen terse scheme:
[`ConversationToWidget.jl`](../../program/src/projection/primitive/ConversationToWidget.jl)
(`rec, ref = recursion, ctx.reference`) and
[`ConversationToSyntax.jl`](../../program/src/projection/primitive/ConversationToSyntax.jl)
name the reference param `ref`. This work converges the remaining files onto
that existing style.

## Canonical scheme (decided)

| Slot | Name |
| --- | --- |
| projection (1st, everywhere) | **`prj`** |
| recursion | **`rec`** |
| printer input (print 3rd) | **`input`** |
| context | **`ctx`** (unchanged) |
| iomap | **`iomap`** (unchanged) |
| reference | **`ref`** |
| reader payload — operation (legacy 3-arg) | **`op`** |
| reader payload — event (legacy 3-arg) | **`evt`** |
| reader change (new 4-arg) | **`change`** (unchanged) |

So the four signatures become:

```julia
projection_print(prj, rec, input, ctx)            # -> iomap
projection_read(prj, rec, change::Change, iomap)  # new 4-arg
projection_read(prj, iomap, op)                   # legacy 3-arg (op or evt)
map_reference_forward(prj, iomap, ref)
map_reference_backward(prj, iomap, ref)
```

## The one fact that makes this safe

**Renaming a parameter is purely local to each method.** Positional call sites
(`projection_print(recursion, recursion, x, …)`, `map_reference_forward(child.projection, child, rest)`)
are unaffected by what a *callee* names its parameters. There is **no
cross-file coupling**: each method's signature and its own body change
together, and nothing else. `prj` has 0 pre-existing standalone uses, so it
introduces no collisions.

## Three correctness hazards (call these out per file)

1. **`reference` → `ref` must never touch the `@reference` / `@reference_case`
   macros** (265 + 116 call sites). A blind text replace would corrupt
   `@reference(...)` into `@ref(...)`. Rename only the *standalone variable*
   `reference` — never `@reference`, the CamelCase types
   (`ProjectionReference`, `ConcreteReferencePath`, `ElementReference`, …), or
   the functions `map_reference_*` / `append_reference`. Word-boundary
   lowercase `reference` not preceded by `@`. (Existing standalone `ref` locals
   live in helper functions and the already-terse Conversation files, not in
   mapper bodies that also bind `reference`, so no variable shadowing arises —
   but verify per file.)

2. **Single-letter `input` rename collides with loop/pattern bindings.** In the
   13 domain printers the input letter sits next to `for (i, e) in …`, range
   patterns `value{s:e}`, `for x in j`, etc. Do the `input` rename **per
   function**, scoped to the actual parameter and its body uses — never a
   global single-letter substitution.

3. **`p` → `prj` includes uses inside `@reference_case` heads** —
   `proj(^(p), inner)`, `ProjectionReference(p, …)`, `projection_read(p, iomap, …)`
   all reference the projection variable and must become `prj`. Word-boundary
   `p`; check for an unrelated local named `p` (rare) before replacing.

`recursion` → `rec` is safe (`RecursiveProjection` is CamelCase, not the word
`recursion`); just confirm no shadowing local `rec`.

## File buckets

**A. Mapper-only / generic — low risk (~29 files).** Only `prj` (or unnamed
`::Type`), `rec`, `ref`; `iomap`/`ctx` unchanged. Most higher-order projections
([`higherorder/`](../../program/src/projection/higherorder/)),
[`generic/`](../../program/src/projection/generic/),
[`compound/`](../../program/src/projection/compound/), and the
widget/graphics/layout readers.

**B. Domain printers with a single-letter input — higher risk (13 files).**
Also need the per-function `input` rename:
[`JsonToSyntax.jl`](../../program/src/projection/primitive/JsonToSyntax.jl),
[`XmlToSyntax.jl`](../../program/src/projection/primitive/XmlToSyntax.jl),
[`MathToSyntax.jl`](../../program/src/projection/primitive/MathToSyntax.jl),
[`BookToSyntax.jl`](../../program/src/projection/primitive/BookToSyntax.jl),
[`JuliaToSyntax.jl`](../../program/src/projection/primitive/JuliaToSyntax.jl),
[`ObjectToSyntax.jl`](../../program/src/projection/primitive/ObjectToSyntax.jl),
[`CollectionToSyntax.jl`](../../program/src/projection/primitive/CollectionToSyntax.jl),
[`FileSystemToSyntax.jl`](../../program/src/projection/primitive/FileSystemToSyntax.jl),
[`PrimitiveToSyntax.jl`](../../program/src/projection/primitive/PrimitiveToSyntax.jl),
[`PrimitiveToText.jl`](../../program/src/projection/primitive/PrimitiveToText.jl),
[`SyntaxToText.jl`](../../program/src/projection/primitive/SyntaxToText.jl),
[`TextToString.jl`](../../program/src/projection/primitive/TextToString.jl),
[`WidgetToGraphics.jl`](../../program/src/projection/primitive/WidgetToGraphics.jl).

**C. The interface + defaults (do first — defines the names).**
[`api/Projection.jl`](../../program/src/api/Projection.jl) and
[`common/Projection.jl`](../../program/src/common/Projection.jl): rename the
default-method params **and** update the signature lines in the docstrings so
the documented API matches.

## Phasing

1. **Bucket C** — `api/Projection.jl` + `common/Projection.jl` (defaults +
   docstrings). Establishes the canonical names.
2. **Bucket A** — mechanical `prj`/`rec`/`ref` across the low-risk files. Group
   by directory; one commit per directory is fine since the edits are uniform.
3. **Bucket B** — the 13 domain printers, **one file per commit**, running the
   narrowest covering test after each (see Verification). This is where the
   `input` and `@reference`/`ref` hazards live.
4. **Reader payload tidy** — normalize the 2 `operation`→`op` and 2
   `event`→`evt` legacy readers (folds into the files they live in).
5. **(Optional, separate)** guide-prose pass — the signature snippets in
   [`guide/projection-system.md`](../../guide/projection-system.md),
   [`guide/editor/reference.md`](../../guide/editor/reference.md) and siblings
   still show `projection/recursion/input/context/reference`. Larger prose
   churn; recommend as a follow-up rather than blocking the code change.

## Verification

Per [`CLAUDE.md`](../../CLAUDE.md), run the **narrowest** covering test after
each file — renames change no behaviour, so any breakage is an `UndefVarError`
from a missed/over-eager rename and surfaces immediately:

- Bucket B per file: e.g. `test_json_to_syntax()` after `JsonToSyntax.jl`,
  `test_syntax_to_text()` after `SyntaxToText.jl`, `test_example(json_example)`,
  etc.
- After Bucket A: the package must still precompile/load (`using ProjecturEd`),
  then a quick `test_printers()` / `test_readers()` / `test_selections()` sweep
  to confirm zero behaviour change.
- Final sweep: grep the four functions to confirm no old names remain — no
  `function projection_print(p::` / `function projection_print(…, recursion,` /
  single-letter inputs / `, reference)` in mapper signatures.
