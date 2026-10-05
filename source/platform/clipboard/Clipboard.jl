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

# The clipboard of the operating system changes, the document does not, so the
# way back is to do nothing. A history steps over it rather than stopping at it.
make_inverse_operation(document, ::WriteOsClipboardOperation) = DoNothingOperation()

# ── Reader gesture helpers ─────────────────────────────────────────────────────

_field_path(name::AbstractString) =
    ConcreteReference(FieldReferenceStep(name), EmptyReference())

# The selected sub-document and its path, or (nothing, nothing) when there is no
# usable (non-empty) selection. The clipboard reads its own selection: every
# write of the live selection starts at the root, so its own suffix is current
# (PAR-SELECTION-WRITTEN-AT-ROOT).
function _selected(input)
    sel = input.selection
    (sel === nothing || sel isa EmptyReference) && return nothing, nothing
    obj = try_evaluate_reference(input, sel, missing)
    obj === missing && return nothing, nothing
    sel, obj
end

"""
    find_clipboard_document(document) -> Document | Nothing

The document that a copy or a note takes when `document` is selected, or
`nothing` when there is none. By default `document` itself, when it is a
document. A domain answers another document when a selection names a frame
around what a person sees, such as a pane tab around the document it shows.
"""
find_clipboard_document(document) = document isa Document ? document : nothing

"""
    ClipboardCopyPolicy()

The policy of the copy that a copy gesture stores. It copies as the plain copy
does, except at a document that refuses a paste (`accepts_pasted_document`),
such as a tool: there it puts the duplicate that the document's kind declares,
so that the copy works apart from the original. The copy is refused when such a
kind declares no duplicate, and when a document holds itself through a
back-link. Made for one copy, because it records every document it copies.
"""
struct ClipboardCopyPolicy <: CopyPolicy
    copies::IdDict{Any,Any}
end
ClipboardCopyPolicy() = ClipboardCopyPolicy(IdDict{Any,Any}())

is_descendable_for_copy(::ClipboardCopyPolicy, document) = accepts_pasted_document(document)
make_copy_placeholder(::ClipboardCopyPolicy, document) =
    has_document_duplicate(document) ? make_document_duplicate(document) :
    throw(DocumentCopyException(document, "it refuses a paste, and its kind declares no duplicate"))
get_copy_memo(policy::ClipboardCopyPolicy) = policy.copies

# The copy the clipboard stores for `document`, or `nothing` when the copy is
# refused.
function _make_clipboard_copy(document)
    try
        copy_document(ClipboardCopyPolicy(), document)
    catch exception
        exception isa DocumentCopyException || rethrow()
        nothing
    end
end

# The path a paste (or a cut) writes `value` to, or `nothing` when it must not
# write. Three rules hold, each checked against the tree as it stands:
#
# 1. The selection names a whole document. A caret or a range names none, so the
#    key goes on to the content, whose own reader pastes text.
# 2. Every document from the content down to the target accepts a pasted
#    document (`accepts_pasted_document`). A record or a tool refuses, and so
#    does everything inside it. Such a document can still be the pasted value:
#    a noted tool, or the duplicate that a copy of one stores.
# 3. The slot takes `value`: an immutable field cell refuses, and so does a slot
#    whose declared type does not admit `value` (`is_admitted_by_declared_type`),
#    and the document in the slot when it does not accept `value` as its
#    replacement (`accepts_pasted_replacement`).
function _find_paste_target(input, value)
    sel = input.selection
    (sel === nothing || sel isa EmptyReference) && return nothing
    try_evaluate_reference(input, sel, missing) isa Document || return nothing
    steps = get_reference_steps(strip_reference_types(sel))
    node = input
    # The document whose domain owns an element: the nearest one above the list.
    owner = input
    for i in eachindex(steps)
        parent = node
        (parent isa Document && !is_element_collection(parent)) && (owner = parent)
        node = try_evaluate_reference(input, _make_steps_path(steps[1:i]), missing)
        node === missing && return nothing
        (node isa Document && !accepts_pasted_document(node)) && return nothing
        i == length(steps) || continue
        _is_slot_accepting(parent, steps[i], value, owner) || return nothing
        accepts_pasted_replacement(node, value) || return nothing
    end
    sel
end

_make_steps_path(steps) =
    foldr((step, tail) -> ConcreteReference(step, tail), steps; init = EmptyReference())

function _is_slot_accepting(parent, step, value, owner)
    # An element of a list is a slot; a step that holds a drawn object is not one.
    if step isa RangeReferenceStep
        declared_type = find_declared_element_type(parent)
        return declared_type === nothing ||
               is_admitted_by_declared_type(owner, declared_type, value)
    end
    step isa FieldReferenceStep || return false
    name = Symbol(step.name)
    hasfield(typeof(parent), name) || return false
    cell = getfield(parent, name)
    cell isa AbstractCell || return true
    cell isa ImmutableCell && return false
    declared_type = parent isa Document ? find_declared_field_type(typeof(parent), name) : nothing
    declared_type === nothing && return value isa get_cell_value_type(cell)
    is_admitted_by_declared_type(parent, declared_type, value)
end

# ── Text targets ──────────────────────────────────────────────────────────────
#
# A selection that ends in a field and a range of that field's text is a text
# target: a text cursor, or a range of characters. A paste there puts text in,
# a copy of a range takes its characters, and the edit is the one that typing
# makes. The field holds a string, nothing, or a number; any other value, such
# as a span of the text domain, is not a text target.

"""
    TextTarget

A place a paste puts text: the selection `path` (rooted at the clipboard
document), the `document` and the `field` it ends in, that field's `value`, the
selected characters `start..stop`, and whether the field holds text or a number
(`kind` is `:text` or `:number`).
"""
struct TextTarget
    path::Reference
    document::Any
    field::Symbol
    value::Any
    start::Int
    stop::Int
    kind::Symbol
end

# The text target the clipboard's selection names, or `nothing`. For an edit
# (`writes`), every document from the content down to the target must accept
# pasted text; a copy reads, and asks none.
function _find_text_target(input; writes::Bool)
    sel = input.selection
    sel isa ConcreteReference || return nothing
    steps = get_reference_steps(strip_reference_types(sel))
    length(steps) >= 3 || return nothing
    range, field = steps[end], steps[end - 1]
    (range isa RangeReferenceStep && field isa FieldReferenceStep) || return nothing
    document = nothing
    for i in 1:(length(steps) - 2)
        document = try_evaluate_reference(input, _make_steps_path(steps[1:i]), missing)
        document === missing && return nothing
        (writes && document isa Document && !accepts_pasted_text(document)) && return nothing
    end
    document isa Document || return nothing
    name = Symbol(field.name)
    hasfield(typeof(document), name) || return nothing
    value = getproperty(document, name)
    kind = _find_text_kind(document, name, value)
    kind === nothing && return nothing
    TextTarget(sel, document, name, value, range.start, range.stop, kind)
end

# Whether a field takes text or a number, or `nothing` when it takes neither. An
# empty field says it by its document, or by the value type of its cell.
function _find_text_kind(document, name::Symbol, value)
    value isa AbstractString && return :text
    value isa Number && return :number
    value === nothing || return nothing
    document isa PrimitiveNumber && return :number
    cell = getfield(document, name)
    T = cell isa AbstractCell ? get_cell_value_type(cell) : Any
    String <: T ? :text : Int <: T ? :number : nothing
end

# The characters `start+1 .. stop` of a target's value.
function _get_text_target_text(target::TextTarget)
    value = target.value
    chars = collect(value isa AbstractString ? value : value === nothing ? "" : string(value))
    n = length(chars)
    String(chars[(clamp(target.start, 0, n) + 1):clamp(target.stop, 0, n)])
end

# The edit that puts `text` over a target's range: the one typing makes.
_make_text_target_edit(target::TextTarget, text::AbstractString) =
    target.kind === :number ? ReplaceNumberRangeOperation(target.path, String(text)) :
                              ReplaceStringRangeOperation(target.path, String(text))

# The text a paste puts at `target`, from `text`, or `nothing` when it puts none.
# A field that holds no line break drops the line breaks `text` ends with, and a
# number field takes only a result that is a number.
function _make_pasted_text(target::TextTarget, text::AbstractString)
    text = replace(String(text), "\r\n" => "\n")
    value = target.value
    (value isa AbstractString && occursin('\n', value)) || (text = rstrip(text, ('\n', '\r')))
    isempty(text) && return nothing
    if target.kind === :number
        old = value === nothing ? "" : string(value)
        result = splice_string(old, target.start, target.stop, text)
        splice_number(old, target.start, target.stop, text) === nothing &&
            !isempty(result) && return nothing
    end
    String(text)
end

# Only a real collection merges; anything else a reader returned is not one.
_collected_intents(op::CollectedIntentsOperation) = op
_collected_intents(::Any) = nothing
