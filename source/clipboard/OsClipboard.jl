"""
    OsClipboardModule

Access to the host operating system's clipboard, behind a stubbable indirection.

The internal-clipboard projection ([`ClipboardToAnyProjectionModule`](@ref)) uses this
to mirror a copy/cut out to the OS clipboard and to fall back to the OS clipboard when
nothing is on the ProjecturEd clipboard.

The default backend shells out to the first available command-line tool
(`xclip` / `xsel` on X11, `wl-paste`/`wl-copy` on Wayland, `pbpaste`/`pbcopy` on
macOS). All reads/writes are wrapped so a missing tool or a failed invocation
degrades gracefully — `read_os_clipboard` returns `nothing` and `write_os_clipboard!`
returns `false` rather than throwing. Headless CI has none of these tools (so the OS
path is inert there); tests install an in-memory fake via
[`set_os_clipboard_backend!`](@ref).
"""
module OsClipboardModule

export read_os_clipboard, write_os_clipboard!, set_os_clipboard_backend!, reset_os_clipboard_backend!

# First program name of a command, e.g. `xclip` for `xclip -selection clipboard -o`.
_prog(cmd::Cmd) = first(cmd.exec)

# Read a command's stdout as a String, or `nothing` if it errors.
function _shell_read(cmd::Cmd)::Union{String,Nothing}
    try
        return read(cmd, String)
    catch
        return nothing
    end
end

# Pipe `text` into a command's stdin, returning `true` on success.
function _shell_write(cmd::Cmd, text::AbstractString)::Bool
    try
        open(cmd, "w") do io
            print(io, text)
        end
        return true
    catch
        return false
    end
end

# Read commands tried in order; first installed tool that yields text wins.
const _READ_COMMANDS = (
    `xclip -selection clipboard -o`,
    `xsel --clipboard --output`,
    `wl-paste --no-newline`,
    `pbpaste`,
)

# Write commands tried in order; first installed tool that succeeds wins.
const _WRITE_COMMANDS = (
    `xclip -selection clipboard -i`,
    `xsel --clipboard --input`,
    `wl-copy`,
    `pbcopy`,
)

function _default_read()::Union{String,Nothing}
    for cmd in _READ_COMMANDS
        Sys.which(_prog(cmd)) === nothing && continue
        out = _shell_read(cmd)
        out === nothing || return out
    end
    nothing
end

function _default_write(text::AbstractString)::Bool
    for cmd in _WRITE_COMMANDS
        Sys.which(_prog(cmd)) === nothing && continue
        _shell_write(cmd, text) && return true
    end
    false
end

# Indirection seam: tests swap these for an in-memory fake clipboard.
const _READER = Ref{Function}(_default_read)
const _WRITER = Ref{Function}(_default_write)

"""
    read_os_clipboard() -> Union{String,Nothing}

Return the OS clipboard's text, or `nothing` when no clipboard tool is available or
the read fails.
"""
read_os_clipboard()::Union{String,Nothing} = _READER[]()

"""
    write_os_clipboard!(text) -> Bool

Write `text` to the OS clipboard. Returns `true` on success, `false` when no
clipboard tool is available or the write fails.
"""
write_os_clipboard!(text::AbstractString)::Bool = _WRITER[](text)

"""
    set_os_clipboard_backend!(; read=_default_read, write=_default_write)

Install clipboard read/write backends. Test seam for an in-memory fake; e.g.

    buf = Ref("")
    set_os_clipboard_backend!(read = () -> buf[], write = t -> (buf[] = t; true))
"""
function set_os_clipboard_backend!(; read::Function=_default_read, write::Function=_default_write)
    _READER[] = read
    _WRITER[] = write
    nothing
end

"Restore the default shell-out clipboard backend."
reset_os_clipboard_backend!() = set_os_clipboard_backend!()

end # module
