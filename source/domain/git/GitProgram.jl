# Fragment of `GitModule` — the verb that finishes the reads of a git document in
# the code of its caller, and the sentence that the system text of a window says
# about the domain.

"""
    read_git_document!(document; editor = find_evaluation_editor()) -> document

Finish the reads of git that `document` makes, and answer `document`, whose fields
then hold final values. A page starts these reads when it shows the document, and
they run off the loop; this call runs them for the code of its caller and waits for
them. A read that failed throws a [`GitException`](@ref) with the words of git.

- A [`GitCommitRange`](@ref): its `commits`, each a [`GitCommit`](@ref) with the
  `header` of the log, the hash, the parents, the author, the date and the subject.
- A [`GitCommit`](@ref): its `header`, its `changes`, one [`GitFileChange`](@ref)
  for each changed file, and the diff of each change, so `commit.diff.text` holds
  the text of the diffs that its page shows, as `git show` writes them.
- A [`GitFileChange`](@ref): its `hunks` and its `diff`.
- A [`GitFileRevision`](@ref): the `text` of the file.

A commit and a file at a revision never change, so a second call reads nothing. A
range reads its commits again only after a ref of it moved.

Use it to read the commits of a range, the changed files and the diff of a commit,
or a file at a revision, before code reads their fields.

# Example

    range_1 = read_git_document!(GitCommitRange("/home/me/inet-cpp", "fd436d7..v4.7.0";
                                                paths = ["src/inet/linklayer/ieee80211"]))
    commit_1 = read_git_document!(range_1.commits[3])
    println(commit_1.header.subject)
    println([something(change.new_path, change.old_path) for change in commit_1.changes])
    print(commit_1.diff.text)
    tab_1 = open_pane!(commit_1)
    show_pane!(tab_1)

See also `GitCommitRange`, `GitCommit`, `GitFileRevision`, `open_pane!`.

For the assistant.
"""
function read_git_document! end

function read_git_document!(range::GitCommitRange; editor = find_evaluation_editor())
    # The listing throws the words of git; the commits hold what it found.
    wait_for_cell!(getfield(range, :listing); editor)
    wait_for_cell!(getfield(range, :commits); editor)
    range
end

function read_git_document!(commit::GitCommit; editor = find_evaluation_editor())
    changes = wait_for_cell!(getfield(commit, :changes); editor)
    wait_for_cell!(getfield(commit, :header); editor)
    # The lines of the diffs read the hunks of every change at once, in one task.
    wait_for_cell!(getfield(commit.diff, :lines); editor)
    foreach(change -> read_git_document!(change; editor), collect(changes))
    commit
end

function read_git_document!(change::GitFileChange; editor = find_evaluation_editor())
    wait_for_cell!(getfield(change, :hunks); editor)
    wait_for_cell!(getfield(change.diff, :lines); editor)
    change
end

function read_git_document!(file::GitFileRevision; editor = find_evaluation_editor())
    wait_for_cell!(getfield(file, :text); editor)
    wait_for_cell!(getfield(file.content, :lines); editor)
    file
end

# A part of a window, as a read of the window answers it, reads as its document.
function read_git_document!(part::ReferencedDocument{<:GitDocument}; editor = find_evaluation_editor())
    read_git_document!(get_document(part); editor)
    part
end
