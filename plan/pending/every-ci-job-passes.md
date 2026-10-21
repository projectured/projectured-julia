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
2. [ ] `test_sdl()` passes: the scroll paint of a window, and the tree render.
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
- The fix of `CellModule.jl:48` moves `is_cell_provisional` into the first
  export statement, after `is_cell_valid`, because `CellInterface.jl` declares
  it. The file is sealed.

## Not in this plan
