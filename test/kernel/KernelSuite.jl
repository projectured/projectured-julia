"""
    test_kernel_layering()

Static layered-architecture guard for `ProjecturedKernel`: the top include list
must be a topological order over the real `import ..XxxModule` edges, every src
file reached exactly once, files under a declared layer folder may only
import from layers of index ≤ their own, cross-layer symbol imports may
name only exported symbols, and every interface file declares without
implementing (PAR-INTERFACE-DECLARES-ONLY).
"""
function test_kernel_layering()
    # `pkgdir` rejects the flat entryfile-at-root layout (main/ProjecturedKernel.jl
    # is not under a src/), so derive the package root from `pathof`.
    main = get_package_source_root(ProjecturedKernel)
    check_layering(main, pathof(ProjecturedKernel);
                   name = "kernel",
                   layers = ["fault", "performance", "cell", "struct", "clock", "event",
                             "device", "gesture", "backend",
                             "document", "reference", "selection", "operation", "intent",
                             "binding", "iomap", "projection", "tool", "llm", "agent",
                             "feed", "editor", "playback"],
                   check_private_imports = true,
                   # A layer's contract file, and its owning module.
                   interface_files = Dict(
                       "fault/FaultInterface.jl"     => :FaultModule,
                       "cell/CellInterface.jl"       => :CellModule,
                       "event/EventInterface.jl"     => :EventModule,
                       "document/DocumentInterface.jl" => :DocumentModule,
                       "reference/ReferenceInterface.jl" => :ReferenceModule,
                       "selection/SelectionInterface.jl"      => :SelectionModule,
                       "operation/OperationInterface.jl" => :OperationModule,
                       "backend/BackendInterface.jl" => :BackendModule,
                       "feed/FeedInterface.jl"       => :FeedModule,
                       "device/DeviceInterface.jl"   => :DeviceModule,
                       "llm/LlmInterface.jl"         => :LlmModule,
                       "agent/AgentInterface.jl"     => :AgentModule,
                       "binding/GestureBindingInterface.jl" => :GestureBindingModule,
                       "projection/ProjectionInterface.jl" => :ProjectionModule,
                       "iomap/IoMapInterface.jl"     => :IoMapModule))
end

"""
    test_kernel()

Run the whole kernel suite: the static layering guard, the `check_layering`
self-tests, and every kernel unit test.
"""
function test_kernel()
    @testset "ProjecturedKernel" begin
        test_kernel_layering()
        test_layering_checkers()
        test_fault_defaults()
        test_fault_record()
        test_fault_store()
        test_fault_cascade()
        test_fault_barrier()
        test_cell()
        test_cell_struct()
        test_cell_struct_plan()
        test_untracked_cell()
        test_cell_fault_scope()
        test_performance_counter()
        test_clock()
        test_printer_context_range()
        test_routed_change()
        test_introduced_path()
        test_projection_reference_step()
        test_projection_defaults()
        test_projection_macro()
        test_document_contract()
        test_document_macro()
        test_reference_builder()
        test_reference_evaluation()
        test_reference_rules()
        test_referenced_document()
        test_type_reference()
        test_selection()
        test_operations()
        test_rerooting()
        test_inversion()
        test_traversal()
        test_description()
        test_intent()
        test_event_module()
        test_gesture_module()
        test_gesture_recognition()
        test_gesture_pattern()
        test_device_module()
        test_gesture_binding()
        test_iomap_reconcile()
        test_iomap_defaults()
        test_headless_backend()
        test_escape_quit()
        test_editor_inbox()
        test_editor_frame_drain()
        test_editor_feeds()
        test_editor_wait()
        test_editor_timer()
        test_build_editor()
        test_editor_fault_barriers()
        test_editor_document_edits()
        test_frame_measurements()
        test_editor_frame_performance()
        test_playback()
        test_llm_defaults()
        test_agent_defaults()
        test_agent_loop()
        test_declared_api()
        test_search_query()
        test_meaning_search()
        test_relevance_search()
        test_search_answer()
        test_code_execution()
        test_docstring_summary()
        test_construct_oracle()
    end
end

export test_kernel, test_kernel_layering
# layering guard (shared by base/visual/domain test packages)
export check_layering, check_slice_edges, get_package_source_root, test_layering_checkers
# kernel unit suites
export test_fault_defaults, test_fault_record, test_fault_store,
       test_fault_cascade, test_fault_barrier,
       test_cell, test_cell_struct, test_cell_struct_plan, test_untracked_cell, test_cell_fault_scope, test_performance_counter, test_clock, test_printer_context_range,
       test_routed_change, test_introduced_path,
       test_projection_reference_step, test_projection_defaults, test_projection_macro,
       test_document_contract, test_document_macro,
       test_reference_builder, test_reference_evaluation, test_reference_rules, test_referenced_document,
       test_type_reference, test_selection,
       test_operations, test_rerooting,
       test_inversion, test_traversal, test_description, test_intent,
       test_event_module, test_gesture_module, test_gesture_recognition,
       test_gesture_pattern,
       test_device_module, test_gesture_binding,
       test_iomap_reconcile, test_iomap_defaults,
       test_headless_backend, test_llm_defaults, test_agent_defaults, test_agent_loop,
       test_declared_api, test_search_query, test_meaning_search, test_relevance_search,
       test_search_answer,
       test_code_execution,
       test_docstring_summary,
       test_editor_inbox, test_editor_frame_drain, test_editor_feeds,
       test_editor_wait, test_editor_timer, test_build_editor, test_frame_measurements,
       test_editor_frame_performance,
       test_editor_fault_barriers, test_editor_document_edits, test_playback
# generic drivers + walker internals reused by the higher test packages
export WalkStatus, _walk!, _WALK_MAX_DEPTH, _WALK_MAX_NODES,
       walk_printer_output, test_printer,
       _ALL_READER_EVENTS, walk_reader_events, test_reader,
       walk_repl_loop, test_repl,
       explore_selections, test_navigation, _assert_reaches_all,
       compare_content, test_construct_oracle
