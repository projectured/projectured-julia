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
    MessageLogLogger(log, previous)

A logger that records `(string(level), string(message))` into `log` and then
forwards every message to `previous`, the logger it replaced.
"""
struct MessageLogLogger <: Base.CoreLogging.AbstractLogger
    log::MessageLog
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
    record_message!(logger.log, string(level), string(message))
    Base.CoreLogging.handle_message(logger.previous, level, message, _module, group, id, file, line;
                                    kwargs...)
end

# ── Install and remove ───────────────────────────────────────────────────────

"""
    install_message_log_capture!(log = get_session_message_log()) -> Base.CoreLogging.AbstractLogger

Install a `MessageLogLogger` over `log` as the global logger, and answer the
logger it replaced.

Do not install twice. Each install wraps the current logger, so two installs
would record every message twice. This is safe to call twice: when the current
global logger is already a `MessageLogLogger`, it is answered unchanged and
nothing is wrapped again.
"""
function install_message_log_capture!(log::MessageLog = get_session_message_log())
    current = Base.CoreLogging.global_logger()
    current isa MessageLogLogger && return current
    Base.CoreLogging.global_logger(MessageLogLogger(log, current))
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
