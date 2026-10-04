# Fragment of `JuliaModule`.
#
# The Julia domain's own insertion hole: the keyword scaffolds, the completion
# that drives their pale-green hint, and `JuliaInsertionToSyntaxLeaf`.
#
# `JuliaInsertion` is a text-buffer hole. Its editing, its commit and its
# navigation are reified as a document-level `@gestures JuliaInsertion` table, the
# way `@gestures PrimitiveString` reifies string char-editing. The projection is
# therefore **printer-only**: it renders the buffer plus a pale-green completion
# continuation, maps the `value{k}` char cursor, and carries no key-capturing
# reader, so raw input falls through to the gesture table — the single source of
# truth.
#
# Keyword-introduced constructs (`function`, `if`, …) do not parse as complete
# source on their own. Type one and commit it, and it expands into a **scaffold of
# holes** (nested `JuliaInsertion`s) with the first hole's char-cursor
# pre-selected. Everything else commits through `parse_julia`.
#
# The generic half of the mechanism — the shared insertion leaf, the completion
# policies and the `*Nothing` placeholder — lives in
# [`SyntaxModule`](@ref), which knows no domain.
# ── Julia keyword scaffolds + completion ───────────────────────────────────────
#
# A partially-typed prefix of a keyword shows a pale-green completion
# continuation (see `get_julia_completion`), signalling it is committable as that
# keyword. Everything else commits by `parse_julia` (a complete sub-expression
# such as `n == 0`).

# Each scaffold pre-selects its first hole's own char cursor (`…value{0}`, the buffer
# offset 0), so it is ready to type into the moment the keyword commits.
const _JULIA_KEYWORD_SCAFFOLDS = Tuple{String,Function}[
    ("function", () -> (d = JuliaFunction(JuliaInsertion(), Any[JuliaInsertion()], JuliaBlock(Any[JuliaInsertion()]));
        set_selection!(d, @reference(d, name.value{0})))),
    ("if", () -> (d = JuliaIf(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]), JuliaBlock(Any[JuliaInsertion()]));
        set_selection!(d, @reference(d, condition.value{0})))),
    ("while", () -> (d = JuliaWhile(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]));
        set_selection!(d, @reference(d, condition.value{0})))),
    ("for", () -> (d = JuliaFor(Any[JuliaForIterator(JuliaInsertion(), JuliaInsertion())], JuliaBlock(Any[JuliaInsertion()]));
        set_selection!(d, @reference(d, iterators[1].variable.value{0})))),
    ("begin", () -> (d = JuliaBegin(JuliaBlock(Any[JuliaInsertion()]));
        set_selection!(d, @reference(d, body.statements[1].value{0})))),
    ("return", () -> (d = JuliaReturn(JuliaInsertion());
        set_selection!(d, @reference(d, value.value{0})))),
]

"""
    make_julia_scaffold(text) -> Document | nothing

The keyword scaffold for `text` when it exactly names a keyword-introduced construct
(cursor pre-placed on the first hole), else `nothing`.
"""
function make_julia_scaffold(text::AbstractString)
    s = strip(text)
    for (kw, make) in _JULIA_KEYWORD_SCAFFOLDS
        s == kw && return make()
    end
    nothing
end

"""
    get_julia_completion(text) -> String

The pale-green continuation for a partially-typed keyword (`"fun"` → `"ction"`), or
`""` when `text` is empty, already a full keyword, or matches no keyword prefix.
"""
function get_julia_completion(text::AbstractString)
    s = strip(text)
    isempty(s) && return ""
    for (kw, _) in _JULIA_KEYWORD_SCAFFOLDS
        (kw != s && startswith(kw, s)) && return kw[length(s)+1:end]
    end
    ""
end

# The keyword scaffolds double as insertion *candidates*: `julia function`
# committed from a DocumentInsertion (or `function` by name inside a Julia
# scope) builds the same scaffold-of-holes the keyword commit does.
@insertion JuliaFunction = make_julia_scaffold("function")
@insertion JuliaIf       = make_julia_scaffold("if")
@insertion JuliaWhile    = make_julia_scaffold("while")
@insertion JuliaFor      = make_julia_scaffold("for")
@insertion JuliaBegin    = make_julia_scaffold("begin")
@insertion JuliaReturn   = make_julia_scaffold("return")

# Commit a Julia hole: a keyword prefix expands to its scaffold; otherwise parse the
# buffer as complete source. Partial / invalid non-keyword source can't commit.
function _julia_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    scaffold = make_julia_scaffold(value)
    scaffold === nothing || return scaffold
    try
        parse_julia(value)
    catch
        nothing
    end
end

# ── JuliaInsertion: gesture-driven structural hole ─────────────────────────────

"""
    JuliaInsertionToSyntaxLeaf(; theme = nothing)

A Julia source-insertion hole. Renders the typed buffer plus a pale-green keyword
completion continuation; all editing/commit is `@gestures JuliaInsertion`. `theme`
is a `JuliaTheme`, scaled or not, or `nothing` for the default styles.
"""
@projection UntrackedCell struct JuliaInsertionToSyntaxLeaf <: Projection
    value::StyleText
    completion::StyleText
    wrong_color::StyleColor
    found_color::StyleColor
end

JuliaInsertionToSyntaxLeaf(; theme = nothing) = JuliaInsertionToSyntaxLeaf(
    get_julia_style(theme, :plain_text),
    get_julia_style(theme, :hint_text),
    get_julia_style(theme, :wrong_color),
    get_julia_style(theme, :found_color))

# `value{k}` char-cursor ↔ the rendered `SyntaxLeaf`'s value span (identity offset).
# The completion after the buffer is a part that the leaf printed.
function map_reference_forward(p::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.output))
        proj(^(p), inner) => inner
        value{s:e} => @reference ::SyntaxLeaf.value::TextString{s:e}::Position
    end
end

function map_reference_backward(p::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ∅ => EmptyReference(get_reference_node_type(iomap.input))
        ::SyntaxLeaf.value{s:e} => @reference ::JuliaInsertion.value::String{s:e}::Position
        __ => make_introduced_reference(p, iomap, reference)
    end
end

# Julia commitability: green when the buffer is a keyword (prefix) or parses as
# complete source, red when it can commit neither way, neutral when empty.
function _julia_state(value::AbstractString)
    isempty(strip(value)) && return :empty
    make_julia_scaffold(value) === nothing || return :unambiguous
    isempty(get_julia_completion(value)) || return :unambiguous
    parsed = try parse_julia(value); true catch; false end
    parsed ? :unambiguous : :invalid
end

_julia_typed_color(p::JuliaInsertionToSyntaxLeaf, value::AbstractString) = begin
    state = _julia_state(value)
    state === :invalid ? p.wrong_color :
    state === :empty   ? p.value.color : p.found_color
end

function print_document(p::JuliaInsertionToSyntaxLeaf, recursion, ins::JuliaInsertion, ctx)
    typed = TextString(Cell(@computation something(ins.value, "")),
                       Cell(p.value.font),
                       Cell(@computation _julia_typed_color(p, something(ins.value, ""))),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(ins, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, ins, SyntaxLeaf(typed;
        close=TextString(() -> get_julia_completion(something(ins.value, "")), p.completion),
        paths...))
    iomap_cell[] = iomap
    iomap
end

# Only the structural selection mapping lives here; raw key input has no method and
# falls through to the generic `read_gesture` fallback → `@gestures JuliaInsertion`.
function read_intent(p::JuliaInsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplacePathOperation)
    path = map_reference_backward(p, iomap, op.path)
    path === nothing ? nothing : make_path_operation(op, path)
end

# Commit the buffer via `_julia_commit` (keyword scaffold or `parse_julia`); the
# rerooted `∅` targets this hole, so a nested hole is replaced in place and the
# cursor lands on the committed value's own selection (a scaffold's first hole).
_julia_ins_commit(ins) =
    (doc = _julia_commit(something(ins.value, ""));
     doc === nothing ? nothing : make_replace_document_operation(EmptyReference(), doc))

# The Tab navigation predicate + in-hole cursor: land on the next `JuliaInsertion`,
# cursor at its buffer offset 0 so it is ready to type.
_is_julia_hole(node) = node isa JuliaInsertion
const _JULIA_HOLE_CURSOR = @reference ::JuliaInsertion.value::String{0}::Position

# Tab: commit the buffer and jump to the next hole.
#  - empty buffer            → just advance (skip the untouched hole).
#  - keyword prefix          → expand to its scaffold; the scaffold already pre-selects
#                              its own first hole, so do NOT advance past it.
#  - complete parseable expr → commit, then advance to the next hole (the mid
#                              ReplaceSelectionOperation leaves the cursor on the
#                              just-committed node, which `SelectNextInsertion` steps past).
#  - otherwise (unparseable) → decline (stay in the buffer, keep typing).
function _julia_ins_tab(ins)
    value = something(ins.value, "")
    isempty(strip(value)) &&
        return SelectNextInsertionOperation(_is_julia_hole, _JULIA_HOLE_CURSOR)
    scaffold = make_julia_scaffold(value)
    scaffold === nothing ||
        return make_replace_document_operation(EmptyReference(), scaffold)
    parsed = try parse_julia(value) catch; nothing end
    parsed === nothing && return nothing
    commit = make_replace_document_operation(EmptyReference(), parsed)
    CompoundOperation(Any[commit.operations...,
                          SelectNextInsertionOperation(_is_julia_hole, _JULIA_HOLE_CURSOR)])
end

# All `JuliaInsertion` editing, reified. Char insert / Backspace / Delete reuse the
# shared `insertion_*` helpers (they decline with `nothing` off a `value[range]`
# cursor, so the gesture keeps propagating); Enter commits in place; Tab commits and
# jumps to the next hole.
@gestures JuliaInsertion begin
    KeyPress(_, t)       => "Insert character"  => insert_insertion_text_operation(doc, t)
    KeyDown(:backspace;) => "Delete backward"   => delete_insertion_text_operation(doc, :backspace)
    KeyDown(:delete;)    => "Delete forward"    => delete_insertion_text_operation(doc, :delete)
    KeyDown(:return;)    => "Commit hole"       => _julia_ins_commit(doc)
    KeyDown(:tab;)       => "Commit + next hole" => _julia_ins_tab(doc)
end
