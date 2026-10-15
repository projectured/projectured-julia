# The documents of the task slice, each made from one build step that has not run,
# so a test makes them with no process.

# A build step that runs `true` in the current folder.
_make_example_build_step() =
    BuildCommandTask(; action = "Compiling", subject = "hello.c", working_directory = ".",
                     arguments = ["true"], input_files = String[], output_files = String[])

# A task that has not started.
make_task_document_example() = TaskDocument(_make_example_build_step())

# A group of one task that has not started.
make_task_group_document_example() =
    wrap_task_group_document(TaskGroup([_make_example_build_step()]; name = "builds", jobs = 1))

# The list of the groups of a session, with no group.
make_task_group_list_document_example() = TaskGroupList()

# The shadow of an execution that has not started, which the pages of an execution
# print.
make_task_execution_document_example() =
    make_task_execution_shadow(TaskExecution(_make_example_build_step()))

# The page of the output stream of that execution.
make_task_stream_document_example() =
    make_task_stream(make_task_execution_document_example(), :output)

# The lines of the output stream of that execution.
make_task_stream_lines_document_example() =
    TaskStreamLines(Ref{Any}(make_task_execution_document_example()), :output)
