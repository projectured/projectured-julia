# Replace the `make_backend` symbol factory with per-site backend selection

> **Status (2026-07-09): implemented, pending local verification.** All ten call sites,
> the `pdf_measure_text` rename + relocation, and the factory removal are done and pushed
> on `claude/make-backend-usage-dufm41`. The work was authored in an environment **without
> Julia**, so nothing has been run. Verify locally with the narrow tests — at minimum
> `test_visual()` / `test_domain()` (TrueType relocation + console/default sites),
> `test_kernel()` (HeadlessBackend test + factory removal), a `test_json_to_syntax()` /
> `test_printer` smoke over the measurer, and `build_executable(compile=false)` plus a real
> `Build.jl` run for the executable/Builder rework (the build-orchestration env, especially
> `Build.jl`'s standalone launch, could not be exercised here).

Goal: remove the symbol-keyed `make_backend(kind)` factory seam and the per-backend
`make_backend(::Val{kind})` registrations, replacing each call site with the cheapest
mechanism that fits it. Symbols go away; the kernel `Backend.jl` shrinks to the abstract
type plus generics.

## Design principle

The object-injection API already exists underneath everything: `run_example(; backend=…)`
takes a constructed `Backend`. The symbol factory is only a thin dep-less *constructor
shim* sitting on top of it. So the replacement is not "object vs symbol" — objects already
win; the question per site is only how the object is obtained.

Three mechanisms, chosen per site:

1. **Object injection (default).** The caller names the concrete type and constructs it
   (`SdlBackend()`, `WebBackend(; host, port)`). Requires the dependency arrow to exist —
   which it legitimately does wherever we use this. Best layering: the lower layer takes a
   `Backend` it never names or constructs. Carries per-backend kwargs naturally. Requires
   importing the concrete type by name (all backend packages already export their type).
2. **Local string→constructor map at a boundary.** For the CLI, where `--backend sdl` is
   inherently a string. The executable *has* the backend deps, so it maps the string to a
   named constructor locally. This relocates the symbol→type mapping to where the deps are;
   it does not reintroduce a kernel seam.
3. **Reflection-based auto-selection (the default-when-none path).** When a site takes an
   optional `backend` and none is provided, `default_backend(prefer)` derives one from the
   loaded `subtypes(Backend)`, matching each entry of the caller's `prefer` list against the
   type's **own name** (`nameof(T)`). This lets a package with no SDL dep (e.g.
   domain-example) obtain an SDL backend without naming the type — it names only the symbol
   `:SdlBackend`, which is data matched by reflection, not a coined key requiring a
   registration method (the crucial difference from the `:sdl` factory). It cannot carry
   backend-specific kwargs (see below), so any such knobs move onto the concrete constructor
   and are supplied by the caller via `backend=`.

   ```julia
   function default_backend(prefer = (:SdlBackend, :WebBackend, :ConsoleBackend))
       loaded = subtypes(Backend)
       for name in prefer
           i = findfirst(T -> nameof(T) === name, loaded)
           i === nothing || return loaded[i]()
       end
       error("default_backend: none of $(prefer) is loaded; loaded: $(nameof.(loaded))")
   end
   ```

   The call site owns the ordering ("prefer SDL, then web, then console") by passing/defaulting
   `prefer`. Fully-qualified names (`"ProjecturedSdl.SdlBackend"`) are allowed to disambiguate
   by module if two backends ever share a short name. Unloaded entries skip; errors only if the
   whole list is absent. `default_backend` lives in the kernel (`Backend.jl`) alongside the
   abstract `Backend` type, using `subtypes` — no dependency on any concrete backend.

## Call sites

| # | Site | Kwargs | Dep present? | Decision |
| --- | --- | --- | --- | --- |
| 10 | `sdl/test/ProjecturedSdlTest.jl:25` | — | yes (`using ProjecturedSdl`) | **object**: `initialize_backend!(SdlBackend())` |
| 9 | `projectured/test/ProjecturedTest.jl:100` | — | yes (dep in `[deps]`, not in scope) | **object**: add `using ProjecturedSdl`, `SdlBackend()` |
| 8 | `visual/example/Harness.jl:25` | — | no | **delete**: vestigial; measurement is SDL-free (see below) |
| 7 | `sdl/example/LiveExamples.jl:136` | — | yes | **object**: `play_live!(SdlBackend(), …)` |
| 3 | `domain/example/Gallery.jl:174` | sdl kwargs | no | **optional backend + reflection default** (see below) |
| 4 | `domain/example/Gallery.jl:452,460` | console kwargs | console via Visual | **object**: `ConsoleBackend(; ansi, clear)` |
| 5 | `domain/example/FileEditor.jl:177` | — | no | **reflection default** (same as #3) |
| 6 | `domain/example/FileEditor.jl:262` | — | console via Visual | **object**: `ConsoleBackend()` |
| 2 | `projectured/example/Examples.jl:51` | `host`, `port` | no | **delete** `run_web_example` (redundant; see below) |
| 1 | `executable/main/ProjecturedExecutable.jl:170` | — | baked backends | **types in build code, friendly flag at runtime** (see below) |

Registrations to remove once all sites are converted: the `make_backend` factory +
fallback in `package/kernel/main/backend/Backend.jl:37-39`, and the `make_backend(::Val{…})`
methods in `HeadlessBackend.jl:45`, `Console.jl:338`, `ProjecturedSdl.jl:2507`,
`ProjecturedWeb.jl:865`. Drop `make_backend` from the kernel export list and the umbrella
re-exports. Update `package/kernel/doc/devices-and-backends.md`, `architecture*.md`,
`naming.md`, and the layering-rule docs that describe the seam.

## Decided details

### #8 Harness.jl — delete, don't convert

`write_example_pdf` calls `initialize_backend!(make_backend(:sdl))` then discards the
backend. The measurement it claims to enable (`measure=truetype_measure_text`, the same
line) is **SDL-free**: `truetype_measure_text` = `pdf_measure_text` reads advance widths
from the font's own TrueType `hmtx` table, and `font_logical_size` reads only the
default-valued `_FONT_ZOOM` cell (`1.0`). SDL init touches nothing this path reads. Delete
the line. Correct the header comment (lines 7-8) and block comment (lines 18-21), both of
which falsely claim PDF font metrics need SDL.

### #3 Gallery.jl `run_example` — optional backend + reflection default

`run_example` (`Gallery.jl:85`) lives in domain-example, which has **no SDL dep**, yet
defaults `backend` to SDL and carries SDL-only kwargs `partial_render`/`debug_dirty`.
Resolution:

- Keep `backend` optional. `backend === nothing && (backend = default_backend())`.
- **Remove `partial_render`/`debug_dirty` from `run_example`'s signature** — reflection
  can't carry them and they are SDL-only. Move them onto `SdlBackend`'s constructor; callers
  who want them pass `backend=SdlBackend(; partial_render=…, debug_dirty=…)`.
- Note: "SDL must be loaded in the session" is already a precondition today (the seam errors
  otherwise), so reflection over the loaded set does not weaken anything.

**Selection policy — resolved.** `default_backend(prefer)` matches the caller's ordered
`prefer` list against `nameof(T)` over loaded `subtypes(Backend)` (see mechanism 3 above).
The call site decides the order via real type names (`:SdlBackend`, …); no coined `:sdl`
key and no per-backend registration. `run_example` uses the default order `(:SdlBackend,
:WebBackend, :ConsoleBackend)`.

### #2 `run_web_example` — delete, don't convert

The wrapper exists only to select the web backend instead of the SDL default. Backend
injection already expresses that: `run_example("json"; backend=WebBackend())`. `WebBackend`'s
constructor already defaults `host`/`port` (`ProjecturedWeb.jl:98`), so no config is lost, and
the caller already has `ProjecturedWeb` loaded (today's `make_backend(:web)` requires it), so
naming `WebBackend` needs no new import. Custom port becomes `run_example("json";
backend=WebBackend(port=9000))`. No internal callers — only exports and docs.

Footprint: remove the definition/docstring (`Examples.jl:40-51`), the export
(`ProjecturedExample.jl:127`), and the passthrough import/export lines in the
adaptagrams/tulip/odbc example packages. Update docs (README ×2, `roadmap.md`,
`debugging.md` ×2, `kernel/doc/devices-and-backends.md` ×4) to the injection idiom.

### #1 CLI — real types in build code, friendly flag at runtime

Two audiences: the **programmer** writing the build spec names real types; the **non-programmer**
running the binary types a short `--backend sdl`. No Val indirection, no coined key authored
anywhere.

- **Build API** (`Builder.jl` / `BuildSpec`): `backends`/`default_backend` take real backend
  **types**, e.g. `build_executable(; backends=[SdlBackend], default_backend=SdlBackend)`. The
  builder derives per type: friendly CLI name (`nameof` → strip `Backend`, lowercase → `sdl`) and
  the `using` module (`parentmodule(SdlBackend)` → `ProjecturedSdl`). The hand-authored
  `KNOWN_BACKENDS` symbol table goes away (module→local-dir may remain, keyed on the module/type).
- **Generated `AppConfig.jl`**: emit the `using` line(s) plus a name→type **data** map — no Val,
  no `make_backend`:
  ```julia
  using ProjecturedSdl
  const APP_BACKENDS        = (; sdl = SdlBackend)   # friendly name → real type
  const APP_DEFAULT_BACKEND = SdlBackend
  ```
- **Runtime** (`ProjecturedExecutable.jl`): drop `make_backend` from the import (line 13);
  `backend_type = opts.backend === nothing ? APP_DEFAULT_BACKEND : APP_BACKENDS[opts.backend]`,
  then `backend = backend_type()`. `resolve_backend` validates the friendly key against
  `keys(APP_BACKENDS)`.
- `AppConfig.default.jl` mirrors the generated shape (`APP_BACKENDS = (; sdl = SdlBackend)`).

`:sdl` then exists only where the end user types it (auto-derived from the type name by the
builder), never as a dispatch key. Consequence: whoever calls `build_executable` must have the
backend types in scope (already true — you can only bake in a backend you have).

## `pdf_measure_text` is misnamed and mis-homed (do both)

The SDL-free TrueType measurer and its machinery live in `PdfBackendModule` but are
format-neutral: the **web backend** imports `pdf_measure_text` (`ProjecturedWeb.jl:39`;
`measure_text(::WebBackend, …) = pdf_measure_text(…)`), and every projection example
defaults `measure=truetype_measure_text`. A neutral alias `truetype_measure_text =
pdf_measure_text` already exists (`Pdf.jl:241`) — the cleanup was started but not finished.

- **Shallow (naming).** Promote `truetype_measure_text` to the primary definition; demote
  `pdf_measure_text` to a deprecated alias or remove it. Update web's import. `truetype_`
  distinguishes this free function from the backend-dispatched `measure_text` generic.
- **Deep (placement).** Move the TrueType metrics machinery — `TrueTypeFont` (`Pdf.jl:60`),
  `text_width` (`Pdf.jl:204`), `_load_ttf`, and the measurer — out of `PdfBackendModule`
  into a font/text-metrics module next to `style/Font.jl` (which already owns
  `font_logical_size`, `_FONT_ZOOM`, `StyleFont`). PDF, web, and examples then import from a
  neutral home instead of reaching into "Pdf". This removes a wrong dependency direction,
  not just a wrong name.

## Execution order (all done — see commit log on the branch)

1. [x] `pdf_measure_text` → `truetype_measure_text` rename + relocation into a new
   `TrueTypeModule` (`package/visual/main/style/TrueType.jl`); Pdf/web/domain rewired.
2. [x] Delete #8's vestigial SDL init; fix its comments.
3. [x] Convert dep-present sites to direct construction (#10, #9, #7 → `SdlBackend()`; #4, #6
   → `ConsoleBackend(…)`).
4. [x] `default_backend` added in base; dep-less example sites #3/#5 use it; #2 deleted; CLI
   #1 reworked (build API takes types, runtime constructs `APP_BACKENDS[kind]()`).
5. [x] Remove the factory + `Val` registrations; drop the `make_backend` export; update docs.

Deferred / not attempted: `get_display_size()`'s implicit "a backend is live" assumption
(`Gallery.jl`, `FileEditor.jl`) — a separate latent global, out of scope for the factory
removal (noted at #5).
