# Each test package needs only what is below it

## 1. Goal

A test package depends only on the packages below the package it tests, so
that the release test of a package (R30) carries a small closure. This is
Step 1 of [release-tests-for-each-package.md](release-tests-for-each-package.md),
decision T3, and decision T6 (a test package for Console, MCP, PDF and Web).
The owner accepted both on 2026-10-01.

`ProjecturedJSON` is the reference fixture of the platform tests. So the order
is: kernel, platform, JSON, the platform tests, then each domain, backend and
adapter with its tests. The umbrella `Projectured`, its example package
`ProjecturedExample`, and a fixture that names several domains stay at the
top, in `ProjecturedTest`.

## 2. Facts (2026-10-01, `main` at `e8be64774`)

Four links make the closure wide. Each one is checked by hand in the code.

1. **`ProjecturedFaultExample`** uses `Projectured` and `ProjecturedExample`.
   From them it takes kernel modules (`ProjectionModule`, `OperationModule`,
   `BackendModule`), the JSON types of its demo document (`JsonObject`,
   `JsonString`, `JsonToSyntax`), and the gallery harness (`run_example`,
   `make_example_editor`, `Example`).
2. **The gallery harness**, `example/projectured/Gallery.jl` in
   `ProjecturedExample`, uses only kernel, platform, console and PDF names,
   except three: `run_console_example` takes the JSON examples as its
   defaults, and `record_assistant_conversation_video` uses
   `make_assistant_projection_example` of `ProjecturedConversationExample`.
3. **`ProjecturedPlatformTest`** depends on `ProjecturedFaultExample`,
   `ProjecturedConversationExample` (which depends on JSON, Julia, Markdown,
   XML and YAML), and on JSON, Julia and XML. Only two of its inner modules
   use them:
   - `ConversationTests`: `ConversationEditorTest.jl` (Julia),
     `ConversationTranscriptTest.jl` (the conversation example and Julia), and
     `AssistantApiTest.jl`, which uses no domain;
   - `ShellTests`: `JuliaTooltipTest.jl` and `TooltipWindowTest.jl` (Julia).
4. **The backend and adapter tests.**
   - `ProjecturedSDLTest` uses `make_json_document_example` and
     `make_graphics_image_projection_example`. The second is a chain from
     JSON to graphics in `example/projectured/`.
   - `ProjecturedVideoTest` uses the JSON examples, `json_build_live`
     (`example/backend/sdl/LiveExamples.jl`, exported by `ProjecturedExample`)
     and `record_application_video` of `ProjecturedSDLExample`, which depends on
     `Projectured` and `ProjecturedExample`.
   - `ProjecturedODBCTest` and `ProjecturedTulipTest` name `Projectured` and
     `ProjecturedExample`, but their test files use no example.

The tests of Console, MCP, PDF and Web are in the umbrella suite:
`test/projectured/backend/ConsoleBackendTest.jl` (the JSON examples),
`PdfWriterTest.jl` (the JSON examples and the graphics image example),
`WebTest.jl` (no example), and `test/projectured/editor/McpTest.jl` (JSON
types, `ToolModule`, `AssistantModule`).

## 3. The changes

- **N1, unused dependencies.** `ProjecturedODBCTest` and `ProjecturedTulipTest`
  lose `Projectured` and `ProjecturedExample`, and name the packages that give
  the names their tests use.
- **N2, a one-domain example goes to its domain.**
  `make_graphics_image_projection_example` moves to `ProjecturedJSONExample`.
- **N3, the gallery harness goes to `ProjecturedPlatformExample`.** The two
  functions that name a domain example stay in `ProjecturedExample`.
- **N4, `ProjecturedFaultExample`** depends on the kernel, the platform, JSON,
  `ProjecturedKernelExample` and `ProjecturedPlatformExample`.
- **N5, `ProjecturedPlatformTest`** keeps `AssistantApiTest.jl`. The tests with
  a Julia fixture move to `ProjecturedJuliaTest`, and
  `ConversationTranscriptTest.jl`, whose fixture names several domains, moves to
  `ProjecturedTest`. Its dependencies on Julia, XML and
  `ProjecturedConversationExample` go.
- **N6, `ProjecturedSDLTest`** depends on `ProjecturedJSONExample` instead of
  `Projectured` and `ProjecturedExample`.
- **N7, `ProjecturedVideoTest`.** `LiveExamples.jl` moves to
  `ProjecturedSDLExample` if its names allow it. A test that records the whole
  application moves to `ProjecturedTest`.
- **N8, four new test packages** (T6): `ProjecturedConsoleTest`,
  `ProjecturedPDFTest`, `ProjecturedWebTest` and `ProjecturedMCPTest`, with the
  tests above moved out of `ProjecturedTest`. Each one is in CI, in
  `environment/all`, and in the testing guide.

**A moved test keeps its assertions.** The sum of the counts of the moved
test functions is the same before and after; a change of a count is a fault of
the move.

## 4. Steps

- [ ] **Step 1, N1.** Run the two suites.
- [ ] **Step 2, N2 and N6.** Run `test_sdl()` and `test_json()`.
- [ ] **Step 3, N3 and N4.** Run the fault tests and the gallery wrappers.
- [ ] **Step 4, N5.** Run `test_platform()` and `test_julia()`.
- [ ] **Step 5, N7.** Run `test_video()`.
- [ ] **Step 6, N8.** Run the four new suites.
- [ ] **Step 7, the check.** The closure script of R30 again: the unregistered
      packages, the registered ones, and the size for each package. The
      guards. The CI-like run of the 28 jobs, and the new ones, against the
      run of `main`.

## 5. Decisions made during the work

(filled in as the work goes)
