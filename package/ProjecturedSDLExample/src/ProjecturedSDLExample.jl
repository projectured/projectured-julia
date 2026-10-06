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
Files pane, the assistant pane — driven by a scripted timeline through a
`VideoBackend`, rather than one projection printed by hand.

Needs native SDL2 (and FFMPEG for recording), so it precompiles only where those
are installed. Its timelines play the JSON examples of `ProjecturedJSONExample`.
"""
module ProjecturedSDLExample

import ProjecturedConsole
import ProjecturedJSON
import ProjecturedKernel
import ProjecturedPDF
import ProjecturedPlatform
using ProjecturedKernelExample
using ProjecturedPlatformExample
using ProjecturedJSONExample
using ProjecturedSDL
using ProjecturedVideo
import ProjecturedKernelExample: Example, make_typein_gestures

const _SOURCES = (ProjecturedPlatform, ProjecturedConsole, ProjecturedJSON, ProjecturedKernel, ProjecturedPDF)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        # An aggregate repeats the modules and the names that this loop binds.
        nameof(_m) in (:KernelModule, :PlatformModule) && continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

# The bodies live in `example/backend/sdl`, not beside this file:
# a package is a name and an include list.
const _SRC_DIR = normpath(joinpath(@__DIR__, "../../../example/backend/sdl"))

include(joinpath(_SRC_DIR, "LiveExamples.jl"))
include(joinpath(_SRC_DIR, "ApplicationVideo.jl"))

export LiveExample, live_examples, play_live_example, record_live_example,
       timed_event, timed_operation, timed_await,
       record_application_video

end # module ProjecturedSDLExample
