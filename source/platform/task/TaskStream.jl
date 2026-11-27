# Fragment of `TaskModule` — one stream of one execution as a page: every line
# that the stream printed, read from its file, with a bar that finds a text, keeps
# the lines that hold a text, follows the end and goes to the first error. The page
# keeps a byte offset into the file, and background cells read the lines around it,
# so no print and no reader of the page reads the file.

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
- `top` — the index in `offsets` of the line at the top: the line that the
  offset names, or with a lead the line that many lines that show above it. It is
  `1` when the window starts there. A window that holds the last lines can start
  before that line, and at the end of the file `top` is one past the last line.
- `before` and `before_steps` — the starts of the lines that show before the
  first, at most one window of them, the nearest first, and for each the count of
  the lines of the file from it to the first line that shows.
- `to_end` — when the window holds the last lines that show, the count of the
  lines of the file from the first line that shows to the end, that line
  included; else `-1`.
- `number` — the number of the first line that shows, when the read knows it: a
  read from the start of the file counts the lines before it, and a read of the
  last lines knows it from the count of the lines of the file. Else `0`.
"""
struct StreamWindow
    offsets::Vector{Int}
    texts::Vector{String}
    steps::Vector{Int}
    top::Int
    before::Vector{Int}
    before_steps::Vector{Int}
    to_end::Int
    number::Int
end

const EMPTY_STREAM_WINDOW = StreamWindow(Int[], String[], Int[], 1, Int[], Int[], -1, 0)

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
    # A file that is shorter than `limit`, such as a file that a person saved, ends
    # the visit at its end.
    while position(io) < limit && !eof(io)
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
function _compute_stream_line_start(io::IO, offset::Int, limit::Int)
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
    read_stream_window(path, flushed, offset, count; filter = "", lead = 0, flushed_count = -1) -> StreamWindow

The `count` lines that show from the line at `offset` in the file at `path`, of
which the first `flushed` bytes hold whole lines. A line shows when it holds
`filter`, or always for an empty `filter`.

- An `offset` inside a line names the next line.
- `lead` lines that show before that line come first, so the line shows that far
  below the top.
- When fewer than `count` lines show from there to the end, the window holds the
  last `count` lines that show. An `offset` at `flushed` gives the last lines.
- `flushed_count`, the count of the lines in the flushed bytes, gives the number
  of the first line of a window of the last lines.

The window also holds the starts of one window of lines that show before its
first, for a move up. It reads the file only around the lines it gives, and
the lines that it passes; a filter that few lines hold can pass many.
"""
function read_stream_window(path::AbstractString, flushed::Int, offset::Int, count::Int;
                            filter::AbstractString = "", lead::Int = 0, flushed_count::Int = -1)
    (flushed <= 0 || count <= 0 || !isfile(path)) && return EMPTY_STREAM_WINDOW
    open(path) do io
        start = _compute_stream_line_start(io, offset, flushed)
        if lead > 0
            (leading, _) = _collect_stream_lines_before(io, start, lead, filter)
            isempty(leading) || (start = last(leading))
        end
        offsets = Int[]
        texts = String[]
        steps = Int[]
        skipped = 0
        passed = 0
        _visit_stream_lines_after(io, start, flushed) do line_start, line
            shows = _does_stream_line_show(line, filter)
            if isempty(offsets)
                shows || (skipped += 1; return true)
            else
                passed += 1
            end
            if shows
                push!(offsets, line_start)
                push!(texts, _make_stream_line_text(line))
                push!(steps, passed)
            end
            length(offsets) < count
        end
        to_end = -1
        top = 1
        number = start == 0 && !isempty(offsets) ? skipped + 1 : 0
        if length(offsets) < count || position(io) >= flushed
            (offsets, texts, steps, to_end) = _read_stream_last_lines(io, flushed, count, filter)
            top = something(findfirst(>=(start), offsets), length(offsets) + 1)
            number = to_end >= 0 && flushed_count >= 0 ? flushed_count - to_end + 1 : 0
        end
        (before, before_steps) = isempty(offsets) ? (Int[], Int[]) :
                                 _collect_stream_lines_before(io, first(offsets), count, filter)
        StreamWindow(offsets, texts, steps, top, before, before_steps, to_end, number)
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
    open(path) do io
        if step > 0
            from = offset < 0 ? 0 : _compute_stream_next_line_start(io, offset)
            found = _find_stream_match_after(io, from, flushed, text, filter)
            found === nothing ? _find_stream_match_after(io, 0, from, text, filter) : found
        else
            from = offset < 0 ? flushed : offset
            found = _find_stream_match_before(io, from, 0, text, filter)
            found === nothing ? _find_stream_match_before(io, flushed, from, text, filter) : found
        end
    end
end

# The start of the line after the line at `offset`.
function _compute_stream_next_line_start(io::IO, offset::Int)
    seek(io, offset)
    readuntil(io, '\n')
    position(io)
end

_does_stream_line_match(line::AbstractString, text::AbstractString, filter::AbstractString) =
    (isempty(text) || occursin(text, line)) && _does_stream_line_show(line, filter)

# The start of the first line from `from` to before `to` that holds `text` and
# shows under `filter`, or `nothing`.
function _find_stream_match_after(io::IO, from::Int, to::Int, text::AbstractString, filter::AbstractString)
    found = nothing
    _visit_stream_lines_after(io, from, to) do start, line
        _does_stream_line_match(line, text, filter) && (found = start)
        found === nothing
    end
    found
end

# The start of the nearest line before `offset`, and not before `floor`, that holds
# `text` and shows under `filter`, or `nothing`.
function _find_stream_match_before(io::IO, offset::Int, floor::Int, text::AbstractString, filter::AbstractString)
    found = nothing
    _visit_stream_lines_before(io, offset) do start, stop
        start < floor && return false
        _does_stream_line_match(_read_stream_line(io, start, stop), text, filter) && (found = start)
        found === nothing
    end
    found
end

# The count of the lines from `from` to before `to` that hold `text` and show under
# `filter`, with the starts of the first and the last of them, or `nothing`.
function _count_stream_matches(path::AbstractString, from::Int, to::Int, text::AbstractString,
                               filter::AbstractString)
    count = 0
    first_match = nothing
    last_match = nothing
    (to > from && isfile(path)) && open(path) do io
        _visit_stream_lines_after(io, from, to) do start, line
            if _does_stream_line_match(line, text, filter)
                count += 1
                first_match === nothing && (first_match = start)
                last_match = start
            end
            true
        end
    end
    (count, first_match, last_match)
end

# ── The background reads of a stream ─────────────────────────────────────────

# The lines that a window of a stream reads: more than any screen shows, so that the
# page shows a part of them and the wheel moves inside them.
const _STREAM_WINDOW_SIZE = 200

# The largest file whose lines the page counts: its scroll bar measures lines, and a
# jump goes to a line. A larger file has a scroll bar that measures bytes.
const _STREAM_COUNTED_SIZE = 32_000_000

"""`true` when the scroll bar of a stream whose file holds `flushed` bytes measures lines."""
is_stream_counted(flushed::Int) = flushed <= _STREAM_COUNTED_SIZE

"""
    StreamSearch

What a search of the file of a stream found, as the page shows it:

- `shown` — the count of the lines that hold the text of the filter, or `-1`
  with no filter;
- `count` — the count of the lines that show and hold the text of Find;
- `place` — the place of the current match among them, or `0` when the page
  has no current match;
- `next` and `previous` — the start of the match after the current one and of
  the match before it, round from the end to the start, or `nothing` with no
  match.
"""
struct StreamSearch
    shown::Int
    count::Int
    place::Int
    next::Union{Int,Nothing}
    previous::Union{Int,Nothing}
end

const EMPTY_STREAM_SEARCH = StreamSearch(-1, 0, 0, nothing, nothing)

# The answer of the number cell: the start of the line, its number, its place among
# the lines that show under the filter (`0` for a file whose lines the page does not
# count), and that filter.
const EMPTY_STREAM_NUMBER = (-1, 0, 0, "")

# The most entries that a memory of a stream keeps in each of its tables.
const _STREAM_MEMORY_SIZE = 8

# Store `value` at `key` of `table`, which keeps a few entries: a full table starts
# again empty.
function _store_stream_entry!(table::AbstractDict, key, value)
    length(table) >= _STREAM_MEMORY_SIZE && !haskey(table, key) && empty!(table)
    table[key] = value
    value
end

# What a count found in the bytes from the start to `read_to`: the count of the lines
# that matched, and the starts of the first and the last of them.
struct _StreamCount
    read_to::Int
    count::Int
    first::Union{Int,Nothing}
    last::Union{Int,Nothing}
end

# For a current match at `found`: the start of the next match in the bytes from it
# to `read_to`, or `nothing`, and the start of the match before it, or `nothing`.
struct _StreamMove
    found::Int
    read_to::Int
    next::Union{Int,Nothing}
    previous::Union{Int,Nothing}
end

# What the searches of a stream found so far, for each text and filter. A file only
# grows at its end, so what a search found in the bytes that it read stays true, and
# a later search reads only the bytes that came:
# - `counts`, the counts of the matches;
# - `places`, the last match whose place a search counted, and that place, so the
#   next count of a place starts there;
# - `moves`, the next match and the match before, for the current match.
# Two batches of one source can run at the same time, so a search holds the lock.
mutable struct _StreamSearchMemory
    const lock::ReentrantLock
    path::Union{String,Nothing}
    counts::Dict{Tuple{String,String},_StreamCount}
    places::Dict{Tuple{String,String},Tuple{Int,Int}}
    moves::Dict{Tuple{String,String},_StreamMove}
end

_StreamSearchMemory() = _StreamSearchMemory(ReentrantLock(), nothing, Dict{Tuple{String,String},_StreamCount}(),
                                            Dict{Tuple{String,String},Tuple{Int,Int}}(),
                                            Dict{Tuple{String,String},_StreamMove}())

# The numbers of the lines that a count found, by the start of the line and the
# filter: the number and the place among the lines that show. A file only grows at
# its end, so a number stays true, and a later count starts at the nearest of them.
mutable struct _StreamNumberMemory
    const lock::ReentrantLock
    path::Union{String,Nothing}
    numbers::Dict{Tuple{Int,String},Tuple{Int,Int}}
end

_StreamNumberMemory() = _StreamNumberMemory(ReentrantLock(), nothing, Dict{Tuple{Int,String},Tuple{Int,Int}}())

# Empty the tables of `memory` when it gets the file of another stream.
function _forget_other_stream!(memory, path::String)
    memory.path == path && return memory
    memory.path = path
    for name in fieldnames(typeof(memory))
        table = getfield(memory, name)
        table isa AbstractDict && empty!(table)
    end
    memory
end

function _count_stream_matches_so_far!(memory::_StreamSearchMemory, path::String, flushed::Int, text::String,
                                       filter::String)
    total = get(memory.counts, (text, filter), _StreamCount(0, 0, nothing, nothing))
    total.read_to >= flushed && return total
    (count, first_match, last_match) = _count_stream_matches(path, total.read_to, flushed, text, filter)
    total = _StreamCount(flushed, total.count + count, something(total.first, first_match, Some(nothing)),
                         something(last_match, total.last, Some(nothing)))
    _store_stream_entry!(memory.counts, (text, filter), total)
end

# One input of a source of a stream, by its first element:
# - `(:window, path, flushed, flushed_count, offset, place, filter, lead)`;
# - `(:number, path, flushed, flushed_count, offset, known_offset, known_line, filter)`;
# - `(:search, path, flushed, find, filter, found)`.
# A stream with no file, or whose file is gone, gets the empty answer.
function _answer_stream_input(memory, input)
    kind = first(input)
    path = input[2]
    if path === nothing || !isfile(path)
        return kind === :window ? EMPTY_STREAM_WINDOW : kind === :number ? EMPTY_STREAM_NUMBER : EMPTY_STREAM_SEARCH
    end
    if kind === :window
        (_, _, flushed, flushed_count, offset, place, filter, lead) = input
        place > 0 || return read_stream_window(path, flushed, offset, _STREAM_WINDOW_SIZE; filter, lead, flushed_count)
        (offset, line) = _compute_stream_place(path, flushed, place, filter)
        window = read_stream_window(path, flushed, offset, _STREAM_WINDOW_SIZE; filter, flushed_count)
        _make_stream_window_with_number(window, offset, line)
    elseif kind === :number
        (_, _, flushed, flushed_count, offset, known_offset, known_line, filter) = input
        lock(memory.lock) do
            _count_stream_line_number!(memory, path, flushed, flushed_count, offset, known_offset, known_line, filter)
        end
    else
        (_, _, flushed, find, filter, found) = input
        lock(() -> _search_stream!(memory, path, flushed, find, filter, found), memory.lock)
    end
end

# The start and the number of the line that shows at `place`: a count from the
# start, for a file whose lines the page counts.
function _compute_stream_place(path, flushed, place, filter)
    found = 0
    number = 0
    line_number = 0
    seen = 0
    open(path) do io
        _visit_stream_lines_after(io, 0, flushed) do start, line
            line_number += 1
            _does_stream_line_show(line, filter) || return true
            seen += 1
            found = start
            number = line_number
            seen < place
        end
    end
    (found, number)
end

# The window with the number of its first line, from the number of the line at
# `offset`, when the window holds that line and has no number of its own.
function _make_stream_window_with_number(window::StreamWindow, offset::Int, line::Int)
    window.number > 0 && return window
    k = findfirst(==(offset), window.offsets)
    k === nothing && return window
    StreamWindow(window.offsets, window.texts, window.steps, window.top, window.before, window.before_steps,
                 window.to_end, line - window.steps[k])
end

# The number of the line at `offset` and its place among the lines that show, as
# `EMPTY_STREAM_NUMBER` holds them. A count starts at the nearest line whose number
# is known: the start, the end, the known place of the page, or a line that an
# earlier count numbered.
function _count_stream_line_number!(memory::_StreamNumberMemory, path, flushed, flushed_count, offset,
                                    known_offset, known_line, filter)
    _forget_other_stream!(memory, path)
    known = get(memory.numbers, (offset, filter), nothing)
    known === nothing || return (offset, first(known), last(known), filter)
    places = [(0, 1), (flushed, flushed_count + 1)]
    known_line > 0 && known_offset <= flushed && push!(places, (known_offset, known_line))
    for ((start, _), (number, _)) in memory.numbers
        push!(places, (start, number))
    end
    (from, number) = argmin(place -> abs(first(place) - offset), places)
    line = from <= offset ? number + count_stream_lines(path, from, offset) :
           number - count_stream_lines(path, offset, from)
    place = !is_stream_counted(flushed) ? 0 : isempty(filter) ? line :
            count_stream_lines(path, 0, offset; filter) + 1
    _store_stream_entry!(memory.numbers, (offset, filter), (line, place))
    (offset, line, place, filter)
end

function _search_stream!(memory::_StreamSearchMemory, path, flushed, find, filter, found)
    _forget_other_stream!(memory, path)
    shown = isempty(filter) ? -1 : _count_stream_matches_so_far!(memory, path, flushed, "", filter).count
    isempty(find) && return StreamSearch(shown, 0, 0, nothing, nothing)
    total = _count_stream_matches_so_far!(memory, path, flushed, find, filter)
    total.count == 0 && return StreamSearch(shown, 0, 0, nothing, nothing)
    place = _count_stream_match_place!(memory, path, flushed, find, filter, found, total.count)
    (next, previous) = _find_stream_neighbours!(memory, path, flushed, find, filter, found, total)
    StreamSearch(shown, total.count, place, next, previous)
end

# The place of the match at `found` among the `count` matches, or `0` when `found`
# names no line that holds the text. The count of the matches before it starts at
# the nearest place where that count is known: the start, the end, or the last
# match whose place a search counted.
function _count_stream_match_place!(memory, path, flushed, find, filter, found, count)
    (found < 0 || found >= flushed) && return 0
    line = open(io -> (seek(io, found); readuntil(io, '\n')), path)
    _does_stream_line_match(line, find, filter) || return 0
    key = (find, filter)
    places = [(0, 0), (flushed, count)]
    haskey(memory.places, key) && push!(places, memory.places[key])
    (from, before) = argmin(place -> abs(first(place) - found), places)
    before_found = from <= found ? before + count_stream_lines(path, from, found; text = find, filter) :
                   before - count_stream_lines(path, found, from; text = find, filter)
    _store_stream_entry!(memory.places, key, (found, before_found))
    before_found + 1
end

# The next match after `found` and the match before it, round from the end to the
# start. The match before stays what the first search found, and the next is
# searched only in the bytes that came since, until one is found.
function _find_stream_neighbours!(memory, path, flushed, find, filter, found, total::_StreamCount)
    found < 0 && return (total.first, total.last)
    key = (find, filter)
    move = get(memory.moves, key, nothing)
    open(path) do io
        if move === nothing || move.found != found
            previous = _find_stream_match_before(io, found, 0, find, filter)
            move = _StreamMove(found, _compute_stream_next_line_start(io, found), nothing, previous)
        end
        if move.next === nothing && move.read_to < flushed
            move = _StreamMove(found, flushed, _find_stream_match_after(io, move.read_to, flushed, find, filter),
                               move.previous)
        end
    end
    _store_stream_entry!(memory.moves, key, move)
    (something(move.next, total.first), something(move.previous, total.last))
end

# The three sources of the reads of one stream: the window, the numbers of its lines
# and the search, each with its own batch, so a long count or search never holds a
# window back.
function _make_stream_sources()
    numbers = _StreamNumberMemory()
    searches = _StreamSearchMemory()
    (window = BackgroundSource(inputs -> Any[_answer_stream_input(nothing, input) for input in inputs];
                               description = "the lines of a stream"),
     number = BackgroundSource(inputs -> Any[_answer_stream_input(numbers, input) for input in inputs];
                               description = "the numbers of the lines of a stream"),
     search = BackgroundSource(inputs -> Any[_answer_stream_input(searches, input) for input in inputs];
                               description = "the search of a stream"))
end

# ── The documents ────────────────────────────────────────────────────────────

"""
    TaskStreamLines(; execution, field, window, number, search)

The lines of one stream of one execution as the stream page shows them, and the
state of that view. The page keeps no list of the lines: it keeps a byte offset
in the file of the stream, and its background cells read the lines around it.

- `execution` — a `Ref` to the shadow of the execution, from which the page reads
  the live lines of the stream: their count, their marks and their file. A
  `Ref`, so a walk and a copy of the documents do not go round through it.
- `field` — `:output` or `:error_output`.
- `top_offset` — the start of the line at the top, or `-1` while a jump of the
  scroll bar of a file whose lines the page counts names only its place, which is
  `top_place`, among the lines that show.
- `top_lead` — the count of the lines that show above the line at `top_offset`,
  after a move to a match.
- `known_offset` and `known_line` — the start and the number of the last line
  whose number the page knew.
- `follow` — `true` while the page follows the end of a stream that grows.
- `find_text` — the text that Find looks for, and `found_offset` the start of the
  line of the current match, or `-1`.
- `filter_text` — the text that each line that shows holds, or empty for every
  line.
- `window`, `number` and `search` — the background cells: the lines around the
  top ([`StreamWindow`](@ref)), the number of the first line of the window, and
  what a search found ([`StreamSearch`](@ref)).

All but the execution, the field and the cells is view state.

Use it to read the lines of one stream of an execution, and the state of the page that shows them.

# Example

    found_1 = search_documents(find_task_group("T3"), part -> part isa TaskStreamLines)

See also `TaskStream`, `TaskExecution` and `find_task_group`.

For the assistant.
"""
@document struct TaskStreamLines <: Document
    execution::Any
    field::Symbol
    top_offset::Int = 0
    top_place::Int = 0
    top_lead::Int = 0
    known_offset::Int = 0
    known_line::Int = 1
    follow::Bool = true
    find_text::String = ""
    found_offset::Int = -1
    filter_text::String = ""
    window::Any = EMPTY_STREAM_WINDOW
    number::Any = EMPTY_STREAM_NUMBER
    search::Any = EMPTY_STREAM_SEARCH
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
execution: its lines, with the background cells that read them, and a bar of the
text to find, the text that the lines that show hold, the follow of the end, the
first error and the file.
"""
function make_task_stream(shadow, field::Symbol)
    holder = Ref{Any}(nothing)
    sources = _make_stream_sources()
    window = make_background_cell(sources.window, () -> _make_stream_window_input(holder[]);
                                  default = EMPTY_STREAM_WINDOW)
    number = make_background_cell(sources.number, () -> _make_stream_number_input(holder[]);
                                  default = EMPTY_STREAM_NUMBER)
    search = make_background_cell(sources.search, () -> _make_stream_search_input(holder[]);
                                  default = EMPTY_STREAM_SEARCH)
    lines = TaskStreamLines(; execution = Ref{Any}(shadow), field, window, number, search)
    holder[] = lines
    TaskStream(field === :output ? "stdout" : "stderr", _make_task_stream_bar(lines), lines)
end

# The inputs of the three cells, read on the loop from the state of the page and the
# shadow of its execution.
function _make_stream_window_input(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    (path, flushed, count) = (output.path, output.flushed_size, output.flushed_count)
    lines.follow && return (:window, path, flushed, count, flushed, 0, lines.filter_text, 0)
    place = lines.top_offset < 0 ? lines.top_place : 0
    (:window, path, flushed, count, max(0, lines.top_offset), place, lines.filter_text, lines.top_lead)
end

function _make_stream_number_input(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    window = lines.window
    isempty(window.offsets) && return (:number, nothing)
    (:number, output.path, output.flushed_size, output.flushed_count, first(window.offsets), lines.known_offset,
     lines.known_line, lines.filter_text)
end

function _make_stream_search_input(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    (:search, output.path, output.flushed_size, lines.find_text, lines.filter_text, lines.found_offset)
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

function _format_stream_matches(lines::TaskStreamLines)
    isempty(lines.find_text) && return ""
    search = lines.search
    is_cell_provisional(getfield(lines, :search)) && return "searching"
    search.count == 0 && return "no match"
    search.place == 0 ? string(search.count, search.count == 1 ? " match" : " matches") :
        string(search.place, " of ", search.count)
end

# ── The operations of the bar ────────────────────────────────────────────────

# Writes of the state of the view of `lines`, as view state.
_make_stream_view_operation(lines::TaskStreamLines, writes::Pair{String}...) =
    ReplaceViewStateOperation(CompoundOperation(Any[ReplaceReferencedValueOperation(lines, name, value)
                                                    for (name, value) in writes]))

# The move of the top to the line that starts at `offset`, `lead` lines that show
# below the top, with the follow of the end off.
_make_stream_show_writes(offset::Int, lead::Int) =
    ("top_offset" => offset, "top_place" => 0, "top_lead" => lead, "follow" => false)

"""
    make_task_stream_find_operation(lines, step) -> Operation or nothing

The move to the next line that holds `find_text`, for `step = 1`, or to the one
before, for `step = -1`, after the current match, and round from the end to the
start. The page shows the line near its top and stops following the end.
`nothing` when no line that shows holds the text, or while the search reads the
file.
"""
function make_task_stream_find_operation(lines::TaskStreamLines, step::Int)
    is_cell_provisional(getfield(lines, :search)) && return nothing
    search = lines.search
    target = step > 0 ? search.next : search.previous
    target === nothing && return nothing
    _make_stream_view_operation(lines, "found_offset" => target, _make_stream_show_writes(target, 3)...)
end

"""
    make_task_stream_first_error_operation(lines) -> Operation or nothing

The move to the first line that the kind of the task marks as an error: every
line shows again, and the page shows the line near its top and stops following
the end. The stream knows where that line starts and its number, so the move
reads no file. `nothing` when the stream has no error line.
"""
function make_task_stream_first_error_operation(lines::TaskStreamLines)
    output = get_task_stream_output(lines)
    offset = get(output.first_mark_offsets, :error, nothing)
    line = get(output.first_mark_lines, :error, nothing)
    (offset === nothing || line === nothing) && return nothing
    _make_stream_view_operation(lines, "filter_text" => "", "found_offset" => offset,
                                "known_offset" => offset, "known_line" => line, _make_stream_show_writes(offset, 3)...)
end

# The open of the file of the stream in a tab, as any file opens.
function _make_stream_file_operation(lines::TaskStreamLines)
    path = get_task_stream_output(lines).path
    path === nothing ? nothing : OpenFileOperation(path)
end
