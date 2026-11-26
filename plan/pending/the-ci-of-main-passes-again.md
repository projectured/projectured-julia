# The CI of main passes again

> **Status:** landed on `main` and pushed (`8ffaa313c`); two failures of other work remain in the CI. Approved by the owner, 2026-11-26 ("Yes" to "Do I fix these two faults of the
> CI?"). The session that pushed `306018039` fixes the red CI of `main`, as `CLAUDE.md`
> ("Main is green") says.

## 1. The faults

The CI run 45710705577 of `306018039` fails in five jobs, the same five as the run of
`28dfc9f93` before it. Two faults cause them.

1. **Static guards.** Two guards fail. `test/suite/exports.jl` gives one export violation:
   `source/kernel/gesture/GestureModule.jl:37: the names are not in the order that
   MouseGesture.jl defines them`. The fragment defines `DragOver`, `DragDrop` and
   `is_drag_leave` before `DragCancel`, but the export line names `DragCancel` first.
   `test/suite/documentation.jl` gives two dead links: `dragtracking.md:94` and `pane.md:291`
   link to `plan/pending/a-tab-moves-along-its-strip-and-between-windows.md`, which moved to
   `plan/done/` in `d85427334` on 2026-11-23. The two lines "no guide under documentation/
   names the slice" of that guard are lines for a person to read, not violations.
2. **The four jobs of `ProjecturedTest`.** They stop before a test runs: "Missing source file"
   for `AgentClientProtocol` and `ClaudeCodeACP`. `environment/all/Manifest.toml` names four
   packages beside the repository by `../../../../../workspace/<Name>.jl`. That path is right
   only at the neutral path of `julia-worktree` (`~/.cache/julia-work/projectured-julia`),
   where commit `b3c3b911c` resolved the environment. In CI, and in a checkout outside
   `bwrap`, it points to a folder that does not exist. `[sources]` of
   `environment/all/Project.toml` names the right path, `../../../<Name>.jl`.

## 2. The steps

- [x] 1. The export line of `GestureModule.jl` names the drag gestures in the order of
  `MouseGesture.jl`, and the two links name the plan in `plan/done/`. Check: the six guards of
  `test/suite/*.jl`, as the CI runs them, pass.
- [x] 2. `environment/all/Manifest.toml` names `AgentClientProtocol`, `AutoIntegration`,
  `ClaudeCodeACP` and `ModelContextProtocol` by the paths of `[sources]`. A `Pkg.resolve()`
  outside `bwrap` writes them. Check: each of the four packages loads from the worktree
  outside `bwrap`, and from its neutral path inside `bwrap`.

  Facts: the resolve changed the four paths and `project_hash`, nothing else. The paths are
  the ones of the manifest before `b3c3b911c`. Outside `bwrap`, each package loads, and Pkg
  calls the manifest current. Inside `bwrap`, each package loads through the link of the
  neutral folder, and Pkg calls the manifest not current: Pkg follows the link to the real
  folder, so it computes another path. So a `Pkg.resolve()` of `environment/all` inside
  `julia-worktree run` writes the wrong paths again; run it outside `bwrap`.
- [x] 3. The land on `main` (`0226dcd78`). No run of all the parts came before it: the change
  moves no code, the guards and the load are checked, and the CI of the push runs the parts.
- [x] 4. The push (`8ffaa313c`, the owner: "Yes"), then the CI run of the push, 45782552859:
  39 jobs pass, among them the static guards, `ProjecturedTest` and `ProjecturedTest
  (integration 1 of 3)`. Two jobs fail, each on one check that the fault of the load hid
  since 2026-11-24:
  - `ProjecturedTest (integration 2 of 3)`: `ApplicationTest.jl:2006`, an Alt+double click
    on a row of the Files pane selects no file (`nothing == ".../a.json"`).
  - `ProjecturedTest (integration 3 of 3)`: `ScrollWorkTest.jl:195`, one frame of a scroll
    of the Files pane makes 13 guards, against the bound 12.

## 3. Found during the work

- The two failures of step 4 are new failures of `main`, as the plan of the JSON views
  (`plan/done/the-editor-shows-a-json-file-through-its-views.md`) says. The CI of
  `23e85358a` (2026-11-23) passed both jobs; the CI of `aea74aa7a` (2026-11-24) failed the
  job of `test_application`. The 18 commits between them hold the land of D12 of the plan
  "a click reaches the innermost part in every view" (`0309f7d80`, `175de196e`,
  `97ed6f026`: the label of a node of a tree reads like the text of a control, and a part in
  the row of a file is the path of the file and then the step of the view).
