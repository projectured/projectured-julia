# Rotating vector animation example.
#
# A point rotates forever on a circle while two line charts trace its
# coordinates: the sine of the angle (the y-coordinate) aligned to the vertical
# axis, and the cosine (the x-coordinate) aligned to the horizontal axis. Every
# animated value is a computed cell that *subscribes* to `clock` via
# `get_reactive_clock_time(clock)`; whichever caller ticks `clock` (the editor's
# read-eval-print loop for a live editor, the recorder for a video capture)
# advances the animation. The phase origin is *sampled* once at construction
# via `get_clock_time(clock)` so the angle starts at zero without the constructor
# itself becoming reactive.
#
# Pass the same `Clock` to both this constructor and the editor that hosts the
# resulting document, and the animation is tied to that editor's private clock
# — two editors in one process animate fully independently. The default is a
# clock with a heartbeat of its own (`start_wall_clock!`), started on the task
# that builds the document, so the document moves wherever it is shown. The
# heartbeat ends when the collector frees the document and its clock.
#
# The scene is painted in the Solarized palette (https://ethanschoonover.com/solarized/)
# on a light base3 background: the rotation path is an *unfilled* ring, only the
# small rotating dot is a filled disc, and dashed grey links project the dot onto
# each chart. Both charts carry their own x/y axes (a zero baseline + an
# amplitude axis). Geometry/timing are keyword arguments; colours are the named
# Solarized `color_solarized_*` constants.
#
# It is perpetual — nothing settles. The projection is the identity
# `IdentityProjection`: the document already *is* the animated `GraphicsCanvas`,
# so it passes straight through to the backend / `write_image`.

function make_rotating_vector_document(; w = 600, h = 600,   # canvas size
                                       cx = 170, cy = 170,    # circle centre
                                       r = 110,               # radius
                                       omega = -0.5,          # angular velocity (rad/s); sign sets direction
                                       n = 260,               # samples per chart window
                                       dt = 0.02,             # angle between adjacent samples
                                       gap = 20,              # gap between circle and charts
                                       clock::Clock = start_wall_clock!(Clock()))
    phase0 = get_clock_time(clock)                  # SAMPLE: no subscription
    angle(t) = omega * (t - phase0)

    x_left = cx + r + gap                      # sine chart's left edge
    y_top  = cy + r + gap                      # cosine chart's top edge

    # solarized-light backdrop (base3) behind everything
    background = GraphicsRect(0, 0, w, h; color = color_solarized_background_lighter)  # base3

    # static circle outline marking the path: an *unfilled* ring (transparent
    # fill + base01 grey outline). Only the dot below is a filled disc.
    ring = GraphicsCircle(cx, cy, r; color = StyleColor(0.0, 0.0, 0.0, 0.0),
                          border_width = 2, border_color = color_solarized_content_darker)

    # chart axes — static, base01 grey. Each wave gets a zero baseline (the time
    # axis) and an amplitude axis spanning ±R, so the oscillation is read against
    # a frame.
    sin_baseline = GraphicsLine(x_left, cy, x_left + n, cy; color = color_solarized_content_darker, width = 1)
    sin_axis     = GraphicsLine(x_left, cy - r, x_left, cy + r; color = color_solarized_content_darker, width = 1)
    cos_baseline = GraphicsLine(cx, y_top, cx, y_top + n; color = color_solarized_content_darker, width = 1)
    cos_axis     = GraphicsLine(cx - r, y_top, cx + r, y_top; color = color_solarized_content_darker, width = 1)

    # The animated elements use the cell-level positional constructor, which wraps
    # each argument in a `Cell`: a computed cell stays one, a plain value becomes a
    # static cell. So the reactive fields are derivations passed in place — no
    # `set_cell_computation!` — and they re-evaluate each frame because they read
    # `get_reactive_clock_time(clock)`.
    #
    # Positional means EVERY field in order, `dash` included. Both polylines used
    # to skip it and pass seven arguments where the type has eight, so each one
    # after `width` landed a place early: `arrow_size` took the `nothing` meant
    # for `selection`, and the SDL renderer threw `Int64(::Nothing)` on the first
    # frame it drew. The keyword constructor cannot be used here — it builds the
    # point vector eagerly, and these points are a thunk.

    # the rotating dot — its centre (cx, cy) SUBSCRIBES to time.
    dot = GraphicsCircle(
        Cell(@computation round(Int32, cx + r * cos(angle(get_reactive_clock_time(clock))))),  # cx
        Cell(@computation round(Int32, cy - r * sin(angle(get_reactive_clock_time(clock))))),  # cy
        7,                                          # radius
        color_solarized_magenta,                    # fill (magenta)
        0,                                          # border_width — filled, no outline
        StyleColor(0.0, 0.0, 0.0, 0.0),             # border_color (none)
        nothing)                                    # selection

    # sine chart — aligned to the Y axis, scrolling right. Newest sample (i = 0)
    # sits at the chart's left edge at the dot's exact cy. `points` is the only
    # computed field.
    sin_chart = GraphicsPolyline(
        Cell(@computation begin
            t = get_reactive_clock_time(clock)          # SUBSCRIBE
            Tuple{Int,Int}[(x_left + i,
                            round(Int, cy - r * sin(angle(t) - i * dt))) for i in 0:n]
        end),
        color_solarized_blue,       # color (blue)
        2,                          # width
        nothing,                    # dash — solid
        false, false, 8,            # start_arrow, end_arrow, arrow_size
        nothing)                    # selection

    # cosine chart — aligned to the X axis, scrolling down. Newest sample (i = 0)
    # sits at the chart's top edge at the dot's exact cx.
    cos_chart = GraphicsPolyline(
        Cell(@computation begin
            t = get_reactive_clock_time(clock)          # SUBSCRIBE
            Tuple{Int,Int}[(round(Int, cx + r * cos(angle(t) - i * dt)),
                            y_top + i) for i in 0:n]
        end),
        color_solarized_green,      # color (green)
        2,                          # width
        nothing,                    # dash — solid
        false, false, 8,            # start_arrow, end_arrow, arrow_size
        nothing)                    # selection

    # dashed link lines from the dot to the newest sample of each chart, base1
    # grey. The moving endpoints are thunks reading the dot's animated cells, so
    # they animate transitively (no extra time read). The fixed chart-edge
    # endpoint is `(x1, y1)`, so the dash pattern is anchored there and the
    # dashes don't crawl as the dot moves.
    sin_link = GraphicsLine(
        x_left,                     # x1 — fixed chart edge
        Cell(@computation dot.cy), # y1
        Cell(@computation dot.cx), # x2
        Cell(@computation dot.cy), # y2
        color_solarized_content_lighter,  # color (base1)
        1,                          # width
        (5, 5),                     # dash (on, off)
        nothing)                    # selection

    cos_link = GraphicsLine(
        Cell(@computation dot.cx), # x1
        y_top,                      # y1 — fixed chart edge
        Cell(@computation dot.cx), # x2
        Cell(@computation dot.cy), # y2
        color_solarized_content_lighter,  # color (base1)
        1,                          # width
        (5, 5),                     # dash (on, off)
        nothing)                    # selection

    GraphicsCanvas([background,
                    sin_baseline, sin_axis, cos_baseline, cos_axis,
                    ring, sin_link, cos_link, sin_chart, cos_chart, dot];
                   w = w, h = h)
end
