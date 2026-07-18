# ═══════════════════════════════════════════════════════════════════════════
# example/LiveExamples.jl
#
# A `LiveExample` captures an existing `Example` and pairs it with a *timeline*
# of predefined, timed entries. The same timeline drives two consumers:
#
#   - `record_live_example(live, "x.mp4")` — headless MP4 (via `record_video`),
#   - `play_live_example(live)`            — a real window the user watches.
#
# A timeline entry is a NamedTuple carrying either an `event` (a device event run
# through the reader, like live input) or an `operation` (a domain `Operation`
# value or a `doc -> op` thunk injected straight into the evaluator), plus a
# `hold` in seconds. `hold` is the dwell after the entry: the recorder turns it
# into `round(hold*fps)` frames (video time), the live player into a wall-clock
# delay before the next entry.
# ═══════════════════════════════════════════════════════════════════════════

"""
    LiveExample(name, example, timeline; initial_selection=nothing,
                width=900, height=600, fps=30)

Bundle an existing `Example` with a timed `timeline` (see file header for the
entry format). `initial_selection` seeds the caret (needed for keyboard typein);
it is either a `Reference` or a `doc -> path` thunk evaluated against the
fresh document. `width`/`height`/`fps` are the presentation defaults for both
recording and live playback.
"""
struct LiveExample
    name::String
    example::Example
    timeline::Vector
    initial_selection
    width::Int
    height::Int
    fps::Int
    LiveExample(name, example, timeline; initial_selection=nothing,
                width=900, height=600, fps=30) =
        new(String(name), example, collect(timeline), initial_selection,
            Int(width), Int(height), Int(fps))
end

# ── Timeline builders ─────────────────────────────────────────────────────

"""
    timed_event(event; hold=0.4) -> NamedTuple

A timeline entry that feeds `event` through the reader (like live input).
"""
timed_event(event; hold::Real=0.4) = (event = event, hold = Float64(hold))

"""
    timed_operation(operation; hold=0.4) -> NamedTuple

A timeline entry that injects `operation` straight into the evaluator. `operation`
is an `Operation` value or a `doc -> op` thunk evaluated at fire time against the
current document — use the thunk form when the op must reference live state.
"""
timed_operation(operation; hold::Real=0.4) = (operation = operation, hold = Float64(hold))

"""
    timed_await(predicate; max_hold=8.0) -> NamedTuple

A timeline entry that lets *asynchronous* editor work settle while it is
recorded. `predicate` is a `doc -> Bool` thunk evaluated against the current
document (e.g. `doc -> assistant_of(doc).status === :idle` after an ENTER kicked
off a streaming assistant turn).

In `record_video` the recorder spins — yielding and emitting roughly `fps`
frames per second — until `predicate` holds or `max_hold` seconds elapse, so the
streamed thinking/text/tool output is captured as a gradual reveal. In
`play_live!` the entry injects no operation; it is a pure `max_hold`-second
dwell during which the live loop renders the streaming turn frame by frame.
"""
timed_await(predicate; max_hold::Real=8.0) = (await = predicate, hold = Float64(max_hold))

# Resolve an `initial_selection` (path or `doc -> path` thunk) against `document`.
_resolve_selection(::Nothing, document) = nothing
_resolve_selection(sel::Function, document) = sel(document)
_resolve_selection(sel, document) = sel

# ── Drivers ────────────────────────────────────────────────────────────────

"""
    record_live_example(live::LiveExample, filename=tempname()*".mp4"; kwargs...) -> String

Record `live`'s timeline into a headless MP4. Reuses `record_video` against the
example's bare document/projection (same content origin as the live window, so a
single timeline's mouse coordinates work in both). Extra `kwargs` pass through to
`record_video` (e.g. `supersample`, `final_hold`, `wait_for`).
"""
function record_live_example(live::LiveExample, filename::AbstractString=tempname()*".mp4"; kwargs...)
    document   = live.example.make_document()
    projection = live.example.make_projection()
    record_video(document, projection, live.timeline, filename;
                 width=live.width, height=live.height, fps=live.fps,
                 initial_selection=_resolve_selection(live.initial_selection, document),
                 kwargs...)
end

function record_live_example(name::AbstractString, filename::AbstractString=tempname()*".mp4"; kwargs...)
    record_live_example(_lookup_live_example(name), filename; kwargs...)
end

"""
    play_live_example(live::LiveExample; width=live.width, height=live.height,
                      initial_hold=0.5)

Open a real window and replay `live`'s timeline at wall-clock speed so the user
watches the scripted session. The example is wrapped in a single
`WindowDocument`/`ScreenDocument` (the same single-window scene `run_example`
builds), so the backend opens a native window; scripted events are routed to that
window via `play_live!`. The window stays interactive after the timeline ends.
"""
function play_live_example(live::LiveExample; width::Integer=live.width,
                           height::Integer=live.height, initial_hold::Real=0.5)
    document   = live.example.make_document()
    projection = live.example.make_projection()

    sel = _resolve_selection(live.initial_selection, document)
    sel === nothing || set_selection!(document, sel)

    window_id = Symbol(live.name)
    win = WindowDocument(; id=window_id, title=live.name,
                         x=100, y=100, width=width, height=height, content=document)
    screen = ScreenDocument([win])

    # Lift the seeded selection to a screen-rooted path, mirroring `run_example`.
    inner_sel = getfield(document, :selection)[]
    inner_sel === nothing || set_selection!(screen, @reference(screen, windows[1].content.^(inner_sel)))

    composed = _multi_window_projection([projection])
    # Timeline operations are authored in the bare-content domain (like the
    # recorder); in the windowed scene they must be rerooted to the screen by the
    # steps that lead to this window's content. Event entries are rerooted by the
    # reader automatically, so they need no prefix.
    play_live!(SdlBackend(), composed, screen, live.timeline;
               window_id=window_id, initial_hold=initial_hold,
               op_prefix = @reference(screen, windows[1].content))
end

function play_live_example(name::AbstractString; kwargs...)
    play_live_example(_lookup_live_example(name); kwargs...)
end

function _lookup_live_example(name::AbstractString)
    idx = findfirst(l -> l.name == name, live_examples)
    idx === nothing && error("Unknown live example: \"$name\". Available: " *
                             join(getfield.(live_examples, :name), ", "))
    live_examples[idx]
end

# ── Predefined live examples ─────────────────────────────────────────────────

# Type "world" into the first string value of the json object ("Alice"), then
# step the caret right a couple of times. Pure events; needs a caret seed.
const json_typein_live = LiveExample("json_typein", json_example,
    vcat(
        make_typein_gestures(" world"),
        [timed_event(KeyDown(:left, ModifierKeys(), false); hold=0.4),
         timed_event(KeyDown(:left, ModifierKeys(), false); hold=0.6)],
    );
    initial_selection = @reference(make_json_document_example(), entries[1].value.value{5}))

# Jump the selection with a timed *operation* (no single event triggers it), then
# type at the new caret. Demonstrates timed operations and events together.
const json_select_and_edit_live = LiveExample("json_select_and_edit", json_example,
    vcat(
        [timed_operation(ReplaceSelectionOperation(@reference(make_json_document_example(), entries[4].value.entries[1].value.value{11})); hold=0.6)],
        make_typein_gestures("!"),
    );
    initial_selection = @reference(make_json_document_example(), entries[1].value.value{5}))

# Insert a brand-new `"role": "admin"` entry into the object. Starting from the
# whole "name" value, `,` appends an empty entry (cursor on its key), type the
# key, Tab moves to the value, `"` starts a string, then type the value. Pure
# structural-authoring gestures (`,`-insert, Tab, type-to-replace).
const json_insert_live = LiveExample("json_insert", json_example,
    vcat(
        [timed_event(KeyPress(','); hold=0.6)],               # add a new entry, cursor on its key
        make_typein_gestures("role"),                          # type the key
        [timed_event(KeyDown(:tab, ModifierKeys()); hold=0.6),    # Tab: key → value (whole)
         timed_event(KeyPress('"'); hold=0.5)],                # start a string value
        make_typein_gestures("admin"),                         # type the value
    );
    initial_selection = @reference(make_json_document_example(), entries[1].value))

# Type the entire nested `json_example` from an empty document, using only typing
# and cursor navigation. Each value is built by type-to-replace (`"` string, digit
# number, `t`/`f` bool, `{` object, `[` array); `Tab` steps an entry key→value.
#
# `,` is **contextual**: from a non-string value caret it inserts a sibling in the
# enclosing object/array directly (no need to first select the value), while inside
# a string it is a literal comma. So a sibling after a number/bool needs no step-out
# at all; after a *string* a single `Right` leaves the string before `,`. Stepping up
# to an *outer* container for a root-level sibling still needs `Alt+Up`
# tree-navigation (that is a genuine level change, not a same-container step). This
# exercises the recursive gesture reader: nested `,`/`Tab` reach the *focused*
# object/array. The result equals `make_json_document_example()` modulo number
# representation (multi-digit numbers reparse to Float) and the trailing
# `"placeholder"` insertion left under the caret.
#
# Empty-document example: a bare `JsonInsertion` (the typed-name insertion buffer) under the full
# JSON projection, whole-selected so the first `{` replaces it with an object.
const json_build_example = Example("json_build", () -> JsonInsertion(), make_json_projection_example)

# `_jb_up(n)`: step up `n` container levels with Alt+Up tree-navigation, to insert a
# sibling at an outer (root) level (3/4 to escape a nested array/object). `_jb_right`:
# a single plain Right to leave a finished *string* value (where `,` is literal) for
# the structural caret just past it. A same-container sibling after a number/bool
# needs neither — `,` inserts there directly.
_jb_up(n) = [timed_event(KeyDown(:up, ModifierKeys(alt=true)); hold=0.22) for _ in 1:n]
_jb_right() = timed_event(KeyDown(:right, ModifierKeys()); hold=0.25)
_jb_tab()   = timed_event(KeyDown(:tab, ModifierKeys()); hold=0.32)
_jb_comma() = timed_event(KeyPress(','); hold=0.40)
_jb_open(c) = timed_event(KeyPress(c); hold=0.40)            # '{' or '['
_jb_key(s)  = make_typein_gestures(s)                        # caret already on the (empty) key
_jb_str(s)  = vcat([timed_event(KeyPress('"'); hold=0.30)], make_typein_gestures(s))
_jb_estr(k, v) = vcat(_jb_key(k), [_jb_tab()], _jb_str(v))   # "k": "v"
_jb_enum(k, v) = vcat(_jb_key(k), [_jb_tab()], make_typein_gestures(v))            # "k": <digits>
_jb_ebool(k, b) = vcat(_jb_key(k), [_jb_tab()], [timed_event(KeyPress(b ? 't' : 'f'); hold=0.3)])

const json_build_live = LiveExample("json_build", json_build_example,
    vcat(
        [_jb_open('{')],
        _jb_estr("name", "Alice"),       [_jb_right(), _jb_comma()],  # string: Right out, then ,
        _jb_enum("age", "30"),           [_jb_comma()],               # number: , inserts directly
        _jb_ebool("active", true),       [_jb_comma()],               # bool already whole-selected
        _jb_key("address"), [_jb_tab(), _jb_open('{')],
            _jb_estr("street", "123 Main St"), [_jb_right(), _jb_comma()],
            _jb_estr("city", "Wonderland"),    [_jb_right(), _jb_comma()],
            _jb_estr("zip", "12345"),
        _jb_up(4), [_jb_comma()],                                    # escape nested object → root sibling
        _jb_key("scores"), [_jb_tab(), _jb_open('[')],
            make_typein_gestures("95"),  [_jb_comma()],
            make_typein_gestures("87"),  [_jb_comma()],
            make_typein_gestures("100"),
        _jb_up(3), [_jb_comma()],                                    # escape nested array → root sibling
        _jb_key("tags"), [_jb_tab(), _jb_open('[')],
            _jb_str("admin"),    [_jb_right(), _jb_comma()],
            _jb_str("editor"),   [_jb_right(), _jb_comma()],
            _jb_str("reviewer"),
        _jb_up(3), [_jb_comma()],
        _jb_key("meta"), [_jb_tab(), _jb_open('{')],
            _jb_estr("created", "2025-01-15"), [_jb_right(), _jb_comma()],
            _jb_enum("version", "2"),          [_jb_comma()],
            _jb_ebool("draft", false),
        _jb_up(3), [_jb_comma()],                                    # escape nested object (bool last) → root sibling
        _jb_key("placeholder"), [_jb_tab()],                         # leave value as the insertion
    );
    initial_selection = Projectured.EmptyReference(),
    width = 760, height = 1000)

const live_examples = LiveExample[
    json_typein_live,
    json_select_and_edit_live,
    json_insert_live,
    json_build_live,
]
