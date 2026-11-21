# Fragment of `AssistantModule` — a command that an external agent runs in a
# terminal of the editor, as one part of its turn: the call of the agent, the task
# of the editor that runs the command, and the line that the agent wrote.

"""
    AgentCommand(call, task; command = "", fold = :default)

A command that an external agent runs in a terminal of the editor, as one part of
its turn. [`AgentCommandToWidget`](@ref) draws it as a short card: the title of
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
@document struct AgentCommand <: ConversationDocument
    call::EvaluatorForm
    task::Any
    command::String
    fold::Symbol
end

function AgentCommand(call::EvaluatorForm, task; command::AbstractString = "", fold::Symbol = :default)
    fold in (:default, :open, :folded) ||
        throw(ArgumentError(string("a fold is one of :default, :open and :folded, not :", fold)))
    task === nothing || task isa TaskDocument ||
        throw(ArgumentError(string("the task of a command is a TaskDocument or nothing, not ", typeof(task))))
    AgentCommand(call, task, String(command), fold)
end

# The line that the agent wrote for the call `form`, which the terminal `words`
# runs: the text input `command` of the call, as Claude Code gives its Bash tool,
# else the words of the terminal.
function _find_agent_command_line(form::EvaluatorForm, words::AbstractVector)
    line = get(form.input, "command", nothing)
    line isa AbstractString && !isempty(strip(line)) ? String(line) : join(words, " ")
end

# Whether the card of `command` shows its command under the title: not when the
# title is the command itself, because the agent gave no description.
_shows_agent_command_line(command::AgentCommand) =
    !isempty(strip(command.command)) && strip(get_evaluation_title(command.call)) != strip(command.command)
