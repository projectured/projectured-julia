"""
    ProjecturedRstExample

The Rst tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedRstExample

import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedPlatform
import ProjecturedRst
using ProjecturedKernelExample
using ProjecturedPlatformExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedKernel, ProjecturedPdf, ProjecturedRst)

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

include("../../../example/domain/rst/RstDocumentExample.jl")
include("../../../example/domain/rst/RstProjectionExample.jl")

export make_rst_text_document_example, make_rst_literal_document_example, make_rst_transition_document_example
export make_rst_comment_document_example, make_rst_target_document_example, make_rst_insertion_document_example
export make_rst_math_block_document_example, make_rst_role_document_example, make_rst_reference_document_example
export make_rst_substitution_reference_document_example, make_rst_footnote_reference_document_example, make_rst_emphasis_document_example
export make_rst_strong_document_example, make_rst_paragraph_document_example, make_rst_literal_block_document_example
export make_rst_line_block_document_example, make_rst_list_item_document_example, make_rst_bullet_list_document_example
export make_rst_enumerated_list_document_example, make_rst_definition_item_document_example, make_rst_definition_list_document_example
export make_rst_field_document_example, make_rst_field_list_document_example, make_rst_block_quote_document_example
export make_rst_footnote_document_example, make_rst_substitution_definition_document_example, make_rst_table_cell_document_example
export make_rst_table_row_document_example, make_rst_grid_table_document_example, make_rst_directive_option_document_example
export make_rst_literal_include_document_example, make_rst_figure_document_example, make_rst_code_block_document_example
export make_rst_image_document_example, make_rst_video_document_example, make_rst_audio_document_example
export make_rst_admonition_document_example, make_rst_toctree_document_example, make_rst_raw_block_document_example
export make_rst_role_definition_document_example, make_rst_directive_document_example, make_rst_section_document_example
export make_rst_root_document_example, make_rst_document_example, make_rst_projection_example
export make_rst_rendered_projection_example

end # module ProjecturedRstExample
