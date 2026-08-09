"""
    ProjecturedDomainTest

Test package for `ProjecturedDomain` — fourth tier of the test-package DAG that
parallels the main DAG (kernel ← base ← visual ← domain ← umbrella; see
plan/pending/test-package-split.md). It hosts:

- the domain documents' tests (json/xml/sql/tabular + parsers);
- the `*ToSyntax` projection tests (json/xml/sql/formula/filesystem) and the
  graph projection tests;
- domain-fixture-driven suites that exercise lower-layer machinery: the
  Console/Pdf backend tests, table selection, TypeReferenceStep checkpoints, and
  the atomic per-stage fixtures;
- the projection-aware JSON selection enumerator
  (`collect_json_tree_selections`) and the JSON content-click checks.

This is where `test_printer(json_example)`-style calls run: the domain fixture
documents are built here (`Fixtures.jl`, mirrored from `ProjecturedExample`
until the examples split per package) and driven by the generic
`ProjecturedKernelTest` drivers.

Everything is aggregated by `test_domain()`; the layering guard is
`test_domain_layering()` (via `ProjecturedKernelTest.check_layering`).

Like the umbrella, this is a **function library**: `using ProjecturedDomainTest`
from the repo-root environment, then call `test_domain()` or any individual
`test_*` function.
"""
module ProjecturedDomainTest

using Test
import ProjecturedKernel
import ProjecturedBase
import ProjecturedVisual
# The concrete domains, in dependency order.
import ProjecturedJson
import ProjecturedYaml
import ProjecturedXml
import ProjecturedMarkdown
import ProjecturedRst
import ProjecturedBook
import ProjecturedMath
import ProjecturedJulia
import ProjecturedSql
import ProjecturedDatabase
import ProjecturedFileSystem
import ProjecturedGraph
import ProjecturedChart
import ProjecturedSequenceChart
import ProjecturedDbCatalog
import ProjecturedFormula
import ProjecturedFsm
import ProjecturedProcess
import ProjecturedConversation
import ProjecturedWorkbench
using ProjecturedKernelTest
using ProjecturedBaseTest
using ProjecturedVisualTest
# The real domain-tier example factories and the tier's registry slice — the
# mirrored Fixtures.jl copies are gone (plan/done/example-package-split.md).
using ProjecturedDomainExample
import ProjecturedVisualTest: test_tree_navigation
import ProjecturedVisualTest: _find_text_iomap, _pipeline_measure, _seg_x_at,
                              _path_contains_projection_ref

# The tests below were written against the flat `Projectured` namespace. Build
# the same flat namespace over the four main-package sources — one mechanical pass,
# exactly like the `Projectured` umbrella's re-export loop (but without
# re-exporting): alias every submodule and `using` its exported names into
# scope.
const _SOURCES = (ProjecturedKernel, ProjecturedBase, ProjecturedVisual,
                  ProjecturedJson, ProjecturedYaml, ProjecturedXml, ProjecturedMarkdown, ProjecturedRst, ProjecturedBook, ProjecturedMath, ProjecturedJulia, ProjecturedSql, ProjecturedDatabase, ProjecturedFileSystem, ProjecturedGraph, ProjecturedChart, ProjecturedSequenceChart, ProjecturedDbCatalog, ProjecturedFormula, ProjecturedFsm, ProjecturedProcess, ProjecturedConversation, ProjecturedWorkbench)

# A submodule this source defines, or a submodule of a package this source
# reaches but the list does not name — a concrete domain that already left
# `ProjecturedDomain` for its own package arrives through that binding.
_alias_here(_src, _m) =
    parentmodule(_m) === _src ||
    (parentmodule(_m) !== Main && !(parentmodule(_m) in _SOURCES))

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        (_m isa Module && _m !== _src && _alias_here(_src, _m)) || continue
        # alias the submodule so `XxxModule.foo` keeps resolving
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        # bring its exported names into scope
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

# ── domain documents ─────────────────────────────────────────────────────────
include("document/FsmTest.jl")
include("document/ProcessTest.jl")
include("projection/ProcessToSyntaxTest.jl")
include("projection/ProcessDiagramTest.jl")
include("projection/ProcessToJuliaCodeTest.jl")
include("projection/ProcessDebugTest.jl")
include("document/JsonTest.jl")
include("document/JsonParserTest.jl")
include("document/RstParserTest.jl")
include("document/JuliaParserTest.jl")
include("document/SqlParserTest.jl")
include("document/SqlDocumentTest.jl")
include("document/SelectionEnumeration.jl")

# ── projections ──────────────────────────────────────────────────────────────
include("projection/FsmToSyntaxTest.jl")
include("projection/FsmDiagramTest.jl")
include("projection/FsmToJuliaCodeTest.jl")
include("projection/JsonToSyntaxTest.jl")
include("projection/XmlToSyntaxTest.jl")
include("projection/SqlToSyntaxTest.jl")
include("projection/FormulaToSyntaxTest.jl")
include("projection/MathToGraphicsTest.jl")
include("projection/FileSystemToSyntaxTest.jl")
include("projection/GraphTest.jl")
include("projection/ChartTest.jl")
include("projection/SequenceChartGeometryTest.jl")
include("projection/SequenceChartTest.jl")
include("projection/SyntaxTreeSelectionTest.jl")
include("projection/TableSelectionTest.jl")

# ── domain-fixture-driven backend / reference / editor suites ────────────────
include("backend/ConsoleBackendTest.jl")
include("backend/PdfTest.jl")
include("reference/TypeReferenceTest.jl")
include("editor/JsonContentClicksTest.jl")
include("editor/JsonPlaceholderNavTest.jl")

# ── moved down from the umbrella: tests whose fixtures are domain documents ───
# (JSON/Julia/SQL/DbCatalog/Workbench/Conversation/GestureMap). Each drives a
# domain projection or the domain-coupled editor loop; none needs an opt-in
# package. Their example factories live in ProjecturedDomainExample.
include("editor/AssistantMvpTest.jl")
include("editor/ConversationPanelTest.jl")
include("editor/ConversationParsingTest.jl")
include("editor/ConversationSerializationTest.jl")
include("editor/GalleryWrapperTest.jl")
include("editor/JuliaTypeinTest.jl")
include("editor/McpTest.jl")
include("editor/WorkbenchFileTest.jl")
include("external/DbCatalogSqlTest.jl")
include("projection/ConversationEditorTest.jl")
include("projection/DocumentInsertionTest.jl")
include("projection/DraggingTest.jl")
include("projection/CommandPaletteTest.jl")
include("projection/GestureHelpTest.jl")
include("projection/GestureLogTest.jl")
include("projection/GestureMapTest.jl")
include("projection/HoverProbeTest.jl")
include("projection/TableNavigationTest.jl")
include("projection/WorkbenchTabClickTest.jl")
include("projection/WorkbenchContentPaneTest.jl")
include("serializer/SerializationTest.jl")
include("serializer/JsonFileTest.jl")
include("serializer/FileProjectS4Test.jl")
include("serializer/FileProjectS5Test.jl")
include("serializer/JuliaAndMarkdownFileTest.jl")
include("serializer/XmlFileTest.jl")
include("serializer/MarkerVocabularyTest.jl")
include("serializer/StubCollectionTest.jl")
include("serializer/MarkdownEmbedTest.jl")
include("serializer/RstEmbedTest.jl")
include("editor/ConstructTest.jl")

"""
    test_domain_layering()

Static layered-architecture guard for every domain package (see
`ProjecturedKernelTest.check_layering`). Each domain is one package holding one
slice, so the guard runs once per package over that package's own include order.
"""
function test_domain_layering()
    for pkg in _SOURCES
        pkg in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual) && continue
        # `pkgdir` rejects the flat entryfile-at-root layout (main/ProjecturedX.jl
        # is not under a src/), so derive the package root from `pathof`.
        main = normpath(dirname(pathof(pkg)))
        check_layering(main, joinpath(main, String(nameof(pkg)) * ".jl");
                       name = lowercase(chopprefix(String(nameof(pkg)), "Projectured")),
                       extra_aliases = _bound_module_aliases(pkg))
    end
end

"""
    _bound_module_aliases(pkg) -> Set{Symbol}

Every module `pkg`'s root module binds that another package defines. A domain
package binds them with a loop rather than a written table, so the static guard
cannot read them off the file and takes this measured set instead.
"""
_bound_module_aliases(pkg) = Set{Symbol}(
    n for n in names(pkg; all = true)
      if isdefined(pkg, n) && getfield(pkg, n) isa Module &&
         getfield(pkg, n) !== pkg && parentmodule(getfield(pkg, n)) !== pkg)

"""
    test_domain()

Run the whole domain suite: the static layering guard and every domain test.
"""
function test_domain()
    @testset "ProjecturedDomain" begin
        test_domain_layering()
        test_domain_examples()
        # documents
        test_fsm()
        test_process()
        test_process_to_syntax()
        test_process_diagram()
        test_process_to_julia_code()
        test_process_debug()
        test_json()
        test_json_parser()
        test_rst_parser()
        test_rst_round_trip()
        test_xml_parser()
        test_sql_parser()
        test_sql_document()
        # projections
        test_fsm_to_syntax()
        test_fsm_diagram()
        test_fsm_to_julia_code()
        test_json_to_syntax()
        test_json_to_syntax_reader()
        test_json_gesture_collection()
        test_json_construct()
        test_yaml_construct()
        test_xml_construct()
        test_xml_to_syntax()
        test_xml_to_syntax_reader()
        test_xml_override_gestures()
        test_sql_to_syntax()
        test_sql_to_syntax_selection()
        test_sql_insert_update_selection()
        test_sql_ddl()
        test_sql_ddl_selection()
        test_formula_to_syntax()
        test_math_to_graphics()
        test_filesystem_to_syntax()
        test_graph()
        test_chart()
        test_chart_scale()
        test_sequencechart_geometry()
        test_sequencechart()
        test_sequencechart_selection()
        test_sequencechart_scale()
        test_syntax_tree_selection()
        test_table_selection()
        # backends / references / clicks on domain fixtures
        test_console_backend()
        test_write_pdf()
        test_type_reference()
        test_json_content_clicks_clean("json fixture",
            make_json_document_example(), make_graphics_image_projection_example())
        test_json_placeholder_navigation()
        # ── moved down from the umbrella (domain-fixture tests) ──────────────
        test_gesture_map()
        test_gesture_help()
        test_command_palette()
        test_command_palette_decorator()
        test_gesture_log()
        test_db_catalog_sql()
        test_reference_inspector_text()
        test_hover_probe()
        test_hover_probe_pipeline()
        test_workbench_tab_click()
        test_workbench_content_pane()
        test_dragging()
        test_serialization()
        test_json_file()
        test_file_project_s4()
        test_file_project_s5()
        test_julia_and_markdown_file()
        test_xml_file()
        test_julia_parser()
        test_marker_vocabulary()
        test_stub_collection()
        test_markdown_embed()
        test_rst_embed()
        test_mcp_tools()
        test_conversation_serialization()
        test_parse_markdown_blocks()
        test_document_insertion()
        test_julia_typein()
        test_conversation_editor()
        test_assistant_composer_panel()
        test_assistant_mvp()
        test_workbench_file_keys()
        test_gallery_wrappers()
        test_table_navigation()
    end
end

"""
    test_domain_examples()

Walk the printer over every domain-tier example (`domain_examples`) — one
`@test` per forced reactive cell, via the generic `test_printer` driver.
"""
function test_domain_examples()
    @testset "DomainExamples" begin
        for ex in domain_examples
            @testset "$(ex.name)" begin
                test_printer(ex)
            end
        end
    end
end

export test_domain, test_domain_layering, test_domain_examples
export test_fsm, test_fsm_to_syntax, test_fsm_diagram, test_fsm_to_julia_code
export test_process, test_process_to_syntax, test_process_diagram,
       test_process_to_julia_code, test_process_debug
export test_rst_parser, test_rst_round_trip, test_rst_corpus, rst_ast_equal
export test_json, test_json_parser, test_xml_parser,
       test_sql_parser, test_sql_document, test_sql_document_nested_select,
       test_sql_boolean_expression
export test_json_to_syntax, test_json_to_syntax_reader, test_json_gesture_collection,
       test_xml_to_syntax, test_xml_to_syntax_reader, test_xml_override_gestures,
       test_sql_to_syntax, test_sql_to_syntax_selection,
       test_sql_insert_update_selection, test_sql_ddl, test_sql_ddl_selection,
       test_formula_to_syntax, test_filesystem_to_syntax, test_graph,
       test_math_to_graphics
export test_chart, test_chart_scale
export test_sequencechart_geometry, test_sequencechart, test_sequencechart_selection
export test_sequencechart_scale
export test_syntax_tree_selection,
       test_table_selection
export test_console_backend, test_write_pdf, test_type_reference
export test_json_content_clicks_clean, collect_json_tree_selections, test_json_placeholder_navigation
export test_construct, reconstruct, test_json_construct, test_yaml_construct, test_xml_construct
# moved down from the umbrella
export test_gesture_map, test_gesture_help, test_gesture_log,
       test_command_palette, test_command_palette_decorator, test_db_catalog_sql,
       test_reference_inspector_text, test_hover_probe, test_hover_probe_pipeline,
       test_workbench_tab_click, test_workbench_content_pane, test_dragging, test_serialization, test_mcp_tools,
       test_mcp_resources, test_conversation_serialization, test_parse_markdown_blocks,
       test_document_insertion, test_julia_typein, test_conversation_editor,
       test_assistant_composer_panel, test_assistant_mvp, test_workbench_file_keys,
       test_gallery_wrappers, test_table_navigation
export test_json_file, test_file_project_s4, test_file_project_s5, test_julia_and_markdown_file, test_xml_file
export test_marker_vocabulary, test_markdown_embed, test_rst_embed, test_julia_parser
export test_stub_collection

end # module ProjecturedDomainTest
