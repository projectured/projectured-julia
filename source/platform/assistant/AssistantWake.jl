# Fragment of `AssistantModule` — the wake: an assistant starts a turn of its own
# when a group of tasks that one of its turns started ends, with a note that says
# why.
#
# A group belongs to the turn during which it started: the group joined the list
# of the session after the start of the turn, and it still runs when the turn
# ends. A group that the turn waited for has ended by then, and wakes nothing. Two
# assistants whose turns run at the same time both see a group that started then;
# each wakes for it.

"""
    ASSISTANT_WAKE_LIMIT

How many turns an assistant may start on its own after a message of the person
when the person allows no more: three. A message raises `wakes_left` of the
assistant to at least this count, and each wake takes one. A note that comes with
no wake left still shows, and starts no turn, so a model that starts a run at each
wake does not go on for ever.
"""
const ASSISTANT_WAKE_LIMIT = 3

# A message of the person gives the assistant at least the wakes that
# `ASSISTANT_WAKE_LIMIT` names, and never takes any away.
_raise_wakes_left!(a::Assistant) = (a.wakes_left = max(a.wakes_left, ASSISTANT_WAKE_LIMIT); nothing)

# Whether `turn` is a note that a held wake wrote.
_is_held_wake_turn(turn::ConversationTurn) =
    is_note_turn(turn) && all(part -> part.content.kind === :wake_held, turn.parts)

# The groups of the session of `editor` that started while `turn` ran and still
# run.
function _find_turn_task_groups(editor, turn::ConversationTurn)
    editor isa Editor || return TaskGroupDocument[]
    started = turn.start_time
    TaskGroupDocument[group for group in collect_task_group_documents(get_session_task_group_list(; editor))
                      if is_task_group_running(group) &&
                         something(get_task_group(group).start_time, -Inf) >= started]
end

# At the end of `turn`, watch each group that it started and that still runs:
# when the scheduler of the group ends, the assistant wakes on the task of the
# editor. A waiter task waits for the scheduler, so nothing holds the editor.
function _watch_turn_task_groups!(editor, a::Assistant, turn::ConversationTurn)
    for group in _find_turn_task_groups(editor, turn)
        scheduler = get_task_group(group).runtime.scheduler
        errormonitor(@async begin
            try
                wait(scheduler)
            catch exception
                exception isa TaskFailedException || rethrow()
            end
            try
                run_on_editor_task!(() -> wake_assistant!(editor, a, group), editor; wait = false,
                                    description = "the wake of the assistant")
            catch exception
                exception isa InvalidStateException || rethrow()
            end
        end)
    end
    nothing
end

"""
    wake_assistant!(editor, assistant, group) -> nothing

Tell `assistant` that the task group `group` ended: add a turn of the editor
with a note that names the group and sums it up, and start a turn with it, which
takes one of the `wakes_left` of the assistant. The note is a `:wake` note and
ends with the count that is left. A turn that runs reads the note in its next
round, as a message that a person typed during the turn.

The note shows, starts no turn and takes no wake when the person must keep the
word. It is a `:wake_held` note then, it says why in its last sentence, and its
button **Go on** starts a turn. The reasons, in this order: the person is typing
a message, the person stopped the group, the person stopped the last turn, and
the assistant has no wake left.
"""
function wake_assistant!(editor, a::Assistant, group::TaskGroupDocument)
    reason = _find_wake_hold_reason(a, group)
    description = _describe_task_group_end(group)
    if reason === nothing
        a.wakes_left -= 1
        note = ConversationNote(string(description, " Wakes left: ", a.wakes_left, "."); kind = :wake)
    else
        note = ConversationNote(string(description, " The assistant does not wake: ",
                                       _WAKE_HOLD_REASONS[reason], ".");
                                kind = :wake_held, action_label = "Go on",
                                action = editor -> send_go_on!(editor, a))
    end
    turn = _make_instant_turn(:user, [ConversationPart(note)])
    push!(a.conversation.turns, turn)
    reason === nothing && _send_user_turn!(editor, a, turn)
    nothing
end

# What the note of a wake says: the title of the group and the line that sums
# it up.
_describe_task_group_end(group::TaskGroupDocument) =
    string("The task group \"", get_document_title(group), "\" ended: ",
           compute_task_group_summary(get_task_group(group)).summary, ".")

# The end of the note of a held wake, by reason.
const _WAKE_HOLD_REASONS = (
    draft = "you have a message that you did not send",
    stopped_group = "a stop ended the group",
    stopped_turn = "you stopped the last turn",
    no_wakes_left = "it has no wakes left")

# The reason why a wake of `a` for `group` may not start a turn now, or `nothing`
# when it may.
function _find_wake_hold_reason(a::Assistant, group::TaskGroupDocument)
    _has_draft_text(a) && return :draft
    get_task_group(group).stopping && return :stopped_group
    _is_last_turn_stopped(a) && return :stopped_turn
    a.wakes_left > 0 || return :no_wakes_left
    nothing
end

# Whether the last turn of the assistant ended by a stop of the person, and the
# person did not write since.
function _is_last_turn_stopped(a::Assistant)
    turns = collect(a.conversation.turns)
    last_assistant = findlast(turn -> turn.role === :assistant, turns)
    last_assistant === nothing && return false
    turns[last_assistant].stop_reason === :cancelled &&
        !any(turn -> turn.role === :user && !is_note_turn(turn), turns[(last_assistant + 1):end])
end

# Whether the person has typed into the composer of `a`.
_has_draft_text(a::Assistant) =
    any(part -> !isempty(strip(_text_to_string(part.content))), collect(a.draft.parts))
