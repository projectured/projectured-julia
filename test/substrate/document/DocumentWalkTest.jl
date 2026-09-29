"""
`DocumentModule`'s `walk_document` — the one reflection walk, and the two searches
over it: `search_documents` (locations are the matched objects) and
`search_references` (locations are `Reference`s).

The point of this suite is the one thing the two **deliberately disagree** about:
the cycle policy. A shared node is *one object* but *two places*, so the value
search must report it once and the path search must report both paths. The walk is
a single traversal serving both — it takes the location functions and the policy as
parameters — so nothing but a test keeps that distinction from being flattened by a
later "simplification" that gave both the same policy and saw every other test stay
green.

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

    # search_documents — :once_per_object. The same object reached twice is the
    # same location, so the second visit has nothing to add.
    @test length(docs) == 1
    @test docs[1] === shared

    # search_references — :once_per_path. Two distinct paths are two distinct selections.
    @test length(refs) == 2
    @test refs[1] != refs[2]
    @test all(r -> evaluate_reference(doc, r) === shared, refs)
end

# ── descend: the caller chooses which children the walk enters ────────────
@testset "descend: a child the caller refuses is neither matched nor walked" begin
    first_alice = PrimitiveString("Alice")
    inner = CellVector([PrimitiveString("Alice")])
    outer = CellVector([first_alice, inner])
    refuse_inner(_, child) = child !== inner
    @test search_documents(outer, is_alice; descend = refuse_inner) == [first_alice]
    @test length(search_references(outer, is_alice; descend = refuse_inner)) == 1
    # The default enters every child, so passing it changes nothing.
    enter_all(_, _) = true
    @test search_documents(outer, is_alice; descend = enter_all) == search_documents(outer, is_alice)
    @test search_references(outer, is_alice; descend = enter_all) == search_references(outer, is_alice)
    @test length(search_documents(outer, is_alice)) == 2
end

# ── Cycles terminate under both policies ──────────────────────────────────
# search_documents's global visited set stops on the revisit; search_references drops only paths
# that loop back through one of their own ancestors. Neither may hang.
@testset "cyclic graph terminates" begin
    a = ListNode(PrimitiveString("x"))
    b = ListNode(PrimitiveString("y"))
    a.next = b
    b.prev = a                      # prev/next close the loop

    is_str(v) = v isa PrimitiveString
    @test length(search_documents(a, is_str)) == 2
    # The path walk records each node of the current path, so the path that comes
    # back to `a` through `b.prev` ends there, and `maxdepth` does not change the
    # count.
    @test length(search_references(a, is_str)) == 2
    @test length(search_references(a, is_str; maxdepth = 8)) ==
          length(search_references(a, is_str; maxdepth = 64))
end

@testset "a doubly linked list: the path count does not grow with maxdepth" begin
    a = ListNode(PrimitiveString("x"))
    b = ListNode(PrimitiveString("y"))
    c = ListNode(PrimitiveString("z"))
    a.next = b; b.prev = a
    b.next = c; c.prev = b

    is_str(v) = v isa PrimitiveString
    # At `b`, a path can go on to `c` or come back to `a`. Only the way on is a
    # new place, so there is one path to each of the three values. A walk that
    # does not cut the loop doubles its paths every two levels, so the depths stay
    # small enough that such a walk fails here and does not hang.
    count_paths(d) = length(search_references(a, is_str; maxdepth = d))
    @test [count_paths(d) for d in (12, 16, 24)] == [3, 3, 3]
end

# ── The path walk builds a reference for a result only ────────────────────
# A deep chain with one match at the bottom. The path search pays for the walk and
# for one path. A search that built the path of each node it visits pays once for
# each node and each depth, several times the cost of the walk.
@testset "a deep path search costs about as much as its walk" begin
    head = ListNode(PrimitiveString("top"))
    node = head
    for _ in 1:200
        node.next = ListNode(PrimitiveNumber(0))
        node = node.next
    end
    node.next = ListNode(PrimitiveString("bottom"))
    is_bottom(v) = v isa PrimitiveString && v.value == "bottom"
    object_walk = DocumentWalk(policy = :once_per_path)
    walk() = walk_document(object_walk, head, is_bottom; maxdepth = 1000)
    search() = search_references(head, is_bottom; maxdepth = 1000)
    @test length(walk()) == length(search()) == 1
    @test evaluate_reference(head, only(search())) === node.next.value
    @test @allocated(search()) < 2 * @allocated(walk())
end

# ── Equal values in two documents ─────────────────────────────────────────
# A scalar leaf has no children, so it cannot close a cycle, and the walk does not
# record it. The second document that holds an equal value is then a match too.
@testset "equal values in two documents: both documents" begin
    first_seven  = PrimitiveNumber(7)
    second_seven = PrimitiveNumber(7)
    sevens = CellVector([first_seven, second_seven])

    for query in (v -> v == 7, "7")
        found = search_documents(sevens, query)
        @test length(found) == 2
        @test found[1] === first_seven
        @test found[2] === second_seven
    end

    # raw=true reports the matched value itself. The two sevens are one value, so
    # they are one location, and the path search tells the two places apart.
    @test search_documents(sevens, v -> v == 7; raw = true) == [7]
    @test length(search_references(sevens, v -> v == 7; raw = true)) == 2
end

# ── A field named `ref` is a field like any other ─────────────────────────
@testset "a match under a field named ref is found" begin
    alice = PrimitiveString("Alice")
    holder = (ref = alice,)
    @test search_documents(holder, is_alice) == [alice]
    @test length(search_references(holder, is_alice)) == 1
end

# ── The strategies agree on everything else ───────────────────────────────
@testset "strategies agree on what matches" begin
    nested = CellVector([PrimitiveString("Alice"), PrimitiveNumber(7)])

    # Same match set, reported two ways: the node, and the path to the node.
    docs = search_documents(nested, is_alice)
    refs = search_references(nested, is_alice)
    @test length(docs) == length(refs) == 1
    @test evaluate_reference(nested, refs[1]) === docs[1]

    # A String/Regex query matches leaves by string form, through both.
    @test length(search_documents(nested, "Alice"))  == 1
    @test length(search_references(nested, r"Al.ce")) == 1

    # raw=true reports the exact matched node, folding nothing up to a document.
    @test search_documents(nested, "Alice"; raw = true) == ["Alice"]
    @test length(search_references(nested, "Alice"; raw = true)) == 1
end

end
end
