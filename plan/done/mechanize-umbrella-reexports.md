# Mechanize the `Projectured` umbrella's re-exports

## Decision

Keep `Projectured` — but only as a **thin REPL convenience** (one import → the full flat
API across kernel/domain/…). Back-compat is **not** a goal. Replace the ~846 hand-written
re-export lines (`const XxxModule = …`, `using X: a, b, c`, `export …`) with an
**automatic** re-export so the umbrella stops drifting and needs no per-symbol edits.

## What the umbrella must still provide (so mechanization doesn't break callers)

Even as a convenience, internal tooling/tests already use it two ways — both must keep
working (verified by grep):

1. **Flat exported names** — `Projectured.projection_print`, `Projectured.GraphicsCanvas`,
   `Projectured.JsonDocument`, `Projectured.TextString`, `Projectured.QuitEvent`, …
2. **Submodule aliases** — `Projectured.JsonModule`, `Projectured.SyntaxToTextModule`,
   `Projectured.ConsoleBackendModule`, `Projectured.EditorModule`, `Projectured.McpModule`,
   `Projectured.LlmModule`, `Projectured.WorkbenchAssistantModule`,
   `Projectured.TextToGraphicsModule`, `Projectured.ReactiveModule`,
   `Projectured.DocumentModule`, `Projectured.ReferenceModule`, … (~20-30 call sites in
   `example/` and `test/`).

A naive `@reexport using …` would give (1) but **drop (2)** — the submodule aliases are
exactly the bulk of the 846 lines. So the mechanization must regenerate both.

## Implementation — loop, zero new deps (preferred)

Generate both flat re-exports and submodule aliases with a loop, keeping the umbrella's
**zero external deps** (it currently depends only on kernel+domain):

```julia
module Projectured
using ProjecturedKernel, ProjecturedDomain   # (+ ProjecturedGraphics, ProjecturedText once those exist)

const _SOURCES = (ProjecturedKernel, ProjecturedDomain)

# 1) re-export every exported name of each source
for m in _SOURCES, n in names(m)
    n === nameof(m) && continue
    @eval export $n
end

# 2) alias every submodule so `Projectured.XxxModule.foo` keeps resolving
for m in _SOURCES, n in names(m; all = true)
    v = getfield(m, n)
    v isa Module && v !== m && @eval const $n = $v
end
end
```

≈15 lines vs. 846, near-zero maintenance.

- **Alternative:** `Reexport.@reexport using ProjecturedKernel, ProjecturedDomain` for (1)
  plus the submodule-alias loop for (2). Cleaner-looking but adds a (tiny) `Reexport`
  dependency to a package that is currently dependency-free — prefer the loop.

## Caveats to handle during implementation

- **Non-exported symbols** the umbrella currently hand-imports (e.g.
  `skip_type_checkpoints`, accessed as `Projectured.skip_type_checkpoints` in
  `TypeReferenceTest`) won't be picked up by an exports-only loop. Either keep a short
  explicit `import …: …` block for those, or `export` them from the owning kernel module.
- **Name collisions** between sources (same exported name from two packages) — the loop
  would `export` the same name twice (harmless) but the binding resolves to whichever
  `using` won; spot-check if kernel and domain export clashing names.

## Interaction with the other plans

- After the [graphics/text extraction](extract-graphics-text-packages.md), add
  `ProjecturedGraphics`, `ProjecturedText` to `_SOURCES` (and the umbrella's `[deps]`) so
  everything stays flat — though `ProjecturedDomain` re-exporting them transitively may
  suffice; decide once that split lands.
- Independent of the [directory reorg](source-tree-reorganization.md) and
  [video extraction](extract-video-package.md).

## Implementation notes (what actually shipped)

Implemented in a worktree off `main`. The ~840-line hand-maintained block
(141 `const XxxModule`, 138 `using …Module: …`, 191 `export …`) is replaced by a
~25-line loop in `package/projectured/src/Projectured.jl`.

**Empirical analysis first** (against the old umbrella, before editing) decided the shape:
- Old surface: 928 exported names, 141 submodule aliases.
- The loop (re-export every exported name of every kernel/domain submodule) would produce
  **1380 exports / 142 aliases** — a strict **superset**. Names the loop would MISS:
  just `Projectured` (the module's own name) → **0 real gaps**. So the "non-exported
  hand-import" caveat (e.g. `skip_type_checkpoints`) did **not** materialize — those names
  are in fact exported by their submodule (`ReferenceModule`), so no explicit `import`
  block was needed.
- **Collision check:** 1379 unique names across the submodules, **0** with conflicting
  bindings → a per-submodule `using …: …` is unambiguous, no need to dedupe.

**Two refinements vs. the sketch:**
- Sources brought in with **`import`** (not `using`) so the loop is the *sole* re-export
  path — nothing leaks from a top-level `using` to conflict with the `const` aliases.
- The loop walks submodules via `names(src; all=true)` + `parentmodule(m) === src` (so
  `ProjecturedDomain`'s aliases of kernel submodules are skipped and each submodule is
  processed once under its true parent), and emits `const`/`using`/`export` via
  `Core.eval(Expr(...))` (batched one `using …: a,b,c` + one `export …` per submodule).

## Verification (all green)

- `Projectured` precompiles (~0.5 s); 1380 exports, 142 aliases (⊇ old).
- All critical flat names (`projection_print`, `GraphicsCanvas`, `skip_type_checkpoints`,
  `record_video`, `make_backend`, …) and submodule aliases
  (`SyntaxToTextModule`, `ConsoleBackendModule`, `McpModule`, `ReactiveModule`, …) present.
- `ProjecturedExample` + `ProjecturedTest` precompile/load — resolving **every** qualified
  `using Projectured.XxxModule: …` site (Object.jl, ConsoleBackendTest, SyntaxToTextTest,
  TypeReferenceTest, AssistantMvpTest, …).
- Tests: `test_printer(json)` 3551/3551, `test_reader(json)` 225/225,
  `test_type_reference` 33/33 (uses `Projectured.skip_type_checkpoints`),
  `test_console_backend` 36/36 (uses `Projectured.ConsoleBackendModule`),
  `test_syntax_to_text` 124/124 (uses `Projectured.SyntaxToTextModule`).

## Status

- [x] Replace the manual re-export block in `Projectured.jl` with the loop (`import` sources + `Core.eval` loop)
- [x] No explicit non-exported-symbol imports needed (empirically 0 gaps; e.g. `skip_type_checkpoints` is submodule-exported)
- [x] Verified `example` + `test` load (qualified `Projectured.XxxModule.*` + flat names resolve) + qualified-access tests pass
