# Fragment of `MessageLogModule`.
#
# The Julia logger that captures `@info`, `@warn` and `@error` into a
# [`MessageLog`](MessageLogDocument.jl).
#
# `Base.CoreLogging` is the module the `Logging` stdlib itself re-exports, so
# extending its generics here needs no dependency on that stdlib — the four
# methods below are the same generic functions a `Logging.AbstractLogger`
# implements.
#
# `MessageLogLogger` wraps the logger it replaces and is transparent to it:
# every decision (`min_enabled_level`, `shouldlog`, `catch_exceptions`) defers
# to the wrapped logger, so installing this one changes nothing about what
# shows in the terminal. `handle_message` is the one method that does more: it
# records the message and then forwards the call, so the terminal still shows
# what it showed before the capture was installed.
"""
    MessageLogLogger(store, previous)

A logger that records `(string(level), string(message))` into `store` — the
producer-side [`MessageLogStore`](@ref), never the log document, because a
logger runs on whatever task logs and only the editor task may write a
document — and then forwards every message to `previous`, the logger it
replaced. The [`MessageLogFeed`](@ref) is what moves the lines on.
"""
struct MessageLogLogger <: Base.CoreLogging.AbstractLogger
    store::MessageLogStore
    previous::Base.CoreLogging.AbstractLogger
end

Base.CoreLogging.min_enabled_level(logger::MessageLogLogger) =
    Base.CoreLogging.min_enabled_level(logger.previous)

Base.CoreLogging.shouldlog(logger::MessageLogLogger, level, _module, group, id) =
    Base.CoreLogging.shouldlog(logger.previous, level, _module, group, id)

Base.CoreLogging.catch_exceptions(logger::MessageLogLogger) =
    Base.CoreLogging.catch_exceptions(logger.previous)

function Base.CoreLogging.handle_message(logger::MessageLogLogger, level, message, _module,
                                         group, id, file, line; kwargs...)
    record_message!(logger.store, string(level), string(message))
    Base.CoreLogging.handle_message(logger.previous, level, message, _module, group, id, file, line;
                                    kwargs...)
end

# ── Install and remove ───────────────────────────────────────────────────────

"""
    install_message_log_capture!(store = get_session_message_log_store()) -> Base.CoreLogging.AbstractLogger

Install a `MessageLogLogger` over `store` as the global logger, and answer
the logger it replaced. Register a [`MessageLogFeed`](@ref) over the same
store on the editor, or the captured lines stay in the store.

Do not install twice. Each install wraps the current logger, so two installs
would record every message twice. This is safe to call twice: when the current
global logger is already a `MessageLogLogger`, it is answered unchanged and
nothing is wrapped again.
"""
function install_message_log_capture!(store::MessageLogStore = get_session_message_log_store())
    current = Base.CoreLogging.global_logger()
    current isa MessageLogLogger && return current
    Base.CoreLogging.global_logger(MessageLogLogger(store, current))
    current
end

"""
    remove_message_log_capture!(previous) -> Base.CoreLogging.AbstractLogger

Put `previous` back as the global logger. `previous` is the logger that
`install_message_log_capture!` answered.
"""
function remove_message_log_capture!(previous::Base.CoreLogging.AbstractLogger)
    Base.CoreLogging.global_logger(previous)
    previous
end

# ── The message log of a window, as a wrapper of `build_editor` ──────────────

"""
    message_log = true

The wrapper of `build_editor` that fills the message log of the session with
what the program logs while the window is open. A start step installs the
capture of the Julia logger, which records each message and passes it on, so the
terminal still shows it; a [`MessageLogFeed`](@ref) moves the lines into the log;
and a stop step puts the logger that the capture replaced back when the loop of
the editor ends. It is off by default.
"""
function wrap_editor!(::Val{:message_log}, layer::Symbol, argument, parts::EditorParts)
    push!(parts.feeds, MessageLogFeed())
    replaced = Ref{Union{Nothing,Base.CoreLogging.AbstractLogger}}(nothing)
    push!(parts.start_steps, _ -> (replaced[] = install_message_log_capture!(); nothing))
    push!(parts.stop_steps, _ -> (replaced[] === nothing || remove_message_log_capture!(replaced[]);
                                  nothing))
    parts
end

get_wrapper_layers(::Val{:message_log}) = (:screen => 10,)
