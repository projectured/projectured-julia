# Fragment of `ShellModule` — the chrome a window is drawn in.
#
# The shell is **drawn, not stored**. The printer builds a `WidgetShell` holding
# the window's own document in its `content` slot and renders that; the document
# itself is never wrapped in one. A menu bar belongs to the binary, and a saved
# user interface holds the person's window and not the binary's furniture.
#
# The shell is built **once** and its content cell is re-read on every print, so
# the widget keeps one identity across prints and the reactive layer sees the
# same nodes (`PAR-STABLE-IOMAP-IDENTITY`). A shell rebuilt per print would make
# every frame a fresh tree.

struct WindowShellProjection <: Projection
    inner::Projection
    renderer::Projection
    bands::Function            # () -> (menu_bar, toolbar, status_bar, context_menu)
    size::Function             # () -> Point2D | Nothing
    shell::Base.RefValue{Any}  # the one WidgetShell, built on the first print
end

"""
    WindowShellProjection(; inner, renderer, bands, size = () -> nothing)

Draw a window inside its chrome.

`inner` draws the window's own content, and `renderer` draws the chrome's
widgets; the content slot of the shell defers to `inner`, so what a pane holds
is drawn exactly as it is without the shell.

`bands` answers `(menu_bar, toolbar, status_bar, context_menu)`, so a host says
what its window offers and this package names none of it. `size` answers the
size to give the shell: **a `WidgetShell` with no size hugs its content**, which
a window shell must not do.
"""
WindowShellProjection(; inner::Projection, renderer::Projection,
                        bands::Function, size::Function = () -> nothing) =
    WindowShellProjection(inner, renderer, bands, size, Ref{Any}(nothing))

@iomap struct WindowShellIoMap
    projection::Any
    input::Any
    output::Any
    child_iomap::Any
end

# ── Printer ───────────────────────────────────────────────────────────────

function print_document(p::WindowShellProjection, recursion, input, ctx)
    shell = _window_shell(p, input)
    child_iomap = print_document(p.renderer, recursion, shell, ctx)
    WindowShellIoMap(p, input, ComputedCell(() -> child_iomap.output), child_iomap)
end

function _window_shell(p::WindowShellProjection, input)
    existing = p.shell[]
    if existing === nothing
        menu_bar, toolbar, status_bar, context_menu = p.bands()
        p.shell[] = WidgetShell(input; menu_bar = menu_bar, toolbar = toolbar,
                                       status_bar = status_bar,
                                       context_menu = context_menu, size = p.size())
        return p.shell[]
    end
    # The window's document can be replaced under the shell — a file re-read, a
    # layout loaded from a file — and the shell holds the one it was given.
    existing.content === input || (existing.content = input)
    existing
end

# ── Reader ────────────────────────────────────────────────────────────────

read_intent(p::WindowShellProjection, recursion, change::Intent, iomap::WindowShellIoMap) =
    read_intent(iomap.child_iomap.projection, recursion, change, iomap.child_iomap)

read_intent(p::WindowShellProjection, iomap::WindowShellIoMap, payload) =
    read_intent(p, nothing, Intent(payload), iomap).operation

# ── Reference mapping ─────────────────────────────────────────────────────
#
# The shell adds one step, `content`, between the window and its document. A
# reference going out gains it and a reference coming back loses it, so nothing
# above or below the shell knows the chrome is there.

map_reference_forward(::WindowShellProjection, iomap::WindowShellIoMap, reference) =
    map_reference_forward(iomap.child_iomap.projection, iomap.child_iomap,
                          extend_reference(EmptyReference(), FieldReferenceStep("content"),
                                           reference))

function map_reference_backward(::WindowShellProjection, iomap::WindowShellIoMap, reference)
    answer = map_reference_backward(iomap.child_iomap.projection, iomap.child_iomap, reference)
    answer isa ConcreteReference || return answer
    head = answer.head
    (head isa FieldReferenceStep && head.name == "content") || return nothing
    answer.tail
end
