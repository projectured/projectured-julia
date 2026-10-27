# An arrowhead sits on its line

Status: IN PROGRESS on the branch `arrowheads`. The owner agreed to option A on 2026-10-27, and asked for a short
plan and its work.

## The ask

The owner, 2026-10-27: "there's some issue with the arrowhead on the curved
edges, some are a bit off in directional terms, like they are not on the curve or
something / what can we do?" After the report of the cause and of two options,
the owner answered "agreed" to option A: the arrowhead points along the curve,
and the line stops at the arrowhead.

## The problem

The facts at `main` `d1bc15444`.

1. `build_polyline_arrowhead` in `GraphicsDocument.jl` points the arrowhead along
   the last segment of the polyline. For a curve, that segment is the last sample,
   so the arrowhead takes the direction of the curve at its tip. A curve that
   still bends within the length of the arrowhead (10 px in a graph) enters the
   arrowhead from the side. In `graph_services_example`, the angle between the
   arrowhead and the chord of the curve under it is 13° to 21° on 6 of 16 edges
   (21° at `web`, 17° at `auth`). The last control point of these curves is 14 to
   25 px from the tip.
2. The SDL and the PDF backends stroke the line up to the tip, under the
   arrowhead. Where the line bends, it shows beside the arrowhead.
3. The web backend sends the flags of the arrows to its browser client, and
   `asset/web/client.js` calculates the arrowhead again, from the last segment.
   `graphics.md` says that each backend draws the same points.

## The decision

- **The arrowhead points along the last `size` px of its line.** Its axis goes
  from the point of the line that is `size` back from the tip, by length along
  the line, to the tip. A line shorter than `size` takes its first point. For a
  straight last segment that is at least `size` long, the triangle is the same as
  before.
- **The line stops where the arrowhead starts.** `compute_polyline_before_arrowheads`
  gives the line without the last `size` px at each end that has an arrowhead, so
  the line ends on the axis of the arrowhead, inside its base. A line that is
  shorter than its arrowheads gives no line.
- **Each backend draws the same points.** SDL and PDF stroke the shortened line
  and fill the triangles of `build_polyline_arrowhead`. The web server sends the
  shortened line and the triangles, and the client fills the triangles that it
  gets.

Graphviz draws an arrowhead the same way: it cuts the curve by the length of the
arrow and draws the arrow on the piece that it cut.

## The steps

1. **The shared rule.** `GraphicsDocument.jl`: `build_polyline_arrowhead` along
   the last `size` px; `compute_polyline_before_arrowheads`; both exported where
   `build_polyline_arrowhead` is. Tests in `test_graphics()`: a straight line
   keeps its triangle and stops at the base; a line that bends within the
   arrowhead has the axis through the point `size` back along it; a curve that
   bends near its tip has its arrowhead on the chord; a line shorter than its
   arrowheads gives no line.
2. **The three backends.** SDL `_stroke_polyline!` and PDF
   `_paint_polyline_points!` stroke the shortened line. The web server sends
   `"pts"` shortened and `"heads"`, the triangles, and `client.js` fills them.
   Pictures of `graph_services_example` with the measure of the angles and the
   enlarged tips. Run `test_graphics()`, `test_graph()`, the test of the web
   backend, the test of the PDF writer, and `test_example` for
   `graph_services_example`.
3. **The guides.** `graphics.md`: the arrowhead and the shortened line; the guide
   of the web backend if it names the element encoding. Then the plan moves to
   `plan/done/`.

## Notes

The work happens in the worktree `projectured-julia-arrowheads` on the branch
`arrowheads`. The landing on `main` waits for the owner.
