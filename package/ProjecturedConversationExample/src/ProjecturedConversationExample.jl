"""
    ProjecturedConversationExample

The Conversation tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedConversationExample

import ProjecturedPlatform
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedMarkdown
using ProjecturedJuliaExample
using ProjecturedMarkdownExample
import ProjecturedJson
import ProjecturedXml
import ProjecturedYaml
using ProjecturedJsonExample
using ProjecturedKernelExample
using ProjecturedSubstrateExample
using ProjecturedXmlExample
using ProjecturedYamlExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedMarkdown, ProjecturedPdf, ProjecturedXml, ProjecturedYaml)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../example/platform/conversation/ConversationDocumentExample.jl")
include("../../../example/platform/conversation/ConversationProjectionExample.jl")
include("../../../example/platform/conversation/AssistantDocumentExample.jl")
include("../../../example/platform/conversation/AssistantProjectionExample.jl")

export _conversation_widget_graphics
export make_conversation_document_example, make_conversation_editor_document_example, make_conversation_part_document_example
export make_assistant_conversation_document_example
export make_conversation_turn_document_example, make_conversation_conversation_document_example, make_conversation_draft_document_example
export make_conversation_widget_projection_example, make_conversation_editor_projection_example
export make_assistant_document_example, make_assistant_projection_example
export conversation_draft_entry, conversation_widget_entry

end # module ProjecturedConversationExample
