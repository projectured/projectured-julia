# The memory of an editor stays flat. One cycle of gestures runs 60 times in one
# window, on a headless backend, as `run_application` builds it. After a warm-up of
# 20 cycles, the test takes a report of what holds the memory of the editor after
# cycle 20, 40 and 60 (`compute_held_memory`). On main the editor keeps about 18 MB
# more in each cycle, so a longer run needs more memory than a part of the suite
# has: the walk needs about 100 bytes for each object that the editor reaches. A holder that keeps more in both
# halves is a store that keeps something in each cycle. Each such store that main
# has is a known growth with its reason, so a fix of a store removes its entry.

using Test

# The stores that keep something in each cycle on main, each as a part of the path
# of its holder, or a pattern of the paths of one store, with its reason. The root
# is "(the root)", and the memory of the process that the editor does not reach is
# "(unreached)". A growth
# that an entry names counts as broken; a growth that no entry names fails, and so
# does an entry that names no growth.
const _MC_KNOWN_GROWTH = Pair{Union{String, Regex}, String}[
    # Store 1 of the plan "an editor says what holds its memory".
    "elements.kept" =>
        "the view of the list of a tab keeps the view of each element that it showed " *
        "(`CellVectorView.kept`), and each view of an element keeps the print in which it " *
        "was made, through the fault scope of the computation of its cell `entries.viewed`: " *
        "about 7.5 MB in each cycle",
    "(the root)" =>
        "about 50 KB more in each cycle that no listed holder explains: holders that gain " *
        "less than the margin each, such as the list of the files of the folder of the " *
        "explorer, and the objects that two holders keep, which belong to the root",
    "(unreached)" =>
        "the process keeps about 1.6 MB more in each cycle that the editor does not reach; " *
        "the walk does not walk into a module, so a store of a module is not seen",
]

const _MC_CYCLE_COUNT = 60
const _MC_REPORT_CYCLES = (20, 40, 60)
# A holder grows when it keeps more than this in each half: about 3.3 KB in each
# cycle of a half of 20 cycles. The list of the files of the folder gains 20 KB to
# 90 KB in a half on main, and its line moves between two holders from run to run,
# so with a smaller margin a run shows it only at some times.
const _MC_GROWTH_MARGIN = 64 << 10
# A growth repeats when the gain of one half is at most this many times the gain of
# the other. A step that happens once, such as a table that doubles, does not.
const _MC_REPEAT_FACTOR = 4
# The memory of the process that the editor does not reach grows when it gains more
# than this in each half: four times the noise of two reports with no gesture
# between them, which was 0.8 MB on main.
const _MC_UNREACHED_MARGIN = 4 << 20
# The capacity of the message log of the process in the test, so the log is full
# after the warm-up: each frame that evaluates an operation logs a line.
const _MC_LOG_CAPACITY = 100

# The report of the editor, with the holders down to 16 KiB.
function _mc_take_report(editor)
    GC.gc(true)
    report = compute_held_memory(editor; minimum_bytes = 16 << 10, minimum_share = 1, limit = 2000)
    GC.gc(true)
    (report = report, live_bytes = Base.gc_live_bytes())
end

# The folder of the test: the files of all the cycles, so the folder that the
# explorer lists does not grow.
function _mc_make_folder(directory)
    write(joinpath(directory, "list.json"), "[{\"name\": \"a\"}, {\"name\": \"b\"}, {\"name\": \"c\"}]")
    write(joinpath(directory, "other.json"), "{\"other\": \"other-value\"}")
    for cycle in 1:_MC_CYCLE_COUNT
        write(joinpath(directory, "page-$cycle.json"), "{\"page\": \"page-$cycle-value\", \"count\": $cycle}")
        write(joinpath(directory, "tab-$cycle.json"), "{\"tab\": \"tab-$cycle-value\"}")
    end
end

# The window of `run_application` over `list.json` in `directory`, with an undo
# capacity of 10, so each history is full after the warm-up.
function _mc_make_window(directory)
    settings = make_settings()
    get_settings_group!(settings, HistorySettings).undo_capacity = 10
    document = _app_focus_first_file!(make_application_document([joinpath(directory, "list.json")];
                                                                root = directory, settings))
    backend = HeadlessBackend()
    editor = build_editor(document, make_application_projection(); backend, settings,
                          window = (; title = "ProjecturEd", width = 1600, height = 1000,
                                    opened_window_projections = make_opened_window_projections()),
                          make_application_wrappers(; root = directory, document)...)
    start_application!(editor)
    drain_operations!(editor)
    run_frame!(editor)
    (editor, backend)
end

# The state of a run of the cycle.
mutable struct _MemoryCycle
    editor::Any
    backend::Any
    directory::String
    time::Float64
end

_mc_shows(cycle::_MemoryCycle, text) = any(entry -> occursin(text, entry[1]), _fw_drawn(cycle.editor))

# The place of the drawn text that holds `text`, below the tab strip.
function _mc_find_place(cycle::_MemoryCycle, text)
    drawn = _fw_drawn(cycle.editor)
    strip_y = minimum(y for (t, x, y) in drawn if t == "Explorer")
    places = [(x, y) for (t, x, y) in drawn if occursin(text, t) && y > strip_y]
    isempty(places) && error("the window draws no `$text`")
    first(places)
end

function _mc_click!(cycle::_MemoryCycle, text)
    cycle.time += 1.0
    _fw_click!(cycle.editor, cycle.backend, _mc_find_place(cycle, text), cycle.time)
end

function _mc_press!(cycle::_MemoryCycle, event)
    cycle.time += 1.0
    _fw_press!(cycle.editor, cycle.backend, event)
end

# A press and a release of the back button at the side of the mouse, on the drawn
# text `text`. The window makes the click of them.
function _mc_press_back_button!(cycle::_MemoryCycle, text)
    cycle.time += 1.0
    (x, y) = _mc_find_place(cycle, text)
    none = ModifierKeys()
    _fw_press!(cycle.editor, cycle.backend, MouseDown(:back, x + 3, y + 3, none; time = cycle.time),
               MouseUp(:back, x + 3, y + 3, none; time = cycle.time))
end

function _mc_show_tab!(cycle::_MemoryCycle, title)
    show_pane!(find_pane(title; editor = cycle.editor); editor = cycle.editor)
    run_frame!(cycle.editor)
end

# The entry of the explorer for the file `name` of the folder.
function _mc_find_explorer_file(cycle::_MemoryCycle, name)
    folder = find_explorer_content(; editor = cycle.editor).entries[1].folders[1].directory
    path = joinpath(cycle.directory, name)
    directory = get_document(folder)
    index = findfirst(file -> file.pathname == path, directory.elements)
    index === nothing && error("the explorer lists no `$name`: the folder `$(directory.pathname)` is ",
                               directory.state, " with ", length(directory.elements), " entries, such as ",
                               [element.pathname for element in first(directory.elements, 2)])
    folder.elements[index]
end

# The folder reads its entries when a part shows them. Its page shows them, as a
# person who opens its row sees them, so the test opens it once and waits.
function _mc_read_folder!(cycle::_MemoryCycle)
    editor = cycle.editor
    _mc_show_tab!(cycle, "Explorer")
    folder = find_explorer_content(; editor).entries[1].folders[1].directory
    open_explorer_page!(folder; editor)
    drain_operations!(editor)
    count = 2 * _MC_CYCLE_COUNT + 2
    _fw_wait_until(() -> length(get_document(folder).elements) == count, editor) ||
        error("the folder of the explorer lists ", length(get_document(folder).elements), " files, not ", count)
end

function _mc_open_explorer_page!(cycle::_MemoryCycle, name)
    open_explorer_page!(_mc_find_explorer_file(cycle, name); editor = cycle.editor)
    drain_operations!(cycle.editor)
    run_frame!(cycle.editor)
end

# One cycle of gestures, number `k`.
function _mc_run_cycle!(cycle::_MemoryCycle, k)
    editor = cycle.editor
    # An element goes in at the start of the list of the tab, and out again.
    _mc_show_tab!(cycle, "list.json")
    list = get_edited_document(find_pane("list.json"; editor))
    list = insert_elements!(list, 1, [parse_natural_text(:json, "{\"name\": \"new-$k\"}")]; editor)
    run_frame!(editor)
    _mc_shows(cycle, "new-$k") || error("cycle $k: the tab shows no inserted element")
    delete_elements!(list, 1; editor)
    run_frame!(editor)
    # The page of a new file in the explorer: a click, a key, and a save.
    _mc_show_tab!(cycle, "Explorer")
    _mc_open_explorer_page!(cycle, "page-$k.json")
    _fw_wait_until(() -> _mc_shows(cycle, "page-$k-value"), editor) ||
        error("cycle $k: the page shows no `page-$k-value`")
    _mc_click!(cycle, "page-$k-value")
    _mc_press!(cycle, KeyPress('x'; time = cycle.time))
    _mc_press!(cycle, KeyDown(:s, ModifierKeys(ctrl = true); time = cycle.time))
    # Another program writes the file, and the page shows the new text.
    write(joinpath(cycle.directory, "page-$k.json"), "{\"page\": \"page-$k-reloaded\", \"count\": $k}")
    _fw_wait_until(() -> _mc_shows(cycle, "page-$k-reloaded"), editor) ||
        error("cycle $k: the page shows no `page-$k-reloaded`")
    # A file in a tab of its own: a click, and the tab closes.
    tab = open_file!(joinpath(cycle.directory, "tab-$k.json"); editor)
    drain_operations!(editor)
    show_pane!(tab; editor)
    run_frame!(editor)
    _mc_click!(cycle, "tab-$k-value")
    close_pane!(find_pane("tab-$k.json"; editor); editor)
    run_frame!(editor)
    # Another page, and Back: the back list holds one more visit.
    _mc_show_tab!(cycle, "Explorer")
    _mc_open_explorer_page!(cycle, "other.json")
    _fw_wait_until(() -> _mc_shows(cycle, "other-value"), editor) ||
        error("cycle $k: the page shows no `other-value`")
    _mc_press_back_button!(cycle, "other-value")
    # A click waits for a second click, so Back shows in a later frame.
    _fw_wait_until(() -> _mc_shows(cycle, "page-$k-reloaded"), editor) ||
        error("cycle $k: Back shows no `page-$k-reloaded`")
    nothing
end

# The largest holders of `report`, one line each.
_mc_describe_largest(report; count = 25) =
    join((string(holder.bytes, "  ", holder.object_count, "  ", holder.path, "  ", nameof(holder.type))
          for holder in first(report.holders, count)), "\n")

# The bytes that each path keeps in `report`. A path that names two holders, such
# as a cell and the document in it, keeps the larger.
function _mc_get_path_bytes(report)
    bytes = Dict{String, Int}()
    for holder in report.holders
        bytes[holder.path] = max(get(bytes, holder.path, 0), holder.bytes)
    end
    bytes
end

# The name of the path of a holder in the lines of the test.
_mc_name_path(path) = isempty(path) ? "(the root)" : path

# Whether `path` is below `above`: it goes on from `above` with a step.
_mc_is_below(path, above) =
    path != above && startswith(path, above) && path[nextind(path, lastindex(above))] in ('.', '[')

"""
    _mc_find_growths(reports; margin) -> Dict{String, Tuple{Int,Int}}

The holders that keep more in both halves of three reports, each with what it
gains in the first and in the second half. A holder below another that grows
explains a part of the gain of the other, so a holder takes only the gain that the
growing holders nearest below it do not explain. A holder grows when that gain is
more than `margin` in each half, and the gain repeats: neither half gains more
than `_MC_REPEAT_FACTOR` times the other. A path that a report does not list keeps
nothing in it.
"""
function _mc_find_growths(reports; margin = _MC_GROWTH_MARGIN)
    (first_bytes, middle_bytes, last_bytes) = map(_mc_get_path_bytes, reports)
    gains = Dict{String, Tuple{Int, Int}}()
    for (path, bytes) in last_bytes
        middle = get(middle_bytes, path, 0)
        gain = (middle - get(first_bytes, path, 0), bytes - middle)
        (gain[1] > margin && gain[2] > margin) && (gains[path] = gain)
    end
    growths = Dict{String, Tuple{Int, Int}}()
    for (path, gain) in gains
        below = [other for other in keys(gains) if _mc_is_below(other, path)]
        nearest = [other for other in below if !any(between -> _mc_is_below(other, between), below)]
        own = (gain[1] - sum(other -> gains[other][1], nearest; init = 0),
               gain[2] - sum(other -> gains[other][2], nearest; init = 0))
        (own[1] > margin && own[2] > margin && max(own...) <= _MC_REPEAT_FACTOR * min(own...)) &&
            (growths[path] = own)
    end
    growths
end

# The types whose objects gain the most bytes in the second half, as a line each.
function _mc_describe_growing_types(reports; count = 8)
    (middle, last_report) = (reports[2], reports[3])
    before = Dict(entry.type => entry.bytes for entry in middle.types)
    gains = sort!([(entry.bytes - get(before, entry.type, 0), entry.type) for entry in last_report.types];
                  by = first, rev = true)
    join((string(gain, "  ", type) for (gain, type) in first(gains, count)), "\n")
end

# The gain in each half of the live memory of the process that the editor does not
# reach.
_mc_get_unreached_gains(reports) =
    Tuple((reports[index + 1].live_bytes - reports[index + 1].report.total_bytes) -
          (reports[index].live_bytes - reports[index].report.total_bytes) for index in 1:2)

# The largest holders below `path` in the last report, each with its gain in the
# two halves, as a line each.
function _mc_describe_below(reports, path; count = 3)
    (first_bytes, middle_bytes, last_bytes) = map(_mc_get_path_bytes, reports)
    below = sort!([other for other in keys(last_bytes) if _mc_is_below(other, path)];
                  by = other -> -last_bytes[other])
    join((string(other[nextind(other, lastindex(path)):end], "  ", get(first_bytes, other, 0), " → ",
                 get(middle_bytes, other, 0), " → ", last_bytes[other])
          for other in first(below, count)), "\n")
end

function test_editor_memory_cycle()
@testset "the memory of an editor stays flat over a cycle of gestures" begin
    log_store = get_session_message_log_store()
    log_capacity = log_store.capacity
    log_store.capacity = _MC_LOG_CAPACITY
    try
        mktempdir() do directory
            _mc_make_folder(directory)
            (editor, backend) = _mc_make_window(directory)
            cycle = _MemoryCycle(editor, backend, directory, 0.0)
            _mc_read_folder!(cycle)
            reports = []
            for k in 1:_MC_CYCLE_COUNT
                _mc_run_cycle!(cycle, k)
                if k in _MC_REPORT_CYCLES
                    timed = @timed _mc_take_report(editor)
                    push!(reports, timed.value)
                    report = timed.value.report
                    @info "the report after cycle $k" report.total_bytes report.object_count report.walk_bytes walk_bytes_per_object = report.walk_bytes / report.object_count seconds = timed.time live_bytes = timed.value.live_bytes largest = _mc_describe_largest(report)
                end
            end
            # A report right after the last, with no gesture between: the noise of the totals.
            again = _mc_take_report(editor)
            @info "the noise of the totals" reached_noise = again.report.total_bytes - reports[3].report.total_bytes unreached_noise = (again.live_bytes - again.report.total_bytes) - (reports[3].live_bytes - reports[3].report.total_bytes)
            held = [entry.report for entry in reports]
            # The root takes the growth of the bytes that the editor reaches that no
            # holder below it explains. The memory of the process that the editor does
            # not reach is a line of its own.
            growths = Dict(_mc_name_path(path) => gain for (path, gain) in _mc_find_growths(held))
            unreached = _mc_get_unreached_gains(reports)
            @info "the memory that the editor does not reach" unreached
            (minimum(unreached) > _MC_UNREACHED_MARGIN && maximum(unreached) <= _MC_REPEAT_FACTOR * minimum(unreached)) &&
                (growths["(unreached)"] = unreached)
            @info "the types that gain the most in the second half" types = _mc_describe_growing_types(held)
            for (name, gain) in sort!(collect(growths); by = first)
                @info "a holder that grows in each half" name gain below = _mc_describe_below(held, name == "(the root)" ? "" : name)
            end
            excused = Dict(path => findfirst(entry -> occursin(first(entry), path), _MC_KNOWN_GROWTH) for path in keys(growths))
            for (path, entry) in excused
                if entry === nothing
                    @test path === "a holder that no known growth names"
                else
                    # @broken: a store that keeps something in each cycle on main; `_MC_KNOWN_GROWTH` names it with its reason.
                    @test_broken path === "a holder that stays flat"
                end
            end
            unused = [first(entry) for (index, entry) in enumerate(_MC_KNOWN_GROWTH) if !(index in values(excused))]
            for key in unused
                named = [(path, [get(_mc_get_path_bytes(report), path, 0) for report in held])
                         for path in keys(_mc_get_path_bytes(held[3])) if occursin(key, path)]
                @info "a known growth that names no growth" key named
            end
            @test isempty(unused)
            foreach(step -> step(editor), editor.stop_steps)
        end
    finally
        log_store.capacity = log_capacity
    end
end
end
