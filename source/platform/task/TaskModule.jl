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

using ..AgentModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..FeedModule
using ..FocusModule
using ..GraphicsModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..PaneModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..ToolModule
using ..WidgetModule
import ..DocumentModule: copy_document, has_document_duplicate, get_document_title
import ..DomainModule: accepts_pasted_document
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..PaneModule: make_pane_tab_title
import ..ProjectionModule: print_document

export AbstractTask, TaskResult, ResultCodes, RUN_RESULT_CODES, TEST_RESULT_CODES,
       UPDATE_RESULT_CODES, get_result_codes, get_result_role, is_expected,
       get_error_message, format_task_parameters, format_elapsed_time, PAST_TENSE,
       format_past_tense, format_task_result, get_task_columns, format_task_column,
       get_task_actions, format_task_details
export TaskOutput, append_output_line!, get_left_out_line_count, collect_output_lines,
       find_last_output_line, format_output_text, TaskExecution, update_task_execution!,
       get_task_execution_snapshot, is_task_running, wait_task_execution,
       stop_task_execution!, get_task_status, finish_task_execution!, start_process_task!,
       sample_task_usage!
export TaskGroup, TaskStartFailure, get_default_job_count, start_task, is_concurrent,
       format_task_group_description, format_task_group_close_description,
       start_task_group!, stop_task_group!, wait_task_group, rerun_task_group!, run_task_group,
       collect_task_group_results, compute_task_group_indices, build_task_group_summary,
       measure_task_group_elapsed_time, measure_task_group_progress,
       TaskGroupResult, compute_task_group_result, format_task_group_summary,
       format_task_group_reason, TaskGroupSummary, compute_task_group_summary, summarize_results
export BuildStepTask, BuildCommandTask, BuildCopyTask, BuildRemoveTask, BuildStepResult,
       read_dependency_file,
       find_build_step_input_files, is_build_step_up_to_date
export TaskFeedStore, TaskFeed, get_session_task_feed_store, register_task_execution!,
       drain_task_feed!, has_task_feed_entries, make_task_feeds
export TaskDocument, start_task!, stop_task!, wait_task_document, reset_task_document!,
       write_task_snapshot!, record_task_result!
export TaskGroupList, get_session_task_group_list, add_task_group!, remove_task_group!,
       set_task_group_opener!, open_task_group_pane
export TaskGroupDocument, make_task_group_identifier, get_task_group, wrap_task_group_document,
       start_task_group_document!, rerun_task_group_document!, stop_task_group_document!,
       wait_task_group_document, select_task_document!, build_task_group_document_counts,
       measure_task_group_document_progress, get_task_group_document_status,
       find_task_group_document
export TaskTheme, ScaledTaskTheme, get_task_style, TaskGroupDocumentToWidgetPane,
       TaskGroupListToWidgetPane, make_task_group_tab_title, make_task_group_list_tab_title,
       format_memory_size, make_task_progress_bar, build_task_graphics_entry
export list_task_groups, find_task_group, describe_task_group, describe_task, get_task_output,
       wait_for_task_group!, stop_tasks!, rerun_tasks!, close_task_group!, make_task_api

include("TaskResult.jl")
include("TaskExecution.jl")
include("TaskGroup.jl")
include("BuildStep.jl")
include("TaskFeed.jl")
include("TaskDocument.jl")
include("TaskGroupList.jl")
include("TaskGroupDocument.jl")
include("TaskTheme.jl")
include("TaskGroupToWidget.jl")
include("TaskVerbs.jl")

end # module TaskModule
