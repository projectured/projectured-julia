# Git domain

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md)

The git domain, `ProjecturedGit`, reads what the `git` program writes about a repository. This document says what the package holds, how it reads the output of git, and why it reads text and not a library.

## How it works

The package holds three documents, which read what they show by the `git` program, and plain values, which functions make from the output of git.

### The documents and their reads

| Document | It holds | Its read |
| --- | --- | --- |
| `GitCommit(repository, revision)` | `header`, a `GitCommitHeader`, and `changes`, a `GitFileChange` for each changed file | `git show -z --raw --numstat -M --diff-merges=first-parent` of `<revision>^{commit}` |
| `GitFileChange` | what the read of its commit knew: the kind, the old and the new path, the counts, whether the file is binary, the first parent as `old_revision` and the commit as `new_revision`; and `hunks` | `git show --patch` of the commit, limited to the old and the new path |
| `GitFileRevision(repository, revision, path; line)` | `text`, and the `line` to show | `git cat-file blob <revision>:<path>` |

Each document holds the absolute path of its repository. Each read is a background cell (see [editor.md](../../kernel/editor.md)), and the cell is the store of the answer: a print that reads a field asks for the read, and a task runs `git` after the frame. While the answer is still to come, the cell is provisional, and the field `reading` is `true` while git runs. A read that failed makes each read of the field throw a `GitException` with the words of git, such as `bad revision` or `not a git repository`. A document has no read state of its own and no operation that stores an answer.

A background work reads no document, so the read of a commit answers values: the header, and a `GitFileSummary` for each file. `changes` is a computation that makes a `GitFileChange` from each summary. A commit never changes, so its answer is final, the computation runs one time, and each change keeps its document. A commit and its changes share one background source, so one task reads the patches of all the files that one frame shows. A commit made with the header of a log, `GitCommit(repository, hash; header)`, holds that header, and its read gives only the changes.

Each run of git is the same with any configuration of a person: `git -C <repository> --no-pager` with `core.quotePath=false`, `color.ui=false` and `log.showSignature=false`, the C locale, no optional lock and no prompt. A revision comes after `--end-of-options`, so a revision that starts with `-` is no option. The read of a patch takes literal paths and the prefixes `a/` and `b/`.

A `.pred` file writes a commit as `GitCommit("<folder>", "<hash>")`, and a file at a revision with its repository, its revision, its path and its line.

### The values of the output of git

A function here reads a text and runs no program, so a test gives it a fixed text.

| Value | It holds | Made by |
| --- | --- | --- |
| `GitCommitHeader` | the full hash, the hashes of the parents, the name and the e-mail address of the author, the date of the author in strict ISO 8601, the subject and the whole message | `parse_git_log_text`, `parse_git_commit_text` |
| `GitFileSummary` | the kind of the change of one file in a commit, the old and the new path, the counts of the added and the removed lines, and whether the file is binary | `parse_git_commit_text` |
| `GitDiffFile` | the kind, the old and the new path, whether the file is binary, and the hunks | `parse_git_diff_text` |
| `GitDiffHunk` | the first line and the count of lines on each side, the heading after the second `@@`, and the lines | `parse_git_diff_text` |
| `GitDiffLine` | the kind (`:kept`, `:removed`, `:added`), the text, the number on each side, and whether the line ends with a line end | `parse_git_diff_text` |

The kind of a change is `:added`, `:deleted`, `:modified`, `:renamed`, `:copied` or `:type_changed`. An added file has no old path, and a deleted file has no new path.

### The three texts

Each function reads one form of output:

- `parse_git_log_text` reads `git log -z --format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%B`. Each field and each commit ends with a NUL byte, so a message can hold any line.
- `parse_git_commit_text` reads `git show -z --raw --numstat` with the same format. After the header come the raw entries, one for each changed file, then the count entries in the same order. A rename or a copy gives two paths in each list. The function checks that the two lists name the same files.
- `parse_git_diff_text` reads a patch: the output of `git diff` or of `git show --patch`. A patch needs no commit header, and a line before the first `diff --git` is no part of a file.

### The paths of a patch

git writes a path of a patch in three forms, and the parse reads each:

- A plain path, after the prefix `a/` on the old side and `b/` on the new side. A path that holds a space ends with a tab on the lines `---` and `+++`.
- A path in C quotes when it holds a control character, a quote or a backslash. With the default `core.quotePath`, git also quotes a byte outside ASCII as three octal digits.
- `/dev/null` for the missing side of an added or a deleted file.

A rename or a copy names its paths on the lines `rename from` and `rename to`. A change of the mode only, a binary file and a new empty file have no lines `---` and `+++`, so the line `diff --git` names the path two times, and its length gives the path.

### The lines of a hunk

The counts of the line `@@` say where a hunk ends. git leaves out a count of 1. A kept line has both numbers, a removed line has the old number, and an added line has the new number. The line `\ No newline at end of file` marks the line before it, so that line has `has_line_end` set to `false`. An empty line in a hunk is a kept empty line, because some tools remove the space at the end of a line.

## How it fits

`ProjecturedGit` depends on the kernel and the platform, and on `ProjecturedPrecompile`. No other domain is below it. AutoIntegration loads it when `Projectured` is loaded, and `ProjecturedAll` holds it. Its suite is `test_git()` in `ProjecturedGitTest`. `ProjecturedGitExample` holds `make_git_example_repository(folder)`, which makes a repository of four commits with fixed names and dates, so each hash is known. It runs git with no global and no system configuration.

Another domain can read a patch of its own with `parse_git_diff_text` and compare the hunks with the hunks of a commit. The four values of a patch are exported for that use.

## Design decisions

- **git computes the diff.** The line numbers then equal the lines of the file at each revision, and the diff in the editor equals the diff in a terminal. A diff in Julia can differ from git, for example in the heuristic of the indent and in `diff.algorithm`.
- **The output of the program, not LibGit2.** LibGit2 is a new dependency, and its API has no patch text and no lines of a hunk. The `git` program needs no Julia dependency.
- **Plain values.** A hunk and a line are immutable values and not documents, so a walk of the documents does not enter the lines of a large diff.
- **The NUL forms.** `-z` and `%x00` separate the fields of the log and the paths of the lists, so no name and no message needs quotes there.

## Usage

```julia
using ProjecturedGit

text = read(`git -C /path/to/repository diff`, String)
for file in parse_git_diff_text(text)
    println(file.kind, " ", something(file.new_path, file.old_path), " ", length(file.hunks), " hunks")
end
```

## Limits

- A patch must use the prefixes `a/` and `b/`. A patch of `git diff --no-prefix`, or with `diff.mnemonicPrefix`, gives an `ArgumentError`.
- The combined diff of a merge (`@@@`) is not read. A merge shows its change against its first parent.
- A patch with Windows line ends keeps the carriage return in the text of each line.
