"""
    ProjecturedSdlExample

The SDL opt-in example package. Hosts the `LiveExample` timelines moved down from
the umbrella example package: each pairs an existing `Example` with a timed event
stream that either

- plays in a real SDL window (`play_live_example`, via `ProjecturedSdl`), or
- records to a headless MP4 (`record_live_example`, via `ProjecturedVideo`'s
  `record_video`).

Needs native SDL2 (and FFMPEG for recording), so it precompiles only where those
are installed. Resolves through the root env and reuses the `ProjecturedExample`
harness (the `Example` struct + the concrete example set).
"""
module ProjecturedSdlExample

using Projectured
using ProjecturedExample
using ProjecturedSdl
using ProjecturedVideo

const _SRC_DIR = @__DIR__

include(joinpath(_SRC_DIR, "LiveExamples.jl"))

export LiveExample, live_examples, play_live_example, record_live_example,
       timed_event, timed_operation, timed_await

end # module ProjecturedSdlExample
