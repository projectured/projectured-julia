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
    button(text, make) = WidgetButton(text; gestures = GestureBinding[
        GestureBinding(MouseClickPattern(:left; modifiers = Symbol[]), (_, _) -> something(make(), DoNothingOperation());
                       description = text, domain = "stream")])
    matches = WidgetLabel(() -> _format_stream_matches(lines))
    WidgetCard(; title = WidgetLabel("Find"), collapsible = false,
               content = HorizontalLayout(Any[
                   ObjectField(lines, "find_text"),
                   button("‹", () -> make_task_stream_find_operation(lines, -1)),
                   button("›", () -> make_task_stream_find_operation(lines, 1)),
                   matches,
                   WidgetLabel("Only lines with"), ObjectField(lines, "filter_text"),
                   WidgetLabel("Follow the end"), ObjectField(lines, "follow"),
                   button("First error", () -> make_task_stream_first_error_operation(lines)),
                   button("Open as a file", () -> _make_stream_file_operation(lines))];
                   vertical_align = :center, gap = get_task_style(nothing, :inline_gap)))
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
