# Fragment of `ExplorerModule` — the file of the content of an explorer: the root
# section that a binary shows for one folder, which the binary writes to the state
# folder of the user when its window closes and reads back at the next start.

"""
    get_explorer_content_file(folder) -> String

The file that keeps the content of the explorer of `folder`:
`projectured/explorer/<name>-<hash>.pred` in the state folder of the user
(`XDG_STATE_HOME`, else `~/.local/state`). `<name>` is the name of the folder and
`<hash>` a short hash of its absolute path, so two folders with one name have two
files.

Use it to find where the explorer of a folder is kept.

# Example

    get_explorer_content_file(pwd())

See also `save_explorer_content!` and `load_explorer_content`.
"""
function get_explorer_content_file end

function get_explorer_content_file(folder::AbstractString)
    path = rstrip(abspath(folder), '/')
    name = isempty(basename(path)) ? "root" : basename(path)
    state = get(ENV, "XDG_STATE_HOME", joinpath(homedir(), ".local", "state"))
    joinpath(state, "projectured", "explorer", string(name, "-", _compute_path_hash(path), ".pred"))
end

# The 32-bit FNV-1a hash of `path`, in hexadecimal: the same at every start and
# in every version of Julia, which `hash` is not.
function _compute_path_hash(path::AbstractString)
    value = 0x811c9dc5
    for byte in codeunits(path)
        value = (value ⊻ UInt32(byte)) * 0x01000193
    end
    string(value; base = 16, pad = 8)
end

"""
    save_explorer_content!(content, path; editor = find_evaluation_editor())

Write the section `content` to the file `path`, each entry as its kind writes
itself: a folder its place, a list of the session of `editor` a mark that a load
gives back as the list of the session of the editor that loads it, a section its
title and its entries. The folder of the file is made when it is missing. A
content that does not write leaves the file as it was, and a warning says why.

Use it to keep the content of an explorer for the next start.

# Example

    save_explorer_content!(get_session_explorer_content(), get_explorer_content_file(pwd()))

See also `load_explorer_content` and `get_explorer_content_file`.
"""
function save_explorer_content! end

function save_explorer_content!(content::ExplorerSection, path::AbstractString; editor = find_evaluation_editor())
    text = try
        run_with_evaluation_editor(() -> print_pred_text(content), editor)
    catch exception
        @warn "The explorer content does not write, so $(path) stays as it was." exception
        return nothing
    end
    mkpath(dirname(path))
    write(path, text)
    nothing
end

"""
    load_explorer_content(path; editor = find_evaluation_editor()) -> ExplorerSection or nothing

The section that the file `path` keeps, read for `editor`: each mark of a list of
a session gives the list of the session of `editor`. `nothing` when there is no
file, or when the file does not read, which a warning says.

Use it to show at a start the content of the explorer that the last window of the
folder showed.

# Example

    load_explorer_content(get_explorer_content_file(pwd()))

See also `save_explorer_content!` and `get_explorer_content_file`.
"""
function load_explorer_content end

function load_explorer_content(path::AbstractString; editor = find_evaluation_editor())
    isfile(path) || return nothing
    content = try
        run_with_evaluation_editor(() -> parse_pred_text(read(path, String)), editor)
    catch exception
        @warn "The explorer content in $(path) does not read." exception
        return nothing
    end
    content isa ExplorerSection ? content : nothing
end
