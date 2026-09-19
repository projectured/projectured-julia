# Fragment of `MessageLogModule` — the feed that connects the store to the
# document. Producers write the store from any task; the editor moves the
# lines into the `MessageLog` once per frame, so no foreign task ever writes
# a cell of the log document.

"""
    MessageLogFeed(; store = get_session_message_log_store(),
                     log = get_session_message_log())

Register it when the editor is created —
`Editor(...; feeds = Feed[MessageLogFeed()])` — and install the capture with
[`install_message_log_capture!`](@ref). A log tab then shows what the
program says, one frame after it says it.
"""
struct MessageLogFeed <: Feed
    store::MessageLogStore
    log::MessageLog
end

MessageLogFeed(; store::MessageLogStore = get_session_message_log_store(),
                 log::MessageLog = get_session_message_log()) =
    MessageLogFeed(store, log)

function drain_changes!(feed::MessageLogFeed, editor)
    lines, dropped = take_message_lines!(feed.store)
    dropped > 0 &&
        record_message!(feed.log, "Warn",
                        "the log store dropped $(dropped) lines between frames")
    for (level, message) in lines
        record_message!(feed.log, level, message)
    end
    length(lines)
end

attach_wake_callback!(feed::MessageLogFeed, wake) =
    (attach_message_log_wake!(feed.store, wake); nothing)
