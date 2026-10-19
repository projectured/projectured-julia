# Fragment of `BackgroundWorkModule` — the feed. The kernel records each work of a
# background cell in the `BackgroundWorkStore` of the editor for free; this feed
# copies the records into the log, at a bounded rate, and only while a view shows
# the log.

"""
    BackgroundWorkFeed(; log = nothing, flush_interval = 0.25, now = time)

The feed that fills the log of the background work: with no `log`, the log of the
session of its editor ([`get_session_background_work_log`](@ref)). The wrapper
`background_work = true` of `build_editor` gives it to an editor.

The log is due when the count of changes of the store differs from the count that
the log showed, and something shows the log: a view that reads its rows, such as
its page or its row in a tree. A due log is copied at most once in each
`flush_interval`, by the clock `now`, and the feed answers that interval as its
deadline while the log is due, so the loop wakes for it. The feed never wakes the
editor otherwise: a record changes only in a frame. An editor whose log no view
shows keeps its records in the store and copies nothing.
"""
mutable struct BackgroundWorkFeed <: Feed
    log::Union{Nothing,BackgroundWorkLog}
    flush_interval::Float64
    now::Function
    flushed_at::Float64
end

BackgroundWorkFeed(; log::Union{Nothing,BackgroundWorkLog} = nothing, flush_interval::Real = 0.25,
                     now::Function = time) =
    BackgroundWorkFeed(log, Float64(flush_interval), now, -Inf)

_get_feed_log(feed::BackgroundWorkFeed, editor) = something(feed.log, get_session_background_work_log(; editor))

_is_background_work_log_due(log::BackgroundWorkLog, store::BackgroundWorkStore) =
    log.change_count != store.change_count && has_dependent_cells(getfield(log, :rows))

function drain_changes!(feed::BackgroundWorkFeed, editor)
    log = _get_feed_log(feed, editor)
    store = get_background_work_store(editor)
    (_is_background_work_log_due(log, store) && feed.now() - feed.flushed_at >= feed.flush_interval) || return 0
    feed.flushed_at = feed.now()
    flush_background_work_log!(log, store)
end

compute_wake_deadline(feed::BackgroundWorkFeed, editor) =
    _is_background_work_log_due(_get_feed_log(feed, editor), get_background_work_store(editor)) ?
        feed.flush_interval : nothing

"""
    background_work = true

The wrapper of `build_editor` that gives the editor a
[`BackgroundWorkFeed`](@ref), so the log of the background work of the session
follows the works of the editor. It is off by default.
"""
function wrap_editor!(::Val{:background_work}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, BackgroundWorkFeed())
    parts
end

get_wrapper_layers(::Val{:background_work}) = (:screen => 20,)
