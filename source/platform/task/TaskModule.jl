"""
    TaskModule

Tasks as `opp_repl` runs them: a piece of work that runs and ends with a result,
the codes a result takes, the words a result is reported in, and the execution of
a task that runs a process. Nothing here knows what the work is: a domain adds
its kinds of task.
"""
module TaskModule

export AbstractTask, TaskResult, ResultCodes, RUN_RESULT_CODES, TEST_RESULT_CODES,
       UPDATE_RESULT_CODES, get_result_codes, get_result_role, is_expected,
       get_error_message, format_task_parameters, format_elapsed_time, PAST_TENSE,
       format_past_tense, format_task_result
export TaskOutput, append_output_line!, get_left_out_line_count, collect_output_lines,
       find_last_output_line, format_output_text, TaskExecution, update_task_execution!,
       get_task_execution_snapshot, is_task_running, wait_task_execution,
       stop_task_execution!, get_task_status, finish_task_execution!, start_process_task!,
       sample_task_usage!

include("TaskResult.jl")
include("TaskExecution.jl")

end # module TaskModule
