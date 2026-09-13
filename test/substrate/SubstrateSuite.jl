"""
Files migrated to `PAR-QUALIFIED-EXTENSION`: bare `using ..Xxx`, and any
extension of a sibling's generic written `Xxx.f(…) = …`. Opt-in and growing, the
same ledger the kernel keeps. See
`plan/pending/qualified-extension-sweep.md`. When it covers every file of a
package the entry can go, and when it covers every package so can the parameter.
"""
const _QUALIFIED_FILES = Dict(
    "ProjecturedCollection"    => Set(["CollectionDocument.jl"]),
    "ProjecturedComponent"     => Set(["ComponentDocument.jl"]),
    "ProjecturedDomain"        => Set(["DocumentCore.jl"]),
    "ProjecturedDragging"      => Set(["DraggingDocument.jl"]),
    "ProjecturedFileFormat"    => Set(["NaturalFormat.jl"]),
    "ProjecturedFileSystem"    => Set(["FileSystemDocument.jl"]),
    "ProjecturedGestureHelp"   => Set(["GestureMap.jl"]),
    "ProjecturedLayout"        => Set(["LayoutDocument.jl"]),
    "ProjecturedFocus"         => Set(["Focus.jl"]),
    "ProjecturedInspector"     => Set(["ReferenceInspector.jl"]),
    "ProjecturedNatural"       => Set(["NaturalNotation.jl"]),
    "ProjecturedPlot"          => Set(["PlotGeometry.jl"]),
    "ProjecturedPrimitive"     => Set(["PrimitiveDocument.jl"]),
    "ProjecturedReflection"    => Set(["BoundedSync.jl"]),
    "ProjecturedSerialization" => Set(["BinarySerialization.jl"]),
    "ProjecturedStyle"         => Set(["Color.jl"]),
    "ProjecturedTooltip"       => Set(["TooltipDocument.jl"]))

"""
    test_substrate_layering()

The static layered-architecture guard of every substrate package (see
`ProjecturedKernelTest.check_layering`). Each package is one concept and
declares no layer index, so the check is the topological include order of its
own entry file plus the file inventory of its own folder.
"""
function test_substrate_layering()
    for pkg in _SOURCES
        pkg === ProjecturedKernel && continue
        main = get_package_source_root(pkg)
        name = String(nameof(pkg))
        check_layering(main, pathof(pkg); name = name,
                       qualified_files = get(_QUALIFIED_FILES, name, Set{String}()))
    end
end

"""
    test_substrate()

Run the whole substrate suite: the layering guard of every package, every unit
test, and the printer walk over the tier's own examples.
"""
function test_substrate()
    @testset "ProjecturedSubstrate" begin
        test_substrate_layering()
        test_substrate_examples()
        test_collection()
        test_document_walk()
        test_bounded_sync()
        test_document_reflection()
        test_copying_projection()
        test_focusing()
        test_reversing()
        test_filtering()
        test_searching()
        test_sorting()
        test_switching()
        test_window_input_unwrapping()
        test_versioning_to_any()
        test_file_project()
        test_marker_language()
        # documents
        test_point_reference()
        test_syntax()
        test_text()
        test_graphics()
        test_affine_transform()
        test_font_metrics()
        test_graphics_layout()
        test_layout_allocator()
        test_layout_constraint_helpers()
        test_primitive()
        test_pane_surgery()
        test_pane_geometry()
        # text / graphics projections
        test_projection_template_hygiene()
        test_projection_template_fixed_children()
        test_plot_geometry()
        test_syntax_to_text()
        test_primitive_to_text()
        test_text_to_graphics()
        test_word_wrapping()
        test_text_filtering()
        test_text_highlighting()
        test_selection_inverting()
        # widget projections
        test_object_to_widget()
        test_object_field_to_widget()
        test_object_field_to_syntax()
        test_reflection_to_widget()
        test_projection_configuring()
        test_cell_table_to_widget_table()
        test_widget_text_editing()
        test_widget_button_behavior()
        test_widget_gestures()
        test_widget_select_dropdown()
        test_widget_menu()
        test_widget_context_menu()
        test_widget_dialog()
        test_widget_action()
        test_widget_icon()
        test_widget_tree()
        test_widget_toolbar()
        test_widget_table()
        test_frozen_table_headers()
        test_widget_lazy_table()
        test_widget_tab_strip()
        test_widget_split_pane()
        test_pane_to_widget()
        test_pane_reader()
        test_pane_gestures()
        test_pane_drag()
        test_pane_rename()
        test_pane_construct()
        test_widget_transform_pane()
        test_layout_closeout()
        test_widget_forms()
        test_anchor_point()
        test_anchored_layout()
        # interaction decorators
        test_clipboard()
        test_tooltip()
        test_split_pane_drag()
        test_scroll_pane_hover()
        test_widget_popup_example()
        # generic drivers over visual examples
        test_collapse_roundtrip()

    end
end

"""
    test_substrate_examples()

Walk the printer over every substrate example (`substrate_examples`) — one
`@test` per forced reactive cell, through the generic `test_printer` driver.
"""
function test_substrate_examples()
    @testset "SubstrateExamples" begin
        for ex in substrate_examples
            @testset "$(ex.name)" begin
                test_printer(ex)
            end
        end
    end
end

export test_substrate, test_substrate_layering, test_substrate_examples
export test_bounded_sync, test_document_reflection
export test_collection, test_copying_projection, test_focusing, test_reversing, test_filtering, test_searching, test_sorting
export test_switching, test_window_input_unwrapping
export test_versioning_to_any
export test_file_project, test_marker_language
export _text_leaf_length, _walk_document, collect_position_selections, collect_tree_selections
export test_point_reference
export test_syntax, test_text, test_graphics, test_affine_transform, test_font_metrics,
       test_graphics_layout, test_layout_allocator, test_layout_constraint_helpers,
       test_primitive, test_pane_surgery, test_pane_geometry, test_pane_to_widget,
       test_pane_reader, test_pane_gestures, test_pane_drag,
       test_pane_rename, test_pane_construct
export test_projection_template_hygiene, test_projection_template_fixed_children
export test_plot_geometry,
       test_syntax_to_text, test_primitive_to_text, test_text_to_graphics,
       test_word_wrapping, test_text_filtering, test_text_highlighting,
       test_selection_inverting
export test_reflection_to_widget
export test_object_field_to_widget, test_object_field_to_syntax
export test_object_to_widget, test_projection_configuring,
       test_widget_text_editing, test_widget_button_behavior, test_widget_gestures,
       test_widget_select_dropdown, test_widget_menu, test_widget_context_menu,
       test_widget_dialog, test_widget_action, test_widget_icon, test_widget_tree,
       test_widget_toolbar, test_widget_table, test_frozen_table_headers, test_widget_lazy_table, test_widget_tab_strip, test_widget_split_pane, test_widget_transform_pane,
       test_layout_closeout, test_widget_forms, test_anchor_point, test_anchored_layout
export test_clipboard, test_tooltip, test_split_pane_drag, test_scroll_pane_hover,
       test_widget_popup_example, test_collapse_roundtrip
export POSITION_NAVIGATION_KEYS, POSITION_SEED_GESTURE, TREE_NAVIGATION_KEYS, TREE_SEED_GESTURE,
       explore_position_selections, test_position_navigation,
       explore_tree_selections, test_tree_navigation
export walk_typein, test_typein
export test_click_roundtrip, test_text_navigation_invariants,
       _find_text_iomap, _find_cursor_rect, _pipeline_measure, _segment_x_at,
       _path_contains_projection_reference
