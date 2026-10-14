# Fragment of `MessageLogModule` — the feed that connects the store to the
# document. Producers write the store from any task; the editor copies the
# lines into its `MessageLog` once per frame, so no foreign task ever writes
# a cell of the log document.

"""
    MessageLogFeed(; store = get_session_message_log_store(), log = nothing)

Register it when the editor is created —
`Editor(...; feeds = Feed[MessageLogFeed()])` — and install the capture with
[`install_message_log_capture!`](@ref). A log tab then shows what the
program says, one frame after it says it.

The feed copies each line of `store` into `log`, or with no `log` into the log of
the session of its editor ([`get_session_message_log`](@ref)), so each editor has
its own log, and two editors that read one store each get every line. A caller
that registers the feed itself detaches its wake when the loop of the editor
ends ([`detach_message_log_wake!`](@ref)); the wrapper `message_log = true` does.
"""
mutable struct MessageLogFeed <: Feed
    store::MessageLogStore
    log::Union{Nothing,MessageLog}
    # The number of the next line of the store to copy.
    next::Int
end

MessageLogFeed(; store::MessageLogStore = get_session_message_log_store(),
                 log::Union{Nothing,MessageLog} = nothing) =
    MessageLogFeed(store, log, 1)

function drain_changes!(feed::MessageLogFeed, editor)
    lines, next, missed = read_message_lines(feed.store, feed.next)
    feed.next = next
    (isempty(lines) && missed == 0) && return 0
    log = something(feed.log, get_session_message_log(; editor))
    missed > 0 &&
        record_message!(log, "Warn",
                        "the log store dropped $(missed) lines between frames")
    for (level, message) in lines
        record_message!(log, level, message)
    end
    length(lines)
end

attach_wake_callback!(feed::MessageLogFeed, wake) =
    (attach_message_log_wake!(feed.store, feed, wake); nothing)
