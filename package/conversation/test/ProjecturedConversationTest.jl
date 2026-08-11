"""
    ProjecturedConversationTest

The Conversation tier of the test-package DAG: the suites whose fixtures are conversation
documents. A suite whose fixture names several domains lives in
`ProjecturedTest` instead.

Everything is aggregated by `test_conversation()`.
"""
module ProjecturedConversationTest

using Test
import ProjecturedBase
import ProjecturedConversation
import ProjecturedJson
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedVisual
import ProjecturedXml
using ProjecturedKernelExample
using ProjecturedVisualExample
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
using ProjecturedConversationExample

const _SOURCES = (ProjecturedBase, ProjecturedConversation, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedVisual, ProjecturedXml)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("projection/ConversationEditorTest.jl")

"""
    test_conversation_layering()

Static layered-architecture guard for `ProjecturedConversation`.
"""
function test_conversation_layering()
    main = normpath(dirname(pathof(ProjecturedConversation)))
    check_layering(main, joinpath(main, "ProjecturedConversation.jl");
                   name = "conversation",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedConversation; all = true)
                         if isdefined(ProjecturedConversation, n) &&
                            getfield(ProjecturedConversation, n) isa Module &&
                            getfield(ProjecturedConversation, n) !== ProjecturedConversation &&
                            parentmodule(getfield(ProjecturedConversation, n)) !== ProjecturedConversation))
end

"""
    test_conversation()

Run this package's whole suite: the layering guard and every conversation test.
"""
function test_conversation()
    @testset "ProjecturedConversation" begin
        test_conversation_layering()
        test_conversation_editor()
    end
end

export test_conversation, test_conversation_layering
export test_conversation_editor

end # module ProjecturedConversationTest
