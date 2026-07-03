# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/JuliaTypeinTest.jl
#
# Julia structural type-in: building the `factorial` function from an empty
# `JuliaInsertion` by the reified `@gestures JuliaInsertion` operations
# (keyword scaffolds + completion, char commit/parse, Tab commit-and-advance),
# and the kernel `SelectNextInsertionOperation` hole navigation.
#
# Three layers are exercised:
#   1. SelectNextInsertionOperation walks holes in document pre-order.
#   2. The gesture-produced operations, applied to a document (with rerooting),
#      compose into exactly `make_julia_document_example()`.
#   3. Interactive: replaying the full keystroke script as real key events through
#      `RecursiveProjection(JuliaToSyntax())` builds the same factorial tree — the
#      end-to-end acceptance, now that every JuliaToSyntax node is templated and so
#      routes nested-hole input and reroots the resulting edits.
# ═══════════════════════════════════════════════════════════════════════════

using Projectured
using Projectured: JuliaInsertion, JuliaFunction, JuliaIdentifier, JuliaInteger, JuliaBlock,
                   JuliaIf, JuliaBinaryOp, JuliaCall, Document,
                   SelectNextInsertionOperation, evaluate_operation, evaluate_reference,
                   set_selection!, with_selection, strip_reference_types,
                   ConcreteReferencePath, FieldReference, RangeReference, EmptyReferencePath,
                   RecursiveProjection, JuliaToSyntax, projection_print, projection_read,
                   KeyPress, KeyDown, Modifiers
using Projectured.ReactiveModule: Cell
using ProjecturedExample: make_julia_document_example

const _JT_M      = Projectured.DocumentInsertionToSyntaxModule
const _jt_reroot = Projectured.OperationRerootingModule.reroot_operation

# `value{0}` — an empty hole's own char cursor.
_jt_v0() = ConcreteReferencePath(FieldReference("value"),
             ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
_jt_hole(node) = node isa JuliaInsertion

# A minimal mutable editor (a whole-root swap rebinds `.document`).
mutable struct _JtEditor; document; iomap; end

# Structural equality ignoring `selection` (holes vs the reference tree).
function _jt_equal(a, b)
    typeof(a) === typeof(b) || return false
    if nameof(typeof(a)) === :CellVector
        length(a) == length(b) || return false
        return all(_jt_equal(a[i], b[i]) for i in 1:length(a))
    end
    for nm in fieldnames(typeof(a))
        nm === :selection && continue
        av = getfield(a, nm); av = av isa Cell ? av[] : av
        bv = getfield(b, nm); bv = bv isa Cell ? bv[] : bv
        if av isa Document || nameof(typeof(av)) === :CellVector
            _jt_equal(av, bv) || return false
        else
            av == bv || return false
        end
    end
    return true
end

# The focused hole's node path: the current selection minus its trailing
# `.value{k}` char cursor (two steps), type checkpoints stripped.
function _jt_hole_path(sel)
    p = strip_reference_types(sel)
    steps = Any[]
    while p isa ConcreteReferencePath
        push!(steps, p.head); p = p.tail
    end
    steps = steps[1:end-2]
    r = EmptyReferencePath()
    for s in Iterators.reverse(steps); r = ConcreteReferencePath(s, r); end
    r
end

_jt_steps(p) = (out = Any[]; while p isa ConcreteReferencePath; push!(out, p.head); p = p.tail; end; Tuple(out))

# Simulate: type `text` into the focused hole, then run the gesture (`:tab` =
# commit-and-advance, `:enter` = commit in place). The gesture op is `∅`-rooted at
# the hole, so it is rerooted to the hole's absolute path (what the projection chain
# does live) before evaluation. Returns the (possibly swapped) document.
function _jt_step!(ed::_JtEditor, text::AbstractString; via::Symbol=:tab)
    holepath = _jt_hole_path(getfield(ed.document, :selection)[])
    hole = evaluate_reference(ed.document, holepath)
    getfield(hole, :value)[] = text
    op0 = via === :tab ? _JT_M._julia_ins_tab(hole) : _JT_M._julia_ins_commit(hole)
    op0 === nothing && return ed.document
    evaluate_operation(ed, _jt_reroot(op0, _jt_steps(holepath)))
    ed.document
end

# ── Interactive driver: real key events through the JuliaToSyntax pipeline ──────
_jt_keys(s) = [KeyPress(c, string(c), Modifiers()) for c in s]
const _JT_TAB = KeyDown(:tab, Modifiers())
const _JT_RET = KeyDown(:return, Modifiers())

# Feed one event through `proj`; returns the (possibly root-swapped) document.
function _jt_feed(proj, doc, ev)
    iom = projection_print(proj, doc)
    op  = projection_read(proj, iom, ev)
    op === nothing && return doc
    ed = _JtEditor(doc, iom)
    evaluate_operation(ed, op)
    ed.document
end

# Replay an event script from a fresh root `JuliaInsertion` through `JuliaToSyntax`.
function _jt_interactive(script)
    proj = RecursiveProjection(JuliaToSyntax())
    doc  = with_selection(JuliaInsertion(""), _jt_v0())
    for ev in script
        doc = _jt_feed(proj, doc, ev)
    end
    doc
end

function test_julia_typein()
    @testset "Julia type-in" begin
        @testset "SelectNextInsertion walks holes in pre-order" begin
            sc = _JT_M.julia_scaffold("function")   # holes: name, params[1], body.statements[1]
            op = SelectNextInsertionOperation(_jt_hole, _jt_v0())
            starts = String[]
            push!(starts, repr(getfield(sc, :selection)[]))
            for _ in 1:3
                evaluate_operation((document = sc,), op)
                push!(starts, repr(getfield(sc, :selection)[]))
            end
            @test occursin("name", starts[1])
            @test occursin("params", starts[2])
            @test occursin("body", starts[3]) && occursin("statements", starts[3])
            @test starts[4] == starts[3]   # clamp at the last hole
        end

        @testset "gesture operations build the factorial tree" begin
            ed = _JtEditor(with_selection(JuliaInsertion(""), _jt_v0()), nothing)
            _jt_step!(ed, "function")               # -> JuliaFunction scaffold, cursor on name
            @test ed.document isa JuliaFunction
            _jt_step!(ed, "factorial")              # name
            _jt_step!(ed, "n")                       # params[1]
            _jt_step!(ed, "if")                      # body stmt -> JuliaIf scaffold, cursor on cond
            _jt_step!(ed, "n == 0")                  # condition
            _jt_step!(ed, "1")                       # then block stmt
            _jt_step!(ed, "n * factorial(n - 1)"; via = :enter)  # else block stmt
            @test _jt_equal(ed.document, make_julia_document_example())
        end

        @testset "interactive build through the JuliaToSyntax pipeline" begin
            # The full keystroke script (see the plan's walkthrough): type each
            # keyword/expression, Tab to commit-and-advance, Enter for the last.
            script = vcat(_jt_keys("function"),           _JT_TAB,
                          _jt_keys("factorial"),          _JT_TAB,
                          _jt_keys("n"),                  _JT_TAB,
                          _jt_keys("if"),                 _JT_TAB,
                          _jt_keys("n == 0"),             _JT_TAB,
                          _jt_keys("1"),                  _JT_TAB,
                          _jt_keys("n * factorial(n - 1)"), _JT_RET)
            doc = _jt_interactive(script)
            @test doc isa JuliaFunction
            @test _jt_equal(doc, make_julia_document_example())
        end
    end
end
