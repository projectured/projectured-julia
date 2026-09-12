"""
`ReferenceModule` — the `@reference` / `@reference_step` construction DSL and the
`@reference_case` pattern-matching DSL. The reference types and both DSLs are
one `ReferenceModule`, so this whole suite lives on the reference layer's
test folder.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document

# Placeholder node types for the typed-step tests below.
struct A end
struct B end
struct C end
struct D end
struct E end
struct F end

# Navigable toy documents for the `@reference(document, path)` annotation test.
@document struct EvalChild
    n::Int
end
@document struct EvalDoc
    child::EvalChild
end

function test_reference_builder()
@testset "ReferenceBuilder" begin

# ── basic forms ──────────────────────────────────────────────────────────

@test (@reference()) == EmptyReference()
@test strip_reference_types(@reference ::A.value::B) ==
      ConcreteReference(FieldReferenceStep("value"), EmptyReference())
@test strip_reference_types(@reference ::A.a::B.b::C.c::D) ==
      ConcreteReference(FieldReferenceStep("a"),
          ConcreteReference(FieldReferenceStep("b"),
              ConcreteReference(FieldReferenceStep("c"), EmptyReference())))

@test strip_reference_types(@reference ::A.xs::B[3]::C) ==
      ConcreteReference(FieldReferenceStep("xs"),
          ConcreteReference(ElementReferenceStep(3), EmptyReference()))

@test strip_reference_types(@reference ::A.xs::B{2}::C) ==
      ConcreteReference(FieldReferenceStep("xs"),
          ConcreteReference(PositionReferenceStep(2), EmptyReference()))

# ── {s:e} range syntax ──────────────────────────────────────────────────

@test strip_reference_types(@reference ::A.xs::B{1:3}::C) ==
      ConcreteReference(FieldReferenceStep("xs"),
          ConcreteReference(RangeReferenceStep(1, 3), EmptyReference()))

let s = 2, e = 7
    @test strip_reference_types(@reference ::A.xs::B{s:e}::C) ==
          ConcreteReference(FieldReferenceStep("xs"),
              ConcreteReference(RangeReferenceStep(2, 7), EmptyReference()))
end

# bare {s:e} as a relative subpath
let s = 4, e = 9
    @test strip_reference_types(@reference ::A{s:e}::B) ==
          ConcreteReference(RangeReferenceStep(4, 9), EmptyReference())
end

# ── [i, j] range syntax ─────────────────────────────────────────────────
#
# The bracket says the numbering: `[…]` counts elements from 1 and `{…}` counts
# the gaps between them from 0. So `xs[2, 3]` is the second and third elements,
# and the step it builds counts the gaps that bound them.

@test strip_reference_types(@reference ::A.xs::B[2, 3]::C) ==
      ConcreteReference(FieldReferenceStep("xs"),
          ConcreteReference(RangeReferenceStep(1, 3), EmptyReference()))

# a range of one element is that element
@test strip_reference_types(@reference ::A.xs::B[2, 2]::C) ==
      strip_reference_types(@reference ::A.xs::B[2]::C)

# the two spellings name the same run
@test strip_reference_types(@reference ::A.xs::B[2, 3]::C) ==
      strip_reference_types(@reference ::A.xs::B{1:3}::C)

let i = 3, j = 5
    @test strip_reference_types(@reference ::A.xs::B[i, j]::C) ==
          ConcreteReference(FieldReferenceStep("xs"),
              ConcreteReference(RangeReferenceStep(2, 5), EmptyReference()))
end

# bare [i, j] as a relative subpath
@test strip_reference_types(@reference ::A[2, 3]::B) ==
      ConcreteReference(RangeReferenceStep(1, 3), EmptyReference())

# ── typed steps: `::T` interleaved with `.field` / `[i]` (step 3b) ────────
# A `.field` or `[i]` following a mid-path `::Type` is a new step, not
# `getfield` on the type value. The types fold onto the nodes their following
# step descends from; the terminal records the landed type.
@test (@reference ::A.entries::B[1]::C.key::D) ==
      ConcreteReference(A, FieldReferenceStep("entries"),
          ConcreteReference(B, ElementReferenceStep(1),
              ConcreteReference(C, FieldReferenceStep("key"),
                  EmptyReference(D))))

# A cursor terminal after a typed chain.
@test (@reference ::A.value::String{0}::Position) ==
      ConcreteReference(A, FieldReferenceStep("value"),
          ConcreteReference(String, RangeReferenceStep(0, 0),
              EmptyReference(Position)))

# `@reference(document, path)` — a typeless skeleton annotated against a live
# document, so the result carries the document's exact node types. Equivalent
# to spelling every type inline, but the types are filled by the document.
let doc = EvalDoc(EvalChild(7))
    @test (@reference(doc, child.n)) == (@reference ::EvalDoc.child::EvalChild.n::Int)
    # …and it evaluates to the same node the plain path reaches.
    @test evaluate_reference(doc, @reference(doc, child.n)) == 7
end

# ── ^() splice ──────────────────────────────────────────────────────────

let p = @reference ::A.children::B[2]::C.name::D
    @test strip_reference_types(@reference ::E.value.^(p)) ==
          ConcreteReference(FieldReferenceStep("value"),
              ConcreteReference(FieldReferenceStep("children"),
                  ConcreteReference(ElementReferenceStep(2),
                      ConcreteReference(FieldReferenceStep("name"), EmptyReference()))))

    @test strip_reference_types(@reference ::E.^(p)) == strip_reference_types(p)

    # @reference_step returns a FieldReferenceStep (a single step, no type). To splice it via
    # ^() in a strict-typed @reference, first build a typed 1-step path from it.
    # (Note: ::A.^(step_path).field::B cannot be written with leading ::A when
    # .^ is involved — Julia parses ::A as the minimal grab, leaving .^(step_path)
    # as a broadcast. Use ^(step_path).field::B with a pre-typed step_path instead.)
    let step = @reference_step value
        step_path = @reference ::A.value::E
        @test strip_reference_types(@reference ^(step_path).field::B) ==
              ConcreteReference(FieldReferenceStep("value"),
                  ConcreteReference(FieldReferenceStep("field"), EmptyReference()))
    end
end

# splice with a single step at the tail
let s = @reference ::A.foo::B
    @test strip_reference_types(@reference ::C.value.^(s)) ==
          ConcreteReference(FieldReferenceStep("value"),
              ConcreteReference(FieldReferenceStep("foo"), EmptyReference()))
end

# splice at start with subsequent steps
# Note: ::A.^(base).inner::B cannot be spelled with a leading ::A type since
# Julia's parser grabs ::A minimally and leaves .^(base) as a broadcast.
# Instead, rely on base being fully typed and add ::B only for the terminal.
let base = @reference ::A.root::B.outer::C
    @test strip_reference_types(@reference ^(base).inner::B) ==
          ConcreteReference(FieldReferenceStep("root"),
              ConcreteReference(FieldReferenceStep("outer"),
                  ConcreteReference(FieldReferenceStep("inner"), EmptyReference())))
end

# ── @reference_step companion ─────────────────────────────────────────────────────

@test (@reference_step value) == FieldReferenceStep("value")
@test (@reference_step xs[4]) == ElementReferenceStep(4)
@test (@reference_step xs{3}) == PositionReferenceStep(3)
@test (@reference_step xs{1:5}) == RangeReferenceStep(1, 5)
@test (@reference_step xs[2, 5]) == RangeReferenceStep(1, 5)
# `@reference_step c.point(2, 3)` moved to the visual test suite alongside PointReferenceStep.

# ── @reference_case range pattern ───────────────────────────────────────

let sample = strip_reference_types(@reference ::A.items::B{2:5}::C)
    matched = @reference_case sample begin
        items{s:e} => (s, e)
    end
    @test matched == (2, 5)
end

# an element-numbered pattern binds the 1-based first and last element
let sample = strip_reference_types(@reference ::A.items::B[2, 5]::C)
    matched = @reference_case sample begin
        items[i, j] => (i, j)
    end
    @test matched == (2, 5)
end

# and it reads the same step the gap-numbered pattern reads
let sample = strip_reference_types(@reference ::A.items::B[2, 5]::C)
    matched = @reference_case sample begin
        items{1:5} => :gap_match
        __ => :fallback
    end
    @test matched == :gap_match
end

# range pattern with literal bounds
let sample = strip_reference_types(@reference ::A.items::B{4:7}::C)
    matched = @reference_case sample begin
        items{4:7} => :literal_match
        __ => :fallback
    end
    @test matched == :literal_match
end

# range pattern matches any RangeReferenceStep, including positions, since they
# are represented identically. The position pattern is more specific, so it
# wins when listed first.
let sample = strip_reference_types(@reference ::A.items::B{3}::C)
    matched = @reference_case sample begin
        items{k}   => :position
        items{s:e} => :range
    end
    @test matched == :position

    matched2 = @reference_case sample begin
        items{s:e} => (:range, s, e)
    end
    @test matched2 == (:range, 3, 3)
end

# ── @reference_case type binding (::t) ───────────────────────────────────
# A lowercase `::t` binds the matched node's folded `type` field; a
# capitalized `::T` is a narrowing assertion instead. Construction's `::t` splices
# the runtime type value, so a bound type round-trips through reconstruction.

# Terminal type binding on a whole-element (∅) selection.
let typed = ConcreteReference(Int, FieldReferenceStep("value"), EmptyReference(String))
    bound_terminal = @reference_case typed begin
        value::t => t
    end
    @test bound_terminal === String        # the terminal node's recorded type

    bound_node = @reference_case typed begin
        ::n.value => n
    end
    @test bound_node === Int                # the node the .value step descends from
end

# ∅::t binds the terminal type of a whole-element selection.
let whole = EmptyReference(Symbol)
    got = @reference_case whole begin
        (∅::t) => t
        __     => :miss
    end
    @test got === Symbol
end

# A bound type splices back through construction (the identity-preserving
# reconstruction pattern generic combinators use).
let src = ConcreteReference(Int, FieldReferenceStep("value"), EmptyReference(String))
    rebuilt = @reference_case src begin
        ::a.value::b => @reference ::a.value::b
    end
    @test rebuilt == src                    # same path, types preserved by binding
end

# `::T.field` after a mid-path `::Type` in a PATTERN (step 3b, pattern side).
let multi = @reference ::A.entries::B[1]::C.key::D
    matched = @reference_case multi begin
        ::A.entries::B[i]::C.key::D => (:hit, i)
        __                          => :miss
    end
    @test matched == (:hit, 1)
end

end
end # test_reference_builder
