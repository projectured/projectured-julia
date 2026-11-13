# The values that the output of git gives, and the functions that read that output.

"""
    GitCommitHeader

The facts of one commit that `git log` gives: the full `hash`, the hashes of its
`parents`, the name and the e-mail address of its author, the date of the author
in strict ISO 8601, the `subject` and the whole `message`. A root commit has no
parent, and a merge has two or more.
"""
struct GitCommitHeader
    hash::String
    parents::Vector{String}
    author_name::String
    author_email::String
    author_date::String
    subject::String
    message::String
end

"""
    GitFileSummary

The change of one file in a commit, as the list of the changed files of the commit
gives it: the `kind` (`:added`, `:deleted`, `:modified`, `:renamed`, `:copied` or
`:type_changed`), the old and the new path, and the counts of the added and the
removed lines. An added file has no old path, and a deleted file has no new path.
A binary file has no lines, so its counts are 0 and `is_binary` is `true`.
"""
struct GitFileSummary
    kind::Symbol
    old_path::Union{String,Nothing}
    new_path::Union{String,Nothing}
    added_count::Int
    removed_count::Int
    is_binary::Bool
end

"""
    GitDiffLine

One line of a hunk: the `kind` (`:kept`, `:removed` or `:added`), the `text` with no
sign and no line end, and the number of the line in the old and in the new file. A
removed line has no new number, and an added line has no old number.
`has_line_end` is `false` for the last line of a file that ends with no line end,
which the patch marks with `\\ No newline at end of file`.
"""
struct GitDiffLine
    kind::Symbol
    text::String
    old_number::Union{Int,Nothing}
    new_number::Union{Int,Nothing}
    has_line_end::Bool
end

"""
    GitDiffHunk

One hunk of the patch of a file: the first line and the count of lines on the old
and on the new side, the `heading` that git writes after the second `@@`, and the
`lines`.
"""
struct GitDiffHunk
    old_start::Int
    old_count::Int
    new_start::Int
    new_count::Int
    heading::String
    lines::Vector{GitDiffLine}
end

"""
    GitDiffFile

The patch of one file: the `kind` (`:added`, `:deleted`, `:modified`, `:renamed` or
`:copied`), the old and the new path, whether git wrote no lines because the file
is binary, and the `hunks`. An added file has no old path, and a deleted file has
no new path. A change of the mode only has no hunks.
"""
struct GitDiffFile
    kind::Symbol
    old_path::Union{String,Nothing}
    new_path::Union{String,Nothing}
    is_binary::Bool
    hunks::Vector{GitDiffHunk}
end

# The count of the fields of one commit in the text of `parse_git_log_text`.
const _HEADER_FIELD_COUNT = 7

"""
    parse_git_log_text(text) -> Vector{GitCommitHeader}

The commits of `text`, which is the output of
`git log -z --format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%s%x00%B`, in the order of the
text. A text with no commit gives an empty vector.
"""
function parse_git_log_text(text::AbstractString)
    fields = split(text, '\0')
    isempty(last(fields)) && pop!(fields)
    length(fields) % _HEADER_FIELD_COUNT == 0 ||
        throw(ArgumentError("the log of git has $(length(fields)) fields, not a multiple of $_HEADER_FIELD_COUNT"))
    GitCommitHeader[_make_commit_header(view(fields, index:(index + _HEADER_FIELD_COUNT - 1)))
                    for index in 1:_HEADER_FIELD_COUNT:length(fields)]
end

function _make_commit_header(fields)
    GitCommitHeader(String(fields[1]), String.(split(fields[2])), String(fields[3]), String(fields[4]),
                    String(fields[5]), String(fields[6]), String(chomp(fields[7])))
end

"""
    parse_git_commit_text(text) -> (header = GitCommitHeader, files = Vector{GitFileSummary})

The header of the commit and the changed files of `text`, which is the output of
`git show -z --raw --numstat` with the format of [`parse_git_log_text`](@ref). The
files are in the order of the text.
"""
function parse_git_commit_text(text::AbstractString)
    tokens = split(text, '\0')
    length(tokens) >= _HEADER_FIELD_COUNT ||
        throw(ArgumentError("the text of a commit has $(length(tokens)) fields, fewer than $_HEADER_FIELD_COUNT"))
    header = _make_commit_header(view(tokens, 1:_HEADER_FIELD_COUNT))
    changes = Tuple{Symbol,Union{String,Nothing},Union{String,Nothing}}[]
    counts = Tuple{Int,Int,Bool,Union{String,Nothing},Union{String,Nothing}}[]
    index = _HEADER_FIELD_COUNT + 1
    while index <= length(tokens)
        # Only the first entry after the header starts with a line end.
        token = lstrip(tokens[index], '\n')
        if isempty(token)
            index += 1
        elseif startswith(token, ":")
            # A raw entry: the modes, the blobs and the status, then one path, or two
            # for a rename or a copy.
            kind = _get_change_kind(first(last(split(token, ' '))))
            if kind === :renamed || kind === :copied
                push!(changes, (kind, String(tokens[index + 1]), String(tokens[index + 2])))
                index += 3
            else
                path = String(tokens[index + 1])
                push!(changes, (kind, kind === :added ? nothing : path, kind === :deleted ? nothing : path))
                index += 2
            end
        else
            # A count entry: the added and the removed lines, then the path, or an empty
            # path and the two paths of a rename or a copy.
            parts = split(token, '\t'; limit = 3)
            length(parts) == 3 || throw(ArgumentError("an entry of the counts of git has no two tabs: $token"))
            is_binary = parts[1] == "-"
            added = is_binary ? 0 : parse(Int, parts[1])
            removed = is_binary ? 0 : parse(Int, parts[2])
            if isempty(parts[3])
                push!(counts, (added, removed, is_binary, String(tokens[index + 1]), String(tokens[index + 2])))
                index += 3
            else
                push!(counts, (added, removed, is_binary, String(parts[3]), String(parts[3])))
                index += 1
            end
        end
    end
    length(changes) == length(counts) ||
        throw(ArgumentError("the commit lists $(length(changes)) changed files and $(length(counts)) counts"))
    files = GitFileSummary[]
    for ((kind, old_path, new_path), (added, removed, is_binary, count_old, count_new)) in zip(changes, counts)
        something(old_path, count_old) == count_old && something(new_path, count_new) == count_new ||
            throw(ArgumentError("the counts of git name $count_old where the list names $(something(old_path, new_path))"))
        push!(files, GitFileSummary(kind, old_path, new_path, added, removed, is_binary))
    end
    (header = header, files = files)
end

# The kind of a change from the letter of its status in the raw list of git.
function _get_change_kind(letter::Char)
    letter == 'A' ? :added :
    letter == 'D' ? :deleted :
    letter == 'M' ? :modified :
    letter == 'R' ? :renamed :
    letter == 'C' ? :copied :
    letter == 'T' ? :type_changed :
    throw(ArgumentError("git gives the status $letter, which a commit does not have"))
end

"""
    parse_git_diff_text(text) -> Vector{GitDiffFile}

The files of the patch `text`, in its order. `text` is the output of `git diff` or
of `git show --patch`: each file starts with a line `diff --git`, and each path has
the prefix `a/` on the old side and `b/` on the new side. A line before the first
file, such as the header of a commit, is no part of a file.
"""
function parse_git_diff_text(text::AbstractString)
    lines = split(text, '\n')
    isempty(last(lines)) && pop!(lines)
    files = GitDiffFile[]
    index = 1
    while index <= length(lines)
        if startswith(lines[index], "diff --git ")
            file, index = _parse_diff_file(lines, index)
            push!(files, file)
        else
            index += 1
        end
    end
    files
end

# The lines of the header of a file that change neither its kind nor its paths.
const _OTHER_HEADER_PREFIXES = ("old mode ", "new mode ", "similarity index ", "dissimilarity index ", "index ")

# The file whose line `diff --git` is at `start`, and the index of the line after it.
function _parse_diff_file(lines, start::Int)
    index = start + 1
    kind = :modified
    from_path = nothing
    to_path = nothing
    while index <= length(lines)
        line = lines[index]
        if startswith(line, "new file mode ")
            kind = :added
        elseif startswith(line, "deleted file mode ")
            kind = :deleted
        elseif startswith(line, "rename from ") || startswith(line, "copy from ")
            kind = startswith(line, "rename") ? :renamed : :copied
            from_path = _parse_header_path(chopprefix(chopprefix(line, "rename from "), "copy from "))
        elseif startswith(line, "rename to ") || startswith(line, "copy to ")
            to_path = _parse_header_path(chopprefix(chopprefix(line, "rename to "), "copy to "))
        elseif !any(prefix -> startswith(line, prefix), _OTHER_HEADER_PREFIXES)
            break
        end
        index += 1
    end
    old_path = nothing
    new_path = nothing
    has_file_lines = false
    is_binary = false
    if index + 1 <= length(lines) && startswith(lines[index], "--- ") && startswith(lines[index + 1], "+++ ")
        old_path = _parse_patch_path(chopprefix(lines[index], "--- "), "a/")
        new_path = _parse_patch_path(chopprefix(lines[index + 1], "+++ "), "b/")
        has_file_lines = true
        index += 2
    elseif index <= length(lines) && (startswith(lines[index], "Binary files ") || lines[index] == "GIT binary patch")
        is_binary = true
        index += 1
        while index <= length(lines) && !startswith(lines[index], "diff --git ")
            index += 1
        end
    end
    hunks = GitDiffHunk[]
    while index <= length(lines) && startswith(lines[index], "@@ ")
        hunk, index = _parse_diff_hunk(lines, index)
        push!(hunks, hunk)
    end
    if from_path !== nothing
        to_path === nothing && throw(ArgumentError("the patch of $from_path names no path after its $kind"))
        old_path, new_path = from_path, to_path
    elseif !has_file_lines
        # A change of the mode only, a binary file and an empty file have no lines
        # `---` and `+++`, so the line `diff --git` names the path.
        path = _parse_git_line_path(lines[start])
        old_path = kind === :added ? nothing : path
        new_path = kind === :deleted ? nothing : path
    end
    GitDiffFile(kind, old_path, new_path, is_binary, hunks), index
end

# The first line of a hunk: the start and the count on each side, and the heading.
# git leaves out a count of 1.
const _HUNK_START = r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: (.*))?$"

# The hunk whose line `@@` is at `start`, and the index of the line after it.
function _parse_diff_hunk(lines, start::Int)
    found = match(_HUNK_START, lines[start])
    found === nothing && throw(ArgumentError("a hunk of a patch starts with \"@@ -\": $(lines[start])"))
    old_start = parse(Int, found[1])
    old_count = found[2] === nothing ? 1 : parse(Int, found[2])
    new_start = parse(Int, found[3])
    new_count = found[4] === nothing ? 1 : parse(Int, found[4])
    heading = found[5] === nothing ? "" : String(found[5])
    hunk_lines = GitDiffLine[]
    old_number, new_number = old_start, new_start
    old_left, new_left = old_count, new_count
    index = start + 1
    while index <= length(lines) && (old_left > 0 || new_left > 0 || startswith(lines[index], "\\"))
        line = lines[index]
        if startswith(line, "\\")
            # `\ No newline at end of file` follows the last line of a side.
            isempty(hunk_lines) && throw(ArgumentError("a hunk starts with a mark of no line end: $(lines[start])"))
            last_line = hunk_lines[end]
            hunk_lines[end] = GitDiffLine(last_line.kind, last_line.text, last_line.old_number,
                                          last_line.new_number, false)
        elseif isempty(line) || startswith(line, " ")
            # A tool that removes the spaces at the end of a line leaves an empty kept line.
            push!(hunk_lines, GitDiffLine(:kept, _get_line_text(line), old_number, new_number, true))
            old_number += 1
            new_number += 1
            old_left -= 1
            new_left -= 1
        elseif startswith(line, "-")
            push!(hunk_lines, GitDiffLine(:removed, _get_line_text(line), old_number, nothing, true))
            old_number += 1
            old_left -= 1
        elseif startswith(line, "+")
            push!(hunk_lines, GitDiffLine(:added, _get_line_text(line), nothing, new_number, true))
            new_number += 1
            new_left -= 1
        else
            throw(ArgumentError("a line of a hunk starts with a space, - or +: $line"))
        end
        index += 1
    end
    (old_left == 0 && new_left == 0) ||
        throw(ArgumentError("the lines of the hunk $(lines[start]) do not match its counts"))
    GitDiffHunk(old_start, old_count, new_start, new_count, heading, hunk_lines), index
end

# The text of a line of a hunk, with no sign.
_get_line_text(line::AbstractString) = isempty(line) ? "" : String(SubString(line, 2))

# The path of a line `rename from`, `rename to`, `copy from` or `copy to`.
_parse_header_path(text::AbstractString) =
    startswith(text, "\"") ? first(_parse_quoted_path(text, 1)) : String(text)

# The path of a line `---` or `+++` with its `prefix` taken off, or `nothing` for
# `/dev/null`. git ends the path with a tab when the path holds a space.
function _parse_patch_path(text::AbstractString, prefix::String)
    text == "/dev/null" && return nothing
    path = startswith(text, "\"") ? first(_parse_quoted_path(text, 1)) : String(chopsuffix(text, "\t"))
    startswith(path, prefix) || throw(ArgumentError("a path of a patch starts with $prefix: $text"))
    String(chopprefix(path, prefix))
end

# The path of a line `diff --git a/<path> b/<path>`, when both sides name the same
# path. With no quotes, the line holds the path two times, so its length gives it.
function _parse_git_line_path(line::AbstractString)
    rest = chopprefix(line, "diff --git ")
    if startswith(rest, "\"")
        path = first(_parse_quoted_path(rest, 1))
        startswith(path, "a/") || throw(ArgumentError("a path of a patch starts with a/: $line"))
        return String(chopprefix(path, "a/"))
    end
    units = codeunits(rest)
    count = length(units)
    (count >= 7 && iseven(count - 5)) || throw(ArgumentError("the line names no path two times: $line"))
    size = (count - 5) ÷ 2
    old_path = String(units[3:(size + 2)])
    new_path = String(units[(size + 6):count])
    (units[1:2] == codeunits("a/") && units[(size + 3):(size + 5)] == codeunits(" b/") && old_path == new_path) ||
        throw(ArgumentError("the line names no path two times: $line"))
    old_path
end

# The escapes of one letter in a quoted path of git.
const _QUOTED_ESCAPES = Dict('a' => 0x07, 'b' => 0x08, 't' => 0x09, 'n' => 0x0a, 'v' => 0x0b, 'f' => 0x0c,
                             'r' => 0x0d, '"' => UInt8('"'), '\\' => UInt8('\\'))

# The path of the quoted name that starts at the quote at byte `start` of `text`, and
# the byte after its closing quote. git writes a name in quotes when it holds a
# control character, a quote or a backslash, and, with `core.quotePath`, a byte
# outside ASCII, as three octal digits.
function _parse_quoted_path(text::AbstractString, start::Int)
    units = codeunits(text)
    bytes = UInt8[]
    index = start + 1
    while index <= length(units)
        unit = units[index]
        if unit == UInt8('"')
            return String(bytes), index + 1
        elseif unit == UInt8('\\') && index + 1 <= length(units)
            next = units[index + 1]
            if UInt8('0') <= next <= UInt8('7') && index + 3 <= length(units)
                push!(bytes, parse(UInt8, String(units[(index + 1):(index + 3)]); base = 8))
                index += 4
            else
                escaped = get(_QUOTED_ESCAPES, Char(next), nothing)
                escaped === nothing && throw(ArgumentError("a quoted path of git has the escape \\$(Char(next)): $text"))
                push!(bytes, escaped)
                index += 2
            end
        else
            push!(bytes, unit)
            index += 1
        end
    end
    throw(ArgumentError("a quoted path of git has no closing quote: $text"))
end
