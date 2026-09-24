# ═══════════════════════════════════════════════════════════════════════════
# ExportCollisionTest.jl
#
# PAR-QUALIFIED-EXTENSION rests on bare `using ..XxxModule`: a file names a
# sibling module and takes its exports, with no symbol list. That is only
# safe while two modules
# never export the same name for two *different* things.
#
# Julia's rule: a name exported by several modules resolves silently when every
# module means the *same binding object* (a re-export), and raises
# `UndefVarError` **on use** when the bindings differ. The re-export case is
# pervasive and healthy here — `evaluate_operation` is one function visible
# through `OperationModule`, `EditorModule`, `PaneModule`
# and `WidgetModule`; `set_cell_computation!` through eight modules — and is not a
# collision. The distinct-binding case is the hazard.
#
# It is a *cross-package* property, so the per-package static guard in
# `CheckLayering.jl` cannot see it: the one instance that ever existed
# (`NothingToSyntaxLeaf`, the insertion placeholder vs. the `nothing` leaf)
# spanned visual and domain. Hence a dynamic check here, in the umbrella — the
# lowest package whose API reaches all four (PAR-LOWEST-PACKAGE).
# ═══════════════════════════════════════════════════════════════════════════

"""
A module belongs to this project when the name of its root package starts with
`Projectured`. The test is the name, not a written-down list: there are fifty
packages and the list would go stale on the next one.
"""
is_project_root(name::Symbol) = startswith(String(name), "Projectured")

"`own_roots` is either a set of package names or a predicate over one."
_in_roots(name::Symbol, roots::Set) = name in roots
_in_roots(name::Symbol, roots) = roots(name)

"""
    project_modules(roots, own_roots) -> Dict{Symbol, Module}

Every module reachable from `roots`, keyed by the name it is bound under — so a
`const BackendApiModule = ProjecturedKernel.BackendModule` alias appears under
both names, exactly as a file that names either one would see it. Descent stops
at anything whose root package is not in `own_roots` (Base, stdlib, SDL, …).
"""
function project_modules(roots, own_roots)
    is_ours(m) = _in_roots(nameof(Base.moduleroot(m)), own_roots)

    mods = Dict{Symbol, Module}()
    seen = Set{Module}()
    function visit(m)
        m in seen && return
        push!(seen, m)
        for n in names(m; all = true, imported = true)
            isdefined(m, n) || continue
            v = getfield(m, n)
            (v isa Module && v !== m && is_ours(v)) || continue
            haskey(mods, n) || (mods[n] = v)
            visit(v)
        end
    end
    foreach(visit, roots)
    mods
end

"""
    export_collisions(roots, own_roots = is_project_root) -> Vector{String}

Every name exported by two or more modules with **distinct bindings**. A
re-export — the same binding object reached through several module names — is
not reported: Julia resolves it without ambiguity.
"""
function export_collisions(roots, own_roots = is_project_root)
    mods = project_modules(roots, own_roots)
    owners = Dict{Symbol, Set{Module}}()
    for m in unique(values(mods)), sym in names(m)
        sym === nameof(m) && continue          # a module's own name is not a hazard
        push!(get!(owners, sym, Set{Module}()), m)
    end
    errs = String[]
    for (sym, ms) in sort(collect(owners); by = x -> string(x[1]))
        length(ms) > 1 || continue
        bindings = unique(getfield(m, sym) for m in ms if isdefined(m, sym))
        length(bindings) > 1 || continue        # re-export — one object, no ambiguity
        push!(errs,
            "$sym is exported with $(length(bindings)) distinct bindings by " *
            join(sort([string(nameof(m)) for m in ms]), ", ") *
            " — a file that bare-`using`s two of these gets UndefVarError on use; " *
            "give the more specific concept a qualified name (PAR-QUALIFIED-EXTENSION)")
    end
    errs
end

"""
    test_export_collisions()

PAR-QUALIFIED-EXTENSION's precondition: no name is exported by two modules with different
bindings, so bare `using ..XxxModule` can never become ambiguous. See
`export_collisions`.
"""
function test_export_collisions()
    @testset "no cross-module export collisions" begin
        errs = export_collisions([Projectured])
        if !isempty(errs)
            println(stderr, "\nExport collisions (PAR-QUALIFIED-EXTENSION):")
            foreach(e -> println(stderr, "  ", e), errs)
        end
        @test isempty(errs)
    end
end

# ── self-test fixture: two modules that really do disagree ─────────────────
# Nested in ProjecturedTest, so its root package is ProjecturedTest and the real
# check (rooted at Projectured) never sees it.

module CollisionFixture
    module Alpha
        export shared, only_alpha
        struct shared; x::Int; end          # one binding…
        only_alpha() = 1
    end
    module Beta
        export shared
        struct shared; s::String; end       # …and a different one, same name
    end
    module Gamma
        using ..Alpha
        export shared                       # a re-export of Alpha's binding
    end
    module Delta
        using ..Alpha
        export only_alpha                   # re-export, distinct name set
    end
end

"""
    test_export_collision_checker()

Self-test for `export_collisions`: it must flag two modules that export the same
name for different things, and must *not* flag a re-export.
"""
function test_export_collision_checker()
    @testset "export_collisions separates a clash from a re-export" begin
        own = Set([:ProjecturedTest])

        # Alpha.shared and Beta.shared are different structs — a real collision.
        errs = export_collisions([CollisionFixture], own)
        @test length(errs) == 1
        @test occursin("shared", errs[1]) && occursin("distinct bindings", errs[1])
        @test occursin("Alpha", errs[1]) && occursin("Beta", errs[1])

        # Gamma re-exports Alpha's `shared`, and Delta re-exports `only_alpha` —
        # both are the same binding object, so neither is reported.
        @test !occursin("only_alpha", errs[1])
        no_clash = export_collisions([CollisionFixture.Alpha, CollisionFixture.Gamma,
                                      CollisionFixture.Delta], own)
        @test isempty(no_clash)
    end
end
