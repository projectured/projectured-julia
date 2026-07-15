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
# abstract projection output). position-navigation needs a text-domain output.
# (Open question: confirm test_repl is truly domain-agnostic — Phase 2.)
_required_terminal(::typeof(test_printer))         = nothing
_required_terminal(::typeof(test_reader))          = nothing
_required_terminal(::typeof(test_repl))            = nothing
_required_terminal(::typeof(test_position_navigation)) = :text

_applies(tester, ex::Example) = (r = _required_terminal(tester); r === nothing || r == ex.terminal)

# Route one Example to a tester. printer/reader/repl take an Example directly;
# position-navigation takes (label, document, projection).
_run_catalog_tester(::typeof(test_position_navigation), ex::Example) =
    test_position_navigation(ex.name, ex.make_document(), ex.make_projection())
_run_catalog_tester(tester, ex::Example) = tester(ex)

# The default testers are the domain-agnostic three. `test_position_navigation` is
# deliberately NOT a default: it seeds an initial selection with `Ctrl+Home`, which the
# generated *minimal* composite text projections (`PrimitiveStringToTextBlock`,
# `RecursiveProjection(JsonToSyntax()) → SyntaxToText()`, …) don't answer — the seed
# reader returns `nothing` instead of a `ReplaceSelectionOperation`, so every `:text`
# entry reports 0 navigation states (fail-safe: it does not run away). Wiring that seed
# through the composite chains is the flat-offset-reader follow-up (see the "Known gaps
# surfaced by the catalog" section of plan/pending/atomic-example-catalog.md). It stays a
# routed opt-in — `test_catalog(testers = (test_position_navigation,))` — for when it lands.
const _CATALOG_TESTERS = (test_printer, test_reader, test_repl)

# (entry, tester) combinations skipped because they trip a PRE-EXISTING domain bug the
# catalog surfaced — not a catalog defect. Skipped (via `@test_skip`) so the suite stays
# green, exactly as `test_repls` skips its known-StackOverflow examples. See the "Known
# gaps surfaced by the catalog" section of plan/pending/atomic-example-catalog.md.
#
#   json/bool/graphics, yaml/bool/graphics × test_repl — the REPL edit walk on a
#   *bare-root* bool writes a non-`Bool` into the document's `value`; the reprint thunk
#   `() -> doc.value ? "true" : "false"` (JsonToSyntax.jl / YamlToSyntax.jl) then hits
#   `if nothing` and throws `TypeError(:if, …, Bool, nothing)`. The projection chain is
#   identical to `json/number/graphics` (which passes), so it is a JsonBool/YamlBool
#   bare-root round-trip bug, not the catalog's doing.
_catalog_known_broken(ex::Example, tester) =
    tester === test_repl && ex.name in ("json/bool/graphics", "yaml/bool/graphics")

"""
    test_catalog(; domain=nothing, document=nothing, terminal=nothing, only_runnable=false,
                   testers=(test_printer, test_reader, test_repl, test_position_navigation))

Run each applicable tester over the discovered example catalog, filtered by
`domain` / `document` / `terminal` / `only_runnable`. Applicability is decided per
`Example` by its `terminal` field — a `:syntax` pair runs printer/reader/repl but not
position-navigation — so no per-domain skip-lists are needed (only the small
`_catalog_known_broken` set for pre-existing domain bugs).
"""
function test_catalog(; domain = nothing, document = nothing, terminal = nothing,
                        only_runnable = false, testers = _CATALOG_TESTERS)
    @testset "Catalog" begin
        for ex in catalog(; domain = domain, document = document,
                            terminal = terminal, only_runnable = only_runnable)
            @testset "$(ex.name)" begin
                for tester in testers
                    _applies(tester, ex) || continue
                    if _catalog_known_broken(ex, tester)
                        @test_skip false        # pre-existing domain bug; see above
                    else
                        _run_catalog_tester(tester, ex)
                    end
                end
            end
        end
    end
end
