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

- [x] **Step 1, N1.** Run the two suites.
- [x] **Step 2, N2 and N6.** Run `test_sdl()` and `test_json()`.
- [x] **Step 3, N3 and N4.** Run the fault tests and the gallery wrappers.
      Done by removing one unused dependency (§5).
- [x] **Step 4, N5.** Run `test_platform()` and `test_julia()`.
      Done. Each suite in its own environment, against `main` measured the same
      way: platform 97502 → 97291 passed (8 broken on both), Julia 410 → 501.
      The four moved functions have 40, 120, 8 and 43 assertions on `main`, so
      91 went to Julia and 120 (`test_conversation_transcript`) to the
      umbrella: nothing is lost.
- [x] **Step 5, N7.** Run `test_video()`.
      Done: 39 passed in its own environment (41 in CI on `main`); the 2
      assertions of the assistant video are in the umbrella.
- [x] **Step 6, N8.** Run the four new suites.
      Done, each in its own environment with no network: Console 140, PDF 50,
      Web 110, MCP 410 passed. The SDL, ODBC and Tulip suites alone: 803, 41
      and 14, the counts of CI on `main`.
- [x] **Step 7, the check.** The closure script of R30 again: the unregistered
      packages, the registered ones, and the size for each package. The
      guards. The CI-like run of the 28 jobs, and the new ones, against the
      run of `main`.
      The closure, measured on 2026-10-01 (the folders that the support
      packages include; a file included through a folder constant is not
      counted, which matters for Video and the umbrella only):

      | Package | Unregistered | Registered | Test folder |
      | --- | --- | --- | --- |
      | `ProjecturedKernel` | 2 | 1 | 0.7 MB |
      | Anthropic, Ollama, OpenRouter, DataFrames, Web, Tulip, ODBC | 3–4 | 2–8 | 0.7–0.8 MB |
      | Console, PDF, SDL | 5 | 5–6 | 0.9–1.0 MB |
      | `ProjecturedPlatform`, a domain, MCP, Video | 4–8 | 5–9 | 2.1 MB |
      | `Projectured` (the umbrella) | 55 | 31 | 3.9 MB |

      Before: 25 unregistered and 24 registered packages for a domain. All 32
      test folders together are about 55 MB. The guards give the findings of
      `main` and no new one.
      The CI-like run `ci9` (`/var/tmp/r30/ci9`, the branch at `7e361d170`, 32
      jobs), against `ci8`: every difference has its cause. Kernel +1 (the
      meaning folder test), Julia 410 → 501 and platform −211 against `main`
      (the moved tests), Video 41 → 39 (the assistant video), the four new
      packages 140, 50, 110 and 410, all passed; SDL, Tulip and ODBC give the
      counts of `environment/all` in their own projects. The umbrella had the 7
      known failure sites of `main` and 10 new errors: the moved transcript test
      names `ProjecturedConversationExample`, which the umbrella test package
      did not import. Fixed in `8740e5d16`; the four tests that moved to the
      umbrella then pass, the transcript with its 120 assertions.
      The last CI-like run `ci10` (`/var/tmp/r30/ci10`, the branch at
      `b7303f070`, 34 jobs in one lane, with R30 done too): every job passes;
      the umbrella `test_integration()` fails at the 7 known sites of `main`
      with the same counts, and the guards give the findings of `main`.

## 5. Decisions made during the work

- **N3 and N4 were not needed.** `ProjecturedPlatformTest` named
  `ProjecturedFaultExample` in its `[deps]` but never loaded it, so the
  dependency goes and the fault example and the gallery stay where they are.
  The inventory had missed that the gallery uses the gallery wrappers, two
  umbrella examples and `run_file_editor`, so its move would have been large.
- **N2: the graphics image example was a duplicate.**
  `make_graphics_image_projection_example` had the body of
  `make_json_projection_example`, so the callers use the JSON example and the
  file is gone.
- **N1: the ODBC and Tulip test packages stand alone.** They had no `[sources]`
  entry for the package they test, and CI ran them in `environment/all`. Now
  they, and the SDL and Video test packages, name what they use and run in
  their own projects in CI. Three ODBC test files loaded the umbrella
  themselves.
- **N5: JSON stays below the platform tests.** `FileDialogTest.jl` saves a file
  in a notation that the test package declares; it used Julia, and now uses
  JSON, the reference fixture. The three tests with a Julia fixture are in
  `test/domain/julia/editor/`, and `ConversationTranscriptTest.jl` is in
  `test/projectured/projection/`.
- **N7: the SDL example package is narrow too.** Its live examples play JSON
  only, so it needs `ProjecturedJSONExample`, not the umbrella; it has its own
  `json_example`. The assistant conversation video uses the conversation
  example of the umbrella, so that testset is now
  `test_assistant_conversation_video()` in the umbrella suite.
- **N8: the umbrella keeps its calls.** It loads the four new packages and
  calls the moved test functions as before, as it does for SDL and Video, so
  its count does not change. Each new package runs the same tests again with
  its layering guard.
- **N8, MCP.** Its new layering guard found that `McpModule.jl` imported `Tool`
  and `Resource` only to win over the names of the protocol. The module now
  names what it takes from the protocol instead. Two tests read the whole
  surface of the application (`test_search_tools_registered`,
  `test_whole_surface_documentation`) and moved to the umbrella, in
  `McpSurfaceTest.jl`. `test_mcp_resources()` was called nowhere on `main`;
  the MCP suite calls it, and its eight tests pass.

Faults found on `main`, not changed here:
- `DatabaseInstanceToDbCatalog.jl:86` calls `set_output_path_computations!`,
  which `OdbcModule` does not import; the ODBC tests read the error as "DB
  unavailable", so 10 of them skip in silence.
- The assistant video test reads any error as "ffmpeg unavailable".
- `ProjecturedExample` exports four `json_*_live` names that it does not
  define.
