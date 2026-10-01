# tool/video/record_lazy_primes.jl
#
# Run it as: julia --project=environment/all tool/video/record_lazy_primes.jl [<output>.mp4]
#
# Screenplay S11: only what you look at is computed. The evaluator defines the
# lazy sieve of all the primes, a filter of it, and the primes around one
# trillion, and shows each list in a pane of its own with a count of the links
# that exist. The wheel scrolls each pane, and the counts follow what the panes
# show. The coordinates are logical pixels of the 1280×720 window with the Files
# pane closed, read off the frames of the rehearsals.
#
# With `PROJECTURED_TAKE_FAST=1` the forms are typed fast, which is the warm-up:
# run it once in the same process before the take, so that no step of the take
# compiles.

using Projectured, ProjecturedKernelExample, ProjecturedSDLExample
using Random

const OUTPUT = isempty(ARGS) ? joinpath(pwd(), "lazy_primes.mp4") : ARGS[1]
const FAST = get(ENV, "PROJECTURED_TAKE_FAST", "") == "1"

const EVALUATOR_BUTTON = (54, 52)       # the toolbar of the window
const RIGHT_PANE = (960, 400)           # Primes, while it is the only list
const BOTTOM_RIGHT = (960, 560)         # Sevens
const BOTTOM_LEFT = (320, 560)          # Around one trillion, under the evaluator
const REST = (1262, 90)                 # the right end of the tab strip, off the lists

const FORMS = (
    load = "using ProjecturedPlatformExample;",
    primes = "primes = sieve(integers_from(2));",
    show_primes = "show_lazy_list!(editor, primes, \"Primes\");",
    sevens = "sevens = lazy_filter(primes, p -> p.value % 10 == 7);",
    show_sevens = "show_lazy_list!(editor, sevens, \"Sevens\");",
    around = "around = make_primes_around(10^12);",
    show_around = "show_lazy_list!(editor, around, \"Around one trillion\");",
)

# The window starts with the Files pane closed, so the evaluator has the width of
# its forms. The selection is a path through the tree, so it is set again after
# the close moves the group of the file one level up.
function close_files_pane!(document)
    selected = try_evaluate_reference(document, get_selection(document), nothing)
    tree = only(search_documents(document, node -> node isa PaneTree))
    files = only(g for g in get_pane_groups(tree)
                 if any(tab -> get_pane_tab_title_string(tab) == "Files", g.tabs))
    apply_pane_operation!(tree, make_pane_close_tab_operation(tree, files, 1))
    selected === nothing ||
        set_selection!(document, annotate_reference_types(document,
                                    first(search_references(document, node -> node === selected))))
    nothing
end

# ── The gestures, in video time ─────────────────────────────────────────────

mods(; kwargs...) = ModifierKeys(; kwargs...)
key(name; hold = 0.35, kwargs...) = (event = KeyDown(name, mods(; kwargs...); time = 0.0), hold = hold)
pause(seconds) = (await = editor -> false, hold = seconds)
move(x, y; hold = 0.04) = (event = MouseMove(x, y, MouseButtons(), mods(); time = 0.0), hold = hold)

# The pointer glides from where it is to where it goes next, so the viewer sees
# where a click or a turn of the wheel lands.
const POINTER = Ref((640, 400))
function glide(target; steps = 12)
    (x0, y0), (x1, y1) = POINTER[], target
    POINTER[] = target
    [move(round(Int, x0 + (x1 - x0) * t), round(Int, y0 + (y1 - y0) * t))
     for t in range(0, 1; length = steps + 1)[2:end]]
end
click(target; hold = 1.0) = Any[glide(target)...,
    (event = MouseClick(:left, target..., 1, mods(); time = 0.0), hold = hold)]

# The wheel turns in steps over the pointer. A positive `dy` scrolls up, so a turn
# down sends a negative one.
wheel(steps::Int; down = true, hold = 0.12) =
    [(event = MouseScroll(0, down ? -3 : 3, POINTER[]..., mods(); time = 0.0), hold = hold)
     for _ in 1:steps]

# A person types code in short runs: a name, a call up to its `(`, an argument up
# to its `,`, and stops a moment between the runs. The speed is the same for the
# whole take.
const TYPE_HOLD = 0.13
const TYPE_JITTER = 0.4
const RUN_GAP = 0.25

function split_code_runs(code)
    runs = String[]
    current = ""
    for c in code
        current *= c
        if (c in ('(', ',', ' ') && length(current) >= 5) || (c == '.' && length(current) >= 12)
            push!(runs, current)
            current = ""
        end
    end
    isempty(current) || push!(runs, current)
    runs
end

function typed(code)
    FAST && return make_typein_gestures(code; hold = 0.02, jitter = 0.0)
    out = Any[]
    for piece in split_code_runs(code)
        append!(out, make_typein_gestures(piece; hold = TYPE_HOLD, jitter = TYPE_JITTER))
        push!(out, pause(RUN_GAP))
    end
    out
end

# A form is typed and runs on Enter; the hold after it is the time to read what
# it showed.
form(code; hold = 1.5) = Any[typed(code)..., key(:return; hold = hold)]

# ── The screenplay ──────────────────────────────────────────────────────────

function make_timeline()
    POINTER[] = (640, 400)
    Any[
        pause(1.0),
        click(EVALUATOR_BUTTON; hold = 1.5)...,              # the evaluator opens
        glide(REST)...,
        form(FORMS.load; hold = 1.0)...,
        form(FORMS.primes; hold = 1.5)...,                   # 1. all the primes, in one line
        form(FORMS.show_primes; hold = 2.5)...,              # 2. only what the pane shows
        glide(RIGHT_PANE)...,
        wheel(30)..., pause(1.8),                            # 3. the count follows the view
        wheel(30; down = false)..., pause(2.0),              #    and stays on the way back
        glide(REST)...,
        form(FORMS.sevens; hold = 1.2)...,                   # 4. a lazy list of a lazy list
        form(FORMS.show_sevens; hold = 2.5)...,
        glide(BOTTOM_RIGHT)...,
        wheel(15)..., pause(2.5),                            #    both counts grow
        glide(REST)...,
        form(FORMS.around; hold = 1.2)...,                   # 5. a far start, both ways
        form(FORMS.show_around; hold = 2.5)...,
        glide(BOTTOM_LEFT)...,
        wheel(3; down = false)..., pause(2.5),               #    the primes below one trillion
        wheel(15)..., pause(2.0),                            #    and above it
        glide(REST)...,
        pause(2.5),                                          # 6. the three counts
    ]
end

function main()
    Random.seed!(11)
    directory = mkpath(joinpath(mktempdir(), "primes"))
    write(joinpath(directory, "README.md"), "# Primes\n\nThe primes, as lazy lists.\n")
    timeline = make_timeline()
    println("entries: ", length(timeline))
    started = time()
    path = record_application_video([joinpath(directory, "README.md")], timeline, OUTPUT;
                                    width = 1280, height = 720, fps = 30, assistant = :none,
                                    root = directory, initial_hold = 1.5, final_hold = 1.5,
                                    supersample = 2, video_time = true, pointer = true,
                                    status_bar = false, prepare = close_files_pane!)
    println("recorded: ", path, " in ", round(time() - started; digits = 1), " s")
end

main()
