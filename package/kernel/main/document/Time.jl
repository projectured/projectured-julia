"""
    TimeModule

The global animation clock, built on the reactive `Cell` engine. A single global
primitive cell holds the current logical time in seconds; the editor's read-eval-print loop
writes it once per frame via `tick_editor_time!`. Because cell writes invalidate dependents
(write-driven propagation), any computed cell that read the time is re-evaluated
on the next pull — which is all animation needs.

An application-level clock layered *on top of* the pure `Cell` engine (it depends
only on `Cell`), not part of the engine itself.

**Relocated** from the cell layer to the document layer: a time value belongs
with the document model, not the reactive engine. This module is **deferred**
pending the clock-as-document redesign (a global wall clock + per-editor clocks;
the `_EDITOR_TIME` global is removed), after which it is renamed `Clock.jl`. See
[plan/pending/per-editor-animation-clock.md](../../../../plan/pending/per-editor-animation-clock.md).

Two ways to read it, named so intent is obvious:
  • `get_reactive_editor_time()` — SUBSCRIBE. A tracked read; the calling cell becomes
    a dependent and re-runs every frame. Use inside an animated thunk. The
    `reactive_` prefix is the loud one: calling it makes you reactive.
  • `get_editor_time()` — SAMPLE. An untracked read that registers no dependency. Use
    to *arm* an animation (capture a start instant) without the arming code itself
    re-running every frame.
"""
module TimeModule

import ..CellModule: Cell

export get_editor_time, get_reactive_editor_time, tick_editor_time!

const _EDITOR_TIME = Cell(0.0)

"""Tracked read of the editor time — subscribe (re-run every frame)."""
get_reactive_editor_time() = _EDITOR_TIME[]

"""Untracked read of the editor time — sample (no dependency)."""
get_editor_time() = peek(_EDITOR_TIME)

"""Write the current logical time, invalidating everything that subscribed."""
tick_editor_time!(t::Real) = (_EDITOR_TIME[] = Float64(t); nothing)

end # module
