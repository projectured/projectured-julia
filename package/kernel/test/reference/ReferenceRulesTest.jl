"""
`ReferenceModule` — `@reference_rules`, the block of arms kept as a value.

The bulk of this suite is a **conformance corpus**: every construct of the pattern
grammar written twice, once as a `@reference_case` block and once as a `ReferenceRules`
object, applied to the same corpus of paths and asserted to answer identically. The two
matchers are one semantics implemented twice — compiled in `ReferenceCase.jl`,
interpreted in `ReferenceRules.jl` — and this corpus is what keeps them from drifting.

Kernel tests use ONLY toy documents, so the paths here are built from the step
vocabulary directly rather than walked out of a document.
"""

using Test
using Serialization
using ProjecturedKernel.ReferenceModule

# ── Toy node types, for the `::T` checkpoints and typed binders ──────────────

struct RulesA end
struct RulesB end
struct RulesC end
struct RulesOther end

# ── A toy extension step, registered in BOTH DSLs ────────────────────────────
#
# `.rulestoy(tag)` exists to prove the two seams stay in step: `match_reference_step`
# generates a branch for `@reference_case`, `match_reference_step_value` matches the
# same pattern against an actual step for `@reference_rules`.

struct RulesToyStep <: ReferenceStep
    tag::Symbol
end

Base.:(==)(a::RulesToyStep, b::RulesToyStep) = a.tag == b.tag
Base.show(io::IO, s::RulesToyStep) = print(io, ".rulestoy(", s.tag, ")")

ReferenceModule.get_reference_step_kind(::RulesToyStep) = :structural
ReferenceModule.evaluate_reference_step(::RulesToyStep, document) = document

ReferenceModule.build_reference_step(::Val{:rulestoy}, tagex) = :($RulesToyStep($tagex))

function ReferenceModule.match_reference_step(::Val{:rulestoy}, hex, argpats, rest_success,
                                              bound, gen_value_match, gen_path_match)
    inner, bound1 = gen_value_match(:($hex.tag), argpats[1], rest_success, bound)
    ex = quote
        if $hex isa $RulesToyStep
            $inner
        else
            _nomatch
        end
    end
    return ex, bound1
end

ReferenceModule.match_reference_step_value(::Val{:rulestoy}, step, argpats, bindings,
                                           match_value, match_path) =
    step isa RulesToyStep ? match_value(step.tag, argpats[1], bindings) : nothing

# ── Path construction shorthands ─────────────────────────────────────────────

_fld(name) = FieldReferenceStep(name)
_el(i) = ElementReferenceStep(i)
_pos(k) = PositionReferenceStep(k)

# Every path the corpus is applied to. Deliberately mixed: plain skeletons, folded node
# types, an unfolded `TypeReferenceStep`, element/position/range steps, an extension
# step, and both empty forms.
function _corpus_paths()
    Reference[
        EmptyReference(),
        EmptyReference(RulesA),
        Reference(_fld("a")),
        Reference(_fld("a"), _fld("b")),
        Reference(_fld("a"), _fld("b"), _fld("c")),
        Reference(_fld("a"), _fld("b"), _fld("c"), _fld("d")),
        Reference(_fld("a"), _fld("dup"), _fld("dup")),
        Reference(_fld("x"), _fld("y")),
        Reference(_fld("buckets"), _el(1), _fld("capacity")),
        Reference(_fld("buckets"), _el(2), _fld("capacity")),
        Reference(_fld("buckets"), _el(7), _fld("capacity")),
        Reference(_fld("buckets"), _el(2)),
        Reference(_fld("items"), _pos(0)),
        Reference(_fld("items"), _pos(3)),
        Reference(_fld("items"), RangeReferenceStep(1, 4)),
        Reference(RulesToyStep(:red)),
        Reference(RulesToyStep(:blue), _fld("c")),
        # folded node types — the canonical at-rest form
        ConcreteReference(RulesA, _fld("a"),
            ConcreteReference(RulesB, _fld("b"), EmptyReference(RulesC))),
        ConcreteReference(RulesOther, _fld("a"),
            ConcreteReference(RulesOther, _fld("b"), EmptyReference(RulesOther))),
        # an unfolded checkpoint step, the transitional build-time shape
        Reference(TypeReferenceStep(RulesA), _fld("a"), _fld("b")),
    ]
end

# Assert a `@reference_case` block and a `ReferenceRules` object answer identically
# across the whole corpus. `case` is the compiled matcher as a one-argument function.
function _conforms(name, case, rules, paths = _corpus_paths())
    @testset "$name" begin
        for path in paths
            expected = case(path)
            actual = apply_reference_rules(rules, path)
            @test actual == expected
        end
    end
end

function test_reference_rules()
@testset "ReferenceRules" begin

    @testset "conformance with @reference_case" begin
        _conforms("literal field path",
            p -> (@reference_case p begin
                a.b.c => :hit
                _     => :miss
            end),
            @reference_rules begin
                a.b.c => :hit
                _     => :miss
            end)

        _conforms("index binder",
            p -> (@reference_case p begin
                buckets[i].capacity => i
                _                   => :miss
            end),
            @reference_rules begin
                buckets[i].capacity => i
                _                   => :miss
            end)

        _conforms("index wildcard and literal, in order",
            p -> (@reference_case p begin
                buckets[2].capacity => :two
                buckets[_].capacity => :any
            end),
            @reference_rules begin
                buckets[2].capacity => :two
                buckets[_].capacity => :any
            end)

        _conforms("typed binder in value position",
            p -> (@reference_case p begin
                a.field(n::AbstractString) => n
                a.field(n::Int)            => :never
            end),
            @reference_rules begin
                a.field(n::AbstractString) => n
                a.field(n::Int)            => :never
            end)


        _conforms("position step",
            p -> (@reference_case p begin
                items{k} => k
                _        => :miss
            end),
            @reference_rules begin
                items{k} => k
                _        => :miss
            end)

        _conforms("range step",
            p -> (@reference_case p begin
                items{s:e} => (s, e)
                _          => :miss
            end),
            @reference_rules begin
                items{s:e} => (s, e)
                _          => :miss
            end)

        _conforms("guard",
            p -> (@reference_case p begin
                when(buckets[i].capacity, i > 3) => :big
                buckets[i].capacity              => :small
            end),
            @reference_rules begin
                when(buckets[i].capacity, i > 3) => :big
                buckets[i].capacity              => :small
            end)

        _conforms("tail bind",
            p -> (@reference_case p begin
                a.rest... => rest
                _         => :miss
            end),
            @reference_rules begin
                a.rest... => rest
                _         => :miss
            end)

        _conforms("empty path",
            p -> (@reference_case p begin
                ∅ => :whole
                _ => :miss
            end),
            @reference_rules begin
                ∅ => :whole
                _ => :miss
            end)

        _conforms("empty path with a bound terminal type",
            p -> (@reference_case p begin
                ∅::t => t
                _    => :miss
            end),
            @reference_rules begin
                ∅::t => t
                _    => :miss
            end)

        _conforms("type checkpoints",
            p -> (@reference_case p begin
                ::RulesA.a::RulesB.b::RulesC => :typed
                _                            => :miss
            end),
            @reference_rules begin
                ::RulesA.a::RulesB.b::RulesC => :typed
                _                            => :miss
            end)

        # The corpus holds one `RulesA`-typed path and one `RulesOther`-typed path of
        # the same shape, so an arm per type is decided by the node type alone.
        _conforms("a type checkpoint narrows",
            p -> (@reference_case p begin
                ::RulesA.a.b     => :a
                ::RulesOther.a.b => :other
                _                => :miss
            end),
            @reference_rules begin
                ::RulesA.a.b     => :a
                ::RulesOther.a.b => :other
                _                => :miss
            end)

        _conforms("a type checkpoint narrows an above-form",
            p -> (@reference_case p begin
                above(::RulesA.a.b.c)     => :a
                above(::RulesOther.a.b.c) => :other
                _                          => :miss
            end),
            @reference_rules begin
                above(::RulesA.a.b.c)     => :a
                above(::RulesOther.a.b.c) => :other
                _                         => :miss
            end)

        _conforms("node type binder",
            p -> (@reference_case p begin
                a::t.b => t
                _      => :miss
            end),
            @reference_rules begin
                a::t.b => t
                _      => :miss
            end)

        _conforms("extension step",
            p -> (@reference_case p begin
                rulestoy(tag).c => tag
                rulestoy(tag)   => (tag, :alone)
                _               => :miss
            end),
            @reference_rules begin
                rulestoy(tag).c => tag
                rulestoy(tag)   => (tag, :alone)
                _               => :miss
            end)

        # `^(…)` reads the construction site on both sides; here the two sites hold the
        # same values, which is what makes the answers comparable at all.
        let k = 2, interp_path = Reference(_fld("a"), _fld("b"))
            _conforms("value interpolation",
                p -> (@reference_case p begin
                    buckets[^(k)].capacity => :interp
                    _                      => :miss
                end),
                @reference_rules begin
                    buckets[^(k)].capacity => :interp
                    _                      => :miss
                end)

            _conforms("whole-path interpolation",
                p -> (@reference_case p begin
                    ^(interp_path) => :same_path
                    _              => :miss
                end),
                @reference_rules begin
                    ^(interp_path) => :same_path
                    _              => :miss
                end)
        end

        # `above(P)` is `@reference_case`'s `above(P)` — the arm holds when the input
        # runs out *inside* P. This is the one place the two vocabularies differ by name
        # rather than by meaning, so it is pinned here.
        _conforms("above(P) is above(P)",
            p -> (@reference_case p begin
                above(a.b.c) => :above
                _             => :miss
            end),
            @reference_rules begin
                above(a.b.c) => :above
                _            => :miss
            end)

        # The empty path is above everything, so an above-arm holds there without ever
        # reaching its index step — and the guard then reads a binding that was never
        # made. Both DSLs raise there, so the corpus for this one leaves it out.
        _conforms("above(P) with an index and a guard",
            p -> (@reference_case p begin
                when(above(buckets[i].capacity), i < 5) => i
                _                                        => :miss
            end),
            (@reference_rules begin
                when(above(buckets[i].capacity), i < 5) => i
                _                                       => :miss
            end),
            filter(p -> p isa ConcreteReference, _corpus_paths()))

        let interp_path = Reference(_fld("a"), _fld("b"), _fld("c"))
            _conforms("above(^(path))",
                p -> (@reference_case p begin
                    above(^(interp_path)) => :above
                    _                      => :miss
                end),
                @reference_rules begin
                    above(^(interp_path)) => :above
                    _                     => :miss
                end)
        end
    end

    @testset "the arm vocabulary" begin
        # One pattern, five forms, over paths that sit above / at / below it.
        shallow = Reference(_fld("a"))
        exact = Reference(_fld("a"), _fld("b"))
        deep = Reference(_fld("a"), _fld("b"), _fld("c"))
        elsewhere = Reference(_fld("x"))

        for (mode, rules) in (
                (:at, @reference_rules begin at(a.b) => :yes end),
                (:bare, @reference_rules begin a.b => :yes end),
                (:below, @reference_rules begin below(a.b) => :yes end),
                (:at_or_below, @reference_rules begin at_or_below(a.b) => :yes end),
                (:above, @reference_rules begin above(a.b) => :yes end),
                (:at_or_above, @reference_rules begin at_or_above(a.b) => :yes end))
            hits = [p for p in (shallow, exact, deep, elsewhere)
                    if apply_reference_rules(rules, p) === :yes]
            expected = mode === :at || mode === :bare ? [exact] :
                       mode === :below ? [deep] :
                       mode === :at_or_below ? [exact, deep] :
                       mode === :above ? [shallow] :
                       [shallow, exact]
            @test hits == expected
        end

        # `prefix(…)` is gone from both DSLs, and each says which form to write.
        @test_throws LoadError @eval @reference_rules begin
            prefix(a.b) => :nope
        end
    end

    @testset "a `::T` narrows, and says nothing where the path has no type" begin
        # Conformance alone cannot catch a regression here: it would still pass if
        # BOTH readings went back to tolerating everything. These assert the answer.
        typed = ConcreteReference(RulesA, _fld("a"),
                    ConcreteReference(RulesB, _fld("b"), EmptyReference(RulesC)))
        untyped = Reference(_fld("a"), _fld("b"))
        unfolded = Reference(TypeReferenceStep(RulesA), _fld("a"), _fld("b"))

        at_rules = @reference_rules begin
            ::RulesOther.a.b => :other
            ::RulesA.a.b     => :a
            _                => :miss
        end
        @test apply_reference_rules(at_rules, typed) === :a          # narrowed to the right arm
        @test apply_reference_rules(at_rules, untyped) === :other    # no type recorded, first arm takes it
        @test apply_reference_rules(at_rules, unfolded) === :a       # the unfolded step narrows too

        # Every mode reads the type step through the same predicate. (Parenthesized
        # macro calls: the `begin … end` block form would swallow the commas.)
        for mode_rules in (
                @reference_rules(begin ::RulesOther.a => :hit end),
                @reference_rules(begin below(::RulesOther.a) => :hit end),
                @reference_rules(begin at_or_below(::RulesOther.a) => :hit end),
                @reference_rules(begin above(::RulesOther.a.b.c) => :hit end),
                @reference_rules(begin at_or_above(::RulesOther.a.b) => :hit end))
            @test apply_reference_rules(mode_rules, typed) === nothing
        end

        # A supertype in the pattern still matches a concrete recorded type.
        @test apply_reference_rules(@reference_rules(begin ::Any.a.b => :hit end), typed) === :hit
    end

    @testset "first match wins, no match answers nothing" begin
        rules = @reference_rules begin
            a.b => :first
            a.b => :second
            _   => :fallback
        end
        @test apply_reference_rules(rules, Reference(_fld("a"), _fld("b"))) === :first
        @test apply_reference_rules(rules, Reference(_fld("q"))) === :fallback

        bare = @reference_rules begin
            a.b => :only
        end
        @test apply_reference_rules(bare, Reference(_fld("q"))) === nothing
        @test apply_reference_rules(bare, nothing) === nothing
        @test apply_reference_rules(@reference_rules(begin end), EmptyReference()) === nothing
    end

    @testset "concatenation is the override mechanism" begin
        base = @reference_rules begin
            a.b => :base
            a.c => :base_only
        end
        override = @reference_rules begin
            a.b => :override
        end
        ab = Reference(_fld("a"), _fld("b"))
        ac = Reference(_fld("a"), _fld("c"))

        # Prepending overrides; appending leaves the first set in charge.
        @test apply_reference_rules(vcat(override, base), ab) === :override
        @test apply_reference_rules(vcat(override, base), ac) === :base_only
        @test apply_reference_rules(vcat(base, override), ab) === :base
        @test length(vcat(base, override)) == 3
    end

    @testset "a rules answer takes the leftover" begin
        leaf = @reference_rules begin
            capacity => 100
            rate     => 10.0
            ∅        => :the_queue_itself
        end
        middle = @reference_rules begin
            at_or_below(queue) => ^(leaf)
            name               => :middle_name
        end
        top = @reference_rules begin
            at_or_below(hosts[_]) => ^(middle)
            linkDelay             => 42
        end

        host(rest...) = Reference(_fld("hosts"), _el(3), rest...)
        @test apply_reference_rules(top, host(_fld("queue"), _fld("capacity"))) == 100
        @test apply_reference_rules(top, host(_fld("queue"), _fld("rate"))) == 10.0
        @test apply_reference_rules(top, host(_fld("queue"))) === :the_queue_itself
        @test apply_reference_rules(top, host(_fld("name"))) === :middle_name
        @test apply_reference_rules(top, Reference(_fld("linkDelay"))) == 42
        # Nothing in the leaf set answers this, and the outer sets do not get a second
        # chance — the first match won.
        @test apply_reference_rules(top, host(_fld("queue"), _fld("nope"))) === nothing
    end

    @testset "an outer arm's bindings reach an inner answer" begin
        inner = @reference_rules begin
            capacity          => 10 * i
            when(rate, i > 2) => (i, j)
        end
        outer = @reference_rules begin
            at_or_below(buckets[i].slots[j]) => ^(inner)
        end
        path(i, j, leaf) = Reference(_fld("buckets"), _el(i), _fld("slots"), _el(j), _fld(leaf))

        @test apply_reference_rules(outer, path(4, 9, "capacity")) == 40
        @test apply_reference_rules(outer, path(5, 1, "rate")) == (5, 1)
        # The inner guard reads the outer binding, and declining leaves no other arm.
        @test apply_reference_rules(outer, path(1, 1, "rate")) === nothing
    end

    @testset "an inner binding shadows an outer one" begin
        inner = @reference_rules begin
            slots[i] => i
        end
        outer = @reference_rules begin
            at_or_below(buckets[i]) => ^(inner)
        end
        @test apply_reference_rules(outer,
            Reference(_fld("buckets"), _el(3), _fld("slots"), _el(8))) == 8
    end

    @testset "^(…) splices a value, not a reference to one" begin
        limit = 20
        rules = @reference_rules begin
            small => ^(limit)
            big   => ^(limit * 100)
        end
        limit = 999   # the object was closed at construction
        @test apply_reference_rules(rules, Reference(_fld("small"))) == 20
        @test apply_reference_rules(rules, Reference(_fld("big"))) == 2000
    end

    @testset "the object is closed" begin
        # A free name in an answer resolves in ReferenceModule, not at the site the
        # rules were written, so a local of that name is invisible to it.
        outside = :the_local_one
        rules = @reference_rules begin
            a => outside
        end
        @test_throws Exception apply_reference_rules(rules, Reference(_fld("a")))
        @test outside === :the_local_one
    end

    @testset "patterns are data" begin
        rules = @reference_rules begin
            buckets[i].capacity => 10 * i
        end
        rule = first(rules.rules)
        @test rule.mode === :at
        @test length(rule.pattern) == 3
        @test rule.guard === nothing
        # The answer's identity is the expression it was written as.
        @test rule.answer.expr == :(10 * i)

        # Two sets written the same way are equal, and differ where they differ.
        same = @reference_rules begin
            buckets[i].capacity => 10 * i
        end
        other = @reference_rules begin
            buckets[i].capacity => 20 * i
        end
        @test rules == same
        @test hash(rules) == hash(same)
        @test rules != other

        # Equality does not depend on the compiled form: apply one and not the other.
        @test apply_reference_rules(rules, Reference(_fld("buckets"), _el(3), _fld("capacity"))) == 30
        @test rules == same

        # A `^(…)` in a pattern is stored as the value it evaluated to, so it compares
        # equal to the same pattern written as a literal.
        let k = 2
            interpolated = @reference_rules begin
                buckets[^(k)] => :hit
            end
            literal = @reference_rules begin
                buckets[2] => :hit
            end
            @test interpolated == literal
            @test first(interpolated.rules).pattern == first(literal.rules).pattern
        end
    end

    @testset "a repeated binder is an equality check" begin
        # This is where the two matchers part company, and deliberately. `@reference_case`
        # generates the rest of a pattern *before* the step in front of it, so the earlier
        # occurrence of a repeated binder emits a comparison against a variable the later
        # occurrence binds in an inner scope — and the match dies reading it. The
        # interpreter reads a pattern left to right, so the later occurrence compares
        # against what the earlier one bound, which is what the DSL documents.
        rules = @reference_rules begin
            a.field(n).field(n) => n
            _                   => :miss
        end
        matching = Reference(_fld("a"), _fld("dup"), _fld("dup"))
        @test apply_reference_rules(rules, matching) == "dup"
        @test apply_reference_rules(rules, Reference(_fld("a"), _fld("b"), _fld("c"))) === :miss

        @test_throws UndefVarError (@reference_case matching begin
            a.field(n).field(n) => n
            _                   => :miss
        end)
    end

    @testset "show prints the surface syntax" begin
        rules = @reference_rules begin
            buckets[2].capacity              => 20
            buckets[i].capacity              => 10 * i
            when(items{k}, k > 0)            => :positive
            above(a.b.c)                     => :above
            at_or_below(hosts[_])            => ^(@reference_rules begin
                                                     name => :inner
                                                 end)
            ∅                                => :whole
            _                                => :miss
        end
        text = sprint(show, rules)
        @test occursin("@reference_rules begin", text)
        @test occursin("buckets[2].capacity => 20", text)
        @test occursin("buckets[i].capacity => 10i", text)
        @test occursin("when(items{k}, k > 0) => :positive", text)
        @test occursin("above(a.b.c) => :above", text)
        @test occursin("at_or_below(hosts[_]) => @reference_rules begin", text)
        @test occursin("name => :inner", text)
        @test occursin("∅ => :whole", text)
        @test occursin("_ => :miss", text)

        # Printing is the expression's job, so it does not change once compiled.
        apply_reference_rules(rules, Reference(_fld("buckets"), _el(5), _fld("capacity")))
        @test sprint(show, rules) == text
    end

    @testset "serialization round-trips the data, not the compiled form" begin
        rules = @reference_rules begin
            buckets[i].capacity   => 10 * i
            at_or_below(hosts[_]) => ^(@reference_rules begin
                                           name => :inner
                                       end)
        end
        capacity = Reference(_fld("buckets"), _el(4), _fld("capacity"))
        inner = Reference(_fld("hosts"), _el(1), _fld("name"))

        function round_trip(source)
            buffer = IOBuffer()
            serialize(buffer, source)
            seekstart(buffer)
            restored = deserialize(buffer)
            @test restored == rules
            @test apply_reference_rules(restored, capacity) == 40
            @test apply_reference_rules(restored, inner) === :inner
            @test sprint(show, restored) == sprint(show, rules)
        end

        # Untouched, then again once the answers have been compiled — the compiled form
        # is a cache of the expression and must not change what crosses the wire.
        round_trip(rules)
        @test apply_reference_rules(rules, capacity) == 40
        round_trip(rules)

        # What an applied answer caches is a *name*, not code. A cached function would
        # put a closure type on the wire that no other process can read back — which is
        # what a serialized rule set depending on its compiled form would mean.
        cache = first(rules.rules).answer.compiled
        @test !isempty(cache)
        @test all(key isa Symbol for key in values(cache))
    end

    @testset "an unregistered extension step says what is missing" begin
        # `.rulestoy` has both halves; a name with only the codegen half is reported by
        # the interpreted seam rather than failing as a MethodError.
        rules = @reference_rules begin
            norules(x) => :nope
        end
        @test_throws ErrorException apply_reference_rules(rules, Reference(RulesToyStep(:red)))
    end

    @testset "`__` is any run of steps" begin
        # A gap makes a pattern denote a SET of paths, so the conformance corpus applies
        # to it exactly as to any other pattern — and every one of these goes through
        # `@reference_case`'s interpreter fallback, since a gap is never compiled.
        _conforms("leading gap",
            p -> (@reference_case p begin
                __.b.c => :ends_bc
                __     => :other
            end),
            (@reference_rules begin
                __.b.c => :ends_bc
                __     => :other
            end))

        _conforms("trailing gap is at_or_below",
            p -> (@reference_case p begin
                a.b.__ => :under_ab
                __     => :other
            end),
            (@reference_rules begin
                a.b.__ => :under_ab
                __     => :other
            end))

        _conforms("middle gap",
            p -> (@reference_case p begin
                a.__.c => :a_to_c
                __     => :other
            end),
            (@reference_rules begin
                a.__.c => :a_to_c
                __     => :other
            end))

        _conforms("gap with a binder after it",
            p -> (@reference_case p begin
                __.buckets[i].capacity => i
                __                     => :other
            end),
            (@reference_rules begin
                __.buckets[i].capacity => i
                __                     => :other
            end))

        _conforms("gap under an arm word",
            p -> (@reference_case p begin
                at_or_below(__.buckets[i]) => i
                __                    => :other
            end),
            (@reference_rules begin
                at_or_below(__.buckets[i]) => i
                __                    => :other
            end))

        _conforms("a gap makes every input above the pattern",
            p -> (@reference_case p begin
                above(__.nowhere) => :above
                __                => :other
            end),
            (@reference_rules begin
                above(__.nowhere) => :above
                __                => :other
            end))

        # `__` alone matches every path, including the empty one — which is what makes it
        # the catch-all every other arm falls through to.
        every = @reference_rules begin
            __ => :any
        end
        for path in _corpus_paths()
            @test apply_reference_rules(every, path) === :any
        end

        # A gap spans nothing as readily as it spans everything.
        exactly = @reference_rules begin
            __.a.__.b.__ => :spans
            __           => :no
        end
        @test apply_reference_rules(exactly, Reference(_fld("a"), _fld("b"))) === :spans
        @test apply_reference_rules(exactly, Reference(_fld("a"), _fld("x"), _fld("b"), _fld("y"))) === :spans
        @test apply_reference_rules(exactly, Reference(_fld("b"), _fld("a"))) === :no
    end

    @testset "`at_or_below(P)` and `P.__` are the same arm" begin
        # The pattern sugar and the arm word have to agree, or one of them is a lie.
        word = @reference_rules begin
            at_or_below(a.b) => :hit
        end
        sugar = @reference_rules begin
            a.b.__ => :hit
        end
        for path in _corpus_paths()
            @test apply_reference_rules(word, path) == apply_reference_rules(sugar, path)
        end
    end

    @testset "a gap is greedy" begin
        # Greediness is observable only where something after the gap is variable-length.
        # Here the tail bind is, so the two readings differ in what `rest` gets: greedy
        # takes the INNER queue and leaves less over.
        rules = @reference_rules begin
            __.queue.rest... => rest
        end
        path = Reference(_fld("net"), _fld("queue"), _fld("a"), _fld("queue"), _fld("b"))
        @test apply_reference_rules(rules, path) == Reference(_fld("b"))

        # With a fixed-length remainder the gap's length is determined, so there is only
        # one candidate split and greediness cannot be observed at all.
        fixed = @reference_rules begin
            __.queue.capacity => :hit
            __                => :miss
        end
        @test apply_reference_rules(fixed,
            Reference(_fld("net"), _fld("queue"), _fld("x"), _fld("queue"), _fld("capacity"))) === :hit
    end

    @testset "the interpreter fallback keeps @reference_case's answer semantics" begin
        # A `@reference_case` result is escaped user code: it must still see the call
        # site, even when the match ran in the interpreter. `outer` is a local here and
        # would be invisible to a rules answer, which is compiled closed.
        outer = 7
        matched = @reference_case Reference(_fld("a"), _fld("buckets"), _el(3)) begin
            __.buckets[i] => i * outer
            __            => :miss
        end
        @test matched == 21

        # A guard reads the interpreter's bindings the same way.
        guarded(p) = @reference_case p begin
            when(__.buckets[i], i > 2) => :big
            __.buckets[i]              => :small
            __                         => :miss
        end
        @test guarded(Reference(_fld("a"), _fld("buckets"), _el(3))) === :big
        @test guarded(Reference(_fld("a"), _fld("buckets"), _el(1))) === :small
        @test guarded(Reference(_fld("a"))) === :miss
    end

end
end # test_reference_rules
