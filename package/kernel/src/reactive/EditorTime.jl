"""
    EditorTimeModule

The global animation clock, built on the reactive `Cell` engine. A single global
primitive cell holds the current logical time in seconds; the editor's main loop
writes it once per frame via `tick!`. Because cell writes invalidate dependents
(write-driven propagation), any computed cell that read the time is re-evaluated
on the next pull — which is all animation needs.

Extracted from `Reactive.jl`: it is an application-level clock layered *on top of*
the pure Cell engine (it depends on `Cell`), not part of the engine itself.

Two ways to read it, named so intent is obvious:
  • `reactive_editor_time()` — SUBSCRIBE. A tracked read; the calling cell becomes
    a dependent and re-runs every frame. Use inside an animated thunk. The
    `reactive_` prefix is the loud one: calling it makes you reactive.
  • `editor_time()` — SAMPLE. An untracked read that registers no dependency. Use
    to *arm* an animation (capture a start instant) without the arming code itself
    re-running every frame.
"""
module EditorTimeModule

import ..ReactiveModule: Cell

export EDITOR_TIME, editor_time, reactive_editor_time, tick!

const EDITOR_TIME = Cell(0.0)

"""Tracked read of the editor time — subscribe (re-run every frame)."""
reactive_editor_time() = EDITOR_TIME[]

"""Untracked read of the editor time — sample (no dependency)."""
editor_time() = peek(EDITOR_TIME)

"""Write the current logical time, invalidating everything that subscribed."""
tick!(t::Real) = (EDITOR_TIME[] = Float64(t); nothing)

end # module
