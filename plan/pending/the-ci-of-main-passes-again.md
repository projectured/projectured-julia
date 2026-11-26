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
- [x] 5. The two checks of the Files pane follow the rules of the tree (the owner, 2026-11-26,
  "yes, fix them"). Each check changes only where a probe shows that the view does what the
  plan of the click work decided, and the probe gives the numbers.

  Facts, from a probe in the worktree at `main` `5fe9fe8fa`:
  - The tree rule of the click plan (`cd006aa96`, landed as `0309f7d80`) says that on the
    label of a node "an Alt+click gives the caret at the character, an Alt+double click the
    label as a whole". On the row of `a.json`, an Alt+double click on the label selects
    `directory.elements[2]`, then the step of `FileSystemToWidgetTree` that ends in `.label`;
    on the icon, on the chevron column or beside the label it selects the file
    `directory.elements[2]`. The ring is off in each case. So `ApplicationTest.jl:2006`
    pressed where the rule now gives the label. The check now tests both: the label (the
    last step is the step of the view, and the path before it is the file `a.json`) and a
    press beside the label (the file).
  - Each row of a tree that shows a part of its input has two canvases for the marks of its
    label, the bands behind the label and the caret on top (`make_label_marks`). The window
    of the scroll draws 1530 canvases, and 528 when `_find_wtree_label_part` gives
    `nothing`: two for each of its 501 rows. A notch makes 18 to 26 records and 10 to 14
    guards, and 14 to 20 records and 6 to 8 guards with no label canvases, by a Revise edit
    in the same process. So each row that comes into view costs two records and two guards
    more, the cost of a label that reads the selection in a cell of its own, as a band does.
    The bound of `ScrollWorkTest.jl:195` goes from 30 records and 12 guards to 40 and 20,
    with the numbers in its comment. The comment keeps the cost of a record of the moved
    content, 306 records and 52 guards, which the probe did not measure again.
  - Check: `integration/test_scroll_work` 26 pass, 0 fail; `integration/test_application` 425
    pass, 0 fail, 3 broken (the 3 markers of `main`); the six guards pass.
- [ ] 6. The land, the push and the CI run of the push.

## 3. Found during the work

- The two failures of step 4 are new failures of `main`, as the plan of the JSON views
  (`plan/done/the-editor-shows-a-json-file-through-its-views.md`) says. The CI of
  `23e85358a` (2026-11-23) passed both jobs; the CI of `aea74aa7a` (2026-11-24) failed the
  job of `test_application`. The 18 commits between them hold the land of D12 of the plan
  "a click reaches the innermost part in every view" (`0309f7d80`, `175de196e`,
  `97ed6f026`: the label of a node of a tree reads like the text of a control, and a part in
  the row of a file is the path of the file and then the step of the view).
