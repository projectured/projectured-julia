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
- [x] **Step 1, console and pdf.** Rename the two modules and their fragments.
      Done: `ConsoleModule` (`ConsoleModule.jl`, `ConsoleBackend.jl`) and
      `PdfModule` (`PdfModule.jl`, `PdfWriter.jl`); the test of the PDF writer
      is `PdfWriterTest.jl`. **The form of a package entry**, decided here and
      kept for every step: the entry of `ProjecturedDataFrames` — the loop that
      binds every submodule of the kernel and the platform as a `const`, the
      include of the module file, `using .<Slice>Module: <names>` and `export`
      of the same names. The console entry exported nothing before; now a
      person who loads `ProjecturedConsole` gets `ConsoleBackend` and
      `render_console`, and `ProjecturedPdf` gives `write_pdf` and
      `GraphicsCanvasToPdfFile`. Tests: the console backend, the PDF writer,
      the export collisions, the layering guard of the platform (which checks
      Console and Pdf): 198 pass.
- [x] **Step 2, sdl, web and video.** A module file for each, the imports out of
      the package entries; the private names of §2 get public names or stay
      inside one module.
      Done in three parts. (a) The three bounds helpers of the graphics slice
      took four `Ref`s each; they are one public accumulator, `ContentBounds`,
      with `extend_content_bounds!`, `extend_element_bounds!`,
      `extend_canvas_bounds!` and `get_content_box` (`3f8da6fdc`); SDL passes
      one through its walk, and Web drops its own copy of the same box. (b)
      The seven offscreen functions of SDL that Video uses are public
      (`cc420e5f7`): the handle holds the logical size, so no call passes it
      again, and the arguments past the third are keywords (the argument
      rule). `_encode_frames_to_video!` is `encode_frames_to_video!`. (c) The
      module files: the guard wants bare module imports, so each module has
      `using ..KernelModule`, `using ..PlatformModule`, its third-party
      packages, and `import` of exactly the names it extends (two qualified
      extensions of SDL that named `ProjecturedKernel` became imports). The
      kernel's `write_image` is exported by the package entry, not by the
      module, which only extends it. White-box tests reach the internals
      through `ProjecturedSdl.SdlModule` and `ProjecturedWeb.WebModule`.
      **Found on the way:** `ApplicationVideoTest.jl:244` failed on `main`
      since the fold put the application in the platform: its way to break a
      paint (a JSON object with a foreign child) no longer fails, because the
      natural renderer reflects a child that the closed JSON chain refused. The
      test breaks a cell instead, which fails in every renderer (`3e2d4771a`).
      Tests: the SDL, Video, Web and builder suites, 1,173 pass.
- [x] **Step 3, the six adapters.** A module file for each.
      Done: `AdaptagramsModule`, `AnthropicModule`, `McpModule`, `OllamaModule`,
      `OpenRouterModule` and `TulipModule`, with the fragments
      `AdaptagramsLayout.jl`, `AnthropicLlm.jl`, `McpServer.jl`, `OllamaLlm.jl`,
      `OpenRouterRelevance.jl` and `TulipConstraintSolver.jl`; their tests
      follow (`AnthropicLlmTest.jl`, `OllamaLlmTest.jl`,
      `OpenRouterRelevanceTest.jl`). The binding loop of each entry takes the
      Projectured packages it depends on: the kernel for the four on the
      kernel, the platform for Tulip, and the Graph domain for Adaptagrams. The
      docstring of each entry is the module's now, and the entry has a short
      one. MCP keeps `import ..ToolModule: Tool, Resource`, because the
      protocol exports a `Tool` and a `Resource` of its own. The layering
      guards of Anthropic, Ollama and OpenRouter take the modules the loop
      binds as aliases, as DataFrames and Tulip did. Tests: the four suites,
      the MCP tests of the umbrella, a load of Adaptagrams: 628 pass, 2 broken
      (the markers that were there).
- [x] **Step 4, the guard.** Every slice folder of `source/` outside the kernel
      holds one file that declares a module, the other files declare none, and
      a package entry of a backend or an adapter includes only its module file.
      Done: `slice_module_violations` in `test/suite/naming.jl`, part of
      `naming_violations`, so the guards job of CI and `test_naming()` run it.
      It checks the groups platform, domain, backend and adapter, and every
      include of a package entry into those groups. On a clone of `main` it
      reports the nine slices and the ten includes; on this branch nothing.
      **The tools are not in it, and that is open:** `source/tool/builder/` and
      `source/tool/repl/` have no module of their own either (the code is a
      fragment of `ProjecturedBuilder` and of `ProjecturedRepl`). The owner
      asked about the backends and approved the adapters; the two tools wait
      for the owner's word.
- [x] **Step 5, the words.** `naming-rules.md` (its example of `<Thing>.jl` is
      `source/backend/sdl/Sdl.jl`), the guides of the backends and adapters,
      `system-anatomy.md`.
      Done: `naming-rules.md` says that the rule of one module per slice holds
      outside the kernel and that the guard checks it, and its example is
      `SdlBackend.jl`; each guide of a backend or an adapter names its module
      and folder (which also gives `source/adapter/openrouter` its guide in the
      eyes of the documentation guard); the graphics guide documents
      `ContentBounds`, the SDL guide the public offscreen renderer; the links
      of `system-anatomy.md`, `devices-and-backends.md`, `llm.md` and
      `adaptagrams.md` follow the new file names.

## 5. Decisions made during the work

(filled in as the work goes)
