# `@document` generated constructors (Option A): trailing-default + single-CellVector

Two complementary `@document` features that together let the JSON domain drop almost all
its hand-written constructors:

- **Rule Y** — positional constructors that omit a *trailing run* of defaulted fields
  (the positional analog of `@kwdef`). Eliminates the primitive ctors.
- **Rule C** — for a struct backed by exactly one `CellVector` field, a constructor that
  takes the elements as a plain `Vector` and wraps them per-element. Eliminates the
  `JsonArray` vector ctor (and is reusable across the other collection documents).

> Context: `jsonvalue` has been removed from Json.jl (commit `3686577`); object/array
> values are now required to already be `Document`, so value-coercion is no longer a
> reason any of these ctors must stay hand-written.

## Problem

The JSON primitives hand-write redundant convenience constructors that `@document`
ought to generate:

```julia
# package/domain/src/document/Json.jl:100,101,125,126,150,151
JsonBool(v::Bool)         = JsonBool(Cell(v),  Cell(nothing))
JsonBool(f::Function)     = JsonBool(Cell(f),  Cell(nothing))
JsonNumber(v::Real)       = JsonNumber(Cell(v), Cell(nothing))
JsonNumber(f::Function)   = JsonNumber(Cell(f), Cell(nothing))
JsonString(v::AbstractString) = JsonString(Cell(v), Cell(nothing))
JsonString(f::Function)       = JsonString(Cell(f), Cell(nothing))
```

These six lines only add **a 1-argument positional form that defaults `selection` to
`nothing`**. They are even redundant *with each other*: the macro's auto-wrapping inner
constructor (`a isa Cell ? a : Cell(a)`, [Document.jl:123-133](../../package/kernel/src/common/Document.jl#L123-L133))
already routes a plain value through `Cell(v)` (value cell) and a `Function` through
`Cell(f)` (computed cell — see [Reactive.jl:128](../../package/kernel/src/common/Reactive.jl#L128)).
So each pair collapses to a single untyped `JsonString(value) = JsonString(value, nothing)`.

Why the macro doesn't already do this: it generates **keyword** constructors only when a
field has a default ([Document.jl:176-189](../../package/kernel/src/common/Document.jl#L176-L189)),
and the JSON primitives declare *no* defaults. Even with a default, a keyword ctor gives
`JsonString(value="hi")`, not the ergonomic `JsonString("hi")` — the macro has no notion
of a **positional** default (the positional analog of `@kwdef`).

## Design — "Rule Y": positional prefix ctors for the trailing-default run, only when ≥1 leading field is required

Extend `@document` so that, in addition to the existing all-fields inner ctor and the
keyword ctors, it emits positional constructors that omit a **trailing run** of
defaulted fields.

Definitions (declaration order, `n` = field count):
- **trailing run** = the maximal suffix of fields that all carry defaults.
- **`req`** = `n − len(trailing run)` = index of the last field *without* a default.
- Generate, for each arity `k` in `req : (n−1)`:
  - `Foo(f₁..f_k)  = Foo(f₁..f_k, default_{k+1}..default_n)`
  - `IFoo(f₁..f_k) = IFoo(f₁..f_k, default_{k+1}..default_n)`
  - bodies forward to the existing n-arg ctor (auto-wrapping inner for `Foo`,
    Julia's default for `IFoo`); defaults are the *raw* declared exprs (the inner ctor
    wraps them in `Cell` for `Foo`, exactly as the keyword ctor already does).

**The `req ≥ 1` guard is the whole safety story.** It means:
- We never emit a 0-positional-arg ctor, so we never collide with the keyword ctor's
  `Foo()` form (which already covers fully-defaulted structs).
- **Fully-defaulted structs (`req = 0`) gain nothing** — JsonArray, JsonObject, every
  `*Insertion`, and all the collection-like documents (Layout/Widget/Book/Sql lists, etc.)
  keep their hand-written variadic/typed ctors untouched. This avoids all
  ambiguity between an untyped generated ctor and a hand-written `Foo(::X...)` /
  `Foo(::SomeType)`.
- Interior defaults followed by a required field (e.g. `TooltipSource`'s
  `style=:tooltip, id`) are *not* droppable positionally — only the trailing `selection`
  is — which matches Julia's positional-default rules.

Emit for **both `Foo` and `IFoo`**, mirroring the existing keyword-ctor treatment
(decision: consistency over a marginally smaller method table; no conflicts either way —
see consequences).

### Macro implementation sketch (in the `if !isempty(defaults)` block, [Document.jl:177](../../package/kernel/src/common/Document.jl#L177))

```julia
default_map = Dict(defaults)
field_names = [fname for (fname, _) in original_fields]
n = length(original_fields)
# keyword ctors (existing) …

# positional prefix ctors (new): drop the trailing run of defaulted fields
trailing = 0
for (fname, _) in Iterators.reverse(original_fields)
    haskey(default_map, fname) || break
    trailing += 1
end
req = n - trailing
if req ≥ 1
    for k in req:(n-1)
        kept   = field_names[1:k]
        filled = Any[default_map[field_names[j]] for j in (k+1):n]
        push!(extra, :($(struct_name)($(kept...)) =
            $(Expr(:call, struct_name, kept..., filled...))))
        push!(extra, :($(i_name)($(kept...)) =
            $(Expr(:call, i_name, kept..., filled...))))
    end
end
```

## Design — "Rule C": single-`CellVector` element constructor

A `CellVector`-backed document (`JsonArray`, `TextText`, …) hand-writes a ctor that takes
the elements as a plain `Vector` and wraps each one in a `Cell`:

```julia
JsonArray(items::Vector{<:JsonDocument}) =
    JsonArray(CellVector(Cell[Cell(x) for x in items]), Cell(false), Cell(nothing))
```

Rule Y can't generate this: these structs are `req = 0` (every field, including the
`CellVector`, has a default), so Rule Y deliberately skips them; and the per-element wrap
is not the macro's scalar `Cell(x)`. Rule C closes exactly that gap.

**Rule:** if a `@document` struct has **exactly one** field whose declared type is
`CellVector`, and **every other field has a default**, generate (for `Foo` only):

```julia
Foo(items::AbstractVector) = Foo(<cv-field ← CellVector(items)>, <other fields ← defaults>)
```

- The per-element wrap reuses the **already-existing** `CellVector(items::AbstractVector)`
  ([Collection.jl:43](../../package/kernel/src/document/Collection.jl#L43)) →
  `CellVector(Cell[Cell(x) for x in items])`. **No kernel/CollectionModule change needed.**
- The inner auto-wrap then stores it as `Cell(CellVector(...))`, matching the existing
  `Cell{CellVector}` field layout.

Two deliberate restrictions, both load-bearing for safety:

1. **`AbstractVector`, not `Vector`.** The common hand-written form is `Foo(::Vector{…})`,
   which is *more specific* than the generated `Foo(::AbstractVector)`. So the generated
   ctor never exactly-redefines an existing one — they coexist and the hand-written one
   keeps winning for typed vectors. ⇒ **Enabling Rule C is non-breaking**, and deleting the
   redundant hand-written ctors is an *incremental* cleanup, not a prerequisite.
2. **Vector form only — no untyped variadic.** A generated `Foo(items...)` would be
   *ambiguous* with the domain's typed-variadic ctors (`JsonObject(::Pair...)`,
   `TextText(::TextDocument...)`) at calls like `JsonObject(p1, p2)`. The single-arg
   `AbstractVector` form has no such conflict (disjoint from `Function`, `Pair...`, and
   `CellVector`-typed ctors).

### Macro sketch (alongside Rule Y, also under `!isempty(defaults)`)

```julia
cv_fields = [fname for (fname, ftype) in original_fields if ftype === :CellVector]
others_defaulted = all(haskey(default_map, f) for (f, _) in original_fields
                       if f ∉ cv_fields)
if length(cv_fields) == 1 && others_defaulted
    cvf = cv_fields[1]
    args = Any[ f == cvf ? :(CellVector(items)) : default_map[f] for f in field_names ]
    push!(extra, :($(struct_name)(items::AbstractVector) =
        $(Expr(:call, struct_name, args...))))
end
```

(Note: the macro records each field's *original* declared type in `original_fields`, so a
`::CellVector` annotation is detectable; a field written `elements = CellVector()` with no
type annotation would need the default-expr inspected, or simply require the explicit
`elements::CellVector = CellVector()` form. JSON already uses the typed form.)

## Json.jl change (the requested target)

### Primitives (Rule Y) — give the three a `selection` default and delete six lines:

```julia
@document struct JsonBool   <: JsonDocument; value::Bool;                 selection::Reference = nothing; end
@document struct JsonNumber <: JsonDocument; value::Union{Real,Nothing};  selection::Reference = nothing; end
@document struct JsonString <: JsonDocument; value::String;               selection::Reference = nothing; end
```

After this, each is `req = 1` → macro emits `JsonString(value) = JsonString(value, nothing)`,
which (via auto-wrap) covers `JsonString("hi")`, `JsonString(() -> …)`, and
`JsonString(Cell(…))` — replacing both old overloads. The macro also now emits a keyword
ctor (`JsonString(; value, selection=nothing)`), which is a harmless addition.

### `JsonObjectEntry` (Rule Y, now unblocked by jsonvalue removal)

```julia
@document struct JsonObjectEntry <: JsonDocument
    key::String
    value::Document
    collapsed::Bool = false
    selection::Reference = nothing
end
```

Becomes `req = 2` → macro emits `JsonObjectEntry(key, value) = JsonObjectEntry(key, value, false, nothing)`,
replacing the hand-written ctor. **Caveat:** the hand-written one does `String(key)`; the
generated one stores `Cell(key)` verbatim. Every current caller already passes a `String`
(`JsonObject(pairs…)` does `JsonObjectEntry(String(k), v)`; gestures pass `""`), so this is
safe today — but it drops the defensive normalization (acceptable; consistent with the
permissive theme).

### `JsonArray` (Rule C) — delete the vector ctor

`JsonArray(items::Vector{<:JsonDocument})` is generated by Rule C (as
`JsonArray(items::AbstractVector)`). Delete it.

The **variadic** `JsonArray(items::JsonDocument...)` is *not* generated (Rule C is
vector-only, on purpose). It is used at **6 sites** (Focusing.jl:5, Clipboard.jl:9,
DraggingTest.jl:54/78/92/108, e.g. `JsonArray(JsonNumber(10), JsonNumber(20))`). Choose:
- **(a)** keep `JsonArray(items::JsonDocument...)` hand-written (1 line remains), or
- **(b, recommended)** convert those 6 call sites to vector literals
  (`JsonArray([JsonNumber(10), JsonNumber(20)])`) and delete the variadic → `JsonArray`
  fully macro-generated.

### `JsonObject` — `Function` form is also eliminable; only `Pair` sugar stays

- `JsonObject(pairs::Pair{<:AbstractString}...)` — the `"k" => v` sugar — has **~20+
  callers** (examples, `DbCatalogToJson`, `JsonParser`'s `JsonObject(pairs...)` splat, most
  tests). Genuinely domain syntax; **stays**.
- `JsonObject(f::Function)` (reactive `CellVector(f)` thunk) has **exactly one caller** — the
  `{` authoring gesture at [Json.jl:444](../../package/domain/src/document/Json.jl#L444):
  `JsonObject(() -> [JsonObjectEntry("", JsonInsertion())])`. The thunk closes over no
  reactive state, so it is computed once and is equivalent to the eager vector form that
  **Rule C already generates** (`JsonObject(::AbstractVector)`). Rewrite that one line to
  `JsonObject([JsonObjectEntry("", JsonInsertion())])` and **delete the `Function` ctor**.
  (Arguably *more* correct: were the cell ever to recompute, the thunk would rebuild a fresh
  entry and discard typed input; the eager form cannot.)

### Resulting Json.jl tally

11 hand-written ctor methods → **1** (best case): only `JsonObject(::Pair...)` remains.
(→ **2** if `JsonArray`'s variadic is kept under option (a).)

| | before | after |
|---|---|---|
| `JsonBool/Number/String` | 6 | 0 (Rule Y) |
| `JsonObjectEntry` | 1 | 0 (Rule Y) |
| `JsonArray` | 2 | 0 (Rule C + convert 6 call sites) / 1 (keep variadic) |
| `JsonObject` | 2 | 1 (Pair sugar; `Function` deleted via gesture rewrite) |

## Consequence analysis (the blast-radius check)

### Rule Y

Extracted field/default layout for **every** `@document struct` and computed `req`. The
result is that the macro change touches almost nothing today, because nearly every
document ends in `selection::Reference` **without** a default (`req = n` → "none"):

1. **Only one existing struct gains a generated ctor: `TooltipSource`**
   ([Tooltip.jl:41-47](../../package/domain/src/document/Tooltip.jl#L41)) —
   fields `child, content, style=:tooltip, id, selection=nothing`, `req = 4`. It gains
   `TooltipSource(child, content, style, id)` (arity 4). It has **no** other arity-4 ctor
   (only the keyword ctor + arity-1 snapshot/hydrate), so **no collision**. No current
   caller constructs it positionally → benign, purely additive.

2. **JSON primitives (in scope).** Gain the arity-1 ctor + a keyword ctor; the six
   redundant lines are deleted. All existing call sites
   (`JsonString("x")`, `JsonNumber(1)`, `JsonBool(true)`, `JsonNumber(() -> base[]*2)` in
   tests) keep working. **Behavior change to note:** the generated arity-1 ctor is
   *untyped*, so `JsonString(x)` for a non-string/non-function `x` now builds a value cell
   instead of raising `MethodError`. This matches how `JsonArray`/`JsonObject` already
   behave (permissive); accepted.

3. **Fully-defaulted structs (`req = 0`) are unaffected** by the `req ≥ 1` guard. This is
   the key safety property and covers every risky case found:
   - JSON: `JsonArray`, `JsonObject`, `JsonNull`, `JsonInsertion` — keep their
     hand-written variadic/`Vector`/`Pair` ctors; no ambiguity introduced.
   - All `*Insertion` types; `GraphGraph`, `GraphLayout`, `TabularGrid`/`TabularRow`,
     `TextText`, `SyntaxConcatenation`, `WorkbenchPage`/`Console`/…, `Workspace`,
     `SqlInsertStatement`/`SqlUpdateStatement`/`SqlWhereClause`/`SqlAllColumns`/join
     markers, `ConversationConversation`, `FormulaEnvironment`, `GestureMap`, etc.
   - The variadic ctors flagged as the ambiguity risk (`HorizontalLayout(;kwargs...)`,
     `WidgetMenu`, `BookBook`, `SqlSelectClause(items...)`, `TextText(spans...)`,
     `JsonObject(pairs...)`, …) all belong to `req = 0` structs → never met by a
     generated untyped ctor.

4. **Interior-default-then-required structs are safe.** `SqlComparison`
   (`left, operator=…, right, selection`) and the `Graphics*` arrow types end in a
   *required* field → `req = n` → "none", unchanged. `TooltipSource` is the lone
   `req` strictly between 1 and `n` (handled in #1).

5. **No test asserts the old behavior.** No test expects a `MethodError` from these
   ctors or a keyword-only form; grep of `package/test` confirms only positional 1-arg
   usage.

### Rule C

Enumerated every `@document struct` with a `CellVector` field. The **"exactly one
CellVector + all other fields defaulted"** gate yields **12 eligible structs**; everything
else is skipped:

- **≥2 `CellVector` fields → skipped** by the "exactly one" guard: `GraphGraph`,
  `GraphLayout`, `SqlInsertStatement`, `XmlElement`, `WidgetTable`, `WidgetSplitPane`.
- **A required non-CellVector field → skipped** by "all others defaulted": essentially all
  the `Sql*`/`Julia*`/`Widget*`/`Layout*`/`Book*` containers, `ScreenDocument`,
  `FileSystemDirectory`, `VersionedObject`, etc.

The **12 eligible**: `JsonArray`, `JsonObject`, `TextText`, `SyntaxConcatenation`,
`ConversationConversation`, `EvaluatorToplevel`, `FormulaEnvironment`, `WorkbenchPage`,
`Workspace`, `TabularGrid`, `TabularRow`, `SqlUpdateStatement`.

**Enabling Rule C is non-breaking for all 12** — the generated `Foo(::AbstractVector)` is
strictly less specific than every existing ctor on these types (which are `::Vector{…}`,
`::CellVector`, `::Function`, typed multi-arg, or typed-variadic), and no untyped variadic
is generated, so no call becomes ambiguous and nothing is redefined. Breakdown:

1. **Redundant hand-written `Foo(::Vector)` → deletable** (the cleanup payoff; the generated
   ctor subsumes it once deleted): `JsonArray`, `TextText` (its `Vector{<:TextDocument}`
   form), `SyntaxConcatenation`, `ConversationConversation`, `EvaluatorToplevel`,
   `FormulaEnvironment`, `WorkbenchPage`, `Workspace`. (Only `JsonArray` is in this plan's
   scope; the rest are follow-up.)
2. **Purely additive, no redundant ctor to remove** — Rule C just adds a vector form that
   coexists: `JsonObject` (keeps `Pair...`; its `Function` ctor is removed separately via
   the gesture rewrite above, not by Rule C), `TabularRow` (keeps the `::CellVector`
   form — disjoint, since `CellVector` is not `<:AbstractVector`),
   `TabularGrid` and `SqlUpdateStatement`. For the latter two the generated 1-arg form
   defaults a *meaningful* field (`col_count` / `table`), so it's **semantically odd but
   harmless** (no existing caller invokes it; it's an unused extra method). If undesirable,
   tighten the gate later to "all other fields default to an *empty/zero* value" — not
   needed for correctness.

## Follow-up cleanup (out of initial scope — same mechanical transform)

A whole family hand-writes the identical "drop `selection`" convenience ctor and would be
deletable by adding `selection::Reference = nothing` to the struct (turning them into
`req ≥ 1` and letting the macro emit the positional ctor). Captured here, **not bundled**
into the initial change to keep it focused:

- Clean 1:1 (single required value field): `MathVariable`, `MathParenthesized`,
  `FormulaReference`, `JuliaIdentifier`, `JuliaInteger`, `JuliaFloat`, `JuliaString`,
  `JuliaBool`, `JuliaSymbol`, `JuliaChar`, `JuliaReturn`, `JuliaBegin`, `XmlText`
  (two overloads → one), `PrimitiveBool/Number/String` (already keyword-only; could also
  gain the positional form).
- `MathAssignment(target, value)` → `req = 2`, arity-2 generated; clean.
- **Needs care (extra 0-arg ctor, not 1:1):** `TabularCell` (`TabularCell()` *and*
  `TabularCell(content)`) and `GraphVertex` (`GraphVertex()` *and*
  `GraphVertex(content::Document)`) supply a content default via a 0-arg ctor; the macro
  would only reproduce the 1-arg form, so the 0-arg convenience must stay (or also default
  `content`). `JuliaInsertion(value="")` carries a typed default on the value itself.

**Rule C follow-up** — delete the now-redundant hand-written `Foo(::Vector)` on the other
eligible structs (each replaced by the generated `Foo(::AbstractVector)`): `TextText`,
`SyntaxConcatenation`, `ConversationConversation`, `EvaluatorToplevel`,
`FormulaEnvironment`, `WorkbenchPage`, `Workspace`. Each touches one file; verify the
struct's other ctors (variadic/thunk) are unaffected before deleting.

## Steps

1. Worktree off `main` (per global CLAUDE.md: implementation work in a dedicated worktree).
2. Implement **Rule Y** and **Rule C** in `@document`
   ([Document.jl](../../package/kernel/src/common/Document.jl)). Commit.
3. Apply in [Json.jl](../../package/domain/src/document/Json.jl):
   - Primitives: add `selection = nothing`, delete the six lines (Rule Y).
   - `JsonObjectEntry`: add `collapsed = false` + `selection = nothing` defaults, delete
     its hand-written ctor (Rule Y).
   - `JsonArray`: delete the `Vector` ctor (Rule C); convert the 6 variadic call sites to
     vector literals and delete the variadic (decision (b)).
   - `JsonObject`: rewrite the `{` gesture (line 444) to the eager vector form and delete
     the `Function` ctor; keep the `Pair...` ctor.
   - Update the per-type docstrings (they still document the deleted ctors).
   Commit.
4. Convert the 6 `JsonArray(a, b, …)` variadic call sites (Focusing.jl:5, Clipboard.jl:9,
   DraggingTest.jl:54/78/92/108) to vector literals. Commit.
5. Verify: package precompiles; `test_json()` (covers primitive + array + object + entry
   construction); `test_printer/test_reader(json_example)` and `test_repl(json_example)`
   to exercise the rewritten `{` gesture and array authoring. Spot-check the Rule C
   non-breakage by precompiling the whole `domain` package (which defines all 12 eligible
   structs). A targeted `TooltipSource` test if one exists. Per repo CLAUDE.md, do **not**
   default to `test_all` — run narrow scopes first, sweep broadly only if something off.
6. Move this plan to `plan/done/` once implemented.

## Open decisions

- **Generate the full `req:(n-1)` range, or only arity `req`?** For every struct affected
  today (`TooltipSource`, the JSON primitives, `JsonObjectEntry`) the range is a single
  arity, so it doesn't matter yet. Plan specifies the full range (true positional-`@kwdef`
  semantics); easy to restrict to just `req` if a future multi-trailing-default struct
  surfaces a conflict.
- **Mirror to `IFoo`?** Rule Y: yes (consistency with keyword ctors). Rule C: `Foo` only
  (raw-vector construction of the immutable snapshot is never used; keeps the surface
  small). No conflicts found either way.
- **`JsonArray` variadic:** **decided (b)** — convert the 6 variadic call sites to vector
  literals and delete `JsonArray(::JsonDocument...)`, for full elimination (Json.jl → 1
  hand-written ctor: just `JsonObject(::Pair...)`).
