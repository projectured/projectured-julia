"""
    TaskModule

Tasks as `opp_repl` runs them: a piece of work that runs and ends with a result,
the codes a result takes, and the words a result is reported in. Nothing here
knows what the work is: a domain adds its kinds of task.
"""
module TaskModule

export AbstractTask, TaskResult, ResultCodes, RUN_RESULT_CODES, TEST_RESULT_CODES,
       UPDATE_RESULT_CODES, get_result_codes, get_result_role, is_expected,
       get_error_message, format_task_parameters, format_elapsed_time, PAST_TENSE,
       format_past_tense, format_task_result

include("TaskResult.jl")

end # module TaskModule
