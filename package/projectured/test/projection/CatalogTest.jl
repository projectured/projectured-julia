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

# Route one Example to a tester. printer/reader/repl take an Example directly;
# position-navigation takes (label, document, projection).
_run_catalog_tester(::typeof(test_position_navigation), ex::Example) =
    test_position_navigation(ex.name, ex.make_document(), ex.make_projection())
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
