for _n in names(ProjecturedAll; all = true)
    isdefined(ProjecturedAll, _n) || continue
    _m = getfield(ProjecturedAll, _n)
    (_m isa Module && _m !== ProjecturedAll && parentmodule(_m) !== Main) || continue
    Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
end

using ProjecturedExample
import TOML
# The transcript test names the factories of the conversation example by package.
import ProjecturedConversationExample
# The generic test drivers ((label, document, projection) forms), the reflexive
# cell walker, the event battery, and the kernel unit suites live in
# ProjecturedKernelTest — the base of the test-package DAG. The umbrella keeps
# the `Example`-typed overloads and the all-examples sweeps (ExampleSweeps.jl),
# and extends the ground-truth selection enumerators for the domains it owns.
using ProjecturedKernelTest
using ProjecturedPlatformTest
using ProjecturedJSONTest
using ProjecturedJSONTest: test_json_content_clicks_clean
using ProjecturedYAMLTest
using ProjecturedXMLTest
using ProjecturedMarkdownTest
using ProjecturedRSTTest
using ProjecturedBookTest
using ProjecturedMathTest
using ProjecturedJuliaTest
using ProjecturedSQLTest
using ProjecturedDatabaseTest
using ProjecturedGraphTest
using ProjecturedChartTest
using ProjecturedSequenceChartTest
using ProjecturedDBCatalogTest
using ProjecturedFormulaTest
using ProjecturedFSMTest
using ProjecturedProcessTest
using ProjecturedPivotTest

# Re-export every lower tier's test functions, so `using ProjecturedTest` alone
# gives a REPL `test_json()` and `test_platform()` as well as `test_all()`.
for _src in (ProjecturedBookTest, ProjecturedChartTest, ProjecturedPlatformTest, ProjecturedDatabaseTest, ProjecturedDBCatalogTest, ProjecturedFormulaTest, ProjecturedFSMTest, ProjecturedGraphTest, ProjecturedJSONTest, ProjecturedJuliaTest, ProjecturedKernelTest, ProjecturedMarkdownTest, ProjecturedMathTest, ProjecturedProcessTest, ProjecturedPivotTest, ProjecturedRSTTest, ProjecturedSequenceChartTest, ProjecturedSQLTest, ProjecturedXMLTest, ProjecturedYAMLTest)
    for _n in names(_src)
        _n === nameof(_src) && continue
        isdefined(_src, _n) || continue
        Core.eval(@__MODULE__, Expr(:export, _n))
    end
end
import ProjecturedPlatformTest: test_collection, test_copying_projection
import ProjecturedPlatformTest: test_projection_template_hygiene,
                              test_syntax, test_text, test_graphics, test_affine_transform,
                              test_graphics_layout, test_layout_allocator,
                              test_layout_constraint_helpers, test_primitive,
                              test_syntax_to_text, test_primitive_to_text,
                              test_text_to_graphics, test_word_wrapping,
                              test_filtered_text_to_text, test_highlighted_text_to_text,
                              test_selection_inverting,
                              test_object_to_widget, test_find_bar_view_to_widget,
                              test_widget_text_editing, test_widget_button_behavior,
                              test_widget_gestures, test_widget_select_dropdown,
                              test_widget_menu, test_widget_context_menu,
                              test_widget_dialog, test_widget_action, test_widget_icon,
                              test_widget_tree, test_widget_toolbar, test_widget_table,
                              test_widget_transform_pane, test_layout_closeout,
                              test_widget_forms, test_anchor_point,
                              walk_typein, test_typein,
                              test_click_roundtrip, test_text_navigation_invariants,
                              _find_text_iomap, _find_cursor_rect, _pipeline_measure,
                              _segment_x_at, _path_contains_projection_reference
import ProjecturedKernelTest: test_kernel
import ProjecturedPlatformTest: test_platform
import ProjecturedKernelTest: test_printer, test_reader, test_repl,
                              explore_selections, test_navigation,
                              walk_printer_output, walk_reader_events, walk_repl_loop,
                              test_gesture_pattern, test_gesture_binding,
                              WalkStatus, _walk!, _WALK_MAX_DEPTH, _WALK_MAX_NODES,
                              _ALL_READER_EVENTS, _assert_reaches_all
import ProjecturedPlatformTest: collect_position_selections, collect_tree_selections,
                                 test_focusing
# The navigation presets over the generic driver (position + tree gesture sets).
import ProjecturedPlatformTest: test_position_navigation, test_tree_navigation,
                              explore_position_selections, explore_tree_selections
# Opt into the SDL backend package so the test suite can drive rendering /
# write_image / click roundtrips (provides SdlBackend + GraphicsCanvasToImageFile).
# The library itself is SDL-optional; the test package opts in.
using ProjecturedSDL
# Opt into the video package so VideoTest can drive record_video (it provides the
# record_video method on the kernel seam; FFMPEG lives here, not in ProjecturedSDL).
using ProjecturedVideo
# Likewise opt into the Odbc package so the database tests can construct
# adapters/pools/projections and assert on their types (all exported by the package).
using ProjecturedODBC
# Opt into the Tulip solver package so ConstraintSolverTest can construct a
# TulipConstraintSolver and exercise the LP-backed constraint layout.
using ProjecturedTulip
# Opt into the web backend package so WebTest can construct a WebBackend, decode
# client messages into its queue, and start its server.
using ProjecturedWeb
# The opt-in tests themselves now live in per-package test packages (their src
# moved down with the runtime they exercise). The umbrella `using`s them so its
# integration entry points (`test_all`, `test_documents`, `test_projections`)
# keep orchestrating the opt-in suites: test_dirty_rect / test_write_image (Sdl),
# test_constraint_solver (Tulip), test_record_video (Video), and the DB suites
# (Odbc) all resolve through these.
using ProjecturedSDLTest
using ProjecturedTulipTest
using ProjecturedVideoTest
using ProjecturedODBCTest
# The Ollama adapter's suite. It tests translation, so it needs no server; its
# one live test skips itself when none answers.
using ProjecturedAnthropicTest
using ProjecturedOllamaTest
# The suite of the ACP client. It talks to a fake agent in this process and to a
# small child process, so it needs no Node.js and no sign-in.
using ProjecturedACPTest
# The suite of the data frame view. It prints its views without a window.
using ProjecturedDataFramesTest
# A pivot of a data frame names two packages that do not depend on each other.
import DataFrames
import ProjecturedDataFrames
# The suites of the console, PDF and web backends and of the MCP server.
using ProjecturedConsoleTest
using ProjecturedPDFTest
using ProjecturedWebTest
using ProjecturedMCPTest
using ProjecturedAll: ElementReferenceStep, RangeReferenceStep, PositionReferenceStep,
       FieldReferenceStep, PointReferenceStep, TextSpanReferenceStep, ConcreteReference,
       EmptyReference, Reference, map_reference_forward, map_reference_backward, color_red,
       color_blue, color_green, color_white, color_default, color_solarized_background_dark,
       StyleFont

# Built lazily in __init__ (runtime, after the SDL extension has loaded) rather
# than as a precompile-time const, so precompilation doesn't depend on the extension.
function __init__()
    initialize_backend!(SdlBackend())
end

include("ExportCollisionTest.jl")
include("SearchScaleTest.jl")
include("SearchCorpusTest.jl")
include("CallSiteTest.jl")
include("SearchRankingTest.jl")
include("PackageGraphTest.jl")
include("FirstWindowTest.jl")
include("IntegrationLoadingTest.jl")
# The tree guard, which lives at the repository root rather than in a package:
# it reads directories and project files, and it has to run before the packages
# it describes exist. See `plan/done/repository-tree.md` §3.
include("../suite/tree.jl")
include("../suite/naming.jl")
include("../suite/arguments.jl")
include("../suite/exports.jl")
include("../suite/documentation.jl")
include("../suite/style.jl")
# Suites that rose from the domain test package when it dissolved: each
# fixture names several domains, so none of them belongs to one.
include("backend/AssistantConversationVideoTest.jl")
include("backend/BackendChoiceTest.jl")
include("document/SelectionEnumeration.jl")
include("document/PivotDataFrameTest.jl")
include("editor/ConstructTest.jl")
include("editor/ConversationPanelTest.jl")
include("editor/ConversationParsingTest.jl")
include("editor/ConversationSerializationTest.jl")
include("editor/AssistantMvpTest.jl")
include("editor/MessageLogFeedTest.jl")
include("editor/FrameStatisticsFeedTest.jl")
include("editor/AssistantDuplicateTest.jl")
include("editor/ApplicationTest.jl")
include("editor/HistorySweepTest.jl")
include("editor/InsertionInTabTest.jl")
include("projection/ToolViewTest.jl")
include("projection/FileTabTest.jl")
include("editor/UserInterfaceFileTest.jl")
include("editor/EvaluatorToplevelTest.jl")
include("editor/EvaluatorDuplicateTest.jl")
include("editor/ValueViewerTest.jl")
include("editor/ReferencedDocumentEditorTest.jl")
include("editor/GalleryWrapperTest.jl")
include("projection/CommandPaletteTest.jl")
include("projection/DocumentInsertionTest.jl")
include("projection/DraggingProjectionTest.jl")
include("projection/GestureHelpTest.jl")
include("projection/TextRangeSelectionTest.jl")
include("projection/TextClipboardTest.jl")
include("projection/GestureLogProjectionTest.jl")
include("projection/ConversationTranscriptTest.jl")
include("editor/McpSurfaceTest.jl")
include("projection/UndoRoundTripTest.jl")
include("projection/GestureMapTest.jl")
include("projection/ReferenceInspectorTest.jl")
include("projection/TextInkTest.jl")
include("projection/SyntaxTreeSelectionTest.jl")
include("projection/TableNavigationTest.jl")
include("projection/TableSelectionTest.jl")
include("projection/TableCellEditingTest.jl")
include("serializer/FileProjectTest.jl")
include("serializer/MarkerVocabularyTest.jl")
include("serializer/SerializationTest.jl")
include("editor/ExampleTest.jl")
include("editor/ExampleSweeps.jl")
include("editor/PrinterLocalityTest.jl")
include("editor/ReactivityTest.jl")
include("editor/RecursionContractTest.jl")
include("editor/MouseClickTest.jl")
include("projection/CatalogTest.jl")
include("projection/CatalogCoverageTest.jl")
include("projection/NaturalNotationTest.jl")
include("projection/NaturalRegistryTest.jl")

"""
    test_documents()

Umbrella-only document suites — the per-layer document tests now run inside
`test_kernel()` / `test_platform()` / `test_domain()`.
"""
function test_documents()
    @testset "Documents" begin
        test_constraint_solver()     # Tulip-backed LP constraint layout
        test_serialization()         # round-trips the ProjecturedExample fixtures
        test_pivot_data_frame()      # a pivot of a data frame, against DataFrames
    end
end

"""
    test_projections()

Umbrella-only projection suites (example/editor/SDL-coupled) — the per-layer
projection tests now run inside `test_platform()` / `test_domain()`.
"""
function test_projections()
    @testset "Projections" begin
        test_template_structural_locality()
        test_graphics_structural_locality()
        test_gesture_map()
        test_gesture_help()
        test_text_range_selection()
        test_text_clipboard()
        test_db_catalog_sql()
        test_widget_popup_example()
        test_tooltip()
        test_reference_inspector_text()
        test_text_ink_inside_viewports()
        test_split_pane_drag()
        test_dragging()
        test_write_image()
        test_record_video()
        test_assistant_conversation_video()
        test_dirty_rect()
        test_console_backend()
        test_write_pdf()
        test_web_backend()
        test_backend_choice()
    end
end

"""
    test_domain_examples()

Walk the printer over every concrete-domain example. The registry the sweep
walks (`domain_examples`) names factories from all twenty domain example
packages, so the sweep belongs here rather than in any one of them.
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

"""
    test_tree()

The repository tree guard: every top-level folder holds one kind of thing.
`plan/done/repository-tree.md` §3 states the rules and `test/suite/tree.jl`
is them. It loads nothing and reads directory entries, so it runs in well under
a second.
"""
function test_tree()
    @testset "repository tree" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in tree_violations(root)
            @test violation == ""
        end
        @test isempty(tree_violations(root))
    end
end

"""
    test_naming()

The naming guard: every mechanical rule of
`documentation/rule/naming-rules.md`, which `PAR-NAMING-LAW` makes an
invariant. It checks a module name against its file and its slice, an alias no
file declares, an abbreviation the rules ban, a test package's entry point, and
a definition two files of one module state twice.
It does not judge whether a verb fits the work or whether a name reads as
English — those need a person. It loads nothing and runs in well under a second.
"""
function test_naming()
    @testset "naming" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in naming_violations(root)
            @test violation == ""
        end
        @test isempty(naming_violations(root))
    end
end

"""
    test_arguments()

The argument guard: the clause on optional positional arguments of
`documentation/rule/code-quality-rules.md` §4. A public definition outside a port
fails when it takes more than one optional positional argument, or one beside
keyword arguments, unless a `# @optional:` marker says why. A `# @positional:`
marker fails too, because the count of positional arguments is advice. A call of
`get_evaluation_editor` fails anywhere but as the default of an `editor` keyword
(PAR-PER-EDITOR-STATE).

A private helper is out of scope for the optional clause. It loads nothing and
runs in about a second.
"""
function test_arguments()
    @testset "arguments" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in argument_violations(root)
            @test violation == ""
        end
        @test isempty(argument_violations(root))
        # A call of `get_evaluation_editor` stands only as the default of an
        # `editor` keyword: not in a body, not at a call, not for another keyword.
        mktempdir() do fixture
            mkpath(joinpath(fixture, "source"))
            write(joinpath(fixture, "source", "Verbs.jl"), """
                good_verb(x; editor = get_evaluation_editor()) = editor
                typed_verb(x; editor::Any = get_evaluation_editor()) = editor
                function body_read(x)
                    get_evaluation_editor()
                end
                call_site(x) = good_verb(x; editor = get_evaluation_editor())
                other_keyword(x; target = get_evaluation_editor()) = target
                """)
            @test find_evaluation_editor_reads(fixture) ==
                  ["source/Verbs.jl:4", "source/Verbs.jl:6", "source/Verbs.jl:7"]
        end
    end
end

"""
    test_exports()

The export guard: the rule of the export block of
`documentation/rule/code-quality-rules.md` §1. Each `*Module.jl` file under
`source/` has one `export` statement for each fragment, in the order of the
includes, with the names in the order that the fragment defines them, and no
comment inside the block. A module on the list in `test/suite/exports.jl` is
not migrated yet, and it fails when it follows the rule, so that the list stays
true. It loads nothing and runs in about a second.
"""
function test_exports()
    @testset "exports" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in export_violations(root)
            @test violation == ""
        end
        @test isempty(export_violations(root))
    end
end

"""
    test_style()

The style guard: a font, a color and a size come from a theme. A font
description, a color of numbers or of the palette, or a length with a number
outside a theme, a preset, the palette and the registry of font faces fails,
unless a `# @style:` marker says why it stands there. It loads nothing and runs
in about a second.
"""
function test_style()
    @testset "style" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in style_violations(root)
            @test violation == ""
        end
        @test isempty(style_violations(root))
    end
end

"""
    test_documentation()

The writing guard: the part of
`documentation/rule/writing-rules.md` that a program can check — a link whose
target is not there, a `resource://guide/…` that names no guide, a document
without its header line or its summary, a phrase the rules forbid, and a path
of the tree before the move.

It does not judge whether a sentence reads well or whether a claim is true —
those need a person. `documentation_report(root)` lists what a person must
read. It loads nothing and runs in about a second.
"""
function test_documentation()
    @testset "documentation" begin
        root = normpath(joinpath(@__DIR__, "..", ".."))
        for violation in documentation_violations(root)
            @test violation == ""
        end
        @test isempty(documentation_violations(root))
        # The report fails nothing: it names the sentences and the slices a
        # person must judge.
        report = documentation_report(root)
        isempty(report) ||
            println(stderr, "\n$(length(report)) line(s) of the documentation report; " *
                            "run `julia test/suite/documentation.jl` to read them")
    end
end

"""
    test_all()

The full suite: the static guards, the three engine test packages and the twenty
domain test packages, then [`test_integration`](@ref).
"""
function test_all()
    @testset "Projectured" begin
    # The static guards of the rules that a program can check.
    test_tree()
    test_naming()
    test_arguments()
    test_exports()
    test_documentation()
    test_style()
    # The per-package suites: the kernel unit tests, the platform's documents and
    # projections, every domain, and the layering guard of each package.
    test_kernel()
    test_platform()
    test_json()
    test_yaml()
    test_xml()
    test_markdown()
    test_rst()
    test_book()
    test_math()
    test_julia()
    test_sql()
    test_database()
    test_graph()
    test_chart()
    test_sequencechart()
    test_dbcatalog()
    test_formula()
    test_fsm()
    test_process()
    test_pivot()
    test_anthropic()
    test_ollama()
    test_acp()
    test_dataframes()
    test_integration()
    end
end

"""
    test_repository()

The tests of the umbrella that read this repository and not only its packages:
the package graph, from the `Project.toml` files under `package/`, and the
integrations that the umbrella loads, in new processes in `environment/all`. An installed
package has no repository, so the release test of `Projectured` leaves them out.
"""
function test_repository()
    @testset "repository" begin
        test_package_graph()
        test_umbrella_loads_integrations()
        test_integrations_load_with_extensions()
        test_packages_declare_triggers()
        test_essential_names()
    end
end

"""
    test_integration()

The umbrella's full-stack integration tests: the examples, the editor loop, the
SDL, Tulip and Video suites of the umbrella, and the checks that need no live
database. They need the packages and nothing of this repository, so the release
test of `Projectured` runs them. CI runs them in a job of its own, with
[`test_repository`](@ref).
"""
function test_integration()
    @testset "integration" begin
    # Every concrete-domain example through the printer.
    test_domain_examples()
    # PAR-QUALIFIED-EXTENSION's precondition, and cross-package by nature: no
    # name is exported by two modules with different bindings, so bare `using
    # ..XxxModule` can never become ambiguous. The per-package guards cannot
    # see this.
    test_export_collision_checker()
    test_export_collisions()
    # The corpus a search answers on when a window declares what it can draw:
    # thousands of names, with the questions a person asks of them.
    test_search_scale()
    test_search_corpus()
    test_call_site()
    test_search_ranking()
    # Umbrella integration: everything below needs the example registry, the
    # editor loop, or an opt-in backend package (Sdl/Tulip/Odbc/Video).
    test_documents()
    test_projections()
    # The generated atomic-example catalog: printer/reader/repl/position-navigation
    # over every discovered `domain/name/variant` pair, routed by terminal.
    test_catalog()
    # Is the catalog exhaustive? The printers are the list of what it owes.
    test_catalog_coverage()
    test_natural_renders_every_atom()
    test_natural_round_trips_every_atom()
    test_natural_notation()
    test_natural_registry()
    test_printers()
    test_readers()
    test_position_navigations()
    test_position_navigations_complete()
    test_repls()
    test_typeins()
    # Character-editing round trip over the generated text atoms (the tester the
    # catalog's default set omits); every text atom types cleanly under the default
    # text projection.
    test_catalog_typeins()
    test_mcp_tools()
    test_search_tools_registered()
    test_whole_surface_documentation()
    test_conversation_serialization()
    test_conversation_transcript()
    test_parse_markdown_blocks()
    test_document_insertion()
    # Every gesture that makes a recorded change is taken back, and the document
    # returns to the text it had.
    test_undo_round_trip()
    # The first window of a data frame compiles little in a fresh process.
    test_first_window_compiles_little()
    # Every gesture that changes no document leaves the history as it was.
    test_history_sweep()
    test_julia_typein()
    test_conversation_editor()
    test_assistant_mvp()
    test_assistant_duplicate()
    test_message_log_feed()
    test_frame_statistics_feed()
    test_application()
    test_insertion_in_tab()
    test_tool_views()
    test_selection_inspector()
    test_gesture_log_in_tab()
    test_message_log()
    test_file_tab()
    test_user_interface_file()
    test_evaluator_toplevel()
    test_evaluator_duplicate()
    test_value_viewer()
    test_referenced_document_editor()
    test_gallery_wrappers()
    test_mouse_clicks()
    test_click_roundtrips()
    test_text_navigation_invariants_all()
    test_json_content_clicks_clean_all()
    test_collapse_roundtrip()
    test_tree_navigations()
    test_tree_navigations_complete()
    test_table_navigation()
    test_table_cell_editing()
    test_odbc_database_no_db()
    end
end

"""
    test_table()

Narrow runner for the table selection + grid-navigation suites
(`test_table_selection` and `test_table_navigation`), and the editing inside a
cell (`test_table_cell_editing`).
"""
function test_table()
    @testset "Table" begin
        test_table_selection()
        test_table_navigation()
        test_table_cell_editing()
    end
end

export test_all, test_integration, test_repository, test_umbrella_loads_integrations, test_integrations_load_with_extensions,
       test_packages_declare_triggers, test_essential_names, test_documents, test_projections, test_domain_examples,
       test_package_graph, test_tree, test_naming,
       test_arguments, test_exports, test_documentation, test_style
export test_kernel, test_platform, test_domain
export test_first_window_compiles_little
export test_export_collisions, test_export_collision_checker, export_collisions
export test_search_scale, test_search_corpus, test_call_site, test_search_ranking
export test_type_reference, test_gesture_pattern, test_gesture_binding, test_focusing,
       test_console_backend, test_message_log_feed, test_frame_statistics_feed
export test_json_document, test_syntax, test_text, test_graphics, test_affine_transform, test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers, test_constraint_solver, test_collection, test_primitive, test_json_parser, test_xml_parser, test_sql_parser, test_serialization
export test_formula_to_syntax, test_projection_template_hygiene
export test_json_to_syntax, test_json_to_syntax_reader, test_json_gesture_collection, test_gesture_map, test_gesture_help, test_syntax_to_text, test_syntax_tree_selection, test_filesystem_to_syntax, test_primitive_to_text, test_text_to_graphics, test_word_wrapping, test_filtered_text_to_text, test_highlighted_text_to_text, test_selection_inverting, test_object_to_widget, test_find_bar_view_to_widget, test_widget_text_editing, test_widget_button_behavior, test_widget_gestures, test_widget_select_dropdown, test_widget_menu, test_widget_context_menu, test_widget_dialog, test_widget_action, test_widget_icon, test_widget_tree, test_widget_toolbar, test_widget_table, test_layout_closeout, test_widget_forms, test_widget_popup_example, test_copying_projection, test_clipboard, test_versioning_to_any, test_write_image, test_record_video, test_tooltip, test_reference_inspector_text, test_text_ink_inside_viewports, test_split_pane_drag, test_widget_transform_pane, test_dragging, test_anchor_point, test_write_pdf, test_dirty_rect, test_web_backend, test_backend_choice
export test_table, test_table_selection, test_table_navigation, test_table_cell_editing, explore_table_selections
export test_pivot_data_frame
export test_graph_projection, test_conversation_transcript, test_assistant_conversation_video
export test_examples, test_position_navigations, test_position_navigations_complete
export test_printer, test_printers, test_example, test_position_navigation
export measure_printer_locality, explore_selection_locality, test_selection_locality, test_selection_localities, LocalityReport, LocalityCell, is_selection_cell
export explore_structural_locality, report_structural_locality, test_template_structural_locality, test_graphics_structural_locality
export explore_value_locality, test_value_locality, test_value_localities
export explore_position_selections, collect_position_selections, collect_tree_selections, collect_json_tree_selections
export test_recursion_contract, test_recursion_contracts, walk_recursion_contract, walk_reference_roundtrip, probe_delegation
export test_reader, test_readers, walk_reader_events
export test_repl, test_repls, walk_repl_loop
export test_catalog, test_catalog_typeins
export test_catalog_coverage, get_catalog_coverage_gap
export test_natural_renders_every_atom, test_natural_round_trips_every_atom,
       test_natural_notation, test_natural_registry
export test_typein, test_typeins, walk_typein
export test_julia_typein
export test_mouse_click_roundtrip, test_mouse_clicks
export test_click_roundtrip, test_click_roundtrips, test_text_navigation_invariants, test_text_navigation_invariants_all, get_navigation_broken
export test_json_content_clicks_clean, test_json_content_clicks_clean_all
export test_collapse_roundtrip
export test_tree_navigation, test_tree_navigations, test_tree_navigations_complete, explore_tree_selections
export test_assistant_mvp, make_assistant_mvp_setup, make_assistant_mvp_projection
export test_conversation_editor, test_conversation_serialization, test_parse_markdown_blocks
export test_undo_round_trip
export test_application, test_history_sweep, test_insertion_in_tab,
       test_tool_views, test_selection_inspector, test_gesture_log_in_tab, test_message_log,
       test_file_tab, test_user_interface_file, test_evaluator_toplevel, test_evaluator_duplicate,
       test_value_viewer, test_referenced_document_editor,
       test_gallery_wrappers
export test_odbc_database_connection, test_odbc_database, test_odbc_database_no_db
export test_db_catalog, test_db_catalog_syntax, test_db_catalog_sql

# The suites that rose from the dissolved domain test package.
export test_json_construct, test_yaml_construct, test_xml_construct
export test_assistant_composer_panel, test_list_guides, test_read_guide
export test_list_modules, test_list_classes, test_list_functions
export test_read_module_documentation, test_read_class_documentation, test_read_function_documentation
export test_search_guides, test_search_api, test_search_tools_registered
export test_whole_surface_documentation
export test_pane_tab_b1, test_print_object_options, test_search_object
export test_execute_julia_code, test_assistant_editor_reference, test_function_availability
export test_base_extensions, test_mcp_resources, test_mcp_tools
export test_command_palette, test_command_palette_decorator, test_document_insertion
export test_gesture_log, test_file_project
export test_marker_vocabulary
