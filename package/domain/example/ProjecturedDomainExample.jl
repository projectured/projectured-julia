"""
    ProjecturedDomainExample

The domain tier of the example-package DAG that parallels the main DAG
(kernel ← visual ← domain ← umbrella; see
plan/done/example-package-split.md). It hosts:

- the domain-tier `Example` instances and their factories: the concrete
  source domains (json/yaml/xml/sql/formula/math/julia/markdown/book/
  filesystem), the application examples (workbench, conversation, assistant —
  the LLM transport stays behind the kernel agent seam; the assistant examples
  pass an explicit `FakeLlm` test double so they run offline), and the
  cross-domain compositions (mixed documents, graphs, tables, clipboard,
  versioning, dragging);
- the **example gallery**: `run_example` with its workbench / tooltip /
  inspector / clipboard / introspection wrappers (domain vocabulary — the
  reason the gallery lives at this tier), `run_console_example`, and
  `record_assistant_conversation_video`;
- the **file-editor harness** (`EditorDomain`, `run_file_editor`) whose
  domain table wires json/text/xml loaders.

SDL/Video/Web are reached only through the kernel backend seams; the
name-lookup entry points (`run_example("json")`) live in the
`ProjecturedExample` umbrella, which owns the global registry.

The tier's registry slice is `domain_examples`.
"""
module ProjecturedDomainExample

using Profile
import ProjecturedKernel
import ProjecturedBase
import ProjecturedVisual
import ProjecturedDomain
using ProjecturedKernelExample
using ProjecturedVisualExample
import ProjecturedKernelExample: Example, make_typein_gestures

# The example factories were written against the flat `Projectured` namespace.
# Build the same flat namespace over the four main-package sources — one mechanical
# pass, exactly like the `Projectured` umbrella's re-export loop (but without
# re-exporting).
for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual, ProjecturedDomain)
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

include("document/Json.jl")
include("document/Yaml.jl")
include("document/Xml.jl")
include("document/Mixed.jl")
include("document/Natural.jl")
include("document/Book.jl")
include("document/Markdown.jl")
include("document/FileSystem.jl")
include("document/Navigator.jl")
include("document/Focusing.jl")
include("document/Workbench.jl")
include("document/Assistant.jl")
include("document/Conversation.jl")
include("document/Table.jl")
include("document/Graph.jl")
include("document/Chart.jl")
include("document/SequenceChart.jl")
include("document/Fsm.jl")
include("document/Math.jl")
include("document/Julia.jl")
include("document/Formula.jl")
include("document/Wrapper.jl")
include("document/DatabaseInstance.jl")
include("document/Sql.jl")
include("document/Clipboard.jl")
include("document/Versioning.jl")
include("document/Dragging.jl")

include("projection/Json.jl")
include("projection/Yaml.jl")
include("projection/Table.jl")
include("projection/Graph.jl")
include("projection/Chart.jl")
include("projection/SequenceChart.jl")
include("projection/Fsm.jl")
include("projection/Xml.jl")
include("projection/Mixed.jl")
include("projection/Natural.jl")
include("projection/Book.jl")
include("projection/Markdown.jl")
include("projection/FileSystem.jl")
include("projection/Navigator.jl")
include("projection/Focusing.jl")
include("projection/Workbench.jl")
include("projection/Assistant.jl")
include("projection/Conversation.jl")
include("projection/Math.jl")
include("projection/Julia.jl")
include("projection/Formula.jl")
include("projection/Wrapper.jl")
include("projection/Graphics.jl")
include("projection/Sql.jl")
include("projection/Clipboard.jl")
include("projection/Versioning.jl")
include("projection/Dragging.jl")

include("Examples.jl")
include("Gallery.jl")
include("FileEditor.jl")

export EditorDomain, EditorIntrospection, JsonXmlToSyntax, assistant_example, book_example
export build_file_editor, clipboard_example, conversation_editor_example, conversation_example
export conversation_widget_example, domain_for_path, dragging_example, editor_domain
export filesystem_example, filesystem_widget_example, focusing_example, formula_example
export chart_example, chart_line_example, chart_bar_example,
       chart_histogram_example, chart_scatter_example, chart_strip_example,
       chart_inspector_example
export sequencechart_example, sequencechart_vertical_example,
       sequencechart_linear_example, sequencechart_large_example,
       sequencechart_inspector_example, sequencechart_pair_example
export fsm_example, fsm_toggle_example, fsm_diagram_example
export make_fsm_document_example, make_fsm_projection_example,
       make_fsm_tcp_document_example, make_fsm_toggle_document_example,
       make_fsm_variable_document_example, make_fsm_timer_document_example,
       make_fsm_event_document_example, make_fsm_state_document_example,
       make_fsm_transition_document_example, make_fsm_insertion_document_example,
       make_fsm_diagram_document_example, make_fsm_diagram_projection_example
export graph_example, graphics_image_example, json_example, json_insertion_example
export json_sorted_example, julia_example
export make_assistant_document_example, make_assistant_projection_example
export make_book_document_example, make_book_projection_example, make_clipboard_document
export make_clipboard_document_example, make_clipboard_projection
export make_clipboard_projection_example, make_conversation_document_example
export make_conversation_editor_document_example, make_conversation_editor_projection_example
export make_conversation_projection_example, make_conversation_widget_projection_example
export make_database_instance_document_example, make_dragging_document_example
export make_dragging_projection_example, make_filesystem_document_example
export make_filesystem_projection_example, make_filesystem_widget_projection_example
export make_focusing_document_example, make_focusing_projection_example
export make_formula_document_example, make_formula_projection_example
export make_chart_document_example, make_chart_projection_example,
       make_chart_pipeline_example,
       make_chart_line_document_example, make_chart_line_projection_example,
       make_chart_bar_document_example, make_chart_bar_projection_example,
       make_chart_histogram_document_example, make_chart_histogram_projection_example,
       make_chart_scatter_document_example, make_chart_scatter_projection_example,
       make_chart_strip_document_example, make_chart_strip_projection_example,
       make_chart_inspector_document_example, make_chart_inspector_projection_example
export make_sequencechart_document_example, make_sequencechart_projection_example,
       make_sequencechart_pipeline_example,
       make_sequencechart_vertical_document_example, make_sequencechart_vertical_projection_example,
       make_sequencechart_linear_document_example, make_sequencechart_linear_projection_example,
       make_sequencechart_large_document_example, make_sequencechart_large_projection_example,
       make_sequencechart_inspector_document_example, make_sequencechart_inspector_projection_example,
       make_sequencechart_pair_document_example, make_sequencechart_pair_projection_example,
       make_sequencechart_composite_projection_example
export make_graph_document_example, make_graph_projection_example, make_graphics_caching
export make_graphics_image_projection_example, make_introspection_document
export make_introspection_projection, make_json_console_projection_example
export make_json_document_example, make_json_insertion_document_example
export make_json_null_document_example, make_json_null_projection_example
export make_json_projection_example, make_json_sorted_projection_example
export make_json_string_document_example, make_json_string_projection_example
export make_julia_document_example, make_julia_projection_example
export make_markdown_document_example, make_markdown_projection_example
export make_markdown_rendered_projection_example, make_math_document_example
export make_math_projection_example, make_math_table_document_example
export make_math_table_projection_example, make_mixed_document_example
export make_mixed_projection_example, make_natural_document_example
export make_natural_projection_example, make_navigator_document_example
export make_navigator_projection_example, make_scrolling_document, make_scrolling_projection
export make_sql_document_example, make_sql_insert_document_example
export make_sql_insert_syntax_projection_example, make_sql_nested_document_example
export make_sql_nested_syntax_projection_example, make_sql_syntax_projection_example
export make_sql_update_document_example, make_sql_update_syntax_projection_example
export make_table_document_example, make_table_projection_example
export make_text_configuring_projection, make_versioning_document_example
export make_versioning_projection_example, make_workbench_document
export make_workbench_document_example, make_workbench_projection
export make_workbench_projection_example, make_xml_document_example
export make_xml_projection_example, make_yaml_document_example, make_yaml_projection_example
export markdown_example, markdown_rendered_example, math_example, math_table_example
export mixed_example, natural_example, navigator_example, record_assistant_conversation_video
export run_console_example, run_example, run_file_editor, sql_insert_syntax_example
export sql_nested_syntax_example, sql_syntax_example, sql_update_syntax_example, table_example
export versioning_example, warm_file_editor, workbench_example, xml_example, yaml_example
export Example, AtomicDocument, domain_examples, domain_atomic_documents
export EDITOR_DOMAINS, EXTENSION_DOMAINS
# Re-export the kernel-example LLM test doubles so domain test files can use
# them without importing ProjecturedKernelExample directly.
export FakeLlm, ScriptedLlm,
       make_scripted_turn, make_scripted_think, make_scripted_say, make_scripted_run

end # module ProjecturedDomainExample
