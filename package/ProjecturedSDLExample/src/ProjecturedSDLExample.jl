"""
    ProjecturedSDLExample

The SDL opt-in example package. Hosts the `LiveExample` timelines moved down from
the umbrella example package: each pairs an existing `Example` with a timed event
stream that either

- plays in a real SDL window (`play_live_example`, via `ProjecturedSDL`), or
- records to a headless MP4 (`record_live_example`, via `ProjecturedVideo`'s
  `record_video`).

It also hosts `record_application_video`, which records the whole application
window of `run_application` — the menu bar, the toolbar, the tabs, the
navigator, the assistant pane — driven by a scripted timeline through a
`VideoBackend`, rather than one projection printed by hand.

Needs native SDL2 (and FFMPEG for recording), so it precompiles only where those
are installed. Resolves through the root env and reuses the `ProjecturedExample`
harness (the `Example` struct + the concrete example set) and the application
window of `ProjecturedExample`'s `run_application`.
"""
module ProjecturedSDLExample

using Projectured
using ProjecturedExample
using ProjecturedSDL
using ProjecturedVideo

# The bodies live in `example/backend/sdl`, not beside this file:
# a package is a name and an include list.
const _SRC_DIR = normpath(joinpath(@__DIR__, "../../../example/backend/sdl"))

include(joinpath(_SRC_DIR, "LiveExamples.jl"))
include(joinpath(_SRC_DIR, "ApplicationVideo.jl"))

export LiveExample, live_examples, play_live_example, record_live_example,
       timed_event, timed_operation, timed_await,
       record_application_video

end # module ProjecturedSDLExample
