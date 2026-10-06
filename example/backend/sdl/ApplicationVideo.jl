# ═══════════════════════════════════════════════════════════════════════════
# example/backend/sdl/ApplicationVideo.jl
#
# `record_application_video` opens the real application window — the menu bar,
# the toolbar, the tabs, the Files pane and the assistant pane — the same way
# `run_application` does, and drives it from a scripted timeline through a
# `VideoBackend` instead of a native window: the editor loop is `run_editor!`,
# not `record_video`'s own loop and not `play_live!`'s side channel, so the
# recording carries every tool a person sitting at the window has.
# ═══════════════════════════════════════════════════════════════════════════

"""
    record_application_video(paths, timeline, filename; width=1280, height=720,
                             fps=30, assistant=:none, model="", context=0,
                             llm=nothing, root=pwd(), initial_hold=0.5, final_hold=1.0,
                             supersample=2, density=1, video_time=false, pointer=true,
                             partial_render=false, debug_dirty=false, debug_dirty_hold=0,
                             status_bar=true, gesture_overlay=false, measure=FontFileMeasure(),
                             prepare=document -> nothing) -> String

Record the application window of [`run_application`](@ref) — built the same
way, over `paths` and `root`, with the same `assistant`/`model`/`context` — and
encode the session to `filename` (`.mp4`).

[`make_application_document`](@ref) and [`make_application_projection`](@ref)
make the content, `build_editor` builds the editor over a
[`VideoBackend`](@ref) standing in for the native window, with the wrappers of
[`make_application_wrappers`](@ref), which also fill the toolbar's tools (the
message log, the frame statistics, the fault log),
[`start_application!`](@ref) gives it the assistant of the application, and the
real `run_editor!` loop runs. `timeline` is that backend's scripted input. An `(event = …, hold = …)` entry
is a key or a pointer event, and an `(await = editor -> Bool, hold = …)` entry
holds the schedule until its predicate answers true or its `hold` of seconds
runs out — that is how a take waits for a turn of a real model, whose length
nobody knows in advance. Entries fire on the wall-clock schedule `initial_hold`/`final_hold` describe
(see `VideoBackend`); the backend appends its own `WindowQuit` `final_hold`
seconds after the timeline's own last hold runs out, which ends the loop the
same way the window-close button does.

Each frame is drawn at `supersample` times its size and scaled down, which is
what makes a circle and a curve smooth. The default, 2, is the default of a live
window, so the video draws what the window draws.

`video_time = true` records in video time (see `VideoBackend`): an animation
that reads the editor's clock moves one frame of time per frame, also while the
frames are slow to make. A take that waits for a model keeps the wall clock.

`pointer = true` draws the mouse pointer of the timeline over each frame (see
`VideoBackend`).

`partial_render = true` repaints only what changed from one frame to the next,
as a live window with `partial_render` does, and `debug_dirty = true` outlines
that in red on the frames, and `debug_dirty_hold` keeps each outline that many
seconds (see `VideoBackend`). `status_bar = false` leaves out the status bar
of the window (see [`make_application_wrappers`](@ref)). `gesture_overlay =
true` draws the newest gestures, and what each one did, in a panel at the bottom
right of the window; a named tuple such as `(; anchor = :bottom_left)` gives the
options of the panel (see the `gesture_log` wrapper).

`appearance` is the `Appearance` of the window, which every view of the window
draws with and which its Appearance tab changes. The default is the default
look, not the appearance that a person saved, so a take does not depend on the
files of the computer that records it.

`prepare` is called with the document of the application, its pane tree,
before the editor is made, so a take starts from the layout it wants, such as a
pane with the session's gesture log below a file. The wrappers carry the
selection that it sets.

`llm` is the model of the assistant when it is given, as
[`make_application_assistant`](@ref) takes it: a scripted model, or an
`OllamaLlm` with the seed and the temperature of a take.

The frames land in a temporary directory the backend owns and are encoded with
the same `ffmpeg` call [`record_video`](@ref) uses
(`ProjecturedVideo.encode_frames_to_video!`), then discarded.
"""
# The wrappers of the application, with the panel of the newest gestures over the
# content when the take asks for it.
_with_gesture_overlay(wrappers, gesture_overlay, measure) =
    gesture_overlay === false ? wrappers :
    merge(wrappers, (; gesture_log = merge((; overlay = true, measure),
                                           gesture_overlay === true ? (;) : gesture_overlay)))

function record_application_video(paths::AbstractVector, timeline::AbstractVector,
                                  filename::AbstractString;
                                  width::Integer = 1280, height::Integer = 720,
                                  fps::Integer = 30, assistant::Symbol = :none,
                                  model::AbstractString = "", context::Integer = 0,
                                  llm = nothing, root::AbstractString = pwd(),
                                  initial_hold::Real = 0.5, final_hold::Real = 1.0,
                                  supersample::Integer = 2, density::Real = 1,
                                  video_time::Bool = false, pointer::Bool = true,
                                  partial_render::Bool = false, debug_dirty::Bool = false,
                                  debug_dirty_hold::Real = 0, status_bar::Bool = true,
                                  gesture_overlay = false, appearance::Appearance = Appearance(),
                                  measure = FontFileMeasure(), prepare = document -> nothing)
    lowercase(splitext(filename)[2]) == ".mp4" ||
        error("record_application_video: only .mp4 output is supported (got \"$filename\")")
    chat = make_application_assistant(assistant; model = model, context = context, llm = llm)
    # One `Settings` for the histories of the window and for the editor. The take
    # names its render values on its backend, so the settings read them there.
    settings = make_settings()
    settings.is_read_from_targets = true
    document = make_application_document(collect(String, paths); root, assistant = chat,
                                         settings)
    prepare(document)
    title = "ProjecturEd"
    backend = VideoBackend(timeline, Symbol(title); width = width, height = height,
                           fps = fps, initial_hold = initial_hold, final_hold = final_hold,
                           supersample = supersample, density = density, video_time = video_time,
                           pointer = pointer, partial_render = partial_render,
                           debug_dirty = debug_dirty, debug_dirty_hold = debug_dirty_hold)
    # The take records the application as a person sees it, so the editor takes the
    # fault policy of the settings, as `run_application` does.
    fault = get_settings_group!(settings, FaultSettings)
    policy = FaultPolicy(; is_barrier_enabled = fault.is_barrier_enabled,
                         is_console_enabled = fault.is_console_enabled,
                         is_sound_enabled = fault.is_sound_enabled)
    try
        # One appearance for the views, the windows they open, the wrappers and the
        # Appearance tab, as in `run_application`, so a change of the look shows.
        editor = build_editor(document, make_application_projection(; measure, appearance, settings);
                              backend, appearance, settings, fault_policy = policy,
                              window = (; title, width, height,
                                        opened_window_projections =
                                            make_application_content_projections(; measure, appearance,
                                                                                 settings)),
                              _with_gesture_overlay(make_application_wrappers(; root, assistant = chat,
                                                                              status_bar, measure,
                                                                              appearance),
                                                    gesture_overlay, measure)...)
        backend.editor = editor
        start_application!(editor; assistant, model)
        run_editor!(editor)
        encode_frames_to_video!(backend.frames_dir, filename, fps)
    finally
        rm(backend.frames_dir; force = true, recursive = true)
    end
    filename
end
