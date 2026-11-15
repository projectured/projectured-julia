# Fragment of `FileSystemModule` — the files of the folders of a workspace, which
# a search by name lists, and that search.
#
# A task reads the folders off the loop: the files below each folder, without a
# folder whose name starts with a dot and without what a `.gitignore` names. The
# list keeps the answer of the last read, so a search shows it at once, and each
# new search reads the folders again; the list follows when that read ends.

"""
    WORKSPACE_FILE_LIMIT

The most files that a read of the folders of a workspace lists, 100,000. A read
of a larger folder, such as a home folder, stops there, and the list says so.
"""
const WORKSPACE_FILE_LIMIT = 100_000

"""
    WorkspaceFiles(folders, paths, is_cut)

What a read of the folders of a workspace found: `folders`, the absolute folders
in their order; `paths`, the absolute path of each file below them, in path order
within each folder; and `is_cut`, whether the read stopped at the limit.
"""
struct WorkspaceFiles
    folders::Vector{String}
    paths::Vector{String}
    is_cut::Bool
end

"""
    WorkspaceFileList()

The list of the files of the folders of a workspace that an editor keeps, as a
session document (`get_session_workspace_file_list`). Its cells:

- `folders`, the absolute folders that it reads;
- `read_count`, the count of the reads that were asked for, so that a new search
  reads the folders again;
- `reading`, whether a read runs now;
- `files`, a background cell of the `WorkspaceFiles` of the last read, or
  `nothing` before the first read ends.
"""
struct WorkspaceFileList
    folders::Cell
    read_count::Cell
    reading::Cell
    files::Cell
end

function WorkspaceFileList(; limit::Integer = WORKSPACE_FILE_LIMIT)
    folders = Cell(String[])
    read_count = Cell(0)
    reading = Cell(false)
    source = BackgroundSource(inputs -> Any[_read_workspace_files(folders; limit) for (folders, _) in inputs];
                              description = "the files of the folders of the workspace")
    files = make_background_cell(source, () -> (folders[], read_count[]); working = reading)
    WorkspaceFileList(folders, read_count, reading, files)
end

"""
    get_session_workspace_file_list(; editor = find_evaluation_editor()) -> WorkspaceFileList

The list of the files of the folders of the workspace that `editor` keeps, made
at the first call.
"""
function get_session_workspace_file_list end

get_session_workspace_file_list(; editor = find_evaluation_editor()) =
    editor isa Editor ? get_session_document!(WorkspaceFileList, editor, WorkspaceFileList) : WorkspaceFileList()

"""
    read_workspace_files_again!(list, folders) -> list

Ask for a new read of `folders` into `list`: the list answers the files of its
last read until the new read ends. It writes cells, so it runs where the editor
writes, such as in the evaluation of an operation.
"""
function read_workspace_files_again!(list::WorkspaceFileList, folders::AbstractVector{<:AbstractString})
    folders = String[abspath(String(folder)) for folder in folders]
    peek(list.folders) == folders || (list.folders[] = folders)
    list.read_count[] = peek(list.read_count) + 1
    list
end

# The files below `folders`, read now. This runs on a task, and reads no document.
function _read_workspace_files(folders::Vector{String}; limit::Integer = WORKSPACE_FILE_LIMIT)
    paths = String[]
    is_cut = false
    for folder in folders
        isdir(folder) || continue
        is_cut = !_read_workspace_folder!(paths, folder, "", Tuple{String,Vector{GitIgnoreRule}}[], limit)
        is_cut && break
    end
    WorkspaceFiles(folders, paths, is_cut)
end

# The files below the folder `relative` of `root` into `paths`, with the rules of
# the `.gitignore` files above it; `false` when the read stopped at the limit.
function _read_workspace_folder!(paths::Vector{String}, root::String, relative::String, rule_sets, limit::Integer)
    folder = isempty(relative) ? root : joinpath(root, relative)
    ignore_file = joinpath(folder, ".gitignore")
    if isfile(ignore_file)
        rules = read_gitignore_rules(read(ignore_file, String))
        isempty(rules) || (rule_sets = vcat(rule_sets, [(relative, rules)]))
    end
    names = try
        readdir(folder; sort = true)
    catch exception
        exception isa Base.IOError ? String[] : rethrow()
    end
    for name in names
        startswith(name, '.') && continue
        path = joinpath(folder, name)
        child = isempty(relative) ? name : relative * "/" * name
        # A link to a folder is not entered, so a loop of links ends.
        is_folder = isdir(path) && !islink(path)
        is_gitignored(rule_sets, child, is_folder) && continue
        if is_folder
            _read_workspace_folder!(paths, root, child, rule_sets, limit) || return false
        elseif isfile(path)
            length(paths) >= limit && return false
            push!(paths, path)
        end
    end
    true
end

"""
    make_workspace_file_search(list; open_files = String[]) -> WidgetChoiceList

The search of a file by its name over `list`, a `WorkspaceFileList`: a list that a
person types into, of the files that the query matches by its letters in order
(`find_letter_matches`), the file name ranking above its folder. A row shows the
name of the file and its folder. With no query, `open_files`, the absolute paths
of the open files, come first, then the other files in path order. A choice
answers `OpenFileOperation` of the path. A line under the rows says that a read
runs, or that the list stops at the limit.
"""
function make_workspace_file_search(list::WorkspaceFileList; open_files::AbstractVector{<:AbstractString} = String[])
    open_files = String[abspath(String(path)) for path in open_files]
    matches = _WorkspaceFileMatches(nothing, "", Int[], String[])
    WidgetChoiceList(; prompt = "Go to file", placeholder = "type a part of a name",
                     empty = "No file matches", fills_offer = true,
                     footer = () -> _get_workspace_search_footer(list),
                     find = query -> _find_workspace_file_choices!(matches, list.files[], query, open_files),
                     choose = path -> OpenFileOperation(path))
end

# The last search, kept so that the keys of the list, which ask the choices again,
# score no path again.
mutable struct _WorkspaceFileMatches
    files::Any
    query::String
    ranked::Vector{Int}
    texts::Vector{String}
end

function _get_workspace_search_footer(list::WorkspaceFileList)
    list.reading[] && return "Reading the files…"
    files = list.files[]
    files isa WorkspaceFiles && files.is_cut &&
        return "Only the first $(WORKSPACE_FILE_LIMIT) files are listed."
    nothing
end

# The choices of `query` over `files`, as a vector that makes each choice when it
# is read.
function _find_workspace_file_choices!(matches::_WorkspaceFileMatches, files, query::String,
                                      open_files::Vector{String})
    files isa WorkspaceFiles || return WidgetChoice[]
    if matches.files !== files
        matches.files = files
        matches.texts = _make_workspace_file_texts(files)
        matches.query = "\0"
    end
    if matches.query != query
        matches.ranked = isempty(query) ? _rank_open_files_first(files, open_files) :
                         _rank_workspace_files(matches, query)
        matches.query = query
    end
    _WorkspaceFileChoices(files, matches.texts, matches.ranked)
end

# The ranking of `query`. A query that adds letters to the last one can only lose
# matches, so it scores only the matches of the last one; it takes them in the
# order of the paths, so the ranking is the one of a search of every path.
function _rank_workspace_files(matches::_WorkspaceFileMatches, query::String)
    previous = matches.query
    if !isempty(previous) && previous != "\0" && startswith(query, previous)
        subset = sort(matches.ranked)
        return subset[find_letter_matches(query, view(matches.texts, subset); name_start = _get_name_start)]
    end
    find_letter_matches(query, matches.texts; name_start = _get_name_start)
end

# The text of each path that a query matches and a row shows: the path relative
# to its folder, after the name of the folder when there is more than one.
function _make_workspace_file_texts(files::WorkspaceFiles)
    prefix = length(files.folders) > 1
    texts = String[]
    for path in files.paths
        folder = something(findfirst(folder -> startswith(path, folder * "/"), files.folders), 0)
        base = folder == 0 ? dirname(path) : files.folders[folder]
        relative = replace(relpath(path, base), '\\' => '/')
        push!(texts, prefix ? basename(base) * "/" * relative : relative)
    end
    texts
end

# The index of the first character of the name of a path.
_get_name_start(text::AbstractString) = something(findlast(==('/'), collect(text)), 0) + 1

# The open files first, in their order, then the other files in path order.
function _rank_open_files_first(files::WorkspaceFiles, open_files::Vector{String})
    places = Dict(path => index for (index, path) in enumerate(files.paths))
    opened = Int[places[path] for path in open_files if haskey(places, path)]
    taken = Set(opened)
    vcat(opened, Int[index for index in eachindex(files.paths) if !(index in taken)])
end

# The choices of a search, each made when it is read: the name of the file, its
# folder as the note, and its absolute path as the value.
struct _WorkspaceFileChoices <: AbstractVector{WidgetChoice}
    files::WorkspaceFiles
    texts::Vector{String}
    ranked::Vector{Int}
end

Base.size(choices::_WorkspaceFileChoices) = (length(choices.ranked),)

function Base.getindex(choices::_WorkspaceFileChoices, index::Int)
    file = choices.ranked[index]
    text = choices.texts[file]
    folder = dirname(text)
    WidgetChoice(basename(text); value = choices.files.paths[file], icon = :file,
                 note = isempty(folder) ? nothing : folder)
end
