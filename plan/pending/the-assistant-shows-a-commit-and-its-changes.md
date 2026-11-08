# The assistant shows a commit and its changes

> **Kind:** plan · **Status:** a plan of 2026-11-05, at `main` `6b93bfcf3`. No step is done.
> · **Stands on:** [domain-inventory.md](../../documentation/design/domain-inventory.md),
> [navigator.md](../../documentation/package/platform/navigator/navigator.md),
> [link.md](../../documentation/package/platform/link/link.md),
> [editor.md](../../documentation/package/kernel/editor.md) (the background cell),
> [filesystem.md](../../documentation/package/platform/filesystem/filesystem.md) (the folder model),
> [assistant-api-consolidation.md](assistant-api-consolidation.md),
> [the-assistant-finds-its-names-by-reflection.md](the-assistant-finds-its-names-by-reflection.md)
> · **Sibling plans:** G1
> [the-assistant-starts-programs-as-tasks.md](../done/the-assistant-starts-programs-as-tasks.md), G4
> [a-tab-shows-the-file-that-a-program-rewrites.md](a-tab-shows-the-file-that-a-program-rewrites.md)

This plan closes the gap G8 of the inet-cpp plan `plan/pending/ieee80211-chart-baseline-evolution.md`,
§9.3. The owner decided on 2026-11-05 to close G1, G3, G4, G5 and G9 first, then G8.

The use case: the assistant finds the commits of `inet-cpp` that change 17 chart pictures, and it
explains each change from the code change. On the page of an event, the person clicks the commit.
The person then sees its subject, message, author, date, changed files and the diff of each file.
From a line of a diff, the person opens the file at that revision. A checkout is not in this plan:
G1 runs `git checkout` and `git worktree add` as a program task, and the views here need no checkout.

## 1. What exists

The assistant checked each row on 2026-11-05, on main `6b93bfcf3` of projectured-julia and on main
`a1dfa5af3` of omnet-julia.

| Thing | Where | State |
| --- | --- | --- |
| git in projectured-julia | `source/tool/builder/PackageRelease.jl:362`, `:544` | Only the release tool runs git. `source/tool/builder/ProjecturedProgram.jl:91` names `LibGit2_jll` for the build of the binary. No slice reads a repository. |
| The slice `versioning` | `VersionedObject`, `source/platform/versioning/VersioningDocument.jl:63` | A list of versions inside a document. It knows no git. |
| git in omnet-julia | `source/legacy/simulator/LegacyComparisonTask.jl:450`, `:481`; also `:422`, `:435`, `:553` | `make_worktree_project` and `make_git_worktree_step` serve the comparison tests. Three more calls run `git rev-parse` and `git rev-list` on the task of the caller. No name carries the mark. |
| A text diff | none | No diff algorithm, no hunk document and no diff view exist in either repository. The search covered "diff", "hunk", "Myers" and "longest common". |
| LibGit2 | Julia 1.13.1 standard library | A new process does not load it, so the exception of the owner for `FileWatching` does not apply. Its API has `GitDiff` and `diff_tree`, but no patch text, no hunk lines and no worktree. |
| A link | `source/domain/markdown/MarkdownLinkTarget.jl:16-17`, `:82-91`; `NavigatorToWidget.jl:466-478`; `NavigatorPageOpen.jl:176-187` | A link names a section of the page, a file beside the page, or an address with a scheme. A `file:` address opens a tab with a navigator. Each other address goes to the program of the system. No link names a document that is no file. |
| A `git://` address | `find_web_url`, `source/platform/link/UrlInterface.jl:194-198` | Each scheme with `//` is an address outside the editor. `git://host/repo` is also the real protocol of the git daemon. |
| The open of a document | `OpenPageOperation.jl:36-47`; `NavigatorToWidget.jl:460-462`; `NavigatorPageOpen.jl:39-54` | An open that carries a document makes a visit of the navigator for `:here`, and else a new tab with a navigator. It moves no selection. |
| The open of a file at a line | `OpenFileOperation.jl:24-31` | The operation has a path and two wraps. It has no place in the file. |
| Outside state off the loop | `make_background_cell`, `source/kernel/editor/BackgroundCells.jl:181-232`; `FileSystemDocument.jl:303-330`, `:417-436` | A print records a demand, a task reads after the frame, and `apply` stores the answer by an operation. Undo does not record it. A folder reads its entries so. |
| The rows that show | `get_visible_height`, `source/platform/layout/LayoutToGraphics.jl:1177-1191` | A part builds only the rows that show. |
| The names of a domain | `collect_marked_api`, `source/kernel/tool/AssistantMark.jl:48`; `make_editor_api`, `source/platform/application/Application.jl:361-362`; `register_assistant_api!`, `AssistantApi.jl:32`; `WorkflowModule.jl:74` | The line `For the assistant.` in the docstring of a name offers it, and a mark on a type offers its subtypes. `make_editor_api` reads the marks of the loaded modules, so a window offers the names of each package that it loads. `register_assistant_api!` gives only the sentence of a domain for the system text, as the workflow domain does, and the names of a foreign package. |
| omnet_ide | omnet-julia `package/OmnetIde/src/OmnetIde.jl:58-74`, `package/OmnetIde/Project.toml:13-58, 60-84` | The IDE imports each Projectured domain by name, and lists it in `[deps]` and in `[sources]` with a path. A new package does not reach the IDE with no change in omnet-julia. |
| The native rule | `source/platform/assistant/AssistantDocument.jl:17-23` | On main, step 6 of the reflection plan (`97dee7cef`) put the rule into `EDITOR_SYSTEM` (`source/platform/application/Application.jl:406`), where it says "NEVER read files or run programs directly in code. Read a file with the verbs of the editor, such as `open_file!` and `read_document_file`." A model there can not run `git show` itself. `DEFAULT_ASSISTANT_SYSTEM` ends with the same rule. |
| The seals | `SEALING.md` | The inventory covers `source/kernel/` only. No step of this plan changes a kernel file. |

## 2. What the code lacks

1. No document shows a commit, the change of one file, or a file at a revision.
2. No link names a commit, so the event page can not lead to the code.
3. No verb answers the commits of a range or the text of a commit for a model.
4. omnet_ide loads no package that reads git.

## 3. Design

### 3.1 Where git lives

A new package `ProjecturedGit`, with its code in `source/domain/git/` and the module `GitModule`.
It has the triad of a domain: `ProjecturedGit`, `ProjecturedGitExample` and `ProjecturedGitTest`.
It runs the `git` program with a Base `Cmd`, so its `[deps]` are the kernel, the platform and
`ProjecturedPrecompile`. AutoIntegration loads it with `Projectured`, and `ProjecturedAll` holds it.
A machine with no `git` loads the package, and each view shows the failed read.

### 3.2 The documents

The root type is `GitDocument`. Each document holds the absolute path of its repository.

| Document | It holds | Its read |
| --- | --- | --- |
| `GitCommit(repository, revision)` | the full hash, the parents, the author, the date, the subject, the message, and `changes`, a `CellVector` of `GitFileChange` | one `git show` with a fixed `--format`, `--raw`, `--numstat`, `-z`, `-M` and `--diff-merges=first-parent` |
| `GitFileChange` | the kind (`:added`, `:deleted`, `:modified`, `:renamed`, `:copied`, `:type_changed`), the old and new path, the old and new revision, the counts of added and removed lines, and `hunks` | `git show --format= --patch -M --no-ext-diff --no-textconv --diff-merges=first-parent <hash> -- <old path> <new path>` |
| `GitDiffHunk` | the start and count on each side, the text after `@@`, and its lines | stored by the read of its change |
| `GitDiffLine` | the kind (`:kept`, `:removed`, `:added`), the text, the old and the new line number | stored by the read of its change |
| `GitFileRevision(repository, revision, path; line = nothing)` | the text of the file and the line to show | `git cat-file blob <revision>:<path>` |

A hunk and a line are immutable values. The read stores them one time.

### 3.3 How a document reads git

Each read is a background cell, and the cell is the store (D8). A print of the document records a
demand, and a task runs `git` after the frame. The cell keeps the answer. A view asks the cell
whether the answer is still to come (`is_cell_provisional`), whether its work runs (the `working`
cell), or whether the work failed, which a read of the cell throws with the words of git. A git
document has no read state of its own, no apply operation and no `nothing` placeholder. No reader,
printer or computation runs `git`.

- **A commit reads one time.** Its hash names content that never changes. The read resolves a
  revision name, such as `v4.7.0`, to the full hash, and the document keeps the hash. No watch.
- **What a frame shows, a task reads.** A commit makes one `BackgroundSource`, and its changes share
  it. A scroll that shows three new files starts one task that reads the three diffs.
- **Keep what the producer knew.** The read of the commit knows the paths, the kind, the counts
  and both revisions of each change. The change stores them, so its diff read searches nothing.
  The diff knows the line numbers, so the open of a file at a line carries them.
- **The program runs alike everywhere.** Each call is `git -C <repository> --no-pager
  -c core.quotePath=false`, with `LC_ALL=C`, `GIT_OPTIONAL_LOCKS=0` and `GIT_TERMINAL_PROMPT=0`
  added by `addenv`. A read by hash takes no lock, so a checkout in a worktree can run at the
  same time.

### 3.4 What the person sees and does

- **The page of a commit.** The title of the tab is the short hash and the subject. The page shows
  the author, the date, the parents and the message. Then a list of the changed files with their
  kind and counts. Then the diff of each file, as `git show` writes it. The page scrolls itself.
  It builds only the rows that show, and a file reads its diff only when its rows show.
- **A diff.** Each row shows the old number, the new number, the sign and the text. A removed row
  and an added row get the colors of a `GitTheme`. A binary file shows one row that says so.
- **A file at a revision.** Each row shows the number and the text. The page shows the line of the
  open near its top and marks it.
- **The gestures.** On a line of a diff, Ctrl+click opens the file at that line, at the revision of
  that side. It opens as a visit in the same navigator. Ctrl+Shift+click opens a new tab. A removed
  line opens the parent, and a kept or added line opens the commit. On a file row, Ctrl+click opens
  the change of the file as a page. A tooltip of a line gives both numbers and the revision. These
  are the gestures of a Markdown link in the source view. An open moves no selection
  (`NavigatorToWidget.jl:443-445`), and Back returns to the commit.

### 3.5 The link to a commit

A page names a commit with the address form `git+file://<repository>#<revision>`, and a file at a
revision with `git+file://<repository>#<revision>:<path>`. The part after `#` is the syntax of git.
npm and pip use `git+file:` for a repository in a local folder.

    [3fa2c1d](git+file:///home/projectured/workspace/inet-cpp#3fa2c1d)

The link slice gets the generic function `find_url_document(url) -> document or nothing`. It
dispatches on the scheme, `find_url_document(::Val{Symbol("git+file")}, url)`, and the default
answers `nothing`. The git package adds the method. The method makes a document that reads nothing.
Two places of the navigator slice ask it before the program of the system.
`_follow_navigator_target` (`NavigatorToWidget.jl:471`) makes a visit in the same navigator. The
evaluation of `OpenUrlOperation` (`NavigatorPageOpen.jl:171`) opens a new tab. So each domain whose
links name an address gets the form, with no change in that domain. This seam is new, and the
owner accepted it on 2026-11-05 (D5).

### 3.6 The verbs of the assistant

Four names: the types `GitCommit` and `GitFileRevision`, and two verbs. Each verb runs `git` in the
code of the caller, as `read_document_file` reads a file.

    find_git_commits(repository; revisions = "HEAD", paths = String[], first_parent = false,
                     limit = 200) -> Vector{GitCommit}
    describe_git_commit(commit; paths = nothing, context = 3) -> String

`find_git_commits` runs one `git log` and stores the hash, the parents, the author, the date and
the subject in each commit. A range that git refuses throws an `ArgumentError` with the words of
git. `describe_git_commit` answers the header, the message, the file list and the diff of each file
in `paths`. It writes them as `git show` does, with `context` lines around each hunk, in a `String`.

    commits_1 = find_git_commits("/home/projectured/workspace/inet-cpp"; revisions = "fd436d7..v4.7.0",
                                 paths = ["src/inet/linklayer/ieee80211"], first_parent = true)
    text_1 = describe_git_commit(commits_1[3]; context = 10)
    tab_1 = open_pane!(commits_1[3]); show_pane!(tab_1)

A commit is also an element of a workflow node: `pred_arguments` writes the repository and the hash,
so a `.pred` file holds `GitCommit("/home/…/inet-cpp", "3fa2c1d…")`.

**How the names reach the assistant.** The docstring of `GitDocument` and the docstrings of the two
generic functions end with `For the assistant.`. The mark on the root type offers the five document
types. The mark is the only rule: no list names the four names, and `GitModule` registers nothing.
`make_editor_api` reads the marks of the loaded modules, so the Projectured window offers the four
names while `ProjecturedGit` is loaded. omnet_ide offers them after `OmnetIde` imports
`ProjecturedGit`. That change is in omnet-julia, and step 7 makes it (open question 3). Each
docstring is on `function f end` or on the type, in the form that `test_assistant_documentation`
checks.

## 4. Decisions

The owner decided D1, D5 and D8 on 2026-11-05. The assistant proposed D2, D3, D4, D6 and D7.
A decision that the assistant proposed counts as approved when the owner approves this plan for
implementation (the owner, 2026-11-05). The owner can name one to see it first.

- **D1. A domain package that runs the git program.** The owner decided this on 2026-11-05 (option
  A). The adapter rule is for a new Julia dependency, and this package has none. If a second source
  comes, such as LibGit2 or a remote server, the calls of `git` move behind a seam, as the database
  domains and the ODBC adapter do. It adds no Julia dependency, and the diff in
  the editor equals the diff of a terminal. Rejected: an adapter on LibGit2, which is a new
  dependency, and whose API lacks the patch text, so it needs calls into the C library. Rejected: a
  platform slice, because a window that shows no repository must not load git code.
- **D2. git computes the diff.** The line numbers then equal the lines of the file at each revision.
  Rejected: a diff algorithm in Julia over the two texts, which can differ from git (the indent
  heuristic, `diff.algorithm`). Two files outside a repository take `git diff --no-index` later.
- **D3. The hunk and line documents stay in the git domain.** The domain inventory says that two
  domains that need one thing make a framework. A second producer moves them to a platform slice.
- **D4. Make, place and show stay apart.** The verbs answer documents. `open_pane!` places a tab,
  and `show_pane!` shows it. Rejected: `open_commit!(repository, commit)`, which joins make and place
  (assistant-api-consolidation.md §2a).
- **D5. The link form `git+file:` with a method of `find_url_document`.** The owner decided this on
  2026-11-05 (open question 2), both the form and the new generic function. Rejected: `git:`, which
  collides with `git://`. Rejected: a Markdown field, because Markdown must not know git. Rejected: a
  registry of schemes on the editor, which needs a new hook into each editor.
- **D8. The background cell is the store of a read.** The owner decided this on 2026-11-05 (open
  question 4, option B). A commit never changes, so its answer is final after one read and nothing
  merges into documents that exist. The cell already says whether its answer waits, runs or
  failed. The owner's reason of 2026-10-18: one general mechanism, transparent to its consumers,
  and no hand-made read. An `apply` stays only for outside state that changes and whose answer must
  merge into documents that exist, as a folder does. Rejected: `ApplyGitReadOperation` and a read
  state field `:unread`, `:reading`, `:read`, `:failed` in each git document.
- **D6. A merge shows its change against its first parent.** The open of a file then has one old
  revision. Rejected: the combined diff of `git show`, whose lines have no single old number.
- **D7. A model reads a commit with `describe_git_commit`.** The rule of the window on main is in
  `EDITOR_SYSTEM` (`Application.jl:406`) since step 6 of the reflection plan (`97dee7cef`), and it forbids a program that runs in code. Rejected: a model that runs
  `git show` in the code of `execute_julia_code`.

## 5. Steps

Each step runs in a worktree and ends with one commit. `workspace/bin/bounded-run` runs each test: a
test under `test/domain/git/` in `package/ProjecturedGitTest`, one under `test/platform/` in
`package/ProjecturedPlatformTest`, one under `test/projectured/` in `environment/all`.

1. **The package and the parse.** The three packages, `GitModule` and the five document types. The
   pure functions `parse_git_commit_text`, `parse_git_diff_text` and `parse_git_log_text`. The new
   `documentation/package/domain/git/git.md`, whose header says `**For:** developer` (the documentation
   check needs the field since `72a7debd3`), the tables of `domain-inventory.md` and
   `package-rules.md`, `ProjecturedAll`, `PROJECTURED_APPLICATION_IMPORTS`, `environment/all`,
   `ProjecturedTest` and the table `[auto-integration]`. Test: the new `test_git_parse()`
   (`test/domain/git/GitParseTest.jl`) on fixed texts with no git process. It asserts each field and
   each line number of two hunks, a rename with a change, an add and a delete. It also covers a
   binary file, the line `\ No newline at end of file`, and a path with a space and a letter outside
   ASCII. Then `test_git_layering()`, `test_package_graph()`, `test_repository()` and `test_builder()`.
2. **The reads.** The background cells as the store of each read (D8), and `pred_arguments`.
   `make_git_example_repository(folder)` in the example package makes a repository with fixed names
   and dates, so each hash is known. Test: the new `test_git_reading()` (`GitReadTest.jl`), with
   `wait_for_cell!(cell; editor = nothing)`. It asserts the exact hash, subject, message, author,
   date and parents. It asserts the kind, paths and counts of each change, and the hunks of a modified
   file. It covers the text of a file at a revision, a merge, and a root commit. An unknown
   revision and a folder with no repository make a read of the cell throw the words of git.
   `print_pred_text` of a commit gives `GitCommit("<folder>", "<hash>")`.
3. **The views.** `GitCommitToWidget`, `GitFileChangeToWidget`, `GitFileRevisionToWidget`, `GitTheme`,
   the natural rows and the tab titles. An example in `example/projectured/DomainExamples.jl`. Test:
   the new `test_git_views()` (`GitViewTest.jl`) in an editor with the console backend. It asserts the
   text of the header row, a file row, a hunk row, and a removed and an added line with their
   numbers. A diff of 5000 lines builds no more than the rows that show and a margin. A file at a
   revision shows its marked line in its first rows. A failed read shows its reason. Then
   `test_domain_examples()`.
4. **The gestures.** The rules of §3.4 and their descriptions, which the command palette lists. Test:
   the new `test_git_gestures()` (`GitGestureTest.jl`) in a real `Editor` with a navigator on a
   commit. Ctrl+click on a removed line visits the file at the parent at its old line, and Back
   returns. Ctrl+Shift+click on an added line opens a new tab at the new line. Ctrl+click on a file
   row visits its change. The selection of the person stays, and undo records nothing.
5. **The link.** `find_url_document` in `UrlInterface.jl`, its two calls in the navigator slice, and
   the git method for both forms. Test: `test_link()` (`test/platform/link/LinkTest.jl`) and
   `test_open_page_operation()`, with a scheme that the test defines. `:here` makes a visit, and
   `:new_tab` makes a tab. An unknown scheme still goes to the program of the system. Then
   `test_navigator()` and `test_markdown_link_gestures()`. A new testset in `test_git_gestures()`
   clicks both forms on a Markdown page, and a bad hash shows a failed read and throws nothing.
6. **The verbs.** `find_git_commits`, `describe_git_commit`, the docstrings and the marks. Test: the new `test_git_verbs()` (`GitVerbTest.jl`). It asserts the hashes in order for
   `revisions`, `paths`, `first_parent` and `limit`, and the header facts of each commit with no read.
   It asserts the `ArgumentError` of a bad range, and the text of `describe_git_commit` with `paths`
   and `context = 10`. The four names carry the mark `For the assistant.`, so `search_api` finds
   them while the package is loaded. Then
   `test_assistant_documentation()`, `test_assistant_verbs()` and `test_referenced_document_editor()`.
7. **The workload and the live check.** `@compile_ahead` with `run_natural_rows_workload(GitModule)`.
   Then a live check in the Projectured window through its MCP connection. It opens a commit of
   `inet-cpp` with more than 2000 changed lines and scrolls to its end. It clicks a removed line with
   Ctrl, and a `git+file:` link of a Markdown page. `take_picture` shows each view. In omnet-julia,
   in the same landing, `OmnetIde` gets `import ProjecturedGit` and the line in `[deps]` (and the path line
   in `[sources]`, see the risks), then
   `Pkg.resolve()` and `Pkg.precompile()` run, and the same check runs in omnet_ide. Then this plan
   moves to `plan/done/`.

## 6. Risks

- **The navigator change reaches each link.** Step 5 runs `test_navigator()`, `test_link()` and
  `test_markdown_link_gestures()`. An unknown scheme must still reach the program of the system.
- **A walk can enter many lines.** `search_documents` and the selection walk must not enter the
  lines of a large diff. The hunks are plain values or opaque to a walk, and step 3 asserts it.
- **A machine with no git.** Each view shows the failed read. The test packages need git, as a
  checkout of the repository already does.
- **The cost of a process.** Each demanded read starts one `git` process of a few milliseconds. One
  task reads all the files that one frame shows. Step 7 measures a scroll over a large commit.
- **The rank of `search_api` can move**, because the new docstrings name commits and files. Step 6
  runs `test_referenced_document_editor()` and `test_assistant_verbs()`.
- **The rebase of `reflection-api`.** This plan adds no entry to a list, so only the marks meet that
  branch. Step 6 of the branch is on main (`97dee7cef`) and holds the rule in `EDITOR_SYSTEM`, and D7 needs no change
  of code for it.
- **The change in omnet-julia is three lines.** `package/OmnetIde/Project.toml` holds a `[sources]`
  path line for each Projectured package, so a new package needs that line beside `import
  ProjecturedGit` and the line in `[deps]`. Step 7 adds all three.

## 7. Later work

- A repository as a page: the log, the branches and the tags, and a view that follows a branch.
- The line in the current file in the folder of the repository. It needs an open of a file at a
  place, which `OpenFileOperation` lacks, and a map of the line through the later commits.
- A diff of two files outside git (`git diff --no-index`), and a `.diff` file type with a reader.
- The colors of a file at a revision by the domain of its extension; blame; a line in a link address.
- A commit as a link in a cell of a roster (G6).

## 8. Open questions for the owner

1. **The new package (D1).** Answered by the owner on 2026-11-05: the domain package (D1). The
   question was: can `ProjecturedGit` be a domain package in `source/domain/git/` that
   runs the git program? The other choice is an adapter in `source/adapter/git/`. The assistant
   recommends the domain package, because it has no Julia dependency.
2. **The link form and the seam (D5).** Answered by the owner on 2026-11-05: yes to both (D5). The
   question was: can a link name a commit as
   `git+file://<repository>#<revision>`? Can the link slice get `find_url_document`, with one method
   for each scheme? The method table holds
   no state of a session. The assistant recommends both.
3. **The change in omnet-julia.** Decided by the assistant on 2026-11-05: step 7 makes the small
   change in omnet-julia in the same landing, as G9 step 3a does, and no sibling plan is written.
   The question was: `OmnetIde` must import `ProjecturedGit`. That needs a plan file in
   omnet-julia, which this plan does not write. Can the assistant write it, with step 7 as its test?
4. **The read operation.** Answered by the owner on 2026-11-05: no new operation, the background
   cell is the store (D8). The question was: `ApplyGitReadOperation` is a new operation type in the form of
   `ApplyFolderListingOperation`. Is that form right for each read of outside state? The assistant
   recommends it.
5. **The order.** Answered: Steps 1 to 4 landed on main `2bbc18fb5` (omnet-julia `991a89b4f`) on 2026-11-05; both are in `origin/main`. The owner decided the order on 2026-11-05: steps 1 to 4 of `reflection-api` land on main first,
   after a rebase, its tests and the approval of the owner. Then this plan starts from main and
   uses only the mark `For the assistant.`; it adds no name to a hand-kept list.
