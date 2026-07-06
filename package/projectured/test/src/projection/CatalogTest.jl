# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/CatalogTest.jl
#
# Run the *existing* example-testers over the generated catalog
# (ProjecturedExample.catalog()). Each tester declares the terminal domain it
# needs; a catalog `Example` carries its `terminal`; applicability is the lookup.
# No new tester logic — this only routes catalog Examples to the right testers,
# so the scattered skip-lists dissolve. See plan/pending/discovered-example-catalog.md.
# ═══════════════════════════════════════════════════════════════════════════

# The terminal domain each tester needs (nothing = domain-agnostic: works on the
# abstract projection output). text-navigation needs a text-domain output.
# (Open question: confirm test_repl is truly domain-agnostic — Phase 2.)
_required_terminal(::typeof(test_printer))         = nothing
_required_terminal(::typeof(test_reader))          = nothing
_required_terminal(::typeof(test_repl))            = nothing
_required_terminal(::typeof(test_text_navigation)) = :text

_applies(tester, ex::Example) = (r = _required_terminal(tester); r === nothing || r == ex.terminal)

# Route one Example to a tester. printer/reader/repl take an Example directly;
# text-navigation takes (label, document, projection).
_run_catalog_tester(::typeof(test_text_navigation), ex::Example) =
    test_text_navigation(ex.name, ex.make_document(), ex.make_projection())
_run_catalog_tester(tester, ex::Example) = tester(ex)

const _CATALOG_TESTERS = (test_printer, test_reader, test_repl, test_text_navigation)

"""
    test_catalog(; domain=nothing, terminal=nothing, only_runnable=false,
                   testers=(test_printer, test_reader, test_repl, test_text_navigation))

Run each applicable tester over the discovered example catalog, filtered by
`domain` / `terminal` / `only_runnable`. Applicability is decided per `Example`
by its `terminal` field — a `:syntax` pair runs printer/reader/repl but not
text-navigation — so no skip-lists are needed.
"""
function test_catalog(; domain = nothing, terminal = nothing, only_runnable = false,
                        testers = _CATALOG_TESTERS)
    @testset "Catalog" begin
        for ex in catalog(; domain = domain, terminal = terminal, only_runnable = only_runnable)
            @testset "$(ex.name)" begin
                for tester in testers
                    _applies(tester, ex) && _run_catalog_tester(tester, ex)
                end
            end
        end
    end
end
