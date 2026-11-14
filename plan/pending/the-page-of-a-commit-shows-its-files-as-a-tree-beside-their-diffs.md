# The page of a commit shows its files as a tree beside their diffs

> **Kind:** plan · **Status:** proposed, 2026-11-14 · **Branch:** `git-views` (worktree
> `projectured-julia-git-views`), before it lands · **Follows:**
> [the-assistant-shows-a-commit-and-its-changes.md](the-assistant-shows-a-commit-and-its-changes.md)

## 1. The problem

The live check of step 7 of the git views opened commit `1374297` of inet-cpp, whose message has
30 lines. The page of a commit is a `GridLayout` of three rows: the header, with the subject, the
facts, the parents and the message, at the height of its content; the table of the changed files;
and the pane of the diffs. The header took the whole window, so the table and the diffs were below
it, and the page does not scroll. The owner writes long messages, so this is the common case.

## 2. The design (the owner, 2026-11-14)

The owner: "How about a layout with a header and a left and right side. Left would be changed
files, right would be changes. Left would be the, selection decides set of changes included. Root
node includes all on right side, etc." Then three answers: a node for each folder, with a chain of
folders that each hold one folder as one node; the top node is the deepest folder that holds every
changed file ("The extra root node is only needed if more than one folders are modified and it
should rather be a folder"); the message stands on the right above the diffs while the top node is
chosen; a node shows its counts in its line, and its icon shows the kind of the change.

```
commit page
├─ header: subject · hash, author, date · parents
└─ split pane
   ├─ left: DocumentTree of the top folder
   │    showcases/tsn/trafficshaping/timeawareshaper     +294 −2363   ← every diff, and the message
   │    ├─ TimeAwareShaperShowcase.anf                   +107 −2238
   │    ├─ doc                                           +124 −90     ← the diffs under doc
   │    │  └─ index.rst                                  +124 −90
   │    └─ omnetpp.ini                                   +63 −35      ← this diff
   └─ right: a pane of the GitDiffText of the chosen node
```

- **The nodes.** A new document, `GitChangedFolder`: its path from the top folder of the
  repository, its children, the folders then the files, each in the order of their names, and the
  sums of the added and the removed lines of the files under it. A file is its `GitFileChange`. The
  top node is the deepest folder that holds every changed file; when the files are in more than one
  folder at the top of the repository, the top node is the folder of the repository, named by its
  folder name. A chain of folders that each hold one folder and no file is one node, whose label is
  the joined path. A rename is under the folder of its new path, and a deleted file under the folder
  of its old path.
- **The tree.** The tree slice shows the top node (`DocumentTree`): `get_tree_children_steps` of a
  folder names its `children`, and `format_tree_node_label` of a folder and of a change writes the
  name and the counts, `+124 −90`, and `binary` for a binary file. The icon of a change is the kind of
  the change (`get_document_decoration`). A double click or Return on a file opens the page of the
  change, as a tree opens a node.
- **The choice.** The right side shows the node of the tree that the selection names. While the
  person selects in the diffs, the commit keeps the place in its tree as a dormant selection, as the
  explorer keeps its own (`has_dormant_selection(::GitCommit) = true`), so the diffs stay the diffs of
  that node. With no node chosen, the right side shows the top node.
- **The right side.** The `GitDiffText` of the chosen node: at the top node, the message of the
  commit after its subject, then the path and the diff of each file, in the order of the tree; at a
  folder or a file, only the diffs under it. The lines keep their places, so a Ctrl+click on a line
  still opens the file at that line.
- **The header.** The subject, the line of the short hash, the author and the date, and the line of
  the parents: three short lines.

## 3. Decisions

The owner decided the layout, the folder nodes, the top node, the place of the message and the
counts in the line (§2). The assistant proposes, and the owner approves with the plan:

- **D1.** The split pane gives the tree a quarter of the width and the diffs the rest; the divider
  is the one of `WidgetSplitPane`.
- **D2.** The table of the changes (`table` of `GitCommit`, a roster) and the facets of
  `GitFileChange` go: the tree shows the same facts, and nothing else reads the facets. A tree has no
  bar to filter and to sort.
- **D3.** The chosen node is the place in the tree that the stored selection of the commit names,
  live or dormant. No field of view state holds it, so the editor keeps one selection.
- **D4.** The icons of the kinds: the icons of the icon set of the platform that name an added, a
  removed and a changed file, and the changed file for a rename, a copy and a change of type.

## 4. Steps

Each step runs in the worktree `projectured-julia-git-views` and ends with one commit.

1. **The tree of the changed files.** **Done on 2026-11-14.** `GitChangedFolder`, the function that makes the top node from
   the changes of a commit, the generics of a node, the labels and the icons. Test: a new testset of
   `test_git_views()`: the tree of a list of changes made as values, with files at the top, in one
   folder, in a chain of folders, and in two folders at the top; the labels and the sums.
   What the implementation found:
   - `GitChangedFolder` is a plain `Document`, not a `GitDocument`: it reads nothing and holds no
     repository. The fragment is `GitTree.jl`; `_make_changed_folder(changes, repository)` builds
     the top node, and `_collect_node_changes(node)` gives the changes under a node in the order of
     the tree.
   - The icon table of the platform gets three names of Lucide glyphs: `:file_plus` (`file-plus`,
     an added file), `:file_minus` (`file-minus`, a deleted file) and `:file_diff` (`file-diff`,
     every other kind). A folder has `:folder`.
   - The label of a rename or a copy in the same folder is `old → new`, and from another folder
     `new ← old path`; a binary file says `binary` in place of its counts.
   - Results: the new testset 15, `test_git_views()` 43 and the git layering guard 7 pass.
2. **The page.** The header, the split pane, the tree and the text of the chosen node; the message at
   the top node; the dormant place in the tree; the table and the facets go. Test:
   `test_git_views()` and `test_git_gestures()`: the page shows the tree and every diff with the
   message; a click on a folder shows only its diffs, and a click on a file its diff; a click in the
   diffs keeps them; a commit with a long message, which the test adds to its copy of the example
   repository as it adds the long files now, shows its tree and its diffs in the window; a
   Ctrl+click on a line opens the file as before.
3. **The guide and the live check.** `git.md` describes the page. The script of the live check of
   the git views draws `1374297` and `b3e5ccc` of inet-cpp, chooses a folder and a file, and writes
   a picture of each view.

## 5. Risks

- **A commit of thousands of files.** The tree builds only the rows that it shows, and a folder
  reads nothing. The text of the top node holds every diff, as the text of a commit does now.
- **The example repository.** A test that needs folders makes its changes as values, so the hashes
  of the example repository, which many tests name, stay.
