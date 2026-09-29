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

# A compiled `@reference_case` of two arms, for the allocation count of one call.
_rules_compiled_case(path) = @reference_case path begin
    a.b => :hit
    __  => :miss
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
                __    => :miss
            end),
            @reference_rules begin
                a.b.c => :hit
                __    => :miss
            end)

        _conforms("index binder",
            p -> (@reference_case p begin
                buckets[i].capacity => i
                __                  => :miss
            end),
            @reference_rules begin
                buckets[i].capacity => i
                __                  => :miss
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
                __       => :miss
            end),
            @reference_rules begin
                items{k} => k
                __       => :miss
            end)

        _conforms("range step",
            p -> (@reference_case p begin
                items{s:e} => (s, e)
                __         => :miss
            end),
            @reference_rules begin
                items{s:e} => (s, e)
                __         => :miss
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
                __        => :miss
            end),
            @reference_rules begin
                a.rest... => rest
                __        => :miss
            end)

        _conforms("empty path",
            p -> (@reference_case p begin
                ∅ => :whole
                __ => :miss
            end),
            @reference_rules begin
                ∅ => :whole
                __ => :miss
            end)

        _conforms("empty path with a bound terminal type",
            p -> (@reference_case p begin
                ∅::t => t
                __   => :miss
            end),
            @reference_rules begin
                ∅::t => t
                __   => :miss
            end)

        _conforms("type checkpoints",
            p -> (@reference_case p begin
                ::RulesA.a::RulesB.b::RulesC => :typed
                __                           => :miss
            end),
            @reference_rules begin
                ::RulesA.a::RulesB.b::RulesC => :typed
                __                           => :miss
            end)

        # The corpus holds one `RulesA`-typed path and one `RulesOther`-typed path of
        # the same shape, so an arm per type is decided by the node type alone.
        _conforms("a type checkpoint narrows",
            p -> (@reference_case p begin
                ::RulesA.a.b     => :a
                ::RulesOther.a.b => :other
                __               => :miss
            end),
            @reference_rules begin
                ::RulesA.a.b     => :a
                ::RulesOther.a.b => :other
                __               => :miss
            end)

        _conforms("a type checkpoint narrows an above-form",
            p -> (@reference_case p begin
                above(::RulesA.a.b.c)     => :a
                above(::RulesOther.a.b.c) => :other
                __                         => :miss
            end),
            @reference_rules begin
                above(::RulesA.a.b.c)     => :a
                above(::RulesOther.a.b.c) => :other
                __                        => :miss
            end)

        _conforms("node type binder",
            p -> (@reference_case p begin
                a::t.b => t
                __     => :miss
            end),
            @reference_rules begin
                a::t.b => t
                __     => :miss
            end)

        _conforms("extension step",
            p -> (@reference_case p begin
                rulestoy(tag).c => tag
                rulestoy(tag)   => (tag, :alone)
                __              => :miss
            end),
            @reference_rules begin
                rulestoy(tag).c => tag
                rulestoy(tag)   => (tag, :alone)
                __              => :miss
            end)

        # `^(…)` reads the construction site on both sides; here the two sites hold the
        # same values, which is what makes the answers comparable at all.
        let k = 2, interp_path = Reference(_fld("a"), _fld("b"))
            _conforms("value interpolation",
                p -> (@reference_case p begin
                    buckets[^(k)].capacity => :interp
                    __                     => :miss
                end),
                @reference_rules begin
                    buckets[^(k)].capacity => :interp
                    __                     => :miss
                end)

            _conforms("whole-path interpolation",
                p -> (@reference_case p begin
                    ^(interp_path) => :same_path
                    __             => :miss
                end),
                @reference_rules begin
                    ^(interp_path) => :same_path
                    __             => :miss
                end)
        end

        # `above(P)` is `@reference_case`'s `above(P)` — the arm holds when the input
        # runs out *inside* P. This is the one place the two vocabularies differ by name
        # rather than by meaning, so it is pinned here.
        _conforms("above(P) is above(P)",
            p -> (@reference_case p begin
                above(a.b.c) => :above
                __            => :miss
            end),
            @reference_rules begin
                above(a.b.c) => :above
                __           => :miss
            end)

        # The empty path is above everything, so an above-arm holds there without ever
        # reaching its index step — and the guard then reads a binding that was never
        # made. Both DSLs raise there, so the corpus for this one leaves it out.
        _conforms("above(P) with an index and a guard",
            p -> (@reference_case p begin
                when(above(buckets[i].capacity), i < 5) => i
                __                                       => :miss
            end),
            (@reference_rules begin
                when(above(buckets[i].capacity), i < 5) => i
                __                                      => :miss
            end),
            filter(p -> p isa ConcreteReference, _corpus_paths()))

        let interp_path = Reference(_fld("a"), _fld("b"), _fld("c"))
            _conforms("above(^(path))",
                p -> (@reference_case p begin
                    above(^(interp_path)) => :above
                    __                     => :miss
                end),
                @reference_rules begin
                    above(^(interp_path)) => :above
                    __                    => :miss
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
                (:within, @reference_rules begin within(a.b) => :yes end),
                (:above, @reference_rules begin above(a.b) => :yes end),
                (:toward, @reference_rules begin toward(a.b) => :yes end))
            hits = [p for p in (shallow, exact, deep, elsewhere)
                    if apply_reference_rules(rules, p) === :yes]
            expected = mode === :at || mode === :bare ? [exact] :
                       mode === :below ? [deep] :
                       mode === :within ? [exact, deep] :
                       mode === :above ? [shallow] :
                       [shallow, exact]
            @test hits == expected
        end

        # `prefix(…)` is gone from both DSLs, and each says which form to write.
        @test_throws LoadError @eval @reference_rules begin
            prefix(a.b) => :nope
        end

        # So are the two that spelled a disjunction. An arm word names one relation.
        @test_throws Exception @eval @reference_rules begin
            at_or_below(a.b) => :nope
        end
        @test_throws Exception @eval @reference_rules begin
            at_or_above(a.b) => :nope
        end
        @test_throws Exception @eval @reference_case EmptyReference() begin
            at_or_below(a.b) => :nope
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
            __               => :miss
        end
        @test apply_reference_rules(at_rules, typed) === :a          # narrowed to the right arm
        @test apply_reference_rules(at_rules, untyped) === :other    # no type recorded, first arm takes it
        @test apply_reference_rules(at_rules, unfolded) === :a       # the unfolded step narrows too

        # Every mode reads the type step through the same predicate. (Parenthesized
        # macro calls: the `begin … end` block form would swallow the commas.)
        for mode_rules in (
                @reference_rules(begin ::RulesOther.a => :hit end),
                @reference_rules(begin below(::RulesOther.a) => :hit end),
                @reference_rules(begin within(::RulesOther.a) => :hit end),
                @reference_rules(begin above(::RulesOther.a.b.c) => :hit end),
                @reference_rules(begin toward(::RulesOther.a.b) => :hit end))
            @test apply_reference_rules(mode_rules, typed) === nothing
        end

        # A supertype in the pattern still matches a concrete recorded type.
        @test apply_reference_rules(@reference_rules(begin ::Any.a.b => :hit end), typed) === :hit
    end

    @testset "first match wins, no match answers nothing" begin
        rules = @reference_rules begin
            a.b => :first
            a.b => :second
            __  => :fallback
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
            within(queue) => ^(leaf)
            name               => :middle_name
        end
        top = @reference_rules begin
            within(hosts[_]) => ^(middle)
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
            within(buckets[i].slots[j]) => ^(inner)
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
            within(buckets[i]) => ^(inner)
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
            __                  => :miss
        end
        matching = Reference(_fld("a"), _fld("dup"), _fld("dup"))
        @test apply_reference_rules(rules, matching) == "dup"
        @test apply_reference_rules(rules, Reference(_fld("a"), _fld("b"), _fld("c"))) === :miss

        @test_throws UndefVarError (@reference_case matching begin
            a.field(n).field(n) => n
            __                  => :miss
        end)
    end

    @testset "show prints the surface syntax" begin
        rules = @reference_rules begin
            buckets[2].capacity              => 20
            buckets[i].capacity              => 10 * i
            when(items{k}, k > 0)            => :positive
            above(a.b.c)                     => :above
            within(hosts[_])            => ^(@reference_rules begin
                                                     name => :inner
                                                 end)
            ∅                                => :whole
            __                               => :miss
        end
        text = sprint(show, rules)
        @test occursin("@reference_rules begin", text)
        @test occursin("buckets[2].capacity => 20", text)
        @test occursin("buckets[i].capacity => 10i", text)
        @test occursin("when(items{k}, k > 0) => :positive", text)
        @test occursin("above(a.b.c) => :above", text)
        @test occursin("within(hosts[_]) => @reference_rules begin", text)
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
            within(hosts[_]) => ^(@reference_rules begin
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

        _conforms("trailing gap is within",
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
                within(__.buckets[i]) => i
                __                    => :other
            end),
            (@reference_rules begin
                within(__.buckets[i]) => i
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

    @testset "`_` is exactly one step" begin
        _conforms("one step, any kind",
            p -> (@reference_case p begin
                a._   => :a_then_one
                _._   => :two
                at(_) => :one
                __    => :other
            end),
            (@reference_rules begin
                a._   => :a_then_one
                _._   => :two
                at(_) => :one
                __    => :other
            end))

        # `_` counts a step, not a name — an index, a position and an extension step are
        # each one step, so `xs[3]` is two.
        # A bare `_` arm is the retired catch-all and raises (see below), so the
        # one-step arm is written `at(_)` — which is what the arm word was always for.
        one = @reference_rules begin
            _._   => :two
            at(_) => :one
            __    => :other
        end
        @test apply_reference_rules(one, Reference(_fld("a"))) === :one
        @test apply_reference_rules(one, Reference(RulesToyStep(:red))) === :one
        @test apply_reference_rules(one, Reference(_fld("xs"), _el(3))) === :two
        @test apply_reference_rules(one, Reference(_fld("xs"), _pos(0))) === :two
        @test apply_reference_rules(one, EmptyReference()) === :other
        @test apply_reference_rules(one, Reference(_fld("a"), _fld("b"), _fld("c"))) === :other

        # A one-step wildcard is not a search, so it compiles like any other step and
        # never reaches the interpreter.
        @test !ReferenceModule._pattern_has_gap(first((@reference_rules begin
            a._.b => 1
        end).rules).pattern)
    end

    @testset "`__ʔ` takes the shortest run" begin
        # The only place greediness is observable: something after the gap is itself
        # variable-length, so more than one split matches and the two differ in which.
        nested = Reference(_fld("net"), _fld("queue"), _fld("a"), _fld("queue"), _fld("b"))

        greedy = @reference_rules begin
            __.queue.rest... => rest
        end
        lazy = @reference_rules begin
            __ʔ.queue.rest... => rest
        end
        @test apply_reference_rules(greedy, nested) == Reference(_fld("b"))
        @test apply_reference_rules(lazy, nested) ==
              Reference(_fld("a"), _fld("queue"), _fld("b"))

        # Where the split is determined, the two agree — which is the common case.
        for rules in (greedy, lazy)
            @test apply_reference_rules(rules,
                Reference(_fld("net"), _fld("queue"), _fld("only"))) == Reference(_fld("only"))
        end

        _conforms("lazy gap",
            p -> (@reference_case p begin
                __ʔ.b.rest... => rest
                __            => :miss
            end),
            (@reference_rules begin
                __ʔ.b.rest... => rest
                __            => :miss
            end))
    end

    @testset "`__(name)` binds the run it took" begin
        deep = Reference(_fld("net"), _fld("router"), _fld("queue"), _fld("capacity"))
        bound = @reference_rules begin
            __(owner).queue.capacity => owner
        end
        @test apply_reference_rules(bound, deep) == Reference(_fld("net"), _fld("router"))

        # A gap that took nothing binds the empty path, not `nothing`.
        @test apply_reference_rules(bound,
            Reference(_fld("queue"), _fld("capacity"))) == EmptyReference()

        # Greediness decides what the binder gets when both directions match.
        both = Reference(_fld("q"), _fld("x"), _fld("q"), _fld("z"))
        @test apply_reference_rules((@reference_rules begin
            __(owner).q.rest... => owner
        end), both) == Reference(_fld("q"), _fld("x"))
        @test apply_reference_rules((@reference_rules begin
            __ʔ(owner).q.rest... => owner
        end), both) == EmptyReference()

        # Under an above-arm a bound gap names what is left of the input — the part of
        # the member the input reached before running out. Without that the answer would
        # fail reading a name the match never bound.
        @test apply_reference_rules((@reference_rules begin
            above(__(owner).nowhere) => owner
        end), Reference(_fld("x"))) == Reference(_fld("x"))

        _conforms("bound gap",
            p -> (@reference_case p begin
                __(owner).c => owner
                __          => :miss
            end),
            (@reference_rules begin
                __(owner).c => owner
                __          => :miss
            end))

        # A bound gap is data like everything else, and prints as it was written.
        printed = sprint(show, @reference_rules begin
            __ʔ(owner).queue.rest... => (owner, rest)
        end)
        @test occursin("__ʔ(owner).queue.rest... => (owner, rest)", printed)

        @test_throws Exception @eval @reference_rules begin
            __(a, b).c => 1
        end
    end

    @testset "value patterns: ranges, alternation, globs" begin
        hosts(i) = Reference(_fld("hosts"), _el(i), _fld("power"))
        named(n) = Reference(_fld("net"), _fld(n), _fld("cap"))

        _conforms("numeric range",
            p -> (@reference_case p begin
                buckets[1..2].capacity => :low
                buckets[3..99].capacity => :high
                __                      => :miss
            end),
            (@reference_rules begin
                buckets[1..2].capacity => :low
                buckets[3..99].capacity => :high
                __                      => :miss
            end))

        _conforms("glob over a step name",
            p -> (@reference_case p begin
                a.field(glob"b*").c => :b_something
                __                  => :miss
            end),
            (@reference_rules begin
                a.field(glob"b*").c => :b_something
                __                  => :miss
            end))

        # `..` used to reach the matcher as an interpolation and be compared against an
        # Int, so `xs[0..3]` silently never matched. It has a meaning now.
        ranged = @reference_rules begin
            hosts[2..4].power => :mid
            __                => :miss
        end
        @test apply_reference_rules(ranged, hosts(3)) === :mid
        @test apply_reference_rules(ranged, hosts(2)) === :mid
        @test apply_reference_rules(ranged, hosts(4)) === :mid
        @test apply_reference_rules(ranged, hosts(5)) === :miss

        # Alternatives may arrive as data, which is the case N arms cannot cover.
        allowed = ["queue", "buffer"]
        listed = @reference_rules begin
            net.field(any(^(allowed))).cap => :listed
            net.field(any("pool", "pipe")).cap => :literal
            __                             => :miss
        end
        @test apply_reference_rules(listed, named("queue")) === :listed
        @test apply_reference_rules(listed, named("buffer")) === :listed
        @test apply_reference_rules(listed, named("pipe")) === :literal
        @test apply_reference_rules(listed, named("other")) === :miss
        # A spliced STRING is one name, not a set of letters.
        @test apply_reference_rules((@reference_rules begin
            net.field(any(^("queue"))).cap => :one
            __                             => :miss
        end), named("queue")) === :one

        # The glob language, in full.
        for (pattern, name, expected) in (("host*", "hostA", true), ("host*", "host", true),
                                          ("host*", "xhost", false), ("*host", "myhost", true),
                                          ("h?st", "host", true), ("h?st", "hoost", false),
                                          ("mac{a-c}", "maca", true), ("mac{a-c}", "macd", false),
                                          ("mac{^a-c}", "macd", true), ("mac{^a-c}", "maca", false),
                                          ("h{8..12}", "h10", true), ("h{8..12}", "h1", false),
                                          ("h{8..12}", "h12", true), ("a*b*c", "axxbyyc", true),
                                          ("a*b*c", "axxc", false))
            @test glob_matches(pattern, name) == expected
        end
        @test glob_matches("a\\*b", "a*b")
        @test !glob_matches("a\\*b", "axb")
        # Each state of a match is tried once, so many `*` on a long name answer at
        # once. A search of every split takes seconds here.
        @test @elapsed(glob_matches("*a"^10 * "*b", "a"^36)) < 1.0

        # All three print as they were written.
        printed = sprint(show, @reference_rules begin
            hosts[2..4].field(any("a", "b")).field(glob"q*") => 1
        end)
        @test occursin("hosts[2..4]", printed)
        @test occursin("""any("a", "b")""", printed)
        @test occursin("glob\"q*\"", printed)
    end

    @testset "`any(P, Q, …)` chooses between subpaths" begin
        # In PATH position a bare symbol is a field name, which is what makes
        # `any(queue, buffer)` read the way an ini file's alternation does. In value
        # position the same spelling would bind, so the two are not interchangeable.
        _conforms("subpath alternation",
            p -> (@reference_case p begin
                any(a, x).b => :either
                __          => :miss
            end),
            (@reference_rules begin
                any(a, x).b => :either
                __          => :miss
            end))

        _conforms("alternation of multi-step branches",
            p -> (@reference_case p begin
                a.any(b.c, dup.dup) => :branch
                __                  => :miss
            end),
            (@reference_rules begin
                a.any(b.c, dup.dup) => :branch
                __                  => :miss
            end))

        rules = @reference_rules begin
            net.any(queue, buffer).capacity => :either
            net.any(a[i], c[i]).z           => i
            __                              => :miss
        end
        n(xs...) = Reference(_fld("net"), xs...)
        @test apply_reference_rules(rules, n(_fld("queue"), _fld("capacity"))) === :either
        @test apply_reference_rules(rules, n(_fld("buffer"), _fld("capacity"))) === :either
        @test apply_reference_rules(rules, n(_fld("pool"), _fld("capacity"))) === :miss
        @test apply_reference_rules(rules, n(_fld("a"), _el(4), _fld("z"))) == 4
        @test apply_reference_rules(rules, n(_fld("c"), _el(7), _fld("z"))) == 7

        # A branch is judged by whether the WHOLE pattern goes through, not just the
        # branch: `a` matches here but leaves `z` unmatched, so the second branch wins.
        @test apply_reference_rules((@reference_rules begin
            any(a, a.b).c => :hit
            __            => :miss
        end), Reference(_fld("a"), _fld("b"), _fld("c"))) === :hit

        # Alternation composes with gaps.
        @test apply_reference_rules((@reference_rules begin
            __.any(queue, buffer).capacity => :deep
            __                             => :miss
        end), Reference(_fld("x"), _fld("y"), _fld("buffer"), _fld("capacity"))) === :deep

        # Branches that bind different names are refused where they are written, in both
        # positions, rather than failing later for only the inputs that took one branch.
        @test_throws Exception @eval @reference_rules begin
            any(a[i], b).z => i
        end
        @test_throws Exception @eval @reference_rules begin
            xs[any(i, 3)] => i
        end

        # A path being built names one route, not a choice of them.
        @test_throws Exception @eval @reference a.any(b, c).d

        @test occursin("net.any(queue, buffer).capacity => :either", sprint(show, rules))
    end

    @testset "the string spelling parses to the same pattern" begin
        # The claim is not that the two spellings agree on some inputs — it is that they
        # are the same data. Equality is the test.
        @test (@reference_rules begin ref"**.host[*].queue.capacity" => 100 end) ==
              (@reference_rules begin __.host[_].queue.capacity => 100 end)
        @test (@reference_rules begin ref"*.a" => 1 end) ==
              (@reference_rules begin _.a => 1 end)
        @test (@reference_rules begin ref"**?.a" => 1 end) ==
              (@reference_rules begin __ʔ.a => 1 end)
        @test parse_reference_pattern("a.b") ==
              first((@reference_rules begin a.b => 1 end).rules).pattern

        # An index shifts from the 0-based counting a configuration file uses.
        @test apply_reference_rules((@reference_rules begin ref"host[0]" => :first end),
                                    Reference(_fld("host"), _el(1))) === :first
        @test apply_reference_rules((@reference_rules begin ref"host[0]" => :first end),
                                    Reference(_fld("host"), _el(0 + 2))) === nothing
        @test (@reference_rules begin ref"h[0..2].p" => 1 end) ==
              (@reference_rules begin h[1..3].p => 1 end)

        # A name carrying glob characters becomes a glob; a plain one stays a literal.
        @test apply_reference_rules((@reference_rules begin ref"**.host*.p" => :g end),
                                    Reference(_fld("a"), _fld("hostZ"), _fld("p"))) === :g
        @test apply_reference_rules((@reference_rules begin ref"**.host*.p" => :g end),
                                    Reference(_fld("a"), _fld("xhost"), _fld("p"))) === nothing
        @test (@reference_rules begin ref"plain.name" => 1 end) ==
              (@reference_rules begin plain.name => 1 end)

        # An escaped metacharacter is the character, so a name really holding a `*`
        # round-trips as a literal rather than becoming a wildcard.
        escaped = @reference_rules begin
            ref"a\*b"  => :literal_star
            __          => :miss
        end
        @test apply_reference_rules(escaped, Reference(_fld("a*b"))) === :literal_star
        @test apply_reference_rules(escaped, Reference(_fld("axb"))) === :miss

        # Built at run time, from text, with no macro anywhere — the case a rule set read
        # from a configuration file actually is.
        runtime = ReferenceRules([ReferenceRule(:at, parse_reference_pattern("**.queue.capacity"),
                                                nothing, ReferenceRuleAnswer(100))])
        @test apply_reference_rules(runtime,
            Reference(_fld("net"), _fld("q"), _fld("queue"), _fld("capacity"))) == 100

        # And it prints in the Julia spelling, because that is what it is.
        @test occursin("__.queue.capacity => 100", sprint(show, runtime))

        # A run of steps spliced into the middle of a NAME has no reading here.
        @test_throws Exception parse_reference_pattern("host**x.p")
        @test_throws Exception parse_reference_pattern("a..b")
        @test_throws Exception parse_reference_pattern("a[]")
    end

    @testset "a gap whose length is arithmetic compiles" begin
        # Where the pattern is anchored at the tail and everything after the gap takes
        # exactly one step, the run's length is `what is left` minus `what the rest
        # needs` — arithmetic, not a search. Those compile; the rest reach the
        # interpreter. This pins the boundary, which is otherwise invisible: both sides
        # answer identically, which is exactly what the conformance corpus asserts.
        compiled(ex) = !occursin("match_reference_pattern",
                                 string(macroexpand(@__MODULE__, ex)))

        @test compiled(:(@reference_case r begin __.b.c => 1; __ => 2 end))
        @test compiled(:(@reference_case r begin __(o).b.c => o; __ => 2 end))
        @test compiled(:(@reference_case r begin a.__.b[i] => i; __ => 2 end))
        @test compiled(:(@reference_case r begin __ => 1 end))

        # A variable-length remainder puts the length back in question.
        @test !compiled(:(@reference_case r begin __.rest... => rest; __ => 2 end))
        @test !compiled(:(@reference_case r begin __.a.__.b => 1; __ => 2 end))
        # `::T` is non-navigating, so it consumes one step or none.
        @test !compiled(:(@reference_case r begin __.b::Int => 1; __ => 2 end))
        # Only an `at` arm is anchored at the tail; the others leave the leftover free.
        @test !compiled(:(@reference_case r begin within(__.b) => 1; __ => 2 end))
        # An alternation branches, whatever its lengths.
        @test !compiled(:(@reference_case r begin any(a, b).c => 1; __ => 2 end))

        # And the compiled reading answers what the interpreted one does, including for
        # a bound gap and for a path carrying an unfolded checkpoint — the one place the
        # two count steps differently if either gets it wrong.
        _conforms("computed gap, bound",
            p -> (@reference_case p begin
                __(owner).b => owner
                __          => :miss
            end),
            (@reference_rules begin
                __(owner).b => owner
                __          => :miss
            end))
    end

    @testset "the retired catch-all says so" begin
        # `_` used to mean "any path" and now means "one step", so a bare `_` arm is an
        # error rather than a silent reinterpretation — the whole point of the guard.
        @test_throws Exception @eval @reference_rules begin
            _ => :nope
        end
        @test_throws Exception @eval @reference_case EmptyReference() begin
            _ => :nope
        end

        # A wildcard has no construction reading, in any of its spellings.
        @test_throws Exception @eval @reference a._.b
        @test_throws Exception @eval @reference a.__.b
        @test_throws Exception @eval @reference a.__ʔ.b
        @test_throws Exception @eval @reference a.__(owner).b
        @test_throws Exception @eval @reference a.__ʔ(owner).b
    end

    @testset "`within(P)` and `P.__` are the same arm" begin
        # The pattern sugar and the arm word have to agree, or one of them is a lie.
        word = @reference_rules begin
            within(a.b) => :hit
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

    @testset "a call of compiled arms allocates nothing" begin
        path = Reference(_fld("a"), _fld("b"))
        @test _rules_compiled_case(path) === :hit
        @test (@allocated _rules_compiled_case(path)) == 0
    end

end
end # test_reference_rules
