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

1. [ ] The static guards pass.
   - `arguments.jl`: `PivotCrossTable.jl:488`, `:491` (`find_pivot_value`),
     `TaskGroupDocument.jl:379` (`rerun_task_group_document!`).
   - `exports.jl`: `CellModule.jl:48` (sealed 🔒, needs the owner's permission),
     `FileChangeModule.jl:35`, `BuilderModule.jl:35`.
   - `style.jl`: `Application.jl:472`, `FilePageToWidget.jl:72`, `TextDocument.jl:438`.
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

## Not in this plan
