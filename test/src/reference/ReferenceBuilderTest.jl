function test_reference_builder()
@testset "ReferenceBuilder" begin

# ── basic forms ──────────────────────────────────────────────────────────

@test (@reference()) == EmptyReferencePath()
@test (@reference value) == ConcreteReferencePath(FieldReference("value"), EmptyReferencePath())
@test (@reference a.b.c) ==
      ConcreteReferencePath(FieldReference("a"),
          ConcreteReferencePath(FieldReference("b"),
              ConcreteReferencePath(FieldReference("c"), EmptyReferencePath())))

@test (@reference xs[3]) ==
      ConcreteReferencePath(FieldReference("xs"),
          ConcreteReferencePath(ElementReference(3), EmptyReferencePath()))

@test (@reference xs{2}) ==
      ConcreteReferencePath(FieldReference("xs"),
          ConcreteReferencePath(PositionReference(2), EmptyReferencePath()))

# ── {s:e} range syntax ──────────────────────────────────────────────────

@test (@reference xs{1:3}) ==
      ConcreteReferencePath(FieldReference("xs"),
          ConcreteReferencePath(RangeReference(1, 3), EmptyReferencePath()))

let s = 2, e = 7
    @test (@reference xs{s:e}) ==
          ConcreteReferencePath(FieldReference("xs"),
              ConcreteReferencePath(RangeReference(2, 7), EmptyReferencePath()))
end

# bare {s:e} as a relative subpath
let s = 4, e = 9
    @test (@reference {s:e}) ==
          ConcreteReferencePath(RangeReference(4, 9), EmptyReferencePath())
end

# ── ^() splice ──────────────────────────────────────────────────────────

let p = @reference children[2].name
    @test (@reference value.^(p)) ==
          ConcreteReferencePath(FieldReference("value"),
              ConcreteReferencePath(FieldReference("children"),
                  ConcreteReferencePath(ElementReference(2),
                      ConcreteReferencePath(FieldReference("name"), EmptyReferencePath()))))

    @test (@reference ^(p)) == p

    let step = @step value
        @test (@reference ^(step).field) ==
              ConcreteReferencePath(FieldReference("value"),
                  ConcreteReferencePath(FieldReference("field"), EmptyReferencePath()))
    end
end

# splice with a single step at the tail
let s = FieldReference("foo")
    @test (@reference value.^(s)) ==
          ConcreteReferencePath(FieldReference("value"),
              ConcreteReferencePath(FieldReference("foo"), EmptyReferencePath()))
end

# splice at start with subsequent steps
let base = @reference root.outer
    @test (@reference ^(base).inner) ==
          ConcreteReferencePath(FieldReference("root"),
              ConcreteReferencePath(FieldReference("outer"),
                  ConcreteReferencePath(FieldReference("inner"), EmptyReferencePath())))
end

# ── @step companion ─────────────────────────────────────────────────────

@test (@step value) == FieldReference("value")
@test (@step xs[4]) == ElementReference(4)
@test (@step xs{3}) == PositionReference(3)
@test (@step xs{1:5}) == RangeReference(1, 5)
@test (@step c.point(2, 3)) == PointReference(2, 3)

# ── @reference_case range pattern ───────────────────────────────────────

let sample = @reference items{2:5}
    matched = @reference_case sample begin
        items{s:e} => (s, e)
    end
    @test matched == (2, 5)
end

# range pattern with literal bounds
let sample = @reference items{4:7}
    matched = @reference_case sample begin
        items{4:7} => :literal_match
        _ => :fallback
    end
    @test matched == :literal_match
end

# range pattern matches any RangeReference, including positions, since they
# are represented identically. The position pattern is more specific, so it
# wins when listed first.
let sample = @reference items{3}
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

end
end

export test_reference_builder
