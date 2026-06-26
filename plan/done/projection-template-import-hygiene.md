# `@projection_template` import-hygiene fix

> **Status: DONE** (2026-06-26, on `main`). Macro fixed via a module-qualified
> definition name; regression test added
> (`test_projection_template_hygiene`); existing template projections verified
> regression-free. See the implementation note under *The fix*.

Make `@projection_template` define its `projection_print` method on the **canonical
generic** regardless of what the calling module imported, removing a silent
foot-gun that produces a confusing `MethodError` at dispatch time.

## The bug

[`ProjectionTemplate.jl`](../../package/domain/src/projection/ProjectionTemplate.jl)
ends with:

```julia
macro projection_template(projname, intype, builder)
    quote
        function $(esc(:projection_print))(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            $(rule_print)(p, recursion, doc, ctx, $(esc(builder)))
        end
    end
end
```

`$(esc(:projection_print))` makes the method's **name** resolve in the *caller's*
module. If a projection module does **not** `import ..ProjectionApiModule: projection_print`,
the `function projection_print(...)` form defines a **brand-new local generic**
in that module instead of adding a method to
`ProjectionApiModule.projection_print`. Everything precompiles cleanly — but at
runtime the type-dispatcher calls the *canonical* `projection_print`, finds no
matching method, and throws:

```
MethodError: no method matching projection_print(::FooToSyntaxNode, ::RecursiveProjection, ::Foo, ::PrinterContext)
```

This was hit while implementing the OMNeT++ `.test` domain in `omnetpp-pred`: a new
`*ToSyntax` module imported `Projection` but not `projection_print`, and every
template projection silently failed to register. The error gives no hint that a
missing `import` is the cause, so it costs real debugging time.

Note `rule_print` in the same macro is already interpolated as a **function
object** (`$(rule_print)`), which is import-independent. Only the method *name*
uses `esc`, which is the defect.

## The fix ✅ (implemented)

Define the method with a **module-qualified name** (`ProjectionApiModule.projection_print`)
so it always extends the canonical generic the type-dispatcher calls, independent
of caller imports.

> **Implementation note — what did NOT work.** Two earlier attempts failed:
> - Interpolating the *function object* (`function $(projection_print)(...)`)
>   expands to `function ProjecturedKernel.ProjectionApiModule.projection_print(...)`
>   and Julia rejects it as an **`invalid function name`** (a function value is not
>   a legal definition target).
> - A *bare, unescaped* `function projection_print(...)` does **not** extend the
>   canonical generic from the caller's expansion site — it broke dispatch for
>   *every* existing template projection (MethodError). So `esc` "worked" only
>   because existing callers import the name.
>
> The working form is a **dotted module-qualified** definition name.

1. Bind the API module in `ProjectionTemplateModule` (it only imported *names*
   from it, not the module object). Add alongside the existing
   `import ..ProjectionApiModule: …`:

   ```julia
   import ..ProjectionApiModule
   ```

2. Emit a module-qualified definition name. The unescaped `ProjectionApiModule`
   hygiene-resolves to this macro's defining module (which now binds it):

   ```julia
   macro projection_template(projname, intype, builder)
       quote
           function ProjectionApiModule.projection_print(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
               $(rule_print)(p, recursion, doc, ctx, $(esc(builder)))
           end
       end
   end
   ```

   `$(esc(projname))` / `$(esc(intype))` stay escaped — those types *are* defined
   in the caller's module and must resolve there. Only the method name changes.

### Why this is safe / backward-compatible

- Every existing `*ToSyntax` module already imports `projection_print`, so today
  their template methods already land on the canonical generic. A module-qualified
  definition targets that **same** generic — no behavior change for existing
  callers (verified: JsonToSyntax 11/11, XmlToSyntax 7/7, SqlToSyntax 19/19,
  SyntaxToText all green).
- Modules that *omit* the import now also extend the canonical generic instead of
- Modules that *omit* the import now also extend the canonical generic instead of
  silently creating a dead local one.
- The `rule_print` precedent in the same macro proves interpolating a function
  object as the definition target works under the codebase's Julia version.

## Implementation steps

### Step 1 — Apply the macro fix

Edit `ProjectionTemplate.jl`: add the import and swap `$(esc(:projection_print))`
→ `$(projection_print)`.

### Step 2 — Regression test

Add a test that a projection defined in a module which does **not** import
`projection_print` still dispatches. Put it with the existing projection-template
tests (find via `grep -rl projection_template package/test`). Sketch:

```julia
module _NoImportProbe
    import ..Projectured: ...   # Projection, the markers, SyntaxLeaf, TextString, etc.
    # deliberately NOT importing projection_print
    @projection struct ProbeToLeaf <: Projection end
    @projection_template ProbeToLeaf ProbeDoc (p, doc) -> SyntaxLeaf(TextString("ok"))
end
@test projection_print(RecursiveProjection(...), ProbeDoc(...)).output isa SyntaxLeaf
```

The key assertion is that `projection_print` (the canonical one) resolves the
method — which fails on `main` and passes after Step 1.

### Step 3 — Verify no regression

Run the narrowest projection suites that exercise template projections
(e.g. `test_printer(json_example)`, `test_printer(syntax_example)`), then a
broader `test_printers()` if those pass. Do **not** default to `test_all`.

### Step 4 — Optional cleanup + docs

- The now-redundant `projection_print` import in the ~15 `*ToSyntax` modules can be
  left as-is (harmless) or removed in a follow-up; **not** required by this fix.
- Update [`documentation/macros.md`](../../documentation/macros.md): note that
  `@projection_template` defines its method on the canonical `projection_print`
  generic, so a projection module no longer needs to import `projection_print`
  itself (it still needs `Projection` and the markers).

## Out of scope

- The analogous question for `map_reference_forward` / `map_reference_backward` /
  `projection_read`: these are defined generically on `::Projection` *inside*
  `ProjectionTemplateModule` (not emitted per-projection by the macro), so they do
  not have this hazard. No change needed.
