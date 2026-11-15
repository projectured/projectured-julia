# A folder lists its folders first

> **Kind:** change of behavior · **Status:** done, 2026-11-09, on the branch `folders-first` from
> `main` `14121813b`. Not on `main` yet.
> · **Stands on:** [filesystem.md](../../documentation/package/platform/filesystem/filesystem.md)

## 1. The goal

The Files page of the explorer lists the entries of a folder in the order that most file browsers
use:

1. The folders come first, then the files.
2. In each group, the names sort with no regard to case, and a run of digits sorts by its value,
   so `file9.txt` comes before `file10.txt`.
3. When two names are equal by this rule, the order of the character codes decides. Then the order
   is total, and each folder has one order only.

The same order applies to every view of a `FileSystemDirectory` that is read from the disk: the
Files page and the dialog that chooses a path.

## 2. What exists (checked at `14121813b`)

| Fact | Where |
| --- | --- |
| The read of a folder gets its names from `Base.Filesystem._readdirx(path)`, else from `readdir(path)`. Both sort the names by `isless` on `String`, which compares the character codes. | `source/platform/filesystem/FileSystemDocument.jl:445-452` |
| The order now: folders and files are mixed, all uppercase names come before all lowercase names, `_` sorts between them, and `file10.txt` comes before `file9.txt`. The root of this repository lists `.claude/ .git/ .github/ .gitignore CLAUDE.md … SEALING.md asset/ bin/ …`. | measured 2026-11-09 |
| `ApplyFolderListingOperation` merges a new listing into `elements`. It walks both lists in step and compares the names with `<`, so it expects the order of `isless`. An entry with the same name and another kind is a gone entry and a new entry at the same place. | `FileSystemDocument.jl:524-580` |
| The merge gives a correct list also when the old list has another order. Only the documents of kept entries can be lost: an open folder can close. | `FileSystemDocument.jl:524-580`, read 2026-11-09 |
| The docstring of `FileSystemDirectory`, the docstring of `ApplyFolderListingOperation`, the comment of `_read_folder_listing` and the design document say "in the order of their names". | `FileSystemDocument.jl:115`, `:442`, `:486`; `filesystem.md:28`, `:36` |
| The dialog that chooses a path shows the same `FileSystemDirectory` documents (`directory.elements[a]…`). | `source/platform/filesystem/FileSystemChooserToWidget.jl:21`, `:59` |
| The "Go to file" search reads the files with its own `readdir(folder; sort = true)` and lists them in path order. It is not the Files page. | `source/platform/filesystem/WorkspaceFileList.jl:107`, `:213` |
| No function of the source compares names with numbers by value. The help tree sorts with `lowercase` only. | `source/platform/help/HelpTree.jl:112`, `:239` |
| `FileSystemDocument.jl` is not in `SEALING.md`. | grep, 2026-11-09 |
| Twelve test files read real folders and can assert an order: `test_filesystem_document`, `test_filesystem_to_widget`, `test_workspace_to_filesystem`, `test_workspace_duplicate`, `test_explorer`, `test_window_shell`, `test_window_wrappers`, `test_document_decoration`, `test_background_work`, `test_tree_render`, `test_scroll_work`, `test_application`. | grep for `make_filesystem_pathname`, `read_filesystem_folder!` and `WorkspaceFolder(` in `test/` |
| `FileSystemDocumentTest.jl` asserts the old order: `["a.jl", "empty", "sub"]` and `root.elements[3] === sub`. | `test/platform/filesystem/document/FileSystemDocumentTest.jl:72-106` |

## 3. Decisions

- **D1 (the owner, 2026-11-09):** "I agree with your recommendation, no need for an option." The
  order is the one of §1. No setting changes it, and the order does not depend on the locale of the
  computer. So a folder shows the same order on every computer, and a test or a screenshot does not
  change with the machine.

Proposed with this plan:

- **D2:** One comparison decides the order of the read and the order of the merge. The merge
  compares the key of an entry: its kind and its name. Two entries are the same entry only when
  both are equal. A name that changes its kind is then a gone entry and a new entry in the other
  group, and the merge needs no case of its own for it.
- **D3:** The comparison of two names walks them in runs. A run is a sequence of ASCII digits, or
  one other character.
  1. Two runs of digits compare by value: leading zeros are dropped, the shorter run is smaller,
     and runs of the same length compare by their characters. No run is parsed into an integer, so
     a long run can not overflow.
  2. Any other two runs compare by the `lowercase` of their first character.
  3. A name that ends first is smaller: `file` comes before `file1`.
  4. When all runs are equal, `isless` of the two names decides: `README.md` comes before
     `readme.md`, and `file01` before `file1`.
- **D4:** A name that starts with `.` sorts first in its group, because `.` is smaller than a digit
  and a letter. VS Code also lists such a name first. `_` sorts after the digits and before the
  letters.
- **D5:** A letter outside ASCII sorts by its code after `lowercase`: `éclair` comes after
  `zeta`. A correct order of such letters needs the rules of a language, which D1 excludes.
- **D6:** The functions are private to the file system slice, in `FileSystemDocument.jl`:
  `_is_name_before(a, b)` for two names, `_get_entry_key(entry)` for the kind and the name of a
  document, and `_is_entry_before(a, b)` for two keys. Each key has the fields `is_folder` and
  `name`, so a listed entry of the read is a key already. No other slice uses the order now.
- **D7:** A `FileSystemDirectory` made with its entries, by a test or an example, keeps the order
  that its maker gives. The constructor does not sort.
- **D8:** The "Go to file" search keeps its path order. It ranks paths for a query, and it is not
  in this plan.

## 4. Steps

Work in a worktree on the branch `folders-first`. Run Julia with `bounded-run`. Commit after each
step. Do not land on `main` before the owner approves it.

- [x] 1. **The baseline.** On `14121813b`, run the twelve test functions of §2. Write the pass,
  fail, error and broken counts of each into this plan. A failure in this run is a known failure,
  and steps 2 and 3 compare with it.

  Done 2026-11-09 in the worktree, Julia 1.13.1, `environment/all`, `-t 2`, SDL offscreen:

  | Function | Pass | Fail | Error | Broken |
  | --- | --- | --- | --- | --- |
  | `test_filesystem_document` | 34 | 0 | 0 | 0 |
  | `test_filesystem_to_widget` | 41 | 0 | 0 | 0 |
  | `test_workspace_to_filesystem` | 13 | 0 | 0 | 0 |
  | `test_workspace_duplicate` | 18 | 0 | 0 | 0 |
  | `test_explorer` | 383 | 0 | 0 | 0 |
  | `test_window_shell` | 152 | 0 | 0 | 0 |
  | `test_window_wrappers` | 74 | 0 | 0 | 0 |
  | `test_document_decoration` | 60 | 0 | 0 | 0 |
  | `test_background_work` | 21 | 0 | 0 | 0 |
  | `test_tree_render` | 9 | 0 | 0 | 0 |
  | `test_application` | 402 | 1 | 0 | 2 |
  | `test_scroll_work` | 14 | 2 | 0 | 0 |

  The three failures are known on `main`: `ApplicationTest.jl:1008`, the usage text of the bar of
  an agent, and `ScrollWorkTest.jl:127` and `:130`, the copies and the drawn share of a Julia file
  in a focused tab.
- [x] 2. **The order.** In `FileSystemDocument.jl`:
  1. Add `_is_name_before`, `_get_entry_key` and `_is_entry_before` (D3, D6).
  2. `_read_folder_listing` reads with `sort = false` and sorts the listing with
     `_is_entry_before`.
  3. `_apply_folder_listing!` compares keys with `_is_entry_before` and drops the case of a name
     with another kind (D2).
  4. The docstrings of `FileSystemDirectory` and `ApplyFolderListingOperation`, and the comment of
     `_read_folder_listing`, state the order of §1.

  In `FileSystemDocumentTest.jl`:
  1. A test of `_is_name_before` on strings, with no disk: `file9` before `file10`, `a.txt` before
     `Makefile`, `_build` before `docs`, `.config` before `0`, `file` before `file1`, `README.md`
     before `readme.md`, `file01` before `file1`, and a run of 30 digits.
  2. A test on a folder with `.config/ Zeta/ _build/ docs/ .gitignore Makefile README.md a.txt
     file10.txt file9.txt`. The read lists `.config/ _build/ docs/ Zeta/ .gitignore a.txt file9.txt
     file10.txt Makefile README.md`. A new `file2.txt` goes between `a.txt` and `file9.txt`, and
     each entry that stays keeps its document. A file `x` that becomes a folder `x` moves to the
     folders.
  3. The assertions of the old order change to the new order: `["empty", "sub", "a.jl"]`, and the
     indices that follow.

  Run `test_filesystem_document` and compare with step 1.

  Done 2026-11-09. Facts and decisions of the work:
  - Two more private functions: `_compare_entry_names(a, b)` answers -1, 0 or 1 with no tie
    broken, and `_compute_digit_run(name, start)` finds the end of a run of digits and the start of
    its value. `_is_same_entry(key, listed)` replaces `_is_same_entry_kind`.
  - A name on Linux can be invalid UTF-8, and `lowercase` throws for such a character, so the read
    of the whole folder would fail. A character that is not valid compares as it is. The test of
    the order has a name with the byte `0xff`.
  - The merge computes the key of each stored entry once, before the walk.
  - A check of the comparison alone, outside the source, passed 1351 assertions. These included
    that the order is total and transitive over 19 names with case, zeros, digits, `_`, `.`, `é` and
    an invalid byte.
  - Cost, measured alone with random names: 5000 entries sort in 11 ms. 100,000 entries sort in
    121 ms, and the byte order sorts them in 20 ms. The sort runs on the task of the read, not in a
    frame.
  - `test_filesystem_document`: 55 pass, 0 fail, 0 error, 0 broken (step 1: 34). The naming guard
    `test/suite/naming.jl` passes.
- [x] 3. **The other tests.** Run the other eleven test functions of §2. Change each assertion that
  names the old order to the new order, and change nothing else. Compare each count with step 1.
  Record in this plan each assertion that changed.

  Done 2026-11-09. No assertion changed: the fixtures of these tests list their folders before
  their files in both orders, for example `["full", "none", "top.jl"]`. Each count is equal to
  step 1, with the same three known failures (`ApplicationTest.jl:1008`, `ScrollWorkTest.jl:127`
  and `:130`).
- [x] 4. **The document and the live check.** `filesystem.md` states the order of §1 and D2 at
  lines 28 and 36. Open the Files page in the application over the test folder of step 2, take one
  screenshot, and check that the rows show the order of step 2. Record the result in this plan,
  and move the plan to `plan/done/`.

  Done 2026-11-09. `filesystem.md` has a section "The order of a folder" with the rule and its
  reason, and the merge says that an entry stays when its kind and its name stay. The live check
  drew a `WorkspaceExplorer` over the folder of step 2 and `file2.txt`, with `NaturalToGraphics`
  and `write_image`, offscreen. It is the projection that the Files tab shows, but not the whole
  window of the application, and no pointer pressed anything. The rows show `.config _build docs
  Zeta .gitignore a.txt file2.txt file9.txt file10.txt Makefile README.md x`, which is the order
  of step 2.

## 5. Not in this plan

- The order of the "Go to file" search (D8).
- A sort by type, by size or by time, and a setting for the order (D1).
