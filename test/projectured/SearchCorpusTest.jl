"""
The corpus of a whole application: each name is declared once, by the module
that owns it.

A package that re-exports the names of others comes first in the order of names,
and a corpus that let it give them would show `Umbrella.open_pane!` for a verb
that `PaneModule` defines, and would find the folder of the umbrella for its
call sites.
"""

using Test

module SearchCorpusFixture
module Owner
export make_widget, Widget
make_widget() = 1
struct Widget end
end
module AUmbrella
using ..Owner
export make_widget
end
module Rival
export make_widget
make_widget() = 2
end
end

function test_search_corpus()
@testset "the corpus of a whole application" begin
    fixture = SearchCorpusFixture
    # The umbrella comes first, as it does in the order of full names.
    modules = [fixture.AUmbrella, fixture.Owner, fixture.Rival]
    declaration, dropped = make_corpus_declaration(modules)
    given = Dict(first(pair) => last(pair) for pair in declaration)

    @test given[fixture.Owner] == (:Widget, :make_widget)
    @test given[fixture.AUmbrella] == ()
    @test given[fixture.Rival] == ()
    @test dropped == 1

    set, _ = make_corpus_tool_set(modules)
    names = [entry.qualname for entry in ToolModule._api_index(set.api) if entry.kind != "module"]
    @test "Owner.make_widget" in names
    @test !("AUmbrella.make_widget" in names)
end
end
