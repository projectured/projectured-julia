# Fragment of `AssistantModule` — the wake: an assistant whose `wake` is on
# starts a turn of its own when a group of tasks that one of its turns started
# ends, with a note that says why.
#
# A group belongs to the turn during which it started: the group joined the list
# of the session after the start of the turn, and it still runs when the turn
# ends. A group that the turn waited for has ended by then, and wakes nothing. Two
# assistants whose turns run at the same time both see a group that started then;
# each wakes for it.

"""
    ASSISTANT_WAKE_LIMIT

How many turns an assistant starts on its own after one turn of the person:
three. A note that comes after the limit still shows, and starts no turn, so a
model that starts a run at each wake does not go on for ever.
"""
const ASSISTANT_WAKE_LIMIT = 3

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
    a.wake || return nothing
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
with a `:wake` note that names the group and sums it up, and start a turn with
it. A turn that runs reads the note in its next round, as a message that a
person typed during the turn.

The note shows and starts no turn when the person must keep the word: the
person stopped the last turn, the person is typing a message, or the assistant
already woke [`ASSISTANT_WAKE_LIMIT`](@ref) times since the last turn of the
person. An assistant whose `wake` is off does nothing.
"""
function wake_assistant!(editor, a::Assistant, group::TaskGroupDocument)
    a.wake || return nothing
    note = ConversationNote(_describe_task_group_end(group); kind = :wake)
    turn = _make_instant_turn(:user, [ConversationPart(note)])
    allowed = _is_wake_allowed(a)
    push!(a.conversation.turns, turn)
    allowed && _send_user_turn!(editor, a, turn)
    nothing
end

# What the note of a wake says: the title of the group and the line that sums
# it up.
_describe_task_group_end(group::TaskGroupDocument) =
    string("The task group \"", get_document_title(group), "\" ended: ",
           compute_task_group_summary(get_task_group(group)).summary, ".")

# Whether a wake may start a turn now.
function _is_wake_allowed(a::Assistant)
    _has_draft_text(a) && return false
    turns = collect(a.conversation.turns)
    # The turns since the last turn of the person.
    last_person = findlast(turn -> turn.role === :user && !is_note_turn(turn), turns)
    since = last_person === nothing ? turns : turns[(last_person + 1):end]
    # A stop of the person keeps the word with the person.
    any(turn -> turn.role === :assistant && turn.stop_reason === :cancelled, since) && return false
    count(turn -> is_note_turn(turn) && any(part -> part.content.kind === :wake, turn.parts), since) <
        ASSISTANT_WAKE_LIMIT
end

# Whether the person has typed into the composer of `a`.
_has_draft_text(a::Assistant) =
    any(part -> !isempty(strip(_text_to_string(part.content))), collect(a.draft.parts))
