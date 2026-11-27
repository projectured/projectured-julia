# Fragment of `TaskModule` — one stream of one execution as a page: every line
# that the stream printed, read from its file, with a bar that finds a text, keeps
# the lines that hold a text, follows the end and goes to the first error.

# ── The lines of a file ──────────────────────────────────────────────────────

# Where each line of the file of a stream starts, read so far: `starts[k]` is the
# byte at which line `k` starts, and the last entry is the start of the line that
# has no end yet, so the file holds `length(starts) - 1` whole lines. `searches`
# keeps the lines that hold a text, with the count of lines that the search read.
mutable struct _TaskStreamIndex
    path::Union{String,Nothing}
    starts::Vector{Int}
    searches::Dict{String,Tuple{Int,Vector{Int}}}
end

_TaskStreamIndex() = _TaskStreamIndex(nothing, Int[0], Dict{String,Tuple{Int,Vector{Int}}}())

_get_line_count(index::_TaskStreamIndex) = length(index.starts) - 1

# Read the part of the file that came since the last read, and note where each
# new line starts. A file that is not there yet, or a stream with no file, has no
# line.
function _refresh_stream_index!(index::_TaskStreamIndex, path)
    if path != index.path
        index.path = path
        index.starts = Int[0]
        empty!(index.searches)
    end
    (path === nothing || !isfile(path)) && return index
    read_from = last(index.starts)
    filesize(path) > read_from || return index
    bytes = open(io -> (seek(io, read_from); read(io)), path)
    for (offset, byte) in enumerate(bytes)
        byte == UInt8('\n') && push!(index.starts, read_from + offset)
    end
    index
end

# The text of the lines `numbers`, in their order, read from the file.
function _read_stream_lines(index::_TaskStreamIndex, numbers)
    isempty(numbers) && return String[]
    open(index.path) do io
        texts = String[]
        for k in numbers
            seek(io, index.starts[k])
            push!(texts, chomp(String(read(io, index.starts[k + 1] - index.starts[k]))))
        end
        texts
    end
end

# The numbers of the lines that hold `text`, the first first. A search goes on
# from where the last search of the same text ended, so a stream that grows reads
# each line once.
function _search_stream_lines(index::_TaskStreamIndex, text::AbstractString)
    count = _get_line_count(index)
    (searched, found) = get(index.searches, text, (0, Int[]))
    if searched < count
        found = copy(found)
        open(index.path) do io
            seek(io, index.starts[searched + 1])
            for k in (searched + 1):count
                occursin(text, readline(io)) && push!(found, k)
            end
        end
        index.searches[String(text)] = (count, found)
    end
    found
end

# ── The lines around an offset ───────────────────────────────────────────────

# A stream page keeps no list of the lines of its file. A background source reads
# the lines around a byte offset, and stops at the size that the writer flushed
# (`TaskOutput.flushed_size`), which ends at the end of a line. So a read sees whole
# lines only. A line shows when it holds the text of the filter, or always when
# that text is empty.

# The most bytes of a line that a window keeps for the screen.
const _STREAM_LINE_LIMIT = 4096

# The bytes that a read before an offset takes at a time.
const _STREAM_BLOCK_SIZE = 65536

"""
    StreamWindow

The lines of the file of a stream around an offset, as
[`read_stream_window`](@ref) reads them.

- `offsets` and `texts` — the start and the text of each line that shows, the
  first first. A text longer than the screen keeps its first bytes.
- `steps` — for each line that shows, the count of the lines of the file from
  the first line that shows to it: `0` for the first. With a filter, it counts
  the lines that do not show too.
- `top` — the index in `offsets` of the line that the offset names: `1` when
  the window starts there. A window that holds the last lines can start before
  that line, and at the end of the file `top` is one past the last line.
- `before` and `before_steps` — the starts of the lines that show before the
  first, at most one window of them, the nearest first, and for each the count of
  the lines of the file from it to the first line that shows.
- `to_end` — when the window holds the last lines that show, the count of the
  lines of the file from the first line that shows to the end, that line
  included; else `-1`.
"""
struct StreamWindow
    offsets::Vector{Int}
    texts::Vector{String}
    steps::Vector{Int}
    top::Int
    before::Vector{Int}
    before_steps::Vector{Int}
    to_end::Int
end

const EMPTY_STREAM_WINDOW = StreamWindow(Int[], String[], Int[], 1, Int[], Int[], -1)

"""`true` when `window` holds the last lines that show."""
is_stream_window_at_end(window::StreamWindow) = window.to_end >= 0

# The text of a line for the screen: the line with no carriage return at its end,
# cut at the limit of the screen.
function _make_stream_line_text(line::String)
    line = endswith(line, '\r') ? String(chop(line)) : line
    ncodeunits(line) <= _STREAM_LINE_LIMIT && return line
    line[1:prevind(line, _STREAM_LINE_LIMIT + 1)] * "…"
end

_does_stream_line_show(line::AbstractString, filter::AbstractString) = isempty(filter) || occursin(filter, line)

# Visit each line from `offset`, the first first, up to `limit`:
# `visit(start, line)` gets the start of the line and its text with no line
# break, and answers `false` to stop.
function _visit_stream_lines_after(visit, io::IO, offset::Int, limit::Int)
    seek(io, offset)
    while position(io) < limit
        start = position(io)
        visit(start, readuntil(io, '\n')) || return
    end
end

# Visit each line before `offset`, which is the start of a line, the nearest first,
# with a read of blocks backward: `visit(start, stop)` gets the bytes from `start`
# to `stop` of the line, its line break included, and answers `false` to stop.
function _visit_stream_lines_before(visit, io::IO, offset::Int)
    line_end = offset
    # The byte before `offset` is the line break of the line before.
    unread = offset - 1
    while unread > 0
        first_byte = max(0, unread - _STREAM_BLOCK_SIZE)
        seek(io, first_byte)
        block = read(io, unread - first_byte)
        for i in length(block):-1:1
            block[i] == UInt8('\n') || continue
            start = first_byte + i
            visit(start, line_end) || return
            line_end = start
        end
        unread = first_byte
    end
    offset > 0 && visit(0, line_end)
    nothing
end

# The text of the line from `start` to `stop`, with no line break.
function _read_stream_line(io::IO, start::Int, stop::Int)
    seek(io, start)
    String(read(io, stop - start - 1))
end

# The start of the line at `offset` when a line starts there, else the start of
# the next line. A jump of the scroll bar can name any byte.
function _find_stream_line_start(io::IO, offset::Int, limit::Int)
    offset <= 0 && return 0
    offset >= limit && return limit
    seek(io, offset - 1)
    read(io, UInt8) == UInt8('\n') && return offset
    readuntil(io, '\n')
    min(position(io), limit)
end

# The starts of up to `count` lines that show before `offset`, the nearest first,
# with the count of the lines of the file from each to `offset`.
function _collect_stream_lines_before(io::IO, offset::Int, count::Int, filter::AbstractString)
    starts = Int[]
    steps = Int[]
    passed = 0
    count > 0 && _visit_stream_lines_before(io, offset) do start, stop
        passed += 1
        if isempty(filter) || _does_stream_line_show(_read_stream_line(io, start, stop), filter)
            push!(starts, start)
            push!(steps, passed)
        end
        length(starts) < count
    end
    (starts, steps)
end

"""
    read_stream_window(path, flushed, offset, count; filter = "", lead = 0) -> StreamWindow

The `count` lines that show from the line at `offset` in the file at `path`, of
which the first `flushed` bytes hold whole lines. A line shows when it holds
`filter`, or always for an empty `filter`.

- An `offset` inside a line names the next line.
- `lead` lines that show before that line come first, so the line shows that far
  below the top.
- When fewer than `count` lines show from there to the end, the window holds the
  last `count` lines that show. An `offset` at `flushed` gives the last lines.

The window also holds the starts of one window of lines that show before its
first, for a move up. It reads the file only around the lines it gives, and
the lines that it passes; a filter that few lines hold can pass many.
"""
function read_stream_window(path::AbstractString, flushed::Int, offset::Int, count::Int;
                            filter::AbstractString = "", lead::Int = 0)
    (flushed <= 0 || count <= 0 || !isfile(path)) && return EMPTY_STREAM_WINDOW
    open(path) do io
        start = _find_stream_line_start(io, offset, flushed)
        if lead > 0
            (leading, _) = _collect_stream_lines_before(io, start, lead, filter)
            isempty(leading) || (start = last(leading))
        end
        offsets = Int[]
        texts = String[]
        steps = Int[]
        passed = -1
        _visit_stream_lines_after(io, start, flushed) do line_start, line
            isempty(offsets) || (passed += 1)
            if _does_stream_line_show(line, filter)
                isempty(offsets) && (passed = 0)
                push!(offsets, line_start)
                push!(texts, _make_stream_line_text(line))
                push!(steps, passed)
            end
            length(offsets) < count
        end
        to_end = -1
        top = 1
        if length(offsets) < count || position(io) >= flushed
            (offsets, texts, steps, to_end) = _read_stream_last_lines(io, flushed, count, filter)
            top = something(findfirst(>=(start), offsets), length(offsets) + 1)
        end
        (before, before_steps) = isempty(offsets) ? (Int[], Int[]) :
                                 _collect_stream_lines_before(io, first(offsets), count, filter)
        StreamWindow(offsets, texts, steps, top, before, before_steps, to_end)
    end
end

# The last `count` lines that show, the first first, their steps from the first,
# and the count of the lines of the file from the first to the end.
function _read_stream_last_lines(io::IO, flushed::Int, count::Int, filter::AbstractString)
    starts = Int[]
    stops = Int[]
    positions = Int[]
    passed = 0
    _visit_stream_lines_before(io, flushed) do start, stop
        passed += 1
        if _does_stream_line_show(_read_stream_line(io, start, stop), filter)
            push!(starts, start)
            push!(stops, stop)
            push!(positions, passed)
        end
        length(starts) < count
    end
    isempty(starts) && return (Int[], String[], Int[], -1)
    reverse!(starts)
    reverse!(stops)
    reverse!(positions)
    texts = [_make_stream_line_text(_read_stream_line(io, start, stop)) for (start, stop) in zip(starts, stops)]
    to_end = first(positions)
    (starts, texts, [to_end - p for p in positions], to_end)
end

"""
    count_stream_lines(path, from, to; text = "", filter = "") -> Int

The count of the lines that start at a byte from `from` to before `to` in the
file at `path`, that hold `text` and that show under `filter`. An empty text and
an empty filter count every line. `from` and `to` are starts of lines, or `to` is
the flushed size.
"""
function count_stream_lines(path::AbstractString, from::Int, to::Int; text::AbstractString = "",
                            filter::AbstractString = "")
    (to <= from || !isfile(path)) && return 0
    open(path) do io
        seek(io, from)
        count = 0
        if isempty(text) && isempty(filter)
            remaining = to - from
            while remaining > 0
                block = read(io, min(remaining, _STREAM_BLOCK_SIZE))
                isempty(block) && break
                count += Base.count(==(UInt8('\n')), block)
                remaining -= length(block)
            end
        else
            _visit_stream_lines_after(io, from, to) do _, line
                (isempty(text) || occursin(text, line)) && _does_stream_line_show(line, filter) && (count += 1)
                true
            end
        end
        count
    end
end

"""
    find_stream_match(path, flushed, offset, text, step; filter = "") -> Int or nothing

The start of the next line after the line at `offset`, for `step = 1`, or of the
line before it, for `step = -1`, that holds `text` and shows under `filter`,
round from the end to the start. An `offset` of `-1` names no line: the first
match comes for `step = 1` and the last for `step = -1`. `nothing` when no line
holds `text`.
"""
function find_stream_match(path::AbstractString, flushed::Int, offset::Int, text::AbstractString, step::Int;
                           filter::AbstractString = "")
    (isempty(text) || flushed <= 0 || !isfile(path)) && return nothing
    holds(line) = occursin(text, line) && _does_stream_line_show(line, filter)
    open(path) do io
        found = nothing
        if step > 0
            from = offset < 0 ? 0 : (seek(io, offset); readuntil(io, '\n'); position(io))
            for (first_byte, last_byte) in ((from, flushed), (0, from))
                _visit_stream_lines_after(io, first_byte, last_byte) do start, line
                    holds(line) && (found = start)
                    found === nothing
                end
                found === nothing || break
            end
        else
            from = offset < 0 ? flushed : offset
            for (end_byte, floor) in ((from, 0), (flushed, from))
                _visit_stream_lines_before(io, end_byte) do start, stop
                    start < floor && return false
                    holds(_read_stream_line(io, start, stop)) && (found = start)
                    found === nothing
                end
                found === nothing || break
            end
        end
        found
    end
end

# ── The documents ────────────────────────────────────────────────────────────

"""
    TaskStreamLines(execution, field)

The lines of one stream of one execution as the stream page shows them, and the
state of that view.

- `execution` — a `Ref` to the shadow of the execution, from which the page reads
  the live lines of the stream: their count, their marks and their file. A
  `Ref`, so a walk and a copy of the documents do not go round through it.
- `field` — `:output` or `:error_output`.
- `top_row` — the place, among the lines that show, of the line at the top.
- `follow` — `true` while the page follows the end of a stream that grows.
- `find_text` — the text that Find looks for, and `found_line` the number of the
  line of the current match, or `0`.
- `filter_text` — the text that each line that shows holds, or empty for every
  line.
- `index` — where each line of the file starts, as the page read it so far.

All but the execution and the field is view state.

Use it to read the lines of one stream of an execution, and the state of the page that shows them.

# Example

    found_1 = search_documents(find_task_group("T3"), part -> part isa TaskStreamLines)

See also `TaskStream`, `TaskExecution` and `find_task_group`.

For the assistant.
"""
@document struct TaskStreamLines <: Document
    execution::Any
    field::Symbol
    top_row::Int = 1
    follow::Bool = true
    find_text::String = ""
    found_line::Int = 0
    filter_text::String = ""
    index::Any = _TaskStreamIndex()
end

"""
    TaskStream(name, bar, lines)

The page of one stream of one execution: `name`, `stdout` or `stderr`; `bar`, the
widgets that find a text, keep the lines that hold a text, follow the end, go to
the first error and open the file; and `lines`, the [`TaskStreamLines`](@ref) of
the stream. The shadow of each execution holds one for each of its streams
([`make_task_stream`](@ref)).

Use it to reach the page of the standard output or the standard error of an execution.

# Example

    found_1 = search_documents(find_task_group("T3"), part -> part isa TaskStream)

See also `TaskStreamLines`, `TaskExecution` and `find_task_group`.

For the assistant.
"""
@document struct TaskStream <: Document
    name::String
    bar::Any
    lines::Any
end

get_document_title(stream::TaskStream) = stream.name

"""
    make_task_stream(shadow, field) -> TaskStream

The page of the stream `field`, `:output` or `:error_output`, of the shadow of an
execution: its lines, and a bar of the text to find, the text that the lines that
show hold, the follow of the end, the first error and the file.
"""
function make_task_stream(shadow, field::Symbol)
    lines = TaskStreamLines(Ref{Any}(shadow), field)
    TaskStream(field === :output ? "stdout" : "stderr", _make_task_stream_bar(lines), lines)
end

# The bar of a stream page: each button answers an operation on the lines, so the
# readers carry it up as any answer.
function _make_task_stream_bar(lines::TaskStreamLines)
    button(text, make; tooltip = nothing) = WidgetButton(text; tooltip, gestures = GestureBinding[
        GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), (_, _, _) -> something(make(), DoNothingOperation());
                       description = text, domain = "stream")])
    matches = WidgetLabel(() -> _format_stream_matches(lines))
    WidgetCard(; title = "Find", collapsible = false,
               content = HorizontalLayout(Any[
                   ObjectField(lines, "find_text"),
                   button("‹", () -> make_task_stream_find_operation(lines, -1);
                          tooltip = TooltipNote(; title = "Previous match", text = "Go to the previous match.")),
                   button("›", () -> make_task_stream_find_operation(lines, 1);
                          tooltip = TooltipNote(; title = "Next match", text = "Go to the next match.")),
                   matches,
                   WidgetLabel("Only lines with"), ObjectField(lines, "filter_text"),
                   WidgetLabel("Follow the end"), ObjectField(lines, "follow"),
                   button("First error", () -> make_task_stream_first_error_operation(lines)),
                   button("Open as a file", () -> _make_stream_file_operation(lines))];
                   vertical_align = :center, gap = get_widget_style(nothing, :label_gap)))
end

# ── What the lines read ──────────────────────────────────────────────────────

"""
    get_task_stream_output(lines) -> TaskOutput

The bounded lines of the stream that `lines` shows, as the shadow of its
execution holds them now. A read in a cell follows each sync of the shadow.
"""
get_task_stream_output(lines::TaskStreamLines) = getproperty(lines.execution[], lines.field)

# The index of the file of the stream, read up to the lines that the shadow has
# counted so far. A read in a cell follows each sync of the shadow, which writes a
# new copy of the bounded lines when lines came.
function _refresh_task_stream!(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    _refresh_stream_index!(lines.index, output.path)
end

"""
    collect_task_stream_rows(lines) -> AbstractVector{Int}

The numbers of the lines that show: every line of the file, or the lines that
hold `filter_text`.
"""
function collect_task_stream_rows(lines::TaskStreamLines)
    index = _refresh_task_stream!(lines)
    isempty(lines.filter_text) ? (1:_get_line_count(index)) : _search_stream_lines(index, lines.filter_text)
end

"""
    find_task_stream_matches(lines) -> Vector{Int}

The numbers of the lines that show and that hold `find_text`; none for an empty
text.
"""
function find_task_stream_matches(lines::TaskStreamLines)
    isempty(lines.find_text) && return Int[]
    index = _refresh_task_stream!(lines)
    found = _search_stream_lines(index, lines.find_text)
    isempty(lines.filter_text) ? found : sort!(intersect(found, collect_task_stream_rows(lines)))
end

function _format_stream_matches(lines::TaskStreamLines)
    isempty(lines.find_text) && return ""
    matches = find_task_stream_matches(lines)
    isempty(matches) && return "no match"
    place = findfirst(==(lines.found_line), matches)
    place === nothing ? string(length(matches), " matches") : string(place, " of ", length(matches))
end

# ── The operations of the bar ────────────────────────────────────────────────

# Writes of the state of the view of `lines`, as view state.
_make_stream_view_operation(lines::TaskStreamLines, writes::Pair{String}...) =
    ReplaceViewStateOperation(CompoundOperation(Any[ReplaceReferencedValueOperation(lines, name, value)
                                                    for (name, value) in writes]))

# The row at the top that shows line `line` a few lines below the top.
function _get_top_row_for(lines::TaskStreamLines, line::Int)
    rows = collect_task_stream_rows(lines)
    place = something(findfirst(==(line), rows), 1)
    max(1, place - 3)
end

"""
    make_task_stream_find_operation(lines, step) -> Operation or nothing

The move to the next line that holds `find_text`, for `step = 1`, or to the one
before, for `step = -1`, after the current match, and round from the end to the
start. The page shows the line near its top and stops following the end.
`nothing` when no line that shows holds the text.
"""
function make_task_stream_find_operation(lines::TaskStreamLines, step::Int)
    matches = find_task_stream_matches(lines)
    isempty(matches) && return nothing
    current = lines.found_line
    place = step > 0 ? findfirst(>(current), matches) : findlast(<(current), matches)
    line = matches[something(place, step > 0 ? 1 : length(matches))]
    _make_stream_view_operation(lines, "found_line" => line, "top_row" => _get_top_row_for(lines, line),
                                "follow" => false)
end

"""
    make_task_stream_first_error_operation(lines) -> Operation or nothing

The move to the first line that the kind of the task marks as an error: every
line shows again, and the page shows the line near its top and stops following
the end. `nothing` when the stream has no error line.
"""
function make_task_stream_first_error_operation(lines::TaskStreamLines)
    line = get(get_task_stream_output(lines).first_mark_lines, :error, nothing)
    line === nothing && return nothing
    _make_stream_view_operation(lines, "filter_text" => "", "found_line" => line,
                                "top_row" => max(1, line - 3), "follow" => false)
end

# The open of the file of the stream in a tab, as any file opens.
function _make_stream_file_operation(lines::TaskStreamLines)
    path = get_task_stream_output(lines).path
    path === nothing ? nothing : OpenFileOperation(path)
end
