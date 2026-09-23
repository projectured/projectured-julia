# ═══════════════════════════════════════════════════════════════════════════
# example/sdl/ApplicationVideo.jl
#
# `record_application_video` opens the real application window — the menu bar,
# the toolbar, the tabs, the navigator and the assistant pane — the same way
# `run_application` does, and drives it from a scripted timeline through a
# `VideoBackend` instead of a native window: the editor loop is `run_editor!`,
# not `record_video`'s own loop and not `play_live!`'s side channel, so the
# recording carries every tool a person sitting at the window has.
# ═══════════════════════════════════════════════════════════════════════════

"""
    record_application_video(paths, timeline, filename; width=1280, height=720,
                             fps=30, assistant=:none, model="", context=0,
                             root=pwd(), initial_hold=0.5, final_hold=1.0,
                             supersample=1, scale=1,
                             measure=measure_truetype_text) -> String

Record the application window of [`run_application`](@ref) — built the same
way, over `paths` and `root`, with the same `assistant`/`model`/`context` — and
encode the session to `filename` (`.mp4`).

[`make_application_window`](@ref) builds the document and the projection,
[`run_with_window_tools`](@ref) fills in the toolbar's tools (the message log,
the frame statistics, the fault log), `make_editor` builds the editor over a
[`VideoBackend`](@ref) standing in for the native window,
[`start_application!`](@ref) gives it the assistant of the application, and the
real `run_editor!` loop runs. `timeline` is that backend's scripted input. An `(event = …, hold = …)` entry
is a key or a pointer event, and an `(await = editor -> Bool, hold = …)` entry
holds the schedule until its predicate answers true or its `hold` of seconds
runs out — that is how a take waits for a turn of a real model, whose length
nobody knows in advance. Entries fire on the wall-clock schedule `initial_hold`/`final_hold` describe
(see `VideoBackend`); the backend appends its own `WindowQuit` `final_hold`
seconds after the timeline's own last hold runs out, which ends the loop the
same way the window-close button does.

The frames land in a temporary directory the backend owns and are encoded with
the same `ffmpeg` call [`record_video`](@ref) uses
(`ProjecturedVideo._encode_frames_to_video!`), then discarded.
"""
function record_application_video(paths::AbstractVector, timeline::AbstractVector,
                                  filename::AbstractString;
                                  width::Integer = 1280, height::Integer = 720,
                                  fps::Integer = 30, assistant::Symbol = :none,
                                  model::AbstractString = "", context::Integer = 0,
                                  root::AbstractString = pwd(),
                                  initial_hold::Real = 0.5, final_hold::Real = 1.0,
                                  supersample::Integer = 1, scale::Real = 1,
                                  measure = measure_truetype_text)
    lowercase(splitext(filename)[2]) == ".mp4" ||
        error("record_application_video: only .mp4 output is supported (got \"$filename\")")
    chat = make_application_assistant(assistant; model = model, context = context)
    document, projection = make_application_window(collect(String, paths);
                                                    root = root, assistant = chat,
                                                    measure = measure)
    title = "ProjecturEd"
    backend = VideoBackend(timeline, Symbol(title); width = width, height = height,
                           fps = fps, initial_hold = initial_hold, final_hold = final_hold,
                           supersample = supersample, scale = scale)
    try
        run_with_window_tools() do feeds, start
            editor = make_editor(document, projection, title; backend = backend,
                                 width = width, height = height, feeds = feeds,
                                 opened_window_projections =
                                     make_opened_window_projections(;
                                         content = make_application_content_projections(measure = measure),
                                         measure = measure),
                                 screen_wrap = make_popup_screen_wrap())
            backend.editor = editor
            start(editor)
            start_application!(editor, false, assistant, model)
            run_editor!(editor)
        end
        _encode_frames_to_video!(backend.frames_dir, filename, fps)
    finally
        rm(backend.frames_dir; force = true, recursive = true)
    end
    filename
end
