# One grammar, two lowerings: share the reference DSL parser

`ReferenceBuilder.jl` (`@reference` / `@step`) and `ReferenceCase.jl` (`@reference_case`)
walk the **same surface grammar with two separate recursive-descent parsers**, feeding two
parallel step-AST hierarchies. Extract the grammar into one `ReferenceSyntax.jl` fragment
that both lower from.

This is the deferred item #2 from [reference-layer-file-split.md](../done/reference-layer-file-split.md).
It is kernel-only: nothing outside the reference layer touches these parsers.

## The duplication

| | `ReferenceBuilder.jl` | `ReferenceCase.jl` |
| --- | --- | --- |
| grammar entry | `_parse_build_path!` (74) | `_parse_path!` (149) |
| subpath | `_parse_build_subpath` (243) | `_parse_subpath` (264) |
| extension step | `_build_extension_step` (256) | `_pat_extension_step` (274) |
| `{…}` lowering | `_braces_step` (236) | `_braces_pat` (342) |
| `x::T` suffix | `_build_type_suffix!` (201) | `_pat_type_suffix!` (306) |
| leading `::T` | `_build_leading_type!` (222) | `_pat_leading_type!` (327) |
| `::T` + `.field` tail | `_push_type_and_fields!` (182) | `_push_pat_type_and_fields!` (287) |
| step AST | 7 `BuildStep*` structs | 9 `PatStep*` structs |

The two parsers have the same branch structure down to verbatim-identical comments
(`# base[idx] — ElementReference (1-based), or base[i, j] — RangeReference`). Seven AST
shapes are the same concept under two names; `BuildStepPathSplice` and `PatStepPathInterp`
are both the `^(expr)` node.

## Why it can be shared at all

The two ASTs differ only in their **leaf payload**: the builder stores raw Julia
expressions (escaped at codegen) and the matcher stores `PatValue`s (wildcard / bind /
typed-bind / literal / interp). But `_parse_value` is a **pure function of the raw
expression**, applied at parse time for no reason. So a shared parser can keep the **raw
expression** in every leaf slot, and the matcher can call `_parse_value` at *lowering*
time with identical results.

That is the whole trick: **parse the shape once, interpret the leaves per side.**

## The six real divergences (must be preserved exactly)

These are where the same syntax means different things. A naive merge silently changes what
each macro accepts — this table is the contract the implementation must honour.

| Syntax | `@reference` (build) | `@reference_case` (match) |
| --- | --- | --- |
| bare symbol as a **subpath argument** (`.proj(p, sub)`) | a **field** step (falls through to the path parser) | **whole-path bind** — binds the sub-path to the variable `sub` |
| `name...` | *unsupported* (error) | binds the entire remaining tail |
| `base.^(e)` (the `.^` broadcast splice) | path splice at the end of a chain | *unsupported* (error) |
| `::t` (lowercase) | a type step that splices `t`'s **runtime type value** | **binds** the matched node's folded `type` field |
| `_` | a field literally named `"_"` | wildcard (in value position) |
| leading identifier in `@step` (`xs[i]`) | a **placeholder** — dropped, yields only `[i]` | n/a (`@step` is build-only) |

Rule-level forms (`_`, `∅`, `∅::t`, `when`, `prefix`) are *not* part of the path grammar —
they are parsed by `_parse_rule` and stay in `ReferenceCase.jl`.

## Design

**`ReferenceSyntax.jl`** — one grammar, one AST, raw payloads:

```
abstract type RefStep end
RefField(name::String)        # a.b, or a bare symbol in path position — a literal name
RefFieldExpr(expr)            # .field(e) — the name is a runtime expression
RefIndex(expr)                # [i]
RefPosition(expr)             # {k}
RefRange(startexpr, stopexpr) # [i,j] / {s:e}
RefType(expr)                 # ::T  (the lowercase bind/assert split is a LOWERING choice)
RefSplice(expr)               # ^(e) and base.^(e)
RefTailBind(name::Symbol)     # name...
RefExtension(name, args)      # .name(a…); args are RefArgValue(raw) or RefArgSubPath(raw)
```

- `parse_reference_path(ex) -> Vector{RefStep}` — the grammar, shared verbatim.
- `parse_reference_step(ex) -> RefStep` — the `@step` single-step grammar (leading identifier
  is a placeholder). Build-only, but it lives here because it shares the step vocabulary.
- The `::T` helpers (`_type_suffix!`, `_leading_type!`, `_type_and_fields!`) — shared; they
  are already exact mirrors.
- Extension args: the parser consults `dsl_step_subpath_args(Val(name))` (the seam, already
  in `Interface.jl`) to tag each arg `RefArgSubPath` vs `RefArgValue`, and stores the **raw**
  expression either way. It never names a step type it does not own.

**Each lowerer keeps its own semantics** and rejects the nodes it cannot lower:

- `ReferenceBuilder.jl` lowers `RefStep -> Expr` (constructor calls). Rejects `RefTailBind`
  with a clear "`...` is only valid inside `@reference_case`". Applies the **build** subpath
  rule to `RefArgSubPath` (`^(e)` splices; anything else is a path).
- `ReferenceCase.jl` lowers `RefStep -> (match branch, bound names)`. Calls `_parse_value` on
  each raw payload. Splits `RefType` into assert-vs-bind on `_is_type_bind_symbol`. Applies
  the **match** subpath rule to `RefArgSubPath` (a bare symbol is a whole-path bind).

Two behaviour notes, both preserved-or-improved, neither a regression:

- A mid-path `^(e)` in a *pattern* is currently a `MethodError` at macro expansion (there is
  no `_gen_step_match(::PatStepPathInterp, …)`; only the sole-step case is handled). After
  the change it becomes an explicit error message. Still an error, better words.
- `base.^(e)` in a *pattern* currently errors in the parser ("unsupported call form"). After
  the change it parses and the matcher rejects it. Still an error, better words.

## Steps

- [x] **0. Baseline.** Recorded; matched the parent commit's own numbers exactly.
- [x] **1. `ReferenceSyntax.jl`** — the shared AST + grammar, included after `ReferenceSearch.jl`
      and before the two DSL fragments (it calls the `dsl_step_subpath_args` seam while parsing,
      so it must follow `Interface.jl`).
- [x] **2–3. Both DSL fragments rewritten as lowerings.** Landed as one commit (`b19909e0`) —
      see the deviation below. `ReferenceBuilder.jl` 470 → 187 lines, `ReferenceCase.jl` 741 → 579,
      plus the 371-line shared grammar.
- [x] **4. Docs + seal list.**

### Deviation: the matcher kept its `PatStep` vocabulary

The plan said to delete `PatStep*`. It was kept, and that turned out to be the right call —
it is what made the change low-risk. **Only the two parsers were replaced; both lowerers' codegen
is untouched.** The matcher converts the shared `RefStep` AST into its existing `PatStep`
vocabulary at lowering time (`_to_pat`), so all of `_gen_path_match` / `_gen_prefix_match` /
`_gen_step_match` — the genuinely intricate part of `@reference_case` — never moved. A rewrite of
that codegen would have been a much bigger risk for no benefit: `PatStep` is the matcher's private
lowering vocabulary, not a second grammar.

The steps also landed as one commit rather than two: the builder and matcher both stop compiling
the moment the shared parser replaces either one, so there is no loadable intermediate state to
commit.

## Verification

These macros are used across every package, so a parse regression is not a kernel-local
event. The full sweep is warranted here (unlike the file split, which was pure motion).
Baselines, from the parent commit's own message and the split's runs:

| Suite | Baseline |
| --- | --- |
| `test_kernel()` | 338 pass / 0 fail |
| `test_base()` | 82 pass / 0 fail |
| `test_visual()` | 51856 pass / 0 fail |
| `test_domain()` | 125962 pass / **93 fail / 1 error** (pre-existing: the `mixed` and `graph` examples, one table-navigation case) |

Counts must match exactly. The domain failures are pre-existing and must neither grow nor
shrink.

A grammar change is also exactly the kind that passes tests while quietly narrowing what the
macros accept, so beyond the suites: grep the repo for every `@reference` / `@step` /
`@reference_case` call site and confirm the corpus still parses (it is large — the macros are
the reference layer's whole surface, so a full precompile of the umbrella *is* that check).

## Outcome

All four suites came back **identical to the baseline** — kernel 338/338, base 82/82, visual
51856/0-fail/1-broken, domain 125962/93-fail/1-error/15-broken (the domain failures neither grew
nor shrank). The `Projectured` umbrella precompiles, which re-expands every `@reference` /
`@step` / `@reference_case` call site in the repo through the new grammar — the corpus check.

On top of the suites, 12 targeted checks over the six divergences all pass: the `@step`
placeholder, the `_` wildcard, value binding, `rest...` tail binding, `::t` binding vs `::T`
asserting, the `.^` splice, a bare symbol as a subpath argument reading as a *field* to the
builder and a *whole-path bind* to the matcher, and both lowerers rejecting by name what they
cannot lower.

**One assumption in this plan was wrong, and worth recording.** The plan claimed `base.^(e)` was
builder-only because the matcher's parser rejected it. It is subtler than that: Julia's field
access binds tighter than the `.^` broadcast, so `a.^(q).b` parses as `a .^ (q.b)` — a *trailing*
splice, which both DSLs handle. A genuine mid-path splice has to be written `^(q).b`. That form
used to die with a `MethodError` on a missing `_gen_step_match` method; it now reports that
interpolation must be the sole step of a pattern.

Landed:

| Commit | |
| --- | --- |
| `fc15bc76` | the plan |
| `b19909e0` | the shared grammar — `ReferenceSyntax.jl`, both DSLs become lowerings |
