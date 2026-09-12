"""
    LayoutGeometryModule

The geometry the ported layouters are written in, from OMNeT++'s
`src/layout/geometry.h`: a three-dimensional point `Pt`, a size `Rs`, a
positioned rectangle `Rc`, and a segment `Ln`.

The third dimension is not decoration. `ForceDirectedGraphLayouter` can lift the
embedding off the base plane and pull it back down with a spring, which lets a
tangled graph untangle through a dimension the drawing does not have. The
drawing then reads x and y and ignores z.

**One deviation from the original.** `Pt`, `Rs`, `Rc` and `Ln` are immutable
here, and every operation answers a new value. The C++ mutates in place and
copies by hand where a copy is needed (`Pt(variable->getPosition()).add(...)`);
a missed copy there is an aliasing bug that a port would inherit silently. An
immutable value cannot have that bug, so it is worth the deviation.

`NaN` means "not assigned yet" throughout, as it does in the original: a
coordinate is nil until something assigns it, and `convert_nan_to_zero` is what turns an
unassigned coordinate into a usable one.
"""
module LayoutGeometryModule

export Pt, Rs, Rc, Ln,
       pt_nil, pt_zero, pt_radial, is_nil, is_zero, is_fully_specified,
       pt_length, pt_length_square, pt_distance, pt_normalize, pt_multiply,
       pt_reverse, convert_nan_to_zero, with_base_plane_projection, get_base_plane_length,
       get_base_plane_length_square, get_base_plane_distance, get_base_plane_angle,
       rotate_base_plane, transpose_base_plane, with_x, with_y, with_z,
       rs_nil, get_diagonal_length, area,
       rc_nil, rc_from_center_size, rc_left, rc_right, rc_top, rc_bottom,
       rc_center, rc_left_top, rc_right_top, rc_left_bottom, rc_right_bottom,
       rc_center_top, rc_center_bottom, rc_left_center, rc_right_center,
       rc_contains, rc_bounding, ln_nil, rc_base_plane_distance,
       rc_base_plane_contains, rc_base_plane_intersects,
       Cc, cc_center_top, cc_center_bottom, cc_left_center, cc_right_center,
       cc_intersect, cc_enclosing

# ── Pt ───────────────────────────────────────────────────────────────────────

"""
    Pt(x, y, z)

A point in three dimensions. `z == 0` is the base plane, which is what the
drawing shows.
"""
struct Pt
    x::Float64
    y::Float64
    z::Float64
end

Pt(x::Real, y::Real, z::Real) = Pt(Float64(x), Float64(y), Float64(z))

"A point with nothing assigned yet."
pt_nil() = Pt(NaN, NaN, NaN)

"The origin."
pt_zero() = Pt(0.0, 0.0, 0.0)

"The base-plane point at `radius` from the origin, at `angle` radians."
pt_radial(radius::Real, angle::Real) = Pt(cos(angle) * radius, sin(angle) * radius, 0.0)

"`true` when no coordinate is assigned."
is_nil(pt::Pt) = isnan(pt.x) && isnan(pt.y) && isnan(pt.z)

"`true` when every coordinate is assigned."
is_fully_specified(pt::Pt) = !isnan(pt.x) && !isnan(pt.y) && !isnan(pt.z)

is_zero(pt::Pt) = pt.x == 0 && pt.y == 0 && pt.z == 0

Base.:+(a::Pt, b::Pt) = Pt(a.x + b.x, a.y + b.y, a.z + b.z)
Base.:-(a::Pt, b::Pt) = Pt(a.x - b.x, a.y - b.y, a.z - b.z)
Base.:-(a::Pt) = Pt(-a.x, -a.y, -a.z)
Base.:*(a::Pt, d::Real) = Pt(a.x * d, a.y * d, a.z * d)
Base.:*(d::Real, a::Pt) = a * d
Base.:/(a::Pt, d::Real) = Pt(a.x / d, a.y / d, a.z / d)

"Componentwise product — a scale with a different factor per axis."
pt_multiply(a::Pt, b::Pt) = Pt(a.x * b.x, a.y * b.y, a.z * b.z)

pt_reverse(a::Pt) = -a

pt_length(pt::Pt) = sqrt(pt.x^2 + pt.y^2 + pt.z^2)
pt_length_square(pt::Pt) = pt.x^2 + pt.y^2 + pt.z^2

pt_distance(a::Pt, b::Pt) = pt_length(a - b)

"The unit vector along `pt`."
pt_normalize(pt::Pt) = pt / pt_length(pt)

"Every unassigned coordinate becomes zero, and the rest keep their value."
convert_nan_to_zero(pt::Pt) = Pt(isnan(pt.x) ? 0.0 : pt.x,
                         isnan(pt.y) ? 0.0 : pt.y,
                         isnan(pt.z) ? 0.0 : pt.z)

with_base_plane_projection(pt::Pt) = Pt(pt.x, pt.y, 0.0)
get_base_plane_length(pt::Pt) = sqrt(pt.x^2 + pt.y^2)
get_base_plane_length_square(pt::Pt) = pt.x^2 + pt.y^2
get_base_plane_distance(a::Pt, b::Pt) = get_base_plane_length(a - b)
get_base_plane_angle(pt::Pt) = atan(pt.y, pt.x)

"`pt` turned by `angle` radians about the z axis. An unassigned point does not turn."
function rotate_base_plane(pt::Pt, angle::Real)
    current = get_base_plane_angle(pt)
    isnan(current) && return pt
    length = get_base_plane_length(pt)
    turned = current + angle
    Pt(cos(turned) * length, sin(turned) * length, pt.z)
end

"`pt` turned a quarter turn in the base plane."
transpose_base_plane(pt::Pt) = Pt(pt.y, -pt.x, pt.z)

with_x(pt::Pt, x::Real) = Pt(x, pt.y, pt.z)
with_y(pt::Pt, y::Real) = Pt(pt.x, y, pt.z)
with_z(pt::Pt, z::Real) = Pt(pt.x, pt.y, z)

# ── Rs ───────────────────────────────────────────────────────────────────────

"""
    Rs(width, height)

A size parallel to the base plane.
"""
struct Rs
    width::Float64
    height::Float64
end

Rs(width::Real, height::Real) = Rs(Float64(width), Float64(height))

rs_nil() = Rs(NaN, NaN)
is_nil(rs::Rs) = isnan(rs.width) && isnan(rs.height)
is_fully_specified(rs::Rs) = !isnan(rs.width) && !isnan(rs.height)
get_diagonal_length(rs::Rs) = sqrt(rs.width^2 + rs.height^2)
area(rs::Rs) = rs.width * rs.height

# ── Rc ───────────────────────────────────────────────────────────────────────

"""
    Rc(pt, rs)
    Rc(x, y, z, width, height)

A rectangle parallel to the base plane, positioned at its **top-left** corner.
"""
struct Rc
    pt::Pt
    rs::Rs
end

Rc(x::Real, y::Real, z::Real, width::Real, height::Real) = Rc(Pt(x, y, z), Rs(width, height))

rc_nil() = Rc(pt_nil(), rs_nil())
is_nil(rc::Rc) = is_nil(rc.pt) && is_nil(rc.rs)

"The rectangle of `size` whose centre is `center`."
rc_from_center_size(center::Pt, size::Rs) =
    Rc(center.x - size.width/2, center.y - size.height/2, center.z, size.width, size.height)

rc_left(rc::Rc) = rc.pt.x
rc_right(rc::Rc) = rc.pt.x + rc.rs.width
rc_top(rc::Rc) = rc.pt.y
rc_bottom(rc::Rc) = rc.pt.y + rc.rs.height
rc_left_top(rc::Rc) = rc.pt
rc_center(rc::Rc) = Pt(rc.pt.x + rc.rs.width/2, rc.pt.y + rc.rs.height/2, rc.pt.z)

rc_center_top(rc::Rc) = Pt(rc.pt.x + rc.rs.width/2, rc.pt.y, rc.pt.z)
rc_center_bottom(rc::Rc) = Pt(rc.pt.x + rc.rs.width/2, rc.pt.y + rc.rs.height, rc.pt.z)
rc_left_center(rc::Rc) = Pt(rc.pt.x, rc.pt.y + rc.rs.height/2, rc.pt.z)
rc_right_center(rc::Rc) = Pt(rc.pt.x + rc.rs.width, rc.pt.y + rc.rs.height/2, rc.pt.z)
rc_right_bottom(rc::Rc) = Pt(rc.pt.x + rc.rs.width, rc.pt.y + rc.rs.height, rc.pt.z)
rc_left_bottom(rc::Rc) = Pt(rc.pt.x, rc.pt.y + rc.rs.height, rc.pt.z)
rc_right_top(rc::Rc) = Pt(rc.pt.x + rc.rs.width, rc.pt.y, rc.pt.z)

rc_contains(rc::Rc, p::Pt) =
    rc.pt.x <= p.x <= rc.pt.x + rc.rs.width && rc.pt.y <= p.y <= rc.pt.y + rc.rs.height

"""
    rc_base_plane_contains(rc, p; strictly = false) -> Bool

Whether `p` is inside `rc`, in the base plane. `strictly` excludes the border.
"""
rc_base_plane_contains(rc::Rc, p::Pt; strictly::Bool = false) =
    strictly ? (rc.pt.x < p.x < rc.pt.x + rc.rs.width && rc.pt.y < p.y < rc.pt.y + rc.rs.height) :
               (rc.pt.x <= p.x <= rc.pt.x + rc.rs.width && rc.pt.y <= p.y <= rc.pt.y + rc.rs.height)

"""
    rc_base_plane_intersects(rc, other; strictly = false) -> Bool

Whether any corner of `rc` falls inside `other`, which is the test
`HeapEmbedding` uses to reject a candidate position. It is the original's test,
corners only, so a rectangle crossing another without a corner inside it is not
reported.
"""
rc_base_plane_intersects(rc::Rc, other::Rc; strictly::Bool = false) =
    rc_base_plane_contains(other, rc_left_top(rc); strictly = strictly) ||
    rc_base_plane_contains(other, rc_right_top(rc); strictly = strictly) ||
    rc_base_plane_contains(other, rc_left_bottom(rc); strictly = strictly) ||
    rc_base_plane_contains(other, rc_right_bottom(rc); strictly = strictly)

# ── Cc ───────────────────────────────────────────────────────────────────────

"""
    Cc(origin, radius)

A circle, parallel to the base plane. `StarTreeEmbedding` models a whole subtree
as one of these and then packs circles rather than rectangles, which is why the
picture it draws reads as a star of stars.
"""
struct Cc
    origin::Pt
    radius::Float64
end

Cc(x::Real, y::Real, z::Real, radius::Real) = Cc(Pt(x, y, z), Float64(radius))

cc_center_top(cc::Cc) = Pt(cc.origin.x, cc.origin.y - cc.radius, cc.origin.z)
cc_center_bottom(cc::Cc) = Pt(cc.origin.x, cc.origin.y + cc.radius, cc.origin.z)
cc_left_center(cc::Cc) = Pt(cc.origin.x - cc.radius, cc.origin.y, cc.origin.z)
cc_right_center(cc::Cc) = Pt(cc.origin.x + cc.radius, cc.origin.y, cc.origin.z)

"""
    cc_intersect(cc, other) -> Vector{Pt}

Where two circles cross, in the base plane: two points, or none when they do not
cross or share an origin.
"""
function cc_intersect(cc::Cc, other::Cc)
    big = cc.radius^2
    small = other.radius^2
    d = get_base_plane_distance(cc.origin, other.origin)
    d2 = d * d
    d2 == 0 && return Pt[]
    a = d2 - small + big
    y2 = (4 * d2 * big - a * a) / (4 * d2)
    y2 < 0 && return Pt[]
    y = sqrt(y2)
    x = a / (2 * d)
    angle = get_base_plane_angle(other.origin - cc.origin)
    Pt[rotate_base_plane(Pt(x, y, 0), angle) + cc.origin,
       rotate_base_plane(Pt(x, -y, 0), angle) + cc.origin]
end

"""
    cc_enclosing(a, b) -> Cc
    cc_enclosing(circles) -> Cc

The smallest circle covering the given ones. The many-circle form folds the
pairwise one from the left, exactly as the original does; that is an
approximation of the true minimum enclosing circle and not the minimum itself.
"""
function cc_enclosing(a::Cc, b::Cc)
    distance = pt_distance(a.origin, b.origin)
    d = distance + max(a.radius, b.radius - distance) + max(b.radius, a.radius - distance)
    pt = Pt(d/2 - max(a.radius, b.radius - distance), 0, 0)
    angle = get_base_plane_angle(b.origin - a.origin)
    Cc(rotate_base_plane(pt, angle) + a.origin, d/2)
end

function cc_enclosing(circles)
    result = first(circles)
    for circle in circles
        result = cc_enclosing(result, circle)
    end
    result
end

"""
    rc_bounding(rectangles) -> Rc

The smallest rectangle covering all of them, or a nil rectangle when there are
none.
"""
function rc_bounding(rectangles)
    left = Inf; top = Inf; right = -Inf; bottom = -Inf
    any = false
    for rc in rectangles
        any = true
        left = min(left, rc_left(rc)); top = min(top, rc_top(rc))
        right = max(right, rc_right(rc)); bottom = max(bottom, rc_bottom(rc))
    end
    any || return rc_nil()
    Rc(left, top, 0.0, right - left, bottom - top)
end

# ── Ln ───────────────────────────────────────────────────────────────────────

"""
    Ln(begin_pt, end_pt)

A segment. The layouters use one only as the answer of
[`rc_base_plane_distance`](@ref), where a `NaN` coordinate means "this axis does
not constrain the direction".
"""
struct Ln
    begin_pt::Pt
    end_pt::Pt
end

Ln(x1::Real, y1::Real, z1::Real, x2::Real, y2::Real, z2::Real) =
    Ln(Pt(x1, y1, z1), Pt(x2, y2, z2))

ln_nil() = Ln(pt_nil(), pt_nil())
is_nil(ln::Ln) = is_nil(ln.begin_pt) && is_nil(ln.end_pt)

"""
    rc_base_plane_distance(rc, other) -> (Ln, Float64)

The shortest segment between two rectangles in the base plane, and its length.

The nine cases are the nine positions `other` can be in relative to `rc` — left,
over, right, and the same again above and below — read off a three-by-three
grid. In the four corner cases the segment joins two corners. In the four edge
cases the rectangles overlap on one axis, so the distance is measured on the
other one alone and the segment carries `NaN` on the axis that does not
constrain it. In the middle case the rectangles overlap and the distance is
zero.
"""
function rc_base_plane_distance(rc::Rc, other::Rc)
    x1 = rc.pt.x; y1 = rc.pt.y; z = rc.pt.z
    x2 = rc.pt.x + rc.rs.width; y2 = rc.pt.y + rc.rs.height
    x3 = other.pt.x; y3 = other.pt.y; z_other = other.pt.z
    x4 = other.pt.x + other.rs.width; y4 = other.pt.y + other.rs.height

    bx = x2 <= x3 ? 0 : (x4 <= x1 ? 2 : 1)
    by = y2 <= y3 ? 0 : (y4 <= y1 ? 2 : 1)

    b = by * 3 + bx
    if b == 0
        (Ln(x2, y2, z, x3, y3, z_other), get_base_plane_distance(Pt(x2, y2, 0), Pt(x3, y3, 0)))
    elseif b == 1
        (Ln(NaN, y2, z, NaN, y3, z_other), y3 - y2)
    elseif b == 2
        (Ln(x1, y2, z, x4, y3, z_other), get_base_plane_distance(Pt(x1, y2, 0), Pt(x4, y3, 0)))
    elseif b == 3
        (Ln(x2, NaN, z, x3, NaN, z_other), x3 - x2)
    elseif b == 4
        (ln_nil(), 0.0)
    elseif b == 5
        (Ln(x1, NaN, z, x4, NaN, z_other), x1 - x4)
    elseif b == 6
        (Ln(x2, y1, z, x3, y4, z_other), get_base_plane_distance(Pt(x2, y1, 0), Pt(x3, y4, 0)))
    elseif b == 7
        (Ln(NaN, y1, z, NaN, y4, z_other), y1 - y4)
    else
        (Ln(x1, y1, z, x4, y4, z_other), get_base_plane_distance(Pt(x1, y1, 0), Pt(x4, y4, 0)))
    end
end

end # module
