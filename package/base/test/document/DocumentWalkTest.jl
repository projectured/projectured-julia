"""
`DocumentModule`'s `walk_document` — the one reflection walk, and the two
strategies over it: `ValueWalk` (locations are the matched objects,
`search_documents`) and `PathWalk` (locations are `ReferencePath`s,
`search_references`).

The point of this suite is the one thing the two strategies **deliberately
disagree** about: `visit_policy`. A shared node is *one object* but *two places*,
so a value walk must report it once and a path walk must report both paths. The
walk is a single traversal serving both, so nothing but a test keeps that
distinction from being flattened by a later "simplification" — which is exactly
what would happen if someone gave both strategies the same visit policy and saw
every other test stay green.

Lives in `base` (not `kernel`) because expressing a shared subtree needs a
collection document, and `CellVector` is base's.
"""

function test_document_walk()
@testset "DocumentWalk" begin

is_alice(v) = v isa PrimitiveString && v.value == "Alice"

# ── A shared subtree: ONE object occupying TWO slots ──────────────────────
# The value walk sees one node; the path walk sees two places to put a cursor.
shared = PrimitiveString("Alice")
doc    = CellVector([shared, shared])

@testset "shared subtree: one object, two places" begin
    docs = search_documents(doc, is_alice)
    refs = search_references(doc, is_alice)

    # ValueWalk — :once_per_object. The same object reached twice is the same
    # location, so the second visit has nothing to add.
    @test length(docs) == 1
    @test docs[1] === shared

    # PathWalk — :once_per_path. Two distinct paths are two distinct selections.
    @test length(refs) == 2
    @test refs[1] != refs[2]
    @test all(r -> evaluate_reference(doc, r) === shared, refs)
end

# ── Cycles terminate under both policies ──────────────────────────────────
# ValueWalk's global visited set stops on the revisit; PathWalk drops only paths
# that loop back through one of their own ancestors. Neither may hang.
@testset "cyclic graph terminates" begin
    a = ListNode(PrimitiveString("x"))
    b = ListNode(PrimitiveString("y"))
    a.next = b
    b.prev = a                      # prev/next close the loop

    is_str(v) = v isa PrimitiveString
    @test length(search_documents(a, is_str)) == 2
    @test !isempty(search_references(a, is_str))
    # maxdepth bounds a structure whose nodes are never the *same* object, which
    # the visited set alone cannot stop.
    @test length(search_references(a, is_str; maxdepth = 8)) <
          length(search_references(a, is_str; maxdepth = 64))
end

# ── The strategies agree on everything else ───────────────────────────────
@testset "strategies agree on what matches" begin
    nested = CellVector([PrimitiveString("Alice"), PrimitiveNumber(7)])

    # Same match set, reported two ways: the node, and the path to the node.
    docs = search_documents(nested, is_alice)
    refs = search_references(nested, is_alice)
    @test length(docs) == length(refs) == 1
    @test evaluate_reference(nested, refs[1]) === docs[1]

    # A String/Regex query matches leaves by textual form, through both.
    @test length(search_documents(nested, "Alice"))  == 1
    @test length(search_references(nested, r"Al.ce")) == 1

    # raw=true reports the exact matched node, folding nothing up to a document.
    @test search_documents(nested, "Alice"; raw = true) == ["Alice"]
    @test length(search_references(nested, "Alice"; raw = true)) == 1
end

end
end
