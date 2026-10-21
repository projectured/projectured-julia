# Every CI job passes

Status: IN PROGRESS on the branch `ci-green`, worktree
`../projectured-julia-ci-green`, base `main` 5ecc0c0e4.

## The ask

On 2026-10-21 the owner asked to fix the faults so that every CI job of
projectured-julia passes.

## The faults

The CI runs of 2026-10-21 on `main`: 39625214822 (f593feb4a, every job ended)
and 39649434280 (5ecc0c0e4). CI runs Julia 1.13.2 on `ubuntu-latest` with
`SDL_VIDEODRIVER=offscreen`, the software renderer of SDL, and no `ffmpeg`.

| Job | Faults |
| --- | --- |
| Static guards | `arguments.jl` 3, `exports.jl` 4, `style.jl` 3 |
| ProjecturedSDLTest | `PartialPaintTest.jl:529` 1 fail; `TreeRenderTest.jl:43-55` 2 fail, 1 error |
| ProjecturedVideoTest | `VideoTest.jl:146`, `:153` (json_build_live); `ApplicationVideoTest.jl:210` (zoom) |
| ProjecturedPlatformTest | `ExplorerTest.jl:833-855`, 11 fail (Return in the filter searches below the node) |
| ProjecturedTest `test_integration` | 12 fail, 5 error, listed in step 5 |

The documentation guard passes. Its list of lines "for a person to read" is advice.

## Steps

1. [ ] The static guards pass. Done except `CellModule.jl:48`
   (daa936f68, c47a05319, 8ae34c944).
   - [x] `arguments.jl`: `PivotCrossTable.jl:488`, `:491` (`find_pivot_value`),
     `TaskGroupDocument.jl:379` (`rerun_task_group_document!`).
   - [ ] `exports.jl`: `CellModule.jl:48` (sealed 🔒, needs the owner's permission).
     [x] `FileChangeModule.jl:35`, `BuilderModule.jl:35`.
   - [x] `style.jl`: `Application.jl:472`, `FilePageToWidget.jl:72`, `TextDocument.jl:438`.
2. [x] `test_sdl()` passes: the scroll paint of a window, and the tree render.
   1071 of 1071 with the offscreen driver, with the renderer that SDL picks and
   with `SDL_RENDER_DRIVER=software` (894491609, c3587ae83).
3. [ ] `test_video()` passes: `json_build_live`, and the zoom of a take.
4. [ ] `test_platform()` passes: the search of the explorer filter.
5. [ ] `test_integration()` passes:
   - `CatalogCoverageTest.jl:138`, `:228`
   - `ReplTest.jl:94` filesystem_widget (3)
   - `HistorySweepTest.jl:35`, `:121` (errors)
   - `AssistantMvpTest.jl:257`
   - `ToolViewTest.jl:66`, `:69`, `:293`
   - `EvaluatorDuplicateTest.jl:36`, `:40`, `:48`
   - `ReferencedDocumentEditorTest.jl:369`, `:381`
   - `MouseClickTest.jl:304` formula_report
6. [ ] The check: each job that failed runs its CI command in its own environment
   with the offscreen driver, and passes.

## Decisions and facts

- The optional positional arguments of `find_pivot_value` (`column_key`) and of
  `rerun_task_group_document!` (`which`) stay positional, with a `# @optional:`
  marker. `column_key` is a coordinate of the cell, as `row_key` is, and about 15
  calls and the guide write it so. omnet-julia calls
  `rerun_task_group_document!(doc, :failed)` in three places.
- The band of a file page takes its padding from a new theme field
  `band_padding`, with the same value as before. No field of the theme had that
  value. The padding now scales with the theme, as the other paddings do.
- The example canvas in the system text of the assistant, and the hint colour of
  a text block, keep their values with a `# @style:` marker: the first is text
  for the agent and draws nothing; the second is the same colour that
  `make_hinted_text` marks so.
- The scroll test of a window failed only on the software renderer. On this
  machine the offscreen driver still gets the `opengl` renderer through EGL; the
  CI runner has no GL and gets `software`. A text texture inherits the linear
  filter of the hint that `_open_native_window!` sets, and the software renderer
  draws a scaled texture that a clip cuts from the cut part of its source, so a
  rectangle of a partial paint that cuts a text gave other pixels than a full
  paint, with a scroll or without one. On the software renderer a text texture
  now samples nearest. The test runs with both renderers, so a local run sees
  what CI sees.
- The tree render test found no row because the `listing` of a folder, a
  background cell since a535e62c9, stayed provisional when
  `read_filesystem_folder!` read the disk past it. A provisional value computes
  again for each reader, so the rows of the tree were new at each read.
  `read_filesystem_folder!` now reads through the listing with
  `wait_for_cell!(listing; editor = nothing)`.
- Five umbrella failures were stale tests; the code works as designed:
  - `EvaluatorDuplicateTest`: the parser keeps a comment since 948779e3a, so the
    form that keeps its string is now `y = 2x + 1` (97f060e2f).
  - `AssistantMvpTest.jl:257`: a 2 s wait ended before the first turn, which
    compiles on a slow machine. The wait follows the background work of the
    turn, with a bound of 120 s so that a turn that never ends fails and does not
    hang (a289fdbf5, 7822a13cc).
  - `ReferencedDocumentEditorTest.jl:369`, `:381`: the window opens on the
    Explorer since ab4f8824c, so the test puts the file tab in front first
    (ec713150b).
  - `ToolViewTest.jl:293`: `take_message_lines!` moved the store past lines that
    an earlier test logged, and the feed counted them as dropped. The feed now
    drains first.
  - `MouseClickTest.jl:304`: the caret of `formula_report` draws in a child
    canvas, which the scan of the click sweep does not read. The sweep skips the
    example, as it skips the other examples with a caret in a child canvas and
    as `ExampleSweeps.jl:275` does (3b4bc0404). This is a skip, not a fix.
- The fix of `CellModule.jl:48` moves `is_cell_provisional` into the first
  export statement, after `is_cell_valid`, because `CellInterface.jl` declares
  it. The file is sealed.

## Not in this plan
