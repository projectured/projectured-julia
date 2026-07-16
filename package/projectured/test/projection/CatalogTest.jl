# ═══════════════════════════════════════════════════════════════════════════
# test/projection/CatalogTest.jl
#
# Run the *existing* example-testers over the generated catalog
# (ProjecturedExample.catalog()). Each tester declares the terminal domain it
# needs; a catalog `Example` carries its `terminal`; applicability is the lookup.
# No new tester logic — this only routes catalog Examples to the right testers,
# so the scattered skip-lists dissolve. See plan/pending/discovered-example-catalog.md.
# ═══════════════════════════════════════════════════════════════════════════

# The terminal domain each tester needs (nothing = domain-agnostic: works on the
# abstract projection output). Position-navigation seeds and moves the caret by *visual*
# geometry (`Ctrl+Home` → first caret, arrows → spatial steps), which only the graphics
# layer computes — the `:home` seed reader lives in `TextToGraphics`. So it needs a
# `:graphics` terminal: a projection that stops at `:text` has no caret geometry and its
# seed read returns `nothing`. (The manual `text`/`json` examples navigate for the same
# reason — their projections run all the way through `TextToGraphics`.)
_required_terminal(::typeof(test_printer))         = nothing
_required_terminal(::typeof(test_reader))          = nothing
_required_terminal(::typeof(test_repl))            = nothing
_required_terminal(::typeof(test_position_navigation)) = :graphics

_applies(tester, ex::Example) = (r = _required_terminal(tester); r === nothing || r == ex.terminal)

# ── Known-broken registry ──────────────────────────────────────────────────
# Every document type is a catalog atom — including ones whose projection still has a
# bug (a bare compound/leaf exercises paths the big curated examples don't). Such an entry
# stays in the catalog; its failure is the visible TODO, recorded `@test_broken` keyed on
# the specific failing signature so a *different* failure still surfaces as an unmarked
# `Fail` (a regression). Fix the projection, then delete its clause here. Enumerate the
# open bugs with `grep "@catalog-broken"`.
#
# @catalog-broken sql/comparison, sql/select_item: a bare node atom receives an editing
#   gesture the node's `ChildrenIoMap` `read_intent` has no method for — a `read_intent`
#   MethodError, and its reprint fallout `FieldError`.
# @catalog-broken julia/binary_op, julia/assignment: repl reprint throws `FieldError(Nothing, :output)`.
_catalog_edit_broken(name) =
    (occursin("sql/comparison/", name) || occursin("sql/select_item/", name) ||
     occursin("julia/binary_op/", name) || occursin("julia/assignment/", name)) ?
        ((ev, msg) -> occursin("FieldError", msg) || occursin("MethodError", msg)) :
    occursin("filesystem/directory/", name) ?
        ((ev, msg) -> occursin("under-typed", msg)) : nothing

# @catalog-broken yaml/sequence: graphics Ctrl+Home seed returns nothing (0 nav states).
# @catalog-broken filesystem/directory: graphics click hits an under-typed `@reference` in
#   `FileSystemDirectoryToSyntaxNode`'s backward map; the nav walk collects it and reaches 0 states.
_catalog_seed_broken(name) =
    (occursin("yaml/sequence/", name) || occursin("filesystem/directory/", name)) ? (_errs -> true) : nothing

_catalog_throws_broken(name) =
    occursin("filesystem/directory/", name) ? (msg -> occursin("under-typed @reference", msg)) : nothing

# Route one Example to a tester, threading its known-broken signatures. printer has no
# known breaks; reader/repl take an event predicate; position-navigation takes seed/throws.
_run_catalog_tester(::typeof(test_position_navigation), ex::Example) =
    test_position_navigation(ex.name, ex.make_document(), ex.make_projection();
                             seed_broken=_catalog_seed_broken(ex.name),
                             throws_broken=_catalog_throws_broken(ex.name))
_run_catalog_tester(::typeof(test_reader), ex::Example) =
    test_reader(ex.name, ex.make_document(), ex.make_projection(); broken=_catalog_edit_broken(ex.name))
_run_catalog_tester(::typeof(test_repl), ex::Example) =
    test_repl(ex.name, ex.make_document(), ex.make_projection(); broken=_catalog_edit_broken(ex.name))
_run_catalog_tester(tester, ex::Example) = tester(ex)

const _CATALOG_TESTERS = (test_printer, test_reader, test_repl, test_position_navigation)

"""
    test_catalog(; domain=nothing, document=nothing, terminal=nothing, only_runnable=false,
                   testers=(test_printer, test_reader, test_repl, test_position_navigation))

Run each applicable tester over the discovered example catalog, filtered by
`domain` / `document` / `terminal` / `only_runnable`. Applicability is decided per
`Example` by its `terminal` field — a `:syntax` pair runs printer/reader/repl but not
position-navigation (which needs a `:graphics` terminal) — so no skip-lists are needed.
"""
function test_catalog(; domain = nothing, document = nothing, terminal = nothing,
                        only_runnable = false, testers = _CATALOG_TESTERS)
    @testset "Catalog" begin
        for ex in catalog(; domain = domain, document = document,
                            terminal = terminal, only_runnable = only_runnable)
            @testset "$(ex.name)" begin
                for tester in testers
                    _applies(tester, ex) && _run_catalog_tester(tester, ex)
                end
            end
        end
    end
end
