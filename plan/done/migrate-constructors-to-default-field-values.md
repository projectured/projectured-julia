# Migrate custom constructors to inline default field values

## Goal

Now that `@document` / `@projection` / `@iomap` accept `Base.@kwdef`-style inline
field defaults (see `plan/done/macro-default-field-values.md` and
`documentation/macros.md` → "Default field values"), replace the hand-written
convenience constructors **whose only job is to fill in defaults** with inline
field defaults, deleting the now-redundant constructor.

```julia
# before
@document struct JsonNull <: JsonDocument
    selection::Reference
end
JsonNull() = JsonNull(Cell(nothing))

# after
@document struct JsonNull <: JsonDocument
    selection::Reference = nothing
end
# JsonNull() now resolves to the macro-generated keyword constructor
```

This is the "use the new feature" follow-up the done plan deferred ("Do not
change any usages yet … there is nothing to migrate").

## The one hard constraint that decides what's migratable

The macro-generated keyword constructor is **keyword-only with zero positional
parameters**:

```julia
function Foo(; field1, field2 = default2, ...)   # generated when ≥1 default present
    Foo(field1, field2, ...)                      # forwards to positional inner ctor
end
```

(See the emitted form in `package/kernel/src/common/Document.jl:177-189` —
mirrored in `Projection.jl` and `IoMap.jl`.)

Consequences, which gate the entire migration:

- A call that passes **any positional argument** never reaches the keyword ctor.
  So `Foo(x)` still requires a positional constructor `Foo(x)` to exist — adding
  an inline default does **not** let you delete it.
- A call with **zero positional arguments** (`Foo()` or `Foo(; kw=…)`) *does*
  reach the keyword ctor, **provided every field has a default** (a field without
  one becomes a *required keyword*, so `Foo()` would throw `UndefKeywordError`).

Therefore a convenience constructor is removable **iff it has zero required
positional parameters** and its body is a pure forward of constant/keyword
defaults to the canonical constructor. In practice that means:

1. **Zero-arg** `T() = T(<all constant defaults>)` — the dominant case.
2. **Pure keyword-only** `T(; a, b = d, …) = T(a, b, …)` where each keyword maps
   1:1 to a field **with no type coercion or side effects**.

Everything that takes a required positional arg (`T(x) = T(x, nothing)`, and all
the `Widget*` / `Graphics*` / most `Sql*` / `Julia*` / `Layout*` builders) **stays
as is** — it cannot be expressed as an inline default without rewriting every call
site to all-keyword form, which is out of scope.

## Mechanical migration recipe

For each in-scope type:

1. For **every** field the convenience ctor fills with a constant, append that
   constant as an inline default on the field declaration, **dropping the
   `Cell(...)` wrapper** (the macro auto-wraps): `selection::Reference = nothing`,
   `expanded::Bool = false`, `nodes::CellVector = CellVector()`, etc.
2. **Preserve the existing type annotation verbatim**; only append `= <default>`.
   The default must be a legal value of the declared type — already guaranteed
   here because the value is exactly what the old ctor stored (`Reference =
   Union{Nothing, ReferencePath}`, so `selection = nothing` is honest; see the
   honesty gotcha in `documentation/macros.md`).
3. Delete the convenience constructor (Tier 1) or only the zero-arg overload
   (Tier 2 — keep the positional siblings).
4. The macro now emits a keyword ctor for both `T` and `IT`; `T()` and
   `T(; …)` resolve to it. Positional construction and snapshot/hydrate are
   unchanged.

## Inventory

Counts produced by scanning every `@document`/`@projection`/`@iomap` type for its
source-level outer constructors.

### Tier 1 — full elimination (29 types) ✅ recommended

The type's **only** custom constructor is a single zero-positional forwarder, so
it disappears entirely.

Zero-arg `T()` (27):

| File | Types |
|------|-------|
| `Json.jl` | `JsonInsertion`, `JsonNull` |
| `Xml.jl` | `XmlInsertion` |
| `Text.jl` | `TextInsertion` |
| `Math.jl` | `MathInsertion` |
| `Image.jl` | `ImageInsertion` |
| `Graphics.jl` | `GraphicsInsertion`, `GraphicsFence` |
| `Graph.jl` | `GraphInsertion` |
| `Widget.jl` | `WidgetInsertion` |
| `Book.jl` | `BookInsertion` |
| `Clipboard.jl` | `ClipboardInsertion` |
| `FileSystem.jl` | `FileSystemInsertion` |
| `Julia.jl` | `JuliaNothing`, `JuliaBreak`, `JuliaContinue` |
| `Sql.jl` | `SqlDistinct`, `SqlInnerJoin`, `SqlLeftOuterJoin`, `SqlRightOuterJoin`, `SqlFullOuterJoin`, `SqlCrossJoin` |
| `Workbench.jl` | `WorkbenchInsertion`, `WorkbenchOperator`, `WorkbenchSearcher` |
| `Primitive.jl` (kernel) | `PrimitiveInsertion` |
| `Syntax.jl` | `SyntaxInsertion` |

Pure keyword-only forwarders (2):

- `DocumentNothing` (`Document.jl`) — `DocumentNothing(; selection=nothing) = DocumentNothing(Cell(selection))`
  → `selection::Reference = nothing`.
- `TooltipSource` (`Tooltip.jl`) — `TooltipSource(; child, content, style=:tooltip, id)`
  → `style::Symbol = :tooltip`, `selection::Reference = nothing`; `child`/`content`/`id`
  stay annotation-only so they remain required keywords. No coercion in the body, so
  the generated keyword ctor is behaviourally identical.

### Tier 2 — drop only the zero-arg overload, keep positional siblings (28 types) — optional

These have a zero-arg `T()` **and** positional convenience ctors. We can give every
field an inline default and delete just the `T()` overload; the positional siblings
stay. Smaller payoff (the empty default is now declared inline *and* re-passed by the
siblings — mild duplication) and a larger blast radius for the core ones, so this tier
is a judgment call.

**Recommended subset** (single positional sibling, domain-local, low risk):
`ConversationConversation`, `EvaluatorToplevel`, `FormulaEnvironment`, `GraphGraph`,
`GraphVertex`, `GraphLayout`, `JuliaReturn`, `SqlAllColumns`, `SqlWhereClause`,
`SqlInsertStatement`, `SqlUpdateStatement`, `SyntaxConcatenation`, `TabularCell`,
`TabularRow`, `TabularGrid`, `TextText`, `WorkbenchConsole`, `WorkbenchEvaluator`,
`WorkbenchNavigator`, `WorkbenchPage`, `Workspace`, `JsonArray`, `JsonObject`.

**Explicitly skip** (core, heavily overloaded, and/or coercing siblings — the zero-arg
overload is not worth the destabilisation risk): `CellVector`, `CellMatrix`, `CellTable`
(`Collection.jl`, kernel — `CellVector()` alone is constructed in hundreds of places),
`ScreenDocument` (kernel), `GraphicsCanvas` (five `Int32`-coercing siblings).

### Projection config structs — `@projection` with inline defaults (related category)

Simple projections are plain `struct … <: Projection`, and several carry a
hand-written **keyword-only convenience constructor that only fills defaults** —
the exact smell this migration targets. Convert them to **`@projection`** with the
default inline and drop the constructor; the macro generates the keyword ctor (and
transparent Cell-backed field access) while the positional ctor still works:

```julia
# before
struct JsonNullToSyntaxLeaf <: Projection
    style::StyleText
end
JsonNullToSyntaxLeaf(; style = StyleText(…)) = JsonNullToSyntaxLeaf(style)

# after
@projection struct JsonNullToSyntaxLeaf <: Projection
    style::StyleText = StyleText(…)
end
```

Use the project's own `@projection` macro here (not `Base.@kwdef`) for consistency
with the rest of the codebase; it needs `import ..ProjectionModule: var"@projection"`
**and `import ..ReactiveModule: Cell`** (the macro expands to `Cell(...)`).

**Hard constraint — fields must not hold a function/callable.** `@projection`
auto-wraps every field with `Cell(...)`, and `Cell(f::Function)` builds a *computed
thunk*, not a stored function — so a config field that holds a callable (e.g.
`marker_eligible::Any = _default_marker_eligible`, a `predicate`, a `measure`) would
be **invoked** when read, silently breaking the projection (the documented gotcha in
macros.md). Only convert structs whose fields are plain value config
(`StyleText`/`StyleFont`/`StyleColor`/`Int`/`String`/`Bool`). This rules out
`SyntaxNodeToText` (its `marker_eligible` is a function) and the generic/behavioural
projections (`SortingProjection`, `FilteringProjection`, `WordWrapping`, …). Safe
whenever the type is also only constructed zero-arg/keyword (no positional call site
depends on the bare struct ctor).

- [x] **JsonToSyntax.jl**: 7 projection config structs (`JsonNullToSyntaxLeaf`,
  `JsonInsertionToSyntaxLeaf`, `JsonBoolToSyntaxLeaf`, `JsonNumberToSyntaxLeaf`,
  `JsonStringToSyntaxLeaf`, `JsonArrayToSyntaxNode`, `JsonObjectToSyntaxNode`)
  converted to `@projection` with inline `StyleText` defaults. `test_json_to_syntax`
  11/11.
- [x] **Phase B — the `*To*` style-config structs (98 across 13 files).** Converted
  every plain `struct … <: Projection` with a pure default-forwarding keyword ctor in
  JuliaToSyntax (31), SqlToSyntax (26), ObjectToSyntax (8), BookToSyntax (6),
  MathToSyntax (5), DbCatalogToSyntax (5), FormulaToSyntax (4), XmlToSyntax (3),
  PrimitiveToSyntax (3), DbCatalog/Primitive/FileSystem/Collection/ReferenceToText, …
  Added the `@projection`/`Cell` imports per file. **Skipped** (not pure value config):
  `SqlBooleanBinaryToSyntaxNode` (required positional arg), `SyntaxNodeToWidget`
  (`String()`/`Int()` coercion), `PrimitiveStringToTextText` (cross-keyword default).
  **Reverted `SyntaxNodeToText` (SyntaxToText.jl)** — converting it cascaded thousands
  of failures across *every* syntax-rendered example (its `marker_eligible::Any` is a
  function; see the hard constraint above). With it kept plain, the full
  `test_printers` (168245) and `test_readers` (18900) sweep is **0 failures** — matching
  the clean-tree baseline. Done in a dedicated worktree (`worktree-projection-config-defaults`)
  since main had since advanced + been pushed.

### Out of scope — and why

- **Leading-positional default ctors** `T(x) = T(x, nothing)` (`SyntaxNavigation`,
  `MathVariable`, `JuliaIdentifier`/`JuliaInteger`/`JuliaString`/…, `JsonBool`/`JsonNumber`/`JsonString`,
  `XmlText`, `FileSystemFile`, `SqlTableAlias`, …). Removing them breaks positional calls
  (keyword-only constraint).
- **Mixed positional + keyword builders** (`Widget*`, `Graphics*` element ctors, most
  `Sql*`, `Julia*`, `Layout*`, `Book*`). Same reason; they also carry required positional
  args.
- **Coercion / side-effect forwarders** — they do real work, not just defaults:
  `WindowDocument` and `DatabaseCredentials` (`String(...)`/`Int(...)` coercion that the
  untyped generated keyword ctor would drop, breaking `I…` snapshots), `WorkbenchAssistant`
  (coercion **and** a `draft.assistant = a` back-link), and the
  `value::AbstractString=""` insertions (`JuliaInsertion`, `FormulaInsertion`,
  `DocumentInsertion`).
- **Transform ctors** — not defaults at all: `TextString(content, style) = TextString(content, style.font, style.color)`,
  `JuliaAssignment(target, value) = JuliaAssignment(:(=), …)`, `JuliaRange(start, stop) = JuliaRange(start, nothing, stop)`,
  the `SyntaxLeaf` string/function overloads.

## Steps

- [x] **Step 0 — prove the mechanism on one type first.** Done on the Json domain
      (`JsonNull`, `JsonInsertion`) on `main`. Verified empirically: `JsonNull()`,
      `JsonNull(; selection=p)`, positional construction, and `IJsonNull(JsonNull())`
      snapshot all work; `JsonInsertion()` defaults `value === nothing`. The linchpin
      (zero-arg `T()` resolving to the generated keyword ctor when all fields default)
      is confirmed. `ProjecturedDomain` precompiles clean; `test_json()` 29/29 and
      `test_json_to_syntax()` 11/11 pass.
- [x] **Step 1 — Tier 1 (all 29 types).** Applied the recipe to the 27 zero-arg
      types + `DocumentNothing` + `TooltipSource` across 18 files. Every field
      defaulted to `nothing` (all are `value::Any`/`selection::Reference`, both of
      which admit `nothing`), except `TooltipSource` (`style::Symbol = :tooltip`;
      `child`/`content`/`id` stay required keywords). Verified: `ProjecturedDomain`
      precompiles clean; all 27 zero-arg/keyword types **construct via the generated
      keyword ctor and snapshot to their `I`-type** (27/27); `test_cell` 25/25,
      `test_collection` 32/32, `test_syntax` 10/10, `test_json_to_syntax` 11/11,
      `test_json` 29/29.
  - [x] **Json** (`Json.jl`): `JsonInsertion`, `JsonNull`.
  - [x] **Rest**: Xml, Text, Math, Image, Graphics (`GraphicsInsertion`,
        `GraphicsFence`), Graph, Widget, Book, Clipboard, FileSystem, Julia
        (`JuliaNothing`/`JuliaBreak`/`JuliaContinue`), Sql (`SqlDistinct` + 5 joins),
        Workbench (`WorkbenchInsertion`/`WorkbenchOperator`/`WorkbenchSearcher`),
        Syntax, Document (`DocumentNothing`), Tooltip (`TooltipSource`), and
        Primitive (kernel).
- [x] **Step 2 — Tier 2 recommended subset.** Dropped the zero-arg overload on 21
      domain-local types (kept positional siblings), adding inline defaults to every
      field: `ConversationConversation`, `EvaluatorToplevel`, `FormulaEnvironment`,
      `GraphGraph`, `GraphLayout`, `JuliaReturn`, `SqlAllColumns`, `SqlWhereClause`,
      `SqlInsertStatement`, `SqlUpdateStatement`, `SyntaxConcatenation`, `TabularRow`,
      `TabularGrid`, `TextText`, `WorkbenchConsole`, `WorkbenchEvaluator`,
      `WorkbenchNavigator`, `WorkbenchPage`, `Workspace`, `JsonArray`, `JsonObject`.
      **Excluded `GraphVertex` and `TabularCell`** (originally in the subset): both
      have a `content::Document` field whose zero-arg ctor stores `nothing`, but the
      abstract `Document` annotation does not admit `Nothing`, so inlining
      `content::Document = nothing` would encode a default that can't round-trip
      through the `I`-snapshot (the honesty gotcha in macros.md). Their hand-written
      zero-arg ctors are left as-is until the annotation is widened to
      `Union{Document,Nothing}` (separate concern). Verified: all 21 construct +
      snapshot (21/21); `test_cell`/`test_collection`/`test_json`/`test_syntax`/
      `test_text`/`test_graphics_layout`/`test_json_to_syntax` all green.
- [x] **Step 3 — grep for stragglers.** Re-ran the inventory scan: the only
      remaining zero-arg `T() = …` ctors on macro types are the **7 deliberately
      excluded** ones — `CellVector`/`CellMatrix`/`CellTable`/`ScreenDocument`
      (kernel), `GraphicsCanvas`, and `GraphVertex`/`TabularCell`. No accidental
      misses, and the green `test_printers`/`test_readers` sweep confirms no
      out-of-scope ctor was removed.
- [x] **Step 4 — docs.** Added to `documentation/macros.md`: a note that inline
      defaults are now the codebase idiom (insertion-cursor types + `@projection`
      style-config structs), **and** the new gotcha that a macro-wrapped field can't
      hold a `Function` (`Cell(::Function)` becomes a thunk — the trap that kept
      `SyntaxNodeToText` a plain struct).

## Verification

- Per the repo testing guidance: run the **smallest** covering test for each touched
  domain, never `test_all`. Map: Json→`test_json()`, Xml→`test_xml()`,
  Syntax→`test_syntax()`, Sql→`test_sql()`/`test_syntax`, Text→`test_text*`,
  Widget→relevant widget example, kernel→`test_cell()`.
- After each file: `using ProjecturedDomain` (and `ProjecturedKernel` for kernel
  edits) must precompile clean.
- Behavioural invariant to spot-check after a representative migration: `T()` and
  `IT(T())` both succeed, and any positional construction that existed before still
  type-checks.

## Risks / notes

- **Linchpin to confirm in Step 0:** `T()` (zero positional) resolving to the
  generated keyword ctor when *all* fields default. This is the whole basis of the
  migration; verify empirically before the bulk edits.
- Adding a default makes a type gain a keyword ctor (`T(; …)`) and an `IT(; …)`.
  This is purely additive — positional dispatch is unchanged — but grep for any
  reflection over a type's constructor set before assuming zero behavioural change.
- Tier 2 introduces mild duplication (default declared inline *and* re-passed by the
  surviving positional sibling). Acceptable; flagged so it isn't "fixed" by also
  deleting the sibling (which would break positional calls).
- Kernel collection primitives (`CellVector`/`CellMatrix`/`CellTable`/`ScreenDocument`)
  are deliberately excluded — huge call-site fan-out for a one-line saving.

## Process

- Work in a dedicated git worktree, not the main checkout.
- Commit per file/domain; mark steps done here as you go and record any deviation.
- Move this plan to `plan/done/` once Tier 1 (and any chosen Tier 2 subset) is
  complete and the per-domain tests are green.
