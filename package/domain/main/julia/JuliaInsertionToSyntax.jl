"""
    JuliaInsertionToSyntaxModule

The Julia domain's own insertion hole: the keyword scaffolds, the completion
that drives their pale-green hint, and `JuliaInsertionToSyntaxLeaf`.

`JuliaInsertion` is a text-buffer hole. Its editing, its commit and its
navigation are reified as a document-level `@gestures JuliaInsertion` table, the
way `@gestures PrimitiveString` reifies string char-editing. The projection is
therefore **printer-only**: it renders the buffer plus a pale-green completion
continuation, maps the `value{k}` char cursor, and carries no key-capturing
reader, so raw input falls through to the gesture table — the single source of
truth.

Keyword-introduced constructs (`function`, `if`, …) do not parse as complete
source on their own. Type one and commit it, and it expands into a **scaffold of
holes** (nested `JuliaInsertion`s) with the first hole's char-cursor
pre-selected. Everything else commits through `juliaparse`.

The generic half of the mechanism — the shared insertion leaf, the completion
policies and the `*Nothing` placeholder — lives in
[`DocumentInsertionToSyntaxModule`](@ref), which knows no domain.
"""
module JuliaInsertionToSyntaxModule

import ..ProjectionApiModule: print_document, read_intent,
                              map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..SelectionModule: with_selection
import ..DomainModule: var"@insertion"
import ..DocumentInsertionToSyntaxModule: insertion_insert, insertion_delete
import ..JuliaModule: JuliaInsertion,
                      JuliaFunction, JuliaIf, JuliaWhile, JuliaFor, JuliaForIterator,
                      JuliaBegin, JuliaReturn, JuliaBlock
import ..JuliaParserModule: juliaparse
import ..EventModule: KeyPress, KeyDown
import ..GestureBindingModule: var"@gestures"
import ..SyntaxModule: SyntaxLeaf
import ..TextModule: TextString
import ..StyleTextModule: StyleText, DStyleText
import ..FontModule: font_ubuntu_monospace_regular_20
import ..ColorModule: color_solarized_green, color_solarized_red,
                      color_completion_hint, color_default
import ..OperationModule: replace_document, ReplaceSelectionOperation,
                          SelectNextInsertionOperation, CompoundOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, EmptyReference, Position
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..ProjectionReferenceStepModule: introduced_reference
import ..IoMapModule: SimpleIoMap
import ..CellModule: Cell, ComputedCell

export JuliaInsertionToSyntaxLeaf, julia_completion, julia_scaffold

# ── Julia keyword scaffolds + completion ───────────────────────────────────────
#
# A partially-typed prefix of a keyword shows a pale-green completion
# continuation (see `julia_completion`), signalling it is committable as that
# keyword. Everything else commits by `juliaparse` (a complete sub-expression
# such as `n == 0`).

# Each scaffold pre-selects its first hole's own char cursor (`…value{0}`, the buffer
# offset 0), so it is ready to type into the moment the keyword commits.
const _JULIA_KEYWORD_SCAFFOLDS = Tuple{String,Function}[
    ("function", () -> (d = JuliaFunction(JuliaInsertion(), Any[JuliaInsertion()], JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, name.value{0})))),
    ("if", () -> (d = JuliaIf(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]), JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, condition.value{0})))),
    ("while", () -> (d = JuliaWhile(JuliaInsertion(), JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, condition.value{0})))),
    ("for", () -> (d = JuliaFor(Any[JuliaForIterator(JuliaInsertion(), JuliaInsertion())], JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, iterators[1].variable.value{0})))),
    ("begin", () -> (d = JuliaBegin(JuliaBlock(Any[JuliaInsertion()]));
        with_selection(d, @reference(d, body.statements[1].value{0})))),
    ("return", () -> (d = JuliaReturn(JuliaInsertion());
        with_selection(d, @reference(d, value.value{0})))),
]

"""
    julia_scaffold(text) -> Document | nothing

The keyword scaffold for `text` when it exactly names a keyword-introduced construct
(cursor pre-placed on the first hole), else `nothing`.
"""
function julia_scaffold(text::AbstractString)
    s = strip(text)
    for (kw, make) in _JULIA_KEYWORD_SCAFFOLDS
        s == kw && return make()
    end
    nothing
end

"""
    julia_completion(text) -> String

The pale-green continuation for a partially-typed keyword (`"fun"` → `"ction"`), or
`""` when `text` is empty, already a full keyword, or matches no keyword prefix.
"""
function julia_completion(text::AbstractString)
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
@insertion JuliaFunction = julia_scaffold("function")
@insertion JuliaIf       = julia_scaffold("if")
@insertion JuliaWhile    = julia_scaffold("while")
@insertion JuliaFor      = julia_scaffold("for")
@insertion JuliaBegin    = julia_scaffold("begin")
@insertion JuliaReturn   = julia_scaffold("return")

# Commit a Julia hole: a keyword prefix expands to its scaffold; otherwise parse the
# buffer as complete source. Partial / invalid non-keyword source can't commit.
function _julia_commit(value::AbstractString)
    isempty(strip(value)) && return nothing
    scaffold = julia_scaffold(value)
    scaffold === nothing || return scaffold
    try
        juliaparse(value)
    catch
        nothing
    end
end

# ── JuliaInsertion: gesture-driven structural hole ─────────────────────────────

"""
    JuliaInsertionToSyntaxLeaf()

A Julia source-insertion hole. Renders the typed buffer plus a pale-green keyword
completion continuation; all editing/commit is `@gestures JuliaInsertion`.
"""
@projection struct JuliaInsertionToSyntaxLeaf <: Projection
    value::ImmutableCell{DStyleText}
    completion::ImmutableCell{DStyleText}
end

JuliaInsertionToSyntaxLeaf() = JuliaInsertionToSyntaxLeaf(
    StyleText(font_ubuntu_monospace_regular_20, color_default),
    StyleText(font_ubuntu_monospace_regular_20, color_completion_hint))

# `value{k}` char-cursor ↔ the rendered `SyntaxLeaf`'s value span (identity offset).
function map_reference_forward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        value{k} => @reference ::SyntaxLeaf.value::TextString{k}::Position
    end
end

function map_reference_backward(::JuliaInsertionToSyntaxLeaf, iomap, reference)
    @reference_case reference begin
        ::SyntaxLeaf.value{k} => @reference ::JuliaInsertion.value::String{k}::Position
    end
end

# Julia commitability: green when the buffer is a keyword (prefix) or parses as
# complete source, red when it can commit neither way, neutral when empty.
function _julia_state(value::AbstractString)
    isempty(strip(value)) && return :empty
    julia_scaffold(value) === nothing || return :unambiguous
    isempty(julia_completion(value)) || return :unambiguous
    parsed = try juliaparse(value); true catch; false end
    parsed ? :unambiguous : :invalid
end

_julia_typed_color(p::JuliaInsertionToSyntaxLeaf, value::AbstractString) = begin
    state = _julia_state(value)
    state === :invalid ? color_solarized_red :
    state === :empty   ? p.value.color      : color_solarized_green
end

function print_document(p::JuliaInsertionToSyntaxLeaf, recursion, ins::JuliaInsertion, ctx)
    typed = TextString(ComputedCell(() -> something(ins.value, "")),
                       Cell(p.value.font),
                       ComputedCell(() -> _julia_typed_color(p, something(ins.value, ""))),
                       Cell(nothing), Cell(nothing), Cell(nothing), Cell(nothing))
    SimpleIoMap(p, ins, SyntaxLeaf(typed;
        close=TextString(() -> julia_completion(something(ins.value, "")), p.completion),
        selection=getfield(ins, :selection)))
end

# Only the structural selection mapping lives here; raw key input has no method and
# falls through to the generic `read_gesture` fallback → `@gestures JuliaInsertion`.
function read_intent(p::JuliaInsertionToSyntaxLeaf, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    path = op.path
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep || return nothing
    h.name == "value" ? op :
        ReplaceSelectionOperation(introduced_reference(p, iomap.input, path))
end

# Commit the buffer via `_julia_commit` (keyword scaffold or `juliaparse`); the
# rerooted `∅` targets this hole, so a nested hole is replaced in place and the
# cursor lands on the committed value's own selection (a scaffold's first hole).
_julia_ins_commit(ins) =
    (doc = _julia_commit(something(ins.value, ""));
     doc === nothing ? nothing : replace_document(EmptyReference(), doc))

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
    scaffold = julia_scaffold(value)
    scaffold === nothing || return replace_document(EmptyReference(), scaffold)
    parsed = try juliaparse(value) catch; nothing end
    parsed === nothing && return nothing
    commit = replace_document(EmptyReference(), parsed)
    CompoundOperation(Any[commit.operations...,
                          SelectNextInsertionOperation(_is_julia_hole, _JULIA_HOLE_CURSOR)])
end

# All `JuliaInsertion` editing, reified. Char insert / Backspace / Delete reuse the
# shared `insertion_*` helpers (they decline with `nothing` off a `value[range]`
# cursor, so the gesture keeps propagating); Enter commits in place; Tab commits and
# jumps to the next hole.
@gestures JuliaInsertion begin
    KeyPress(_, t)       => "Insert character"  => insertion_insert(doc, t)
    KeyDown(:backspace;) => "Delete backward"   => insertion_delete(doc, :backspace)
    KeyDown(:delete;)    => "Delete forward"    => insertion_delete(doc, :delete)
    KeyDown(:return;)    => "Commit hole"       => _julia_ins_commit(doc)
    KeyDown(:tab;)       => "Commit + next hole" => _julia_ins_tab(doc)
end

end # module
