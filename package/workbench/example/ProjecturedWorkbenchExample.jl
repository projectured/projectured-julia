"""
    ProjecturedWorkbenchExample

The Workbench tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedWorkbenchExample

import ProjecturedBase
import ProjecturedBook
import ProjecturedConversation
import ProjecturedFileSystem
import ProjecturedJson
import ProjecturedJulia
import ProjecturedKernel
import ProjecturedMarkdown
import ProjecturedSql
import ProjecturedVisual
import ProjecturedWorkbench
import ProjecturedXml
import ProjecturedYaml
import ProjecturedMath
using ProjecturedBookExample
using ProjecturedJsonExample
using ProjecturedJuliaExample
using ProjecturedMarkdownExample
using ProjecturedSqlExample
using ProjecturedXmlExample
using ProjecturedYamlExample
using ProjecturedConversationExample
using ProjecturedFileSystemExample
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedBase, ProjecturedBook, ProjecturedConversation, ProjecturedFileSystem, ProjecturedJson, ProjecturedJulia, ProjecturedKernel, ProjecturedMarkdown, ProjecturedMath, ProjecturedSql, ProjecturedVisual, ProjecturedWorkbench, ProjecturedXml, ProjecturedYaml)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("document/Assistant.jl")
include("document/Navigator.jl")
include("document/Workbench.jl")
include("document/Wrapper.jl")
include("projection/Assistant.jl")
include("projection/Navigator.jl")
include("projection/Workbench.jl")
include("projection/Wrapper.jl")

include("document/Table.jl")

export make_table_document_example, make_math_table_document_example
export make_assistant_document_example, make_navigator_document_example, make_workspace_folder_document_example
export make_workspace_document_example, make_workbench_document_example, make_workbench_operator_document_example
export make_workbench_searcher_document_example, make_workbench_evaluator_document_example, make_workbench_descriptor_document_example
export make_workbench_console_document_example, make_workbench_navigator_document_example, make_workbench_page_document_example
export make_workbench_editor_document_example, make_workbench_assistant_document_example, make_workbench_workbench_document_example
export make_scrolling_document, make_introspection_document, make_clipboard_document
export make_dragging_document, make_shell_document, make_workbench_document
export make_assistant_projection_example, make_navigator_projection_example, make_workbench_projection_example
export make_graphics_caching, make_scrolling_projection, make_dragging_projection
export make_shell_projection, make_command_palette_projection, make_introspection_projection
export make_clipboard_projection, make_text_configuring_projection, make_workbench_projection

end # module ProjecturedWorkbenchExample
