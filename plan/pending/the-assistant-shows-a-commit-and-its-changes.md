# The assistant shows a commit and its changes

> **Kind:** plan · **Status:** a plan of 2026-11-05, at `main` `6b93bfcf3`. Step 2a and the export of
> the parse were added on 2026-11-13 (D9). No step is done.
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

A second user is the baseline catch-up walk in omnet_ide (omnet-julia
`plan/pending/the-ide-follows-the-baseline-catch-up.md` §5.3). Its walk map shows all the commits of a
range and marks the commits that touch a list of paths. The map updates when `git fetch` moves
`origin/master`. Its step view parses the patch of each experiment, which is the output of `git diff`
and not a commit, and shows the hunks of a commit with marks of its own.

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
5. No document holds the commits of a range, so no view can show a range that moves.

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
| `GitCommitRange(repository, revisions; paths = String[])` | `commits`, a `CellVector` of `GitCommit` with the header facts of the log, and the folders that hold the refs of the range | `git log` with a fixed `--format`, `-z`, the revisions and `--` with the paths (D9) |

A hunk and a line are immutable values. The read stores them one time.

`parse_git_diff_text(text) -> Vector{GitDiffFile}` reads the output of `git diff` as it is, so a
patch needs no commit header. A `GitDiffFile` is an immutable value: the old and the new path, the
kind, `is_binary` and its hunks. The read of a `GitFileChange` takes the one file of its patch. The
package exports `parse_git_diff_text`, `GitDiffFile`, `GitDiffHunk` and `GitDiffLine`, so another
domain can parse a patch of its own and compare its hunks with the hunks of a commit.

### 3.3 How a document reads git

Each read is a background cell, and the cell is the store (D8). A print of the document records a
demand, and a task runs `git` after the frame. The cell keeps the answer. A view asks the cell
whether the answer is still to come (`is_cell_provisional`), whether its work runs (the `working`
cell), or whether the work failed, which a read of the cell throws with the words of git. A git
document has no read state of its own, no apply operation and no `nothing` placeholder. No reader,
printer or computation runs `git`.

- **A commit reads one time.** Its hash names content that never changes. The read resolves a
  revision name, such as `v4.7.0`, to the full hash, and the document keeps the hash. No watch.
- **A range reads again when a ref moves (D9).** A range is outside state that changes, so it
  reads as a folder reads: its `apply` merges the answer by hash, and a holder watches the folders
  of its refs. Each commit of a range is a `GitCommit` and reads its changes as any commit does.
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
- **D9. A range of commits is a document that reads like a folder.** The owner approved this on
  2026-11-13 (open question 6). A range names refs, and a ref moves, so the commits of a range are
  outside state that changes. D8 leaves that case to an `apply`. The merge by hash keeps the
  document of each commit that stays, so a view keeps its marks and its selection. The paths go to
  git after `--` as they are, so the rules of a pathspec are those of git, such as
  `:(exclude)*.rst`. A view that needs two lists, such as all commits and the commits that touch
  some paths, holds two ranges and compares the hashes. Rejected: `find_git_commits` with no limit
  in the code of a view, which does not update. Rejected: a flag on each commit from the paths
  that it changes, which needs a match of pathspecs in Julia that can differ from git.
- **D6. A merge shows its change against its first parent.** The open of a file then has one old
  revision. Rejected: the combined diff of `git show`, whose lines have no single old number.
- **D7. A model reads a commit with `describe_git_commit`.** The rule of the window on main is in
  `EDITOR_SYSTEM` (`Application.jl:406`) since step 6 of the reflection plan (`97dee7cef`), and it forbids a program that runs in code. Rejected: a model that runs
  `git show` in the code of `execute_julia_code`.

## 5. Steps

Each step runs in a worktree and ends with one commit. `workspace/bin/bounded-run` runs each test: a
test under `test/domain/git/` in `package/ProjecturedGitTest`, one under `test/platform/` in
`package/ProjecturedPlatformTest`, one under `test/projectured/` in `environment/all`.

1. **The package and the parse.** **Done on 2026-11-13.** The three packages, `GitModule` and the five document types. The
   pure functions `parse_git_commit_text`, `parse_git_diff_text` and `parse_git_log_text`, and the
   value `GitDiffFile` (§3.2), which the package exports with the hunk and the line. The new
   `documentation/package/domain/git/git.md`, whose header says `**For:** developer` (the documentation
   check needs the field since `72a7debd3`), the tables of `domain-inventory.md` and
   `package-rules.md`, `ProjecturedAll`, `PROJECTURED_APPLICATION_IMPORTS`, `environment/all`,
   `ProjecturedTest` and the table `[auto-integration]`. Test: the new `test_git_parse()`
   (`test/domain/git/GitParseTest.jl`) on fixed texts with no git process. It asserts each field and
   each line number of two hunks, a rename with a change, an add and a delete. It also covers a
   binary file, the line `\ No newline at end of file`, and a path with a space and a letter outside
   ASCII. A patch of three files from `git diff`, with no commit header, gives three `GitDiffFile`.
   Then `test_git_layering()`, `test_package_graph()`, `test_repository()` and `test_builder()`.
   What the implementation found:
   - Step 1 makes two packages, `ProjecturedGit` and `ProjecturedGitTest`. The example package comes
     in step 2 with `make_git_example_repository`, its first function. The document types also come
     in step 2, because each field of a document is the cell of its read (D8).
   - Step 1 gives five plain immutable values, not documents: `GitCommitHeader`, `GitFileSummary`
     (one changed file of a commit, from `--raw` and `--numstat`), `GitDiffFile`, `GitDiffHunk` and
     `GitDiffLine` (with `has_line_end`). The package exports them and the three parse functions.
     `parse_git_commit_text` answers `(header, files)` and checks that the two lists of git name
     the same files.
   - The forms of git 2.53: `git log -z` ends each field and each commit with a NUL byte.
     `git show -z --raw --numstat` puts a line end between the header and the raw entries. A path
     with a space ends with a tab on the lines `---` and `+++`. The default `core.quotePath` quotes
     a byte outside ASCII as three octal digits. A change of the mode only, a binary file and an
     empty file have no lines `---` and `+++`, so the parse takes the path from the length of the
     line `diff --git`.
   - The parse needs the prefixes `a/` and `b/`. So the reads of step 2 pass `--src-prefix=a/` and
     `--dst-prefix=b/`, and the settings `diff.noprefix` and `diff.mnemonicPrefix` of a person
     change nothing.
   - `ProjecturedBuild` also imports the package, because `test_builder()` asserts that
     `PROJECTURED_APPLICATION_IMPORTS` equals the domains of `ProjecturedAll`.
   - Results: `test_git()` 45 pass; the naming guard passes; `test_package_graph()` 559 pass;
     `test_repository()` 616 pass; `test_builder()` 613 pass and 1 error, which main has since
     `2f118e96c` (the release copy of `CellStruct.jl:39`); `test_documentation()` fails the same 4
     checks as main (private names in other documents).
2. **The reads.** **Done on 2026-11-13.** The background cells as the store of each read (D8), and `pred_arguments`.
   `make_git_example_repository(folder)` in the example package makes a repository with fixed names
   and dates, so each hash is known. Test: the new `test_git_reading()` (`GitReadTest.jl`), with
   `wait_for_cell!(cell; editor = nothing)`. It asserts the exact hash, subject, message, author,
   date and parents. It asserts the kind, paths and counts of each change, and the hunks of a modified
   file. It covers the text of a file at a revision, a merge, and a root commit. An unknown
   revision and a folder with no repository make a read of the cell throw the words of git.
   `print_pred_text` of a commit gives `GitCommit("<folder>", "<hash>")`.
   What the implementation found:
   - The documents: `GitDocument`, `GitCommit(repository, revision; header = nothing)`,
     `GitFileChange` and `GitFileRevision(repository, revision, path; line = nothing)`, with
     `GitException`, whose `message` holds the words of git. A field such as `header`, `changes`,
     `hunks` or `text` is the cell of the read, and `reading` is the `working` cell of the read.
   - A background work reads no document and answers values. So the read of a commit answers the
     header and a `GitFileSummary` for each file, and `changes` is a computation that makes a
     `GitFileChange` for each. The answer of a commit is final, so the computation runs one time,
     and each change keeps its document. A `header` that a log gave is a plain cell, and then the
     read gives only the changes.
   - One `BackgroundSource` serves a commit and its changes: an input is a tuple whose first
     element names the read (`:commit`, `:patch`, `:file`). A work that throws fails the reads of
     its batch, as each background cell does.
   - The read of a commit names `<revision>^{commit}`, so an annotated tag gives its commit. Each
     read puts `--end-of-options` before a revision, so a revision that starts with `-` is no
     option, and the read of a patch takes `--literal-pathspecs`, so a path that starts with `:`
     names a file. Each run also sets `color.ui=false` and `log.showSignature=false`.
   - `ProjecturedGitExample` holds `make_git_example_repository`. It runs git with no global and no
     system configuration. Its first two commits have the hashes of the fixed texts of step 1.
   - A `.pred` file writes a commit as `GitCommit("<folder>", "<hash>")`, one argument on each
     line, and the revision while no read gave the hash. `GitFileChange` has no `pred_arguments`:
     the read of its commit makes it, and step 4, which opens a change as a page, decides how such
     a page is saved.
   - Results: `test_git()` 86 pass (the read test 41); the naming guard passes;
     `test_package_graph()` 562 pass and `test_repository()` 619 pass with the example package; the
     documentation report is the same as on main.
2a. **The commits of a range (D9).** **Done on 2026-11-13.** `GitCommitRange` and `ApplyGitCommitRangeOperation`. The read
   is a background cell of the repository, the revisions, the paths and `read_count`. It answers
   the commits in the order of `git log`, with no cap, and the folders that hold the refs of the
   range: the folder of each loose ref that the revisions name, such as `refs/remotes/origin` for
   `origin/master`, the common git folder for `packed-refs`, and the git folder of the worktree for
   `HEAD`. The apply merges by hash and stores the folders. A holder acquires the range, and while
   it holds the range, `watch_folder!` watches the folders that the last read stored. A change
   raises `read_count`, so a part that shows the range asks again. The release stops the watch and
   keeps the commits. Test: the new `test_git_range()` (`GitRangeTest.jl`) on the example
   repository. It asserts the hashes of a range in order, and of the same range with a path and with
   an `:(exclude)` pathspec. In an editor with a `FileChangeStore`, it makes a new commit on the
   branch, moves a remote ref with `git update-ref`, and moves it again after `git pack-refs --all`.
   After each change the range reads again, the new hash comes first, and each `GitCommit` that
   stays is the same document. An unknown revision makes a read of the cell throw the words of git.
   What the implementation found:
   - The owner chose to build step 3 before step 2a, so 2a came after the views.
   - `GitCommitRange` holds `repository`, `revisions`, `paths`, `commits`, `folders`, `read_count`,
     `reading` and `listing`, the background cell of the read. `commits` is a computation that reads
     `listing` and answers the vector that the apply writes, so any part that shows the commits
     records a demand for the read, and the commits stay while a new read runs or after a read
     failed. The read of `listing` throws the words of git. A walk reads neither field.
   - One read runs `git log -z` of the revisions and the paths, `git rev-parse --path-format=absolute
     --git-dir --git-common-dir`, and `git rev-parse --symbolic-full-name` of the revisions, which
     names the refs. A ref of a worktree (`refs/bisect`, `refs/worktree`) is in the git folder of the
     worktree, every other ref in the common folder. A ref that `packed-refs` holds takes the nearest
     folder above its own that exists. `rev-parse` takes no `--end-of-options`, so a revision that
     starts with `-` does not go to it; the log reads it after `--end-of-options` and refuses it.
   - `ApplyGitCommitRangeOperation` merges as `_merge_range_commits!`: the commits that stay at the
     start and at the end keep their documents, and the rest is one `ReplaceReferencedValueOperation`
     of the vector. It moves the watch to the new folders while `is_document_held`.
   - A range has a page too, which the plan did not name: the owner asked for a picture of a range,
     and the natural renderer, with no page for the range, fell back to its generic printer and did
     not end in 9 minutes. The owner approved a page in the form of the others on 2026-11-13, "but
     the order of fields per row should follow gitk", then "the hash should be added", then "hash
     before commit message but shortened". A first version made the rows a git text with columns in
     spaces; the owner asked "why is it not a table widget or a grid layout?", and approved a roster.
     So `GitCommitRange` holds `table`, the arrangement of a roster whose source is
     `CollectionItems` of its `commits`, in the form of the background work log. The columns are the
     facets `hash` (short), `subject`, `author` (with the e-mail address) and `date` of `GitCommit`.
     `GitCommitRangeToWidget` draws a line and the table, and its reader keeps the arrangement and
     opens a row at its place (`keep_held_arrangement`, `retarget_held_row_open`). The table builds
     only its shown rows, filters and sorts in its bar, and the hash of a row opens the commit.
   - The list of the changed files of a commit is a roster too (the owner, 2026-11-13: "Yes" to the
     table of the files before step 4). `GitCommit` holds `table`, a roster of its `changes` with the
     facets `path`, `change`, `added` and `removed` of `GitFileChange` and the shares 6:1:1:1; the
     path of a row is the link to the page of the change. The page of a commit is a grid: the header
     as labels, the table (a third of the height below it), the diffs in a pane (the rest). The text
     of a commit holds only the diffs. The table of a range has the shares 1:5:3:2.
   - Results: `test_git()` 150 pass with the table of the files of a commit (before it: 148 with the table of a range (before it: 141, the range test 22, in an editor with a `FileChangeFeed`: a
     remote ref moves, the refs are packed and the ref moves again, a commit lands on the branch);
     `test_repository()` 619 and `test_package_graph()` 562 pass; the naming guard passes; the
     documentation report is the same as on main.
3. **The views.** **Done on 2026-11-13.** `GitCommitToWidget`, `GitFileChangeToWidget`, `GitFileRevisionToWidget`, `GitTheme`,
   the natural rows and the tab titles. An example in `example/projectured/DomainExamples.jl`. Test:
   the new `test_git_views()` (`GitViewTest.jl`) in an editor with the console backend. It asserts the
   text of the header row, a file row, a hunk row, and a removed and an added line with their
   numbers. A diff of 5000 lines builds no more than the rows that show and a margin. A file at a
   revision shows its marked line in its first rows. A failed read shows its reason. Then
   `test_domain_examples()`.
   What the implementation found:
   - The owner reviewed a first version, whose pages built their own rows of labels in a lazy list,
     and decided on 2026-11-13: "use existing views, documents, projections; projectured can already
     display and navigate text and add line numbers; keep the git specific coloring, structure". The
     owner also asked for the text domain itself (`TextBlock`, `TextLine`, `TextString`) in place of
     `MarkedText`. So the text domain draws each page, and the first version is gone.
   - New: `GitTextLine` (a plain value: a kind, a text, the label of its gutter), the abstract
     `GitText` with `GitDiffText` and `GitFileText` (fields `lines` and `text`), and the projection
     `GitTextToText`. A commit and a change hold their `diff`, a file at a revision its `content`.
   - `GitTextToText` makes a `TextLine` for each line, with one `TextString` in the style of its kind
     from `GitTheme`, and puts the label of a line of a diff, its old and its new number, into the
     `number` lane of its `TextGutter`. The hunks hold the numbers, so nothing counts them again, and
     no platform projection changes. A text of a file has no labels: `TextLineNumbering` numbers it.
   - The chain of a text is the chain of the code of a file (`make_source_file_code_projection` of the
     language server adapter, `make_julia_file_code_projection`): the git stage, then
     `TextLineNumbering` for a file, then `TextBlockToScrollLayout`, in a recursion with the rows of
     `TextGutter`, `TextBlock` and `GraphicsCanvas`. `make_graphics_projection` of each text type
     gives it.
   - A page is the form of the view of an open file: a `VerticalLayout` with a `WidgetScrollPane` of
     the text (and a title above it for a file at a revision), chained with
     `VerticalLayoutToGraphicsCanvas`. The recursion of the renderer draws the pane and the text, and
     the pane takes apart the `ScrollLayout`, so the gutter stays at the left edge.
   - The reader of `GitTextToText` keeps a selection, the part under the pointer and a drag, and
     answers nothing for a `ReplaceRangeOperation`, a `ReplaceReferencedValueOperation` and a key
     (the owner: "your git projection can ignore the editing operations in the reader coming from the
     text domain"). The test clicks into a text, moves the caret with Right, types, and the text stays.
   - The text of a commit holds every diff, as `git show` writes it, so its first draw reads all the
     patches of the commit, in one task for each frame. "A file reads its diff only when its rows
     show" no longer holds. Step 7 measures a large commit.
   - The pane scrolls to a part only for an answer that shows it (`ShowSelectionOperation`). So the
     page of a file at a revision starts at its first line, and step 4, the open of a file at a
     line, brings the line into view. The named line has the kind `:marked` and its style.
   - A walk of the documents reads no `hunks`, `diff` or `content` (`is_field_walked`).
   - The package graph asks a package with natural rows to compile them: `ProjecturedGit` ends with
     `@compile_ahead run_natural_rows_workload(GitModule)` now, not in step 7.
   - The test uses the headless backend, as the explorer and the navigator tests do, not the console
     backend, which draws a text and no widget page. `test_printer(git_example)` runs in place of the
     whole `test_domain_examples()`. `ProjecturedExample` holds `ProjecturedGitExample`.
   - The PDF backend draws no element of a canvas whose elements are a `ListNode`, so a page with a
     lazy list prints blank in a PDF. `write_image` of the SDL backend draws it.
   - Results: `test_git()` 119 pass; `test_printer(git_example)`, `test_package_graph()` 562 and
     `test_repository()` 619 pass; the naming guard passes; the documentation report is the same as
     on main; the style guard fails one line, `BookModule.jl:34`, as on main.
4. **The gestures.** **Done on 2026-11-14.** The rules of §3.4 and their descriptions, which the command palette lists. Test:
   the new `test_git_gestures()` (`GitGestureTest.jl`) in a real `Editor` with a navigator on a
   commit. Ctrl+click on a removed line visits the file at the parent at its old line, and Back
   returns. Ctrl+Shift+click on an added line opens a new tab at the new line. Ctrl+click on a file
   row visits its change. The selection of the person stays, and undo records nothing.
   What the implementation found (step 4 in part, 2026-11-13):
   - Each line of a diff carries a `GitLinePlace` (the repository, the revision and the path of its
     side, and its number there): a removed line the old side, a kept or an added line the new side,
     the start of a hunk and the path of a file their first line.
   - The text domain answers a Ctrl+click with the caret at its point. The 4-argument reader of
     `GitTextToText` finds the line of that caret and answers `OpenPageOperation(GitFileRevision(...),
     EmptyReference(), :here)`, or `:new_tab` with Shift, in the place of the caret, so the selection
     of the person stays. The navigator makes the open a visit, and Back returns.
   - A click on the path of a file in the table of a commit opens the change, and a click on the
     hash of a row of a range opens the commit: the links of the roster, with no code of the git
     domain. So the plan's Ctrl+click on a file row is a plain click on the link.
   - The page of a file at a revision brings its named line into view. The owner: "There should be a
     reveal operation on the scroll pane taking a reference. Revealing the selection at start is an
     option on the scroll pane." So:
     - `RevealPartOperation(reference)` (layout slice, beside `KeepPointOperation`) asks the panes
       that hold the part to scroll the least amount that shows it. The reader of a scroll pane
       whose content holds the part answers the scroll, or nothing when the part shows already;
       a pane that does not hold it lets it go up. It is no edit, so undo records nothing.
     - `WidgetScrollPane` takes the option `is_selection_revealed` (default `false`). While the
       scroll position is the one of its construction, the print scrolls to show the selection of
       its content, and the readers of the pane scroll from that offset. The first scroll of a
       person writes the position, so the option stops.
     - A pane whose content draws as parts (a gutter at the left edge) shows the part in its
       center canvas.
     - The selection of a `GitFileText` is a caret at the start of the named line.
     What the implementation found (done, 2026-11-14):
     - `revealed_position` is the latch: the `Point2D` that the pane starts with. Each scroll writes
       a new `Point2D`, so the start ends at the first scroll, and no write path changes.
     - The print finds the offset once, the first time the selected part has a box in a view with
       an extent, and the offset then holds: a click that moves the selection does not move the
       view. The IO map keeps it (`revealed_scroll`), and each reader of the pane (the wheel, a bar,
       a point under the pointer, a show) scrolls from it.
     - The start puts the part in the middle of the view (my decision: an open at line 3000 that
       puts the line on the last row of the view hides what follows it). A reveal and a selection
       to show keep the least move.
     - `_scroll_pane_to_show` now also works for a content that the pane takes apart. Each text that
       `TextBlockToScrollLayout` draws is such a content, also with no gutter, so a selection to
       show now scrolls the pane of a Julia file and of a document of the language server as well.
     - The selection of the text of a file is `.lines[k]`, a reference with no offset in the text,
       which the forward map of `GitTextToText` makes the caret at the start of line `k`. So it
       holds before the read of the file comes. A click writes the usual `.text{s}`.
     - The new field changes the type of `WidgetScrollPane`, so a recorded call that names the type
       no longer resolves. The list of `ProjecturedGraph` has 62 of 601 such calls, more than the
       10 % at which a list fails, so its load warns. Step 7 records the lists again.
     - Results: `test_scroll_pane_show()` 25, `test_text_gutter()` 49, `test_git()` 165 pass;
       `test_scroll_pane_parts()`, `test_scroll_pane_hover()`, `test_scroll_pane_bar()`,
       `test_widget_table_bar()`, `test_widget_rows_scroll()`, `test_text_folding()` 24,
       `test_undo()` 141, the navigator suites, `test_julia_file_view()`, `test_julia_code_pieces()`
       and `test_graph_layout_zoom()` 38 pass; the naming guard passes. Known failures of main
       stay: `NavigatorChoicesTest.jl:174/178/208/211`, `GraphScrollPaneTest.jl:183-210`, and two
       checks of `test_platform_layering()` on files that this branch does not change.
   - The two opens and a tooltip are one table of gesture bindings of `GitTextToText`
     (`_make_git_line_bindings`), so what fires is what the command palette lists. A binding gets
     only its document and the event, so the reader makes the table for one line: for a click,
     the line of the caret that the text domain answers, fired as an override of that caret; for
     a listing and a rest of the pointer, the line under the pointer or of the selection, by the
     rule of `find_pointed_part`. The palette runs an open with no event, at the line of the
     caret. The tooltip of a line of a diff names the file, the short revision and the line that
     its Ctrl+click opens; a line with no place has no tooltip, and its opens show greyed.
     - A row of a listing runs only when its binding has a `name`, so each open is named by its
       description.
     - The test types into the list with `shell = true`, as the application does: in an editor
       with no shell, a key of the window does not reach the list of the palette, although the
       selection is in its query. That is a fault of the platform outside this plan.
     - Results: `test_git()` 176 pass (`test_git_gestures()` 21).
   - Results: `test_git()` 162 pass (`test_git_gestures()`: the visit and Back, the new tab, the link
     of the table, the selection that stays).
5. **The link.** **Done on 2026-11-14.** `find_url_document` in `UrlInterface.jl`, its two calls in the navigator slice, and
   the git method for both forms. Test: `test_link()` (`test/platform/link/LinkTest.jl`) and
   `test_open_page_operation()`, with a scheme that the test defines. `:here` makes a visit, and
   `:new_tab` makes a tab. An unknown scheme still goes to the program of the system. Then
   `test_navigator()` and `test_markdown_link_gestures()`. A new testset in `test_git_gestures()`
   clicks both forms on a Markdown page, and a bad hash shows a failed read and throws nothing.
   What the implementation found (2026-11-14):
   - The git method is in a fragment of its own, `GitAddress.jl`. The first `:` of the fragment
     ends the revision. An address with a host, with no revision, or with an empty revision or
     path names nothing, and the open goes on to the program of the system.
   - The method reads escaped characters with the decoder of the link slice, which is public now
     as `decode_url_text` (renamed from a private name with `julia-rename.jl`).
   - `ProjecturedGitTest` does not depend on the Markdown domain: a test package depends only on
     the packages below it. So the testset of the git test clicks labels whose press answers the
     target form of `OpenPageOperation`, the answer of a Markdown link, and the navigator resolves
     it as it resolves a Markdown link. `test_markdown_link_gestures()` covers the Markdown side.
   - Results: `test_git()` 189, `test_open_page_operation()` 103, `test_link()` 2109,
     `test_navigator_to_widget()` 69, `test_navigator_gestures()` 26,
     `test_markdown_link_gestures()` 18 and `test_markdown_link_target()` 14 pass.
6. **The verbs.** **Done on 2026-11-14.** `find_git_commits`, `describe_git_commit`, the docstrings and the marks. Test: the new `test_git_verbs()` (`GitVerbTest.jl`). It asserts the hashes in order for
   `revisions`, `paths`, `first_parent` and `limit`, and the header facts of each commit with no read.
   It asserts the `ArgumentError` of a bad range, and the text of `describe_git_commit` with `paths`
   and `context = 10`. The four names carry the mark `For the assistant.`, so `search_api` finds
   them while the package is loaded. Then
   `test_assistant_documentation()`, `test_assistant_verbs()` and `test_referenced_document_editor()`.
   The owner changed this step on 2026-11-14 ("the assistant should be able to control the git
   domain in the editor", then "Yes" to the proposal): the two verbs go, because
   `find_git_commits` repeats `GitCommitRange` and `describe_git_commit` is a text form only for the
   assistant, which the rule of 2026-11-07 forbids (the assistant reads values). In their place:
   - The assistant uses the documents: `GitCommitRange`, `GitCommit`, `GitFileChange` and
     `GitFileRevision`, which the mark on `GitDocument` offers, and `open_pane!`, `show_pane!` and
     the commands of the pages for the editor.
   - One verb, `read_git_document!(document; editor)` (`GitProgram.jl`), finishes the reads of git
     of a document in the code of its caller, as `read_filesystem_folder!` does for a folder, with
     `wait_for_cell!`: the listing and the commits of a range; the changes, the header and the
     lines of the diffs of a commit, then the hunks of each change; the text of a file at a
     revision. A read that failed throws the `GitException`. A part, a `ReferencedDocument`,
     reads as its document, as the documentation check asks of a verb.
   - `first_parent`, `limit` and `context` go: a range reads all its commits with one `git log`,
     and a diff has the 3 lines of context of git.
   - `GitModule.__init__` gives the system text a sentence that names the documents and the verb
     (`register_assistant_api!`).
   - Tests: `test_git_verbs()` with no editor, and a case of `test_assistant_verbs()` in which the
     code of the assistant reads a range and a commit and opens the commit as a page. The walker
     of drawn texts of that test follows a lazy list by the links that its layout built.
   - Results: `test_git()` 214 (`test_git_verbs()` 25), `test_assistant_verbs()` 92 and
     `test_referenced_document_editor()` 134 pass; the naming guard passes.
     `test_assistant_documentation()` passes for every git name and has 4 errors of main, on files
     that this branch does not change: the docstrings of `get_range_direction`, `get_range_ends`
     and `make_range_reference_step` lack the form, and the example of `describe_task` calls
     `get_task_document_result`, which no model can write.
7. **The workload and the live check.** `@compile_ahead` with `run_natural_rows_workload(GitModule)`.
   Then a live check in the Projectured window through its MCP connection. It opens a commit of
   `inet-cpp` with more than 2000 changed lines and scrolls to its end. It clicks a removed line with
   Ctrl, and a `git+file:` link of a Markdown page. `take_picture` shows each view. In omnet-julia,
   in the same landing, `OmnetIde` gets `import ProjecturedGit` and the line in `[deps]` (and the path line
   in `[sources]`, see the risks), then
   `Pkg.resolve()` and `Pkg.precompile()` run, and the same check runs in omnet_ide. Then this plan
   moves to `plan/done/`.
   What the implementation found (2026-11-14):
   - The workload: `ProjecturedGit` already compiled its natural rows ahead (step 3). Its list is
     recorded now (`record_package_calls!`, 53 calls). The list of `ProjecturedGraph` is recorded
     again, because the new field of `WidgetScrollPane` (step 4) made more than 10 % of it stale
     (865 calls). The list of `ProjecturedSDL` is recorded again too: 106 of its 906 calls were
     stale on main already, over the limit, and the new field added one. The list of
     `ProjecturedExample` is recorded again (8239 calls): 722 of its 7834 calls were stale on main,
     and the 64 that name the scroll pane took it just over the limit. Its workload fails for the 4
     examples that fail on main (`json_sorted`, `filesystem`, `files`, `chart`).
   - After these recordings a load of the umbrella warns for six lists, as on main: Math, Chart,
     Formula, Pivot, Workflow and Research. No line of them names what this branch changed.
   - The MCP connection of the window (`omnet-ide`, port 9876) did not connect in this session, so
     the live check is a script in `environment/all`: an editor with the fonts of the application
     drives the views, and `write_window_picture`, the writer of `take_picture`, writes a picture of
     the window at each view.
   - Results on `b3e5ccc` of inet-cpp (3 files, 2982 lines of text): the first frame 0.12 s, the
     diffs show after 2.1 s; to the end by a Shift+click on the bar and four wheel turns, 6 frames,
     the slowest 0.56 s, the mean 0.28 s; a Ctrl+click on a removed line at the end opens
     `omnetpp.ini` at the parent at line 46, with the caret at its start, and Back returns; on a
     Markdown page a click on a `git+file:` link visits the commit; `read_git_document!` of the
     commit takes 0.12 s.
   - Found: a commit with a long message (`1374297`, 30 lines) fills the page with its header, so
     the table and the diffs are below the window, and the page does not scroll to them. The
     owner designed a new page on 2026-11-14: a tree of the changed files beside their diffs, in
     the plan `the-page-of-a-commit-shows-its-files-as-a-tree-beside-their-diffs.md`.
   - Found, outside this plan: in a text, End moves to the end of the row also with Ctrl, and a
     caret move by a key does not ask the pane to show the caret.
   - omnet-julia: branch `git-views`, worktree `omnet-julia-git-views`, commit `b3e80653f`:
     `import ProjecturedGit` in `OmnetIde`, its lines in `[deps]` and `[sources]` of `OmnetIde`
     and of `environment/all`, and the closure test requires it and counts 37 names. Its
     `[sources]` reach the main checkout of projectured-julia, so its resolve and its tests run
     when this branch lands.

## 6. Risks

- **The navigator change reaches each link.** Step 5 runs `test_navigator()`, `test_link()` and
  `test_markdown_link_gestures()`. An unknown scheme must still reach the program of the system.
- **A walk can enter many lines.** `search_documents` and the selection walk must not enter the
  lines of a large diff. The hunks are plain values or opaque to a walk, and step 3 asserts it.
- **A machine with no git.** Each view shows the failed read. The test packages need git, as a
  checkout of the repository already does.
- **A watch for each held range.** A range watches up to three folders, and the store has a
  `watch_limit`. When `watch_folder!` answers `false`, the range reads only at its acquire. Step 2a
  asserts that the watch starts.
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
6. **The commits of a range (D9).** Answered by the owner on 2026-11-13: approved, as step 2a. The
   question was: can a document `GitCommitRange` hold all the commits of a range, read as a folder
   reads, with a watch of the folders of its refs? The baseline catch-up walk needs it.
