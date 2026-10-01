# One module for each backend and each adapter

## 1. Goal

Every slice of `source/backend/` and `source/adapter/` has the form that the
platform slices and the domains have: one module file `<Slice>Module.jl` with
the docstring, the imports, the exports and the includes, and fragments named
for what they define. The package entry includes the module file, uses it, and
exports the names a person loads the package for.

The owner asked for it (2026-10-01): "I think all backends should have their
own module, why is that not case? … the file names don't really sound
consistent there". The shape was shown and approved the same day ("looks good,
plan and implement").

## 2. Facts (2026-10-01, `main` at `3d0d25ae0`)

- Two forms exist. `console` and `pdf` have a slice module
  (`ConsoleBackendModule`, `PdfBackendModule`), because they were written as
  packages of the substrate. `sdl`, `web` and `video`, and six of the eight
  adapters (`adaptagrams`, `anthropic`, `mcp`, `ollama`, `openrouter`, `tulip`),
  have none: the source file is a fragment of the package module itself, and
  its imports (60 `using` lines for SDL) are in the package entry. `dataframes`
  and `odbc` have the form already.
- The second form breaks `naming-rules.md`, "one module per unit of
  architecture". The naming guard does not see it: it checks that a declared
  module matches its file, not that a slice declares one.
- The names do not follow the rule either: `ConsoleBackendModule.jl` where the
  rule says `<Slice>Module.jl`; `Console.jl`, `Pdf.jl`, `Sdl.jl` and `Web.jl`
  define a backend but have the bare slice name; in `video/`, `Video.jl` holds
  `record_video` and `VideoBackend.jl` the backend.
- Three package entries name private names of other modules, which the
  module-boundary rule (PAR-MODULE-BOUNDARY-IS-API) forbids once the code is
  in a slice module: SDL takes `_bounds_elem!`, `_bounds_extend!` and
  `_get_font` and exports `_open_offscreen_renderer` and
  `_close_offscreen_renderer`; Web takes `_bounds_elem!` and
  `_accumulate_bounds!`; Video takes five private names of SDL.
- 17 files name `ConsoleBackendModule` or `PdfBackendModule`; no downstream
  file does.

## 3. The shape (approved)

```
source/backend/
  console/   ConsoleModule.jl        ConsoleBackend.jl
  pdf/       PdfModule.jl            PdfWriter.jl
  sdl/       SdlModule.jl            SdlBackend.jl
  video/     VideoModule.jl          VideoBackend.jl, VideoRecording.jl
  web/       WebModule.jl            WebBackend.jl
source/adapter/
  adaptagrams/  AdaptagramsModule.jl  AdaptagramsLayout.jl
  anthropic/    AnthropicModule.jl    AnthropicLlm.jl
  mcp/          McpModule.jl          McpServer.jl
  ollama/       OllamaModule.jl       OllamaLlm.jl
  openrouter/   OpenRouterModule.jl   OpenRouterRelevance.jl
  tulip/        TulipModule.jl        TulipConstraintSolver.jl
```

A test named for a file follows it (`VideoTest.jl` → `VideoRecordingTest.jl`,
and the tests of the three model adapters). `SdlBackend.jl` is not split here.

## 4. Steps

- [ ] **Step 0, the baseline.** The guards of CI and the suites of the
      packages that change, on `main`: `test_sdl`, `test_video`, `test_tulip`,
      `test_anthropic`, `test_ollama`, `test_openrouter`, `test_platform` (Console
      and Pdf), the MCP and builder tests of the umbrella.
- [ ] **Step 1, console and pdf.** Rename the two modules and their fragments.
- [ ] **Step 2, sdl, web and video.** A module file for each, the imports out of
      the package entries; the private names of §2 get public names or stay
      inside one module.
- [ ] **Step 3, the six adapters.** A module file for each.
- [ ] **Step 4, the guard.** Every slice folder of `source/` outside the kernel
      holds one file that declares a module, the other files declare none, and
      a package entry of a backend or an adapter includes only its module file.
- [ ] **Step 5, the words.** `naming-rules.md` (its example of `<Thing>.jl` is
      `source/backend/sdl/Sdl.jl`), the guides of the backends and adapters,
      `system-anatomy.md`.

## 5. Decisions made during the work

(filled in as the work goes)
