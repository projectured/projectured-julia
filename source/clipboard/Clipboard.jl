"""
    ClipboardModule

The clipboard domain: a slice that holds one sub-document, a collection that
holds many, the two projections that show them, and access to the host
operating system's clipboard.

This file holds the OS access, because both projections mirror through it. It
also holds `WriteOsClipboardOperation` and the helpers the two readers share.
[ClipboardSliceToAny.jl](ClipboardSliceToAny.jl) and
[ClipboardCollectionToAny.jl](ClipboardCollectionToAny.jl) hold one projection
each.

The OS access sits behind a stubbable indirection. A projection uses it to
mirror a copy or a cut out to the OS clipboard, and to fall back to the OS
clipboard when nothing is on the ProjecturEd one.

The default backend shells out to the first available command-line tool
(`xclip` / `xsel` on X11, `wl-paste`/`wl-copy` on Wayland, `pbpaste`/`pbcopy` on
macOS). All reads/writes are wrapped so a missing tool or a failed invocation
degrades gracefully — `read_os_clipboard` returns `nothing` and `write_os_clipboard!`
returns `false` rather than throwing. Headless CI has none of these tools (so the OS
path is inert there); tests install an in-memory fake via
[`set_os_clipboard_backend!`](@ref).
"""
module ClipboardModule

export read_os_clipboard, write_os_clipboard!, set_os_clipboard_backend!, reset_os_clipboard_backend!
using ..CellModule
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
export ClipboardDocument
using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..IntentModule
using ..OperationModule
import ..OperationModule: evaluate_operation
using ..PrimitiveModule
using ..DomainModule
using ..SelectionModule
using ..TextModule
using ..PrinterContextModule
using ..IoMapModule
using ..GestureBindingModule
using ..EventPatternModule
using ..ProjectionGestureBindingsModule
import ..ProjectionGestureBindingsModule: get_projection_gesture_bindings
export ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
       ClipboardSliceToAnyIoMap, ClipboardCollectionToAnyIoMap,
       ToggleClipboardSliceOperation, ToggleClipboardCollectionOperation,
       WriteOsClipboardOperation
export ClipboardSlice, ClipboardCollection



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


"""
    WriteOsClipboardOperation(text)

Side-effecting operation that writes `text` to the OS clipboard at evaluate time.
It is appended to the copy/cut/note compound when the clipboard projection has a
`to_text` converter, so a ProjecturEd copy is mirrored to the system clipboard.
Best-effort: `write_os_clipboard!` degrades to a no-op (returns `false`) when no
clipboard tool is available, so this never fails an edit.
"""
struct WriteOsClipboardOperation <: Operation
    text::String
end

evaluate_operation(editor, op::WriteOsClipboardOperation) = (write_os_clipboard!(op.text); nothing)

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReference(FieldReferenceStep(name), EmptyReference())

# The selected sub-document and its path, or (nothing, nothing) when there is no
# usable (non-empty) selection.
function _selected(input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReference) && return nothing, nothing
    obj = try_evaluate_reference(input, sel, missing)
    obj === missing && return nothing, nothing
    sel, obj
end

# ── Operation re-rooting ───────────────────────────────────────────────────────
# Prepend `steps` to the reference path carried by a delegated content operation,
# so it is rooted at the clipboard document rather than at `content`.

# Only a real collection merges; anything else a reader returned is not one.
_collected_intents(op::CollectedIntentsOperation) = op
_collected_intents(::Any) = nothing

function _prefix_op(op, steps::Tuple)
    op === nothing && return nothing
    if op isa ReplaceSelectionOperation
        ReplaceSelectionOperation(_prepend(steps, op.path))
    elseif op isa ReplaceStringRangeOperation
        ReplaceStringRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceNumberRangeOperation
        ReplaceNumberRangeOperation(_prepend(steps, op.reference), op.replacement)
    elseif op isa ReplaceReferencedValueOperation
        op.document === nothing ?
            ReplaceReferencedValueOperation(nothing, _prepend(steps, op.reference), op.value) : op
    elseif op isa CompoundOperation
        CompoundOperation(Any[_prefix_op(o, steps) for o in op.operations])
    elseif op isa CollectedIntentsOperation
        # Every seam that prefixes a compound must prefix a collection the same
        # way, or the operations a listing carries arrive rooted one level too deep.
        CollectedIntentsOperation([Intent(i.gesture, _prefix_op(i.operation, steps),
                                          i.description, i.domain)
                                   for i in op.intents])
    else
        op
    end
end

function _prepend(steps::Tuple, path::Reference)
    result = path
    for step in reverse(steps)
        result = ConcreteReference(step, result)
    end
    result
end

include("ClipboardDocument.jl")
include("ClipboardSliceToAny.jl")
include("ClipboardCollectionToAny.jl")

end # module
