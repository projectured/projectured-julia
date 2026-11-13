# The texts that the pages of the git domain show: a line of a text as a plain value,
# the two text documents, and the lines of a commit, of a change and of a file at a
# revision.

"""
    GitTextLine

One line of a git text: its `kind`, which a page draws in the style of that kind,
its `text`, and the `label` of its gutter: the old and the new number of a line of
a diff, or `""`. The kinds are `:subject`, `:fact`, `:message`, `:section`, `:file`,
`:path`, `:hunk`, `:kept`, `:removed`, `:added`, `:marked`, `:note` and `:failure`.
"""
struct GitTextLine
    kind::Symbol
    text::String
    label::String
end

GitTextLine(kind::Symbol, text::AbstractString) = GitTextLine(kind, String(text), "")

"""
    GitText

A text that a page of the git domain shows: its `lines`, a vector of
[`GitTextLine`](@ref), and its `text`, the text of the lines with one line end
between two, where a caret stands. A person reads it, selects in it and copies
from it, and the page takes no edit of it.
"""
abstract type GitText <: GitDocument end

"""
    GitDiffText

The text of a commit or of the change of one file, as `git show` writes it: the
header and the changed files of a commit, then the path and the hunks of each
changed file. The gutter of each line of a diff holds its old and its new number.
"""
@document struct GitDiffText <: GitText
    lines::Any
    text::Any
end

"""
    GitFileText

The text of a file at a revision, with the line that the open of the file names
marked. The gutter of each line holds its number.
"""
@document struct GitFileText <: GitText
    lines::Any
    text::Any
end

# A text of type `T` whose lines `compute_lines()` computes from the reads of git.
function _make_git_text(T::Type, compute_lines::Function)
    lines = Cell(Computation(compute_lines))
    T(lines, Cell(@computation join((line.text for line in lines[]), '\n')))
end

# The value of the cell of a read: the answer, `nothing` while it is still to come,
# or the `GitException` of a read that failed.
function _read_git_answer(cell)
    value = try
        cell[]
    catch exception
        exception isa GitException || rethrow()
        return exception
    end
    is_cell_provisional(cell) ? nothing : value
end

# ── The lines of a commit ───────────────────────────────────────────────────

# The lines of a commit: the subject, the facts and the rest of the message; the list
# of the changed files; and the path and the diff of each changed file.
function _make_commit_lines(revision::String, header_cell, changes_cell)
    header = _read_git_answer(header_cell)
    header === nothing && return [GitTextLine(:subject, revision), GitTextLine(:note, "Reading the commit…")]
    header isa GitException &&
        return [GitTextLine(:subject, revision), GitTextLine(:failure, sprint(showerror, header))]
    lines = [GitTextLine(:subject, header.subject),
             GitTextLine(:fact, string(_format_short_hash(header.hash), " · ", header.author_name, " <",
                                       header.author_email, "> · ", header.author_date)),
             GitTextLine(:fact, _format_parents(header.parents))]
    body = _get_message_body(header.message)
    if !isempty(body)
        push!(lines, GitTextLine(:message, ""))
        append!(lines, (GitTextLine(:message, line) for line in split(body, '\n')))
    end
    changes = _read_git_answer(changes_cell)
    changes isa GitException && return push!(lines, GitTextLine(:failure, sprint(showerror, changes)))
    changes === nothing && return push!(lines, GitTextLine(:note, ""), GitTextLine(:note, "Reading the changes…"))
    changes = collect(changes)
    push!(lines, GitTextLine(:note, ""), GitTextLine(:section, _format_file_count(length(changes))))
    append!(lines, (GitTextLine(:file, _format_file_row(change.kind, change.old_path, change.new_path,
                                                        change.added_count, change.removed_count,
                                                        change.is_binary))
                    for change in changes))
    answers = [_read_git_answer(getfield(change, :hunks)) for change in changes]
    width = maximum(_get_number_width, answers; init = 0)
    for (change, answer) in zip(changes, answers)
        push!(lines, GitTextLine(:note, ""),
              GitTextLine(:path, _format_change_path(change.kind, change.old_path, change.new_path)))
        append!(lines, _make_diff_lines(answer, change.is_binary, width))
    end
    lines
end

_format_short_hash(hash::AbstractString) = first(hash, 7)

_format_parents(parents::Vector{String}) =
    isempty(parents) ? "No parent: the first commit" :
    (length(parents) == 1 ? "Parent " : "Parents ") * join(_format_short_hash.(parents), ", ")

# The message of a commit after its first paragraph, which is the subject.
function _get_message_body(message::AbstractString)
    parts = split(message, "\n\n"; limit = 2)
    length(parts) == 2 ? String(strip(parts[2], '\n')) : ""
end

_format_file_count(count::Int) = string(count, count == 1 ? " changed file" : " changed files")

# The kind of a change in words.
_format_change_kind(kind::Symbol) = kind === :type_changed ? "type changed" : string(kind)

# The path of a change: both paths for a rename or a copy, else the one it has.
_format_change_path(kind::Symbol, old_path, new_path) =
    kind in (:renamed, :copied) ? string(old_path, " → ", new_path) : something(new_path, old_path)

_format_change_counts(added_count::Int, removed_count::Int, is_binary::Bool) =
    is_binary ? "binary" : string("+", added_count, " −", removed_count)

# The row of a changed file in the list of the files, in columns: the kind, the path
# and the counts.
_format_file_row(kind::Symbol, old_path, new_path, added_count::Int, removed_count::Int, is_binary::Bool) =
    string(rpad(_format_change_kind(kind), 13), _format_change_path(kind, old_path, new_path), "  ",
           _format_change_counts(added_count, removed_count, is_binary))

# ── The lines of a change ───────────────────────────────────────────────────

# The lines of the change of one file: its path, its kind, its counts and its
# revisions, then its diff.
function _make_change_lines(kind::Symbol, old_path, new_path, added_count::Int, removed_count::Int,
                            is_binary::Bool, old_revision, new_revision::String, hunks_cell)
    revisions = string(old_revision === nothing ? "no parent" : _format_short_hash(old_revision), " → ",
                       _format_short_hash(new_revision))
    answer = _read_git_answer(hunks_cell)
    [GitTextLine(:path, _format_change_path(kind, old_path, new_path)),
     GitTextLine(:fact, string(_format_change_kind(kind), " · ",
                               _format_change_counts(added_count, removed_count, is_binary), " · ", revisions)),
     GitTextLine(:note, ""),
     _make_diff_lines(answer, is_binary, _get_number_width(answer))...]
end

# The digits of the largest line number of the hunks of a read, or 0.
_get_number_width(answer) =
    answer isa Vector && !isempty(answer) ?
        maximum(hunk -> ndigits(max(hunk.old_start + hunk.old_count, hunk.new_start + hunk.new_count, 1)), answer) : 0

# The lines of the diff of a file, as `git show` writes them: the first line of each
# hunk and each line with its sign, each line of a diff with the label of its
# numbers. A read that is still to come, a read that failed, a binary file and a
# change of the mode only give one line that says so.
function _make_diff_lines(answer, is_binary::Bool, width::Int)
    answer === nothing && return [GitTextLine(:note, "Reading the diff…")]
    answer isa GitException && return [GitTextLine(:failure, sprint(showerror, answer))]
    isempty(answer) && return [GitTextLine(:note, is_binary ? "A binary file: no lines to show." :
                                                             "No line changed: the mode of the file changed.")]
    lines = GitTextLine[]
    for hunk in answer
        push!(lines, GitTextLine(:hunk, _format_hunk_start(hunk)))
        for line in hunk.lines
            sign = line.kind === :removed ? '-' : line.kind === :added ? '+' : ' '
            push!(lines, GitTextLine(line.kind, string(sign, line.text), _format_line_label(line, width)))
            line.has_line_end || push!(lines, GitTextLine(:note, "\\ No newline at end of file"))
        end
    end
    lines
end

# The first line of a hunk as git writes it, which leaves out a count of 1.
_format_hunk_start(hunk::GitDiffHunk) =
    string("@@ -", _format_hunk_side(hunk.old_start, hunk.old_count), " +",
           _format_hunk_side(hunk.new_start, hunk.new_count), " @@", isempty(hunk.heading) ? "" : " " * hunk.heading)

_format_hunk_side(start::Int, count::Int) = count == 1 ? string(start) : string(start, ",", count)

# The label of the gutter of a line of a diff: its old and its new number, each in
# `width` digits, and spaces for the side that does not hold the line.
_format_line_label(line::GitDiffLine, width::Int) =
    string(line.old_number === nothing ? " "^width : lpad(line.old_number, width), " ",
           line.new_number === nothing ? " "^width : lpad(line.new_number, width))

# ── The lines of a file at a revision ───────────────────────────────────────

# The lines of a file at a revision, with the line `named` marked; a note while the
# read is to come, and the words of git for a read that failed.
function _make_file_lines(text_cell, named)
    answer = _read_git_answer(text_cell)
    answer === nothing && return [GitTextLine(:note, "Reading the file…")]
    answer isa GitException && return [GitTextLine(:failure, sprint(showerror, answer))]
    texts = split(answer, '\n')
    length(texts) > 1 && isempty(last(texts)) && pop!(texts)
    [GitTextLine(k == named ? :marked : :kept, text) for (k, text) in enumerate(texts)]
end
