"""
    TaskModule

Tasks as `opp_repl` runs them: a piece of work that runs and ends with a result,
the codes a result takes, the words a result is reported in, the execution of a
task that runs a process, and a group of tasks that runs a number at a time. Its
documents show a task and a group on the screen, a feed carries what an
execution says into them, its panes draw a group and the groups of the
session, and its verbs read and act on the groups from the REPL and from a
model. Nothing here knows what the work is: a domain adds its kinds of task,
and says what a kind adds to the views.
"""
module TaskModule

using Base.ScopedValues: ScopedValue, with
using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..EventModule
using ..FeedModule
using ..FocusModule
using ..GestureBindingModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..StyleModule
using ..SystemProcessModule
using ..ToolModule
using ..TooltipModule
using ..TreeModule
using ..WidgetModule
import ..DocumentModule: copy_document, has_document_duplicate, get_document_title, sync_document!, is_walk_opaque,
                         is_field_walked
import ..RosterModule: collect_roster_parts, collect_roster_items, get_roster_item_type, get_item_facets,
                       compute_item_facet
import ..DomainModule: accepts_pasted_document, get_document_decoration, get_insertion_aliases,
                       make_insertion_document
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments, make_pred_document, is_pred_constructible
import ..NavigatorModule: find_navigator_address
import ..TreeModule: get_tree_children_steps, format_tree_node_label, is_explorer_entry_type

export AbstractTask, TaskResult, ResultCodes, RUN_RESULT_CODES, TEST_RESULT_CODES,
       UPDATE_RESULT_CODES, get_result_codes, get_result_role, is_expected,
       get_error_message, format_task_parameters, get_task_columns, format_task_column,
       get_task_actions, format_task_details, get_task_links, get_task_result_document,
       find_task_output_mark, get_task_output_folder,
       format_elapsed_time, PAST_TENSE, format_past_tense, format_task_result
export TaskOutput, append_output_line!, get_left_out_line_count, collect_output_lines,
       find_last_output_line, format_output_text, get_session_output_folder!,
       remove_task_output_files!, TaskRuntime, TaskExecution,
       update_task_execution!, get_task_execution_version, make_task_execution_shadow,
       describe_task_execution, is_task_running, wait_task_execution, stop_task_execution!,
       get_task_status, finish_task_execution!, TaskFinishFailure, start_process_task!,
       sample_task_usage!
export TaskStreamLines, TaskStream, make_task_stream, get_task_stream_output, collect_task_stream_rows,
       find_task_stream_matches, make_task_stream_find_operation, make_task_stream_first_error_operation
export ImitatedProcess, run_with_process_imitation
export get_default_job_count, start_task, TaskStartFailure, TaskNotStarted,
       TaskGroupSummary, TaskGroupTally, TaskGroupRuntime, TaskGroup, is_concurrent,
       format_task_group_description, format_task_group_close_description,
       compute_task_group_indices, start_task_group!, stop_task_group!, wait_task_group,
       rerun_task_group!, run_task_group, collect_task_group_results,
       measure_task_group_elapsed_time, build_task_group_summary,
       measure_task_group_progress, TaskGroupResult, compute_task_group_result,
       format_task_group_summary, format_task_group_reason, summarize_results,
       compute_task_group_summary, get_task_group_counts, make_task_group_shadow
export BuildStepTask, BuildCommandTask, BuildCopyTask, BuildRemoveTask, BuildStepResult,
       read_dependency_file, find_build_step_input_files, is_build_step_up_to_date
export TaskFeedStore, get_session_task_feed_store, register_task_execution!,
       record_task_execution_sync!, has_task_feed_entries, drain_task_feed!, TaskFeed,
       make_task_feeds
export TaskDocument, is_task_search_field, find_task_document_group, get_current_task_execution,
       get_task_document_status,
       get_task_document_result, collect_task_document_lines, start_task!,
       wait_task_document, stop_task!, reset_task_document!, add_task_execution!,
       get_earlier_task_executions
export TaskGroupDocument, make_task_group_identifier, get_task_group,
       get_task_group_document_summary, get_task_group_document_counts,
       wrap_task_group_document, find_task_group_document, get_task_group_preparation,
       describe_task_group_preparation, start_task_group_document!,
       rerun_task_group_document!, stop_task_group_document!, wait_task_group_document,
       select_task_document!, build_task_group_document_counts,
       measure_task_group_document_progress, get_task_group_document_status
export get_work_item_identifier, describe_work_item_kind, stop_work_item!, describe_work_item
export TaskGroupList, get_session_task_group_list, ClosedTaskGroup, collect_task_group_documents,
       collect_work_items, add_task_group!, remove_task_group!
export TaskTheme, ScaledTaskTheme
export TaskGroupDocumentToWidgetPane, make_task_progress_bar,
       make_task_group_tab_title, TaskGroupListToWidgetPane,
       make_task_group_list_tab_title, ClosedTaskGroupToWidgetPane, build_task_graphics_entry
export TaskDocumentToWidgetPane, TaskExecutionToWidgetPane, TaskStreamToWidget, TaskStreamLinesToWidget,
       TaskStreamLinesToWidgetIoMap
export list_task_groups, find_task_group, describe_task_group, describe_task,
       get_task_output, wait_for_task_group!, wait_for_tasks!, is_task_group_running, stop_tasks!,
       rerun_tasks!, close_task_group!, make_task_api

include("TaskResult.jl")
include("ImitatedProcess.jl")
include("TaskExecution.jl")
include("TaskStream.jl")
include("TaskGroup.jl")
include("BuildStep.jl")
include("TaskFeed.jl")
include("TaskDocument.jl")
include("TaskGroupDocument.jl")
include("TaskWorkItem.jl")
include("TaskGroupList.jl")
include("TaskTheme.jl")
include("TaskGroupToWidget.jl")
include("TaskPagesToWidget.jl")
include("TaskVerbs.jl")

end # module TaskModule
