# Fragment of `AssistantModule` — a command that an external agent runs in a
# terminal of the editor, as one part of its turn: the call of the agent, the task
# of the editor that runs the command, and the line that the agent wrote.

"""
    AgentTerminalCommand(call, task; command = "", fold = :default)

A command that an external agent runs in a terminal of the editor, as one part of
its turn. [`AgentTerminalCommandToWidget`](@ref) draws it as a short card: the title of
the call, the state of the task and its row, the command, and the last lines of
its output.

- `call` is the `EvaluatorForm` of the tool call, which the updates of the call
  keep filling: its header ([`get_evaluation_title`](@ref)) is the title of the
  command, and its `output` is the text that the call answered.
- `task` is the `TaskDocument` that runs the command, a row of the task list, or
  `nothing` for a command that a file gave.
- `command` is the line that the agent wrote, such as `ls -l`, with no shell
  around it.
- `fold` is the choice of a person, as the `fold` of a `ConversationPart`:
  `:default` follows the rule of the transcript, `:open` and `:folded` do not.

A file keeps the call, the command and the fold, and not the task, which is a
process of this session. A command that a file gave shows the last lines of the
text that its call answered in place of the output of its task.
"""
@document struct AgentTerminalCommand <: ConversationDocument
    call::EvaluatorForm
    task::Any
    command::String
    fold::Symbol
end

function AgentTerminalCommand(call::EvaluatorForm, task; command::AbstractString = "", fold::Symbol = :default)
    fold in (:default, :open, :folded) ||
        throw(ArgumentError(string("a fold is one of :default, :open and :folded, not :", fold)))
    task === nothing || task isa TaskDocument ||
        throw(ArgumentError(string("the task of a command is a TaskDocument or nothing, not ", typeof(task))))
    AgentTerminalCommand(call, task, String(command), fold)
end

# A file writes the call, the command and the fold that a person chose; the task
# is a process of this session.
function pred_arguments(command::AgentTerminalCommand)
    keywords = Pair{Symbol,Any}[:call => command.call, :command => command.command]
    command.fold === :default || push!(keywords, :fold => command.fold)
    (), keywords
end

function make_pred_document(::Type{<:AgentTerminalCommand}, positional, keywords)
    values = Dict{Symbol,Any}(keywords)
    AgentTerminalCommand(values[:call], nothing; command = get(values, :command, ""), fold = get(values, :fold, :default))
end

# A command is a tool call of its turn: the work line counts it, and it ends the
# work.
is_conversation_tool_call(::AgentTerminalCommand) = true

# The tree names a command by the header of its call, and marks it as its task:
# its state and the time it took. A command that a file gave is a terminal.
format_tree_node_label(command::AgentTerminalCommand) = get_evaluation_title(command.call)

get_document_decoration(command::AgentTerminalCommand) =
    command.task isa TaskDocument ? get_document_decoration(command.task) : DocumentDecoration(; icon = :terminal)

# The line that the agent wrote for the call `form`, which the terminal `words`
# runs: the text input `command` of the call, as Claude Code gives its Bash tool,
# else the words of the terminal.
function _find_terminal_command_line(form::EvaluatorForm, words::AbstractVector)
    line = get(form.input, "command", nothing)
    line isa AbstractString && !isempty(strip(line)) ? String(line) : join(words, " ")
end

# Whether the card of `command` shows its command under the title: not when the
# title is the command itself, because the agent gave no description.
_shows_terminal_command_line(command::AgentTerminalCommand) =
    !isempty(strip(command.command)) && strip(get_evaluation_title(command.call)) != strip(command.command)

# What a command did, for the text of a conversation: the result of its task, the
# time it took and the name of its row, such as `DONE 0.8 s T5`, or the text that
# its call answered for a command that a file gave.
function _describe_terminal_command_result(command::AgentTerminalCommand)
    task = command.task
    task isa TaskDocument || return command.call.output
    result = get_task_document_result(task)
    words = String[result === nothing ? String(get_task_document_status(task)) : result.result,
                   _format_terminal_command_time(task), get_work_item_identifier(task)]
    join(filter(!isempty, words), " ")
end
