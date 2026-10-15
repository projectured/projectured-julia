# Fragment of `SystemProcessModule` — the page of one process: its facts, a line
# each, and the buttons that interrupt it and stop it. Each line reads only the
# cells of its facts, so a sample that changes the load draws one line again.

"""
    SystemProcessToWidget(; gap)

Prints a [`SystemProcess`](@ref) as its page: the process id and the command,
the folder, the state, the start and the time since it, the processor load, the
memory and the threads, and two buttons. Interrupt sends `SIGINT` and Stop
sends `SIGTERM`, each only to the process that the page shows
([`interrupt_system_process!`](@ref), [`stop_system_process!`](@ref)). The time
since the start reads the time of the last sample, so the page reads no clock.
"""
@projection UntrackedCell struct SystemProcessToWidget
    gap::Int = get_widget_style(nothing, :label_gap)
end

function print_document(p::SystemProcessToWidget, recursion, process::SystemProcess, context)
    interrupt = WidgetButton("Interrupt"; action = _ -> (interrupt_system_process!(process); nothing))
    stop = WidgetButton("Stop"; action = _ -> (stop_system_process!(process); nothing))
    root = VerticalLayout(Any[
        WidgetLabel(() -> string(process.process_id, "  ", process.command)),
        WidgetLabel(() -> "folder " * (isempty(process.folder) ? "unknown" : process.folder)),
        WidgetLabel(() -> "state " * replace(String(process.state), "_" => " ")),
        WidgetLabel(() -> _format_process_times(process)),
        WidgetLabel(() -> string("processor ", _format_processor_load(process.processor_load),
                                 " · memory ", format_memory_size(process.memory),
                                 " · threads ", process.thread_count)),
        HorizontalLayout(Any[interrupt, stop]; vertical_align = :center, gap = p.gap)]; gap = p.gap)
    iomap = ChildrenIoMap(p, process, root, Cell(Any[]))
    # The part under the pointer, so a button lights and takes a press.
    follow_output_mouse_target!(root, () ->
        map_mouse_target_forward(process, path -> map_reference_forward(p, iomap, path)))
    iomap
end

# The start of a process and the time from it to the last sample: `started
# 2026-10-15 18:40:01 · elapsed 1:05`.
function _format_process_times(process::SystemProcess)
    started = "started " * Libc.strftime("%Y-%m-%d %H:%M:%S", process.start_time)
    elapsed = _compute_elapsed_time(process)
    elapsed === nothing ? started : started * " · elapsed " * _format_duration(elapsed)
end

# A duration as a page writes it: `42 s` under a minute, then `12:05` and `1:02:05`.
function _format_duration(seconds::Real)
    total = floor(Int, seconds)
    total < 60 && return string(total, " s")
    hours, rest = divrem(total, 3600)
    minutes, rest = divrem(rest, 60)
    hours == 0 ? string(minutes, ":", lpad(rest, 2, '0')) :
                 string(hours, ":", lpad(minutes, 2, '0'), ":", lpad(rest, 2, '0'))
end

# A process draws as its page, inside any document that a renderer draws, with a
# widget renderer of its own, so a press reaches its buttons.
make_graphics_projection(::Type{SystemProcess}; measure, appearance) =
    ChainingProjection(
        SystemProcessToWidget(; gap = get_widget_style(get_scaled_theme!(appearance, WidgetTheme), :label_gap)),
        RecursiveProjection(FaultCatchingProjection(
            inner = WidgetToGraphics(; measure, theme = get_scaled_theme!(appearance, WidgetTheme),
                                     graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)),
            substitute = FaultToGraphics())))
