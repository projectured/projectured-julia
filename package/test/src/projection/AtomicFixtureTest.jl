# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/AtomicFixtureTest.jl
#
# Proof-of-concept for the test-suite atomization plan
# (plan/pending/test-suite-atomization.md): the per-stage oracle as DATA.
#
# A stage test like `test_json_to_syntax` is not logic — it is a table of
# `(input document → expected rendering)` goldens. Here that table is expressed
# as `AtomicFixture` rows and asserted by ONE generic function (`test_atomic_render`)
# instead of a bespoke `@testset` per stage. Adding a stage means adding rows, not
# writing a test.
#
# Two fixture shapes, exactly the cases from the plan's "technique, by example":
#   • LEAF stage, bare — no recursion, no combinator
#       JsonString("hi")  ─ JsonStringToSyntaxLeaf()        ⇒ "\"hi\""
#   • NODE stage, children MOCKED as already-projected SyntaxLeafs passed through
#     `Preserving` — the parent node-assembly contract in isolation, no real
#     per-element JSON projection:
#       JsonArray([SyntaxLeaf("1"), SyntaxLeaf("2")])
#         ─ Recursive(TypeDispatch(JsonArray⇒JsonArrayToSyntaxNode,
#                                  SyntaxLeaf⇒Preserving))  ⇒ "[1, 2]"
#     (Legitimate because JsonArray.elements is an untyped CellVector — a domain
#     document may hold children from another, already-projected domain.)
# ═══════════════════════════════════════════════════════════════════════════

# An atomic stage fixture. `make_document` / `make_projection` are thunks (as on
# `Example`) so each assertion runs on a fresh, unaliased instance — the reactive
# `mutate` probe must not leave a mutated document behind for the next run.
#
# Oracle fields (all optional; a fixture with none falls back to a no-throw walk):
#   • render        — expected rendering: a `String` (exact) or `output -> Bool`
#                     (predicate, e.g. order-independent object checks).
#   • mutate         — `document -> ()`, a reactivity probe applied after the first
#                     render; asserts the render cell goes stale.
#   • render_after   — expected rendering after `mutate` (same String|predicate form).
struct AtomicFixture
    name::String
    make_document
    make_projection
    render
    mutate
    render_after
end

AtomicFixture(name, make_document, make_projection;
              render=nothing, mutate=nothing, render_after=nothing) =
    AtomicFixture(name, make_document, make_projection, render, mutate, render_after)

# Assert one rendering against a String (exact) or a predicate.
function _assert_render(label, actual, expected)
    if expected isa AbstractString
        actual == expected || @warn "[$label] render mismatch" expected actual
        @test actual == expected
    else
        ok = expected(actual)
        ok || @warn "[$label] render predicate failed" actual
        @test ok
    end
end

# The generic asserter — the whole point. Reused for every stage/combinator/document.
# Mirrors `test_json_to_syntax`'s proven shape: print once, wrap `render` in a Cell
# so the reactive dependency on the document is live, then (optionally) mutate and
# assert the cell goes stale and re-renders.
function test_atomic_render(fx::AtomicFixture)
    @testset "$(fx.name)" begin
        document   = fx.make_document()
        projection = fx.make_projection()
        out_tree   = projection_print(projection, document).output
        out        = Cell(() -> render(out_tree))
        if fx.render !== nothing
            _assert_render(fx.name, out[], fx.render)
        else
            out[]                      # no oracle: at least force the render (smoke)
            @test true
        end
        if fx.mutate !== nothing
            fx.mutate(document)
            @test !isuptodate(out)     # the edit invalidated the render cell
            fx.render_after === nothing || _assert_render(fx.name, out[], fx.render_after)
        end
    end
end

# ── The datafied JSON→Syntax goldens ─────────────────────────────────────────
# This list IS the content of `test_json_to_syntax`'s render assertions, as data.

# Node fixture projection: the real `JsonArrayToSyntaxNode` stage, with its
# children handled by `Preserving` (they are already SyntaxLeafs) rather than a
# recursive JSON pipeline. Same structural shape as the real `JsonToSyntax()`
# dispatch — only the leaf arms are swapped for the mockups.
_json_array_node_projection() =
    RecursiveProjection(TypeDispatchingProjection(
        JsonArray    => JsonArrayToSyntaxNode(),
        SyntaxLeaf   => PreservingProjection(),
        Vector{Cell} => CopyingProjection(),
    ))

const _json_atomic_fixtures = AtomicFixture[
    AtomicFixture("json_null_leaf",       () -> JsonNull(),       () -> JsonNullToSyntaxLeaf();   render = "null"),
    AtomicFixture("json_bool_true_leaf",  () -> JsonBool(true),   () -> JsonBoolToSyntaxLeaf();   render = "true"),
    AtomicFixture("json_bool_false_leaf", () -> JsonBool(false),  () -> JsonBoolToSyntaxLeaf();   render = "false"),
    AtomicFixture("json_number_leaf",     () -> JsonNumber(42),   () -> JsonNumberToSyntaxLeaf(); render = "42"),
    AtomicFixture("json_string_leaf",     () -> JsonString("hi"), () -> JsonStringToSyntaxLeaf(); render = "\"hi\""),
    # Reactivity probe, datafied: edit the string value, the render cell goes stale
    # and re-renders the new value.
    AtomicFixture("json_string_leaf_reactive",
        () -> JsonString("hi"), () -> JsonStringToSyntaxLeaf();
        render = "\"hi\"", mutate = d -> (d.value = "bye"), render_after = "\"bye\""),
    # Node stage with mocked children + Preserving — the headline technique.
    AtomicFixture("json_array_node",
        () -> JsonArray([SyntaxLeaf("1"), SyntaxLeaf("2")]),
        _json_array_node_projection; render = "[1, 2]"),
]

function test_atomic_fixtures()
    @testset "AtomicFixtures" begin
        for fx in _json_atomic_fixtures
            test_atomic_render(fx)
        end
    end
end
