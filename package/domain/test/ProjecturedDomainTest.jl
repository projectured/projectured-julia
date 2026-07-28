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
import ProjecturedDomain
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
for _src in (ProjecturedKernel, ProjecturedBase, ProjecturedVisual, ProjecturedDomain)
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # a submodule defined *by* this source (skip re-exported aliases of the other source)
        (_m isa Module && _m !== _src && parentmodule(_m) === _src) || continue
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
include("document/JsonTest.jl")
include("document/JsonParserTest.jl")
include("document/SqlParserTest.jl")
include("document/SqlDocumentTest.jl")
include("document/SelectionEnumeration.jl")

# ── projections ──────────────────────────────────────────────────────────────
include("projection/JsonToSyntaxTest.jl")
include("projection/XmlToSyntaxTest.jl")
include("projection/SqlToSyntaxTest.jl")
include("projection/FormulaToSyntaxTest.jl")
include("projection/FileSystemToSyntaxTest.jl")
include("projection/GraphTest.jl")
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
include("editor/JuliaTypeinTest.jl")
include("editor/McpTest.jl")
include("editor/WorkbenchFileTest.jl")
include("external/DbCatalogSqlTest.jl")
include("projection/ConversationEditorTest.jl")
include("projection/DocumentInsertionTest.jl")
include("projection/DraggingTest.jl")
include("projection/GestureHelpTest.jl")
include("projection/GestureMapTest.jl")
include("projection/HoverProbeTest.jl")
include("projection/TableNavigationTest.jl")
include("projection/WorkbenchTabClickTest.jl")
include("projection/WorkbenchContentPaneTest.jl")
include("serializer/SerializationTest.jl")
include("editor/ConstructTest.jl")

"""
    test_domain_layering()

Static layered-architecture guard for `ProjecturedDomain` (see
`ProjecturedKernelTest.check_layering`). The domain source is organized into
slice folders whose ordering is enforced by the topological include-order
check; no layer indices are declared.
"""
function test_domain_layering()
    # `pkgdir` rejects the flat entryfile-at-root layout (main/ProjecturedDomain.jl
    # is not under a src/), so derive the package root from `pathof`.
    main = normpath(dirname(pathof(ProjecturedDomain)))
    check_layering(main, joinpath(main, "ProjecturedDomain.jl"); name = "domain")
end

"""
    test_domain()

Run the whole domain suite: the static layering guard and every domain test.
"""
function test_domain()
    @testset "ProjecturedDomain" begin
        test_domain_layering()
        test_domain_examples()
        # documents
        test_json()
        test_json_parser()
        test_xml_parser()
        test_sql_parser()
        test_sql_document()
        # projections
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
        test_filesystem_to_syntax()
        test_graph()
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
        test_db_catalog_sql()
        test_reference_inspector_text()
        test_hover_probe()
        test_hover_probe_pipeline()
        test_workbench_tab_click()
        test_workbench_content_pane()
        test_dragging()
        test_serialization()
        test_mcp_tools()
        test_conversation_serialization()
        test_parse_markdown_blocks()
        test_document_insertion()
        test_julia_typein()
        test_conversation_editor()
        test_assistant_composer_panel()
        test_assistant_mvp()
        test_workbench_file_keys()
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
export test_json, test_json_parser, test_xml_parser,
       test_sql_parser, test_sql_document, test_sql_document_nested_select,
       test_sql_boolean_expression
export test_json_to_syntax, test_json_to_syntax_reader, test_json_gesture_collection,
       test_xml_to_syntax, test_xml_to_syntax_reader, test_xml_override_gestures,
       test_sql_to_syntax, test_sql_to_syntax_selection,
       test_sql_insert_update_selection, test_sql_ddl, test_sql_ddl_selection,
       test_formula_to_syntax, test_filesystem_to_syntax, test_graph
export test_syntax_tree_selection,
       test_table_selection
export test_console_backend, test_write_pdf, test_type_reference
export test_json_content_clicks_clean, collect_json_tree_selections, test_json_placeholder_navigation
export test_construct, reconstruct, test_json_construct, test_yaml_construct, test_xml_construct
# moved down from the umbrella
export test_gesture_map, test_gesture_help, test_db_catalog_sql,
       test_reference_inspector_text, test_hover_probe, test_hover_probe_pipeline,
       test_workbench_tab_click, test_workbench_content_pane, test_dragging, test_serialization, test_mcp_tools,
       test_mcp_resources, test_conversation_serialization, test_parse_markdown_blocks,
       test_document_insertion, test_julia_typein, test_conversation_editor,
       test_assistant_composer_panel, test_assistant_mvp, test_workbench_file_keys,
       test_table_navigation

end # module ProjecturedDomainTest
