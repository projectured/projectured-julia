# Unify the parameter names of the four projection APIs

> **Status (2026-08-12): NOT STARTED.** Re-verified directly: `p::` still
> outnumbers `prj::` 218 to 0 in actual function signatures, `recursion` still
> outnumbers `rec` 85 to 2. The codebase has moved twice since this plan was
> written — first `program/src/...` → `package/kernel/src/...` /
> `package/domain/src/projection/...`, then (2026-08-09) every domain got its
> own package, so the ~42 files this plan targets are now scattered under
> `package/<domain>/main/*.jl` and `package/projection/main/{higherorder,generic,compound}/`,
> not one `package/domain/src/projection/` tree. **Also note:** two of the four
> function names themselves changed in an unrelated refactor —
> `projection_print` is now `print_document` and `projection_read` is now
> `read_intent` (which gained a 4-arg `Intent`/`Change`-based overload
> alongside the legacy 3-arg `(p, iomap, op)` form). This plan's parameter-name
> scope still applies to the renamed functions; update every `projection_print`
> / `projection_read` mention below accordingly. One interesting partial
> convergence: the newer `@projection_template` macro's own lambda convention
> already spells its projection argument `prj` (e.g. `(prj, doc) -> …` in
> `package/book/main/BookToSyntax.jl`, `package/markdown/main/MarkdownToSyntax.jl`,
> and elsewhere) — but that is the template macro's own local lambda-argument
> choice, not a rename of the `print_document`/`read_intent`/`map_reference_*`
> **method signatures** this plan targets, which remain `p`/`recursion`/`reference`
> throughout.

## Context

The four generic projection functions — `projection_print` (now
`print_document`), `projection_read` (now `read_intent`), `map_reference_forward`,
`map_reference_backward` (all in
[`package/kernel/main/projection/ProjectionApi.jl`](../../package/kernel/main/projection/ProjectionApi.jl)) —
are implemented across dozens of files, now scattered under
[`package/<domain>/main/`](../../package) for each domain package plus
[`package/projection/main/{higherorder,generic,compound}/`](../../package/projection/main)
(was one tree, `program/src/projection/`, before the per-domain package
split). Their parameter names have drifted, so the same slot reads differently
from one file to the next. A survey of every signature (figures below are from
the original 2026-06-23 audit against the pre-split tree; re-run the grep
counts before starting, since the file set has since scattered):

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
codebase already uses the chosen terse scheme (paths re-verified 2026-08-12):
[`package/conversation/main/ConversationToWidget.jl`](../../package/conversation/main/ConversationToWidget.jl)
(`rec, ref = recursion, ctx.reference`, still present at lines 121, 138, 156)
and
[`package/conversation/main/ConversationToSyntax.jl`](../../package/conversation/main/ConversationToSyntax.jl)
name the reference param `ref` locally. This work converges the remaining
files onto that existing style.

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
print_document(prj, rec, input, ctx)         # -> iomap  (was projection_print)
read_intent(prj, rec, change::Intent, iomap) # new 4-arg (was projection_read)
read_intent(prj, iomap, op)                  # legacy 3-arg (op or evt)
map_reference_forward(prj, iomap, ref)
map_reference_backward(prj, iomap, ref)
```

*(Function names updated 2026-08-12: `projection_print` is now `print_document`
and `projection_read` is now `read_intent`, with `change::Change` now
`change::Intent` — an unrelated rename that landed since this plan was
written. The parameter-name scheme itself is unaffected.)*

## The one fact that makes this safe

**Renaming a parameter is purely local to each method.** Positional call sites
(`print_document(recursion, recursion, x, …)`, `map_reference_forward(child.projection, child, rest)`)
are unaffected by what a *callee* names its parameters. There is **no
cross-file coupling**: each method's signature and its own body change
together, and nothing else. `prj` has 0 pre-existing standalone uses as an
actual parameter name, so it introduces no collisions.

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
   `proj(^(p), inner)`, `ProjectionReferenceStep(p, …)`, `read_intent(p, iomap, …)`
   (was `projection_read`) all reference the projection variable and must
   become `prj`. Word-boundary `p`; check for an unrelated local named `p`
   (rare) before replacing.

`recursion` → `rec` is safe (`RecursiveProjection` is CamelCase, not the word
`recursion`); just confirm no shadowing local `rec`.

## File buckets

*Paths below are corrected to the current per-domain package layout
(2026-08-12); the original "42 files under `program/src/projection/`" count
and the bucket-A "~29 files" estimate need a fresh inventory, since the tree
that grouped them by directory no longer exists as one tree.*

**A. Mapper-only / generic — low risk.** Only `prj` (or unnamed
`::Type`), `rec`, `ref`; `iomap`/`ctx` unchanged. Most higher-order projections
([`package/projection/main/higherorder/`](../../package/projection/main/higherorder)),
[`package/projection/main/generic/`](../../package/projection/main/generic),
`compound/` (find its current location before starting — not confirmed here),
and the widget/graphics/layout readers (e.g.
`package/widget/main/WidgetToGraphics.jl`, `package/layout/main/LayoutToGraphics.jl`).

**B. Domain printers with a single-letter input — higher risk (13 files, current paths):**
[`package/json/main/JsonToSyntax.jl`](../../package/json/main/JsonToSyntax.jl),
[`package/xml/main/XmlToSyntax.jl`](../../package/xml/main/XmlToSyntax.jl),
[`package/math/main/MathToSyntax.jl`](../../package/math/main/MathToSyntax.jl),
[`package/book/main/BookToSyntax.jl`](../../package/book/main/BookToSyntax.jl),
[`package/julia/main/JuliaToSyntax.jl`](../../package/julia/main/JuliaToSyntax.jl),
[`package/syntax/main/ObjectToSyntax.jl`](../../package/syntax/main/ObjectToSyntax.jl),
[`package/syntax/main/CollectionToSyntax.jl`](../../package/syntax/main/CollectionToSyntax.jl),
[`package/filesystem/main/FileSystemToSyntax.jl`](../../package/filesystem/main/FileSystemToSyntax.jl),
[`package/syntax/main/PrimitiveToSyntax.jl`](../../package/syntax/main/PrimitiveToSyntax.jl),
[`package/text/main/PrimitiveToText.jl`](../../package/text/main/PrimitiveToText.jl),
[`package/syntax/main/SyntaxToText.jl`](../../package/syntax/main/SyntaxToText.jl),
[`package/text/main/TextToString.jl`](../../package/text/main/TextToString.jl),
[`package/widget/main/WidgetToGraphics.jl`](../../package/widget/main/WidgetToGraphics.jl).
Note `JsonToSyntax.jl` has since been rewritten onto `@projection_template` in
large part — check per-function whether a hand-written `print_document`
signature still needs the rename or the template macro already governs it.

**C. The interface + defaults (do first — defines the names).**
[`ProjectionApi.jl`](../../package/kernel/main/projection/ProjectionApi.jl) and
[`Projection.jl`](../../package/kernel/main/projection/Projection.jl): rename the
default-method params **and** update the signature lines in the docstrings so
the documented API matches. *(⏳ OPEN — both still use old param names in
signatures and docstrings; the function names in this file, `projection_print`
→ `print_document` and `projection_read` → `read_intent`, must also be
updated when this plan is picked up.)*

## Phasing

1. **⏳ OPEN (re-verified 2026-08-12):** **Bucket C** — `ProjectionApi.jl` + `Projection.jl` (defaults +
   docstrings). Establishes the canonical names. *At
   `package/kernel/main/projection/ProjectionApi.jl` (docstrings still use
   `projection, recursion, input, context` / `..., reference`) and
   `package/kernel/main/projection/Projection.jl` (`print_document(projection, input)`,
   `map_reference_forward(projection::Projection, iomap, reference)`,
   `read_intent(p::Projection, recursion, change::Intent, iomap)` — old names,
   under the renamed functions).*
2. **⏳ OPEN (re-verified 2026-08-12):** **Bucket A** — mechanical `prj`/`rec`/`ref` across the low-risk files. Group
   by directory; one commit per directory is fine since the edits are uniform.
   *`prj::`/`prj)` appears 0× in any actual method signature (only as a
   `@projection_template` lambda-argument name, a different thing — see status
   banner); `recursion`/`reference` still dominate (85 vs 2, 256 vs 0 in a
   fresh spot count). Files now scattered under
   `package/<domain>/main/` and `package/projection/main/{higherorder,generic,compound,...}`.*
3. **⏳ OPEN (re-verified 2026-08-12):** **Bucket B** — the 13 domain printers, **one file per commit**, running the
   narrowest covering test after each (see Verification). This is where the
   `input` and `@reference`/`ref` hazards live. *All 13 (current paths above)
   still have single-letter inputs where hand-written.*
4. **⏳ OPEN (re-verified 2026-08-12):** **Reader payload tidy** — normalize `operation`→`op` and
   `event`→`evt` legacy readers (folds into the files they live in). *Still
   inconsistent: a fresh spot count over `read_intent(...)` signatures finds
   both `op`/`evt` and stray `operation`/`event` payload names (e.g.
   `package/layout/main/LayoutToGraphics.jl`,
   `package/widget/main/WidgetToGraphics.jl`,
   `package/text/main/TextToGraphics.jl`).*
5. **⏳ OPEN (verified, optional):** **(Optional, separate)** guide-prose pass — the signature snippets in
   [`package/kernel/doc/projection-system.md`](../../package/kernel/doc/projection-system.md)
   (already updated to say `print_document`, still shows old parameter names
   at line 10) and
   [`package/kernel/doc/reference.md`](../../package/kernel/doc/reference.md) and siblings
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
  `function print_document(p::` / `function print_document(…, recursion,` /
  single-letter inputs / `, reference)` in mapper signatures.
