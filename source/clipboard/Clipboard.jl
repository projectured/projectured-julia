# Fragment of `ClipboardModule` — the operating system clipboard: the shell
# commands that read and write it, and the helpers that pick one for the
# platform in hand.

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

# The selection the clipboard acts on, as a path from the clipboard document.
#
# A pane verb writes the selection of the content directly, below the clipboard,
# so the clipboard's own cell can hold an old path. The content's selection is
# the current one; the clipboard's own cell decides only when it names a field
# other than `content`, such as the stored slice on display.
function _get_clipboard_selection(input)
    own = input.selection
    if own isa ConcreteReference
        head = get_reference_head(own)
        (head isa FieldReferenceStep && head.name != "content") && return own
    end
    content = input.content
    inner = (content isa Document && hasproperty(content, :selection)) ? content.selection : nothing
    inner === nothing ? own : ConcreteReference(FieldReferenceStep("content"), inner)
end

# The selected sub-document and its path, or (nothing, nothing) when there is no
# usable (non-empty) selection.
function _selected(input)
    sel = _get_clipboard_selection(input)
    (sel === nothing || sel isa EmptyReference) && return nothing, nothing
    obj = try_evaluate_reference(input, sel, missing)
    obj === missing && return nothing, nothing
    sel, obj
end

# Whether `document` can be held by the clipboard, by a copy or a note. A record
# or a tool can not: it is never pasted, and a deep copy of one can share what
# drives it, or follow a back-link without end.
_is_clipboard_value(document) = document isa Document && accepts_pasted_document(document)

# The path a paste (or a cut) writes `value` to, or `nothing` when it must not
# write. Three rules hold, each checked against the tree as it stands:
#
# 1. The selection names a whole document. A caret or a range names none, so the
#    key goes on to the content, whose own reader pastes text.
# 2. Every document from the content down to the target accepts a pasted
#    document (`accepts_pasted_document`). A record or a tool refuses, and so
#    does everything inside it. Such a document is never pasted either: a copy
#    of a tool can share what drives the original, and a second tool is the
#    work of a duplicate, not of a paste.
# 3. The slot takes `value`: a field cell whose value type `value` is not, or an
#    immutable one, refuses, and so does the document in the slot when it does
#    not accept `value` as its replacement (`accepts_pasted_replacement`).
function _find_paste_target(input, value)
    sel = _get_clipboard_selection(input)
    (sel === nothing || sel isa EmptyReference) && return nothing
    accepts_pasted_document(value) || return nothing
    try_evaluate_reference(input, sel, missing) isa Document || return nothing
    steps = get_reference_steps(strip_reference_types(sel))
    node = input
    for i in eachindex(steps)
        parent = node
        node = try_evaluate_reference(input, _make_steps_path(steps[1:i]), missing)
        node === missing && return nothing
        (node isa Document && !accepts_pasted_document(node)) && return nothing
        i == length(steps) || continue
        _is_slot_accepting(parent, steps[i], value) || return nothing
        accepts_pasted_replacement(node, value) || return nothing
    end
    sel
end

_make_steps_path(steps) =
    foldr((step, tail) -> ConcreteReference(step, tail), steps; init = EmptyReference())

function _is_slot_accepting(parent, step, value)
    step isa FieldReferenceStep || return true
    name = Symbol(step.name)
    hasfield(typeof(parent), name) || return false
    cell = getfield(parent, name)
    cell isa AbstractCell || return true
    cell isa ImmutableCell && return false
    value isa _get_cell_value_type(cell)
end

_get_cell_value_type(::AbstractCell{T}) where {T} = T

# Only a real collection merges; anything else a reader returned is not one.
_collected_intents(op::CollectedIntentsOperation) = op
_collected_intents(::Any) = nothing
