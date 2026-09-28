# A change with a route. The kernel's default reader walks the route of a change
# into the child of a container that the route names, and the child reads a
# gesture with the rest of the route as the part it is for. So a gesture reaches
# a part by its reference, never by a position, and a container needs no code of
# its own for it.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.ReferenceModule
import ProjecturedKernel.OperationModule: ReplaceSelectionOperation
using ProjecturedKernel.GestureModule
import ProjecturedKernel.GestureBindingModule
import ProjecturedKernel.GestureBindingModule: GestureBinding
import ProjecturedKernel.OperationModule
import ProjecturedKernel.OperationModule: Operation

@document struct RouteProbeLeaf
    name::String = ""
end

@document struct RouteProbeBox
    first::RouteProbeLeaf = RouteProbeLeaf()
    second::RouteProbeLeaf = RouteProbeLeaf()
end

# A leaf that records what reaches it, and answers a selection of itself.
struct RouteProbeLeafProjection <: Projection
    log::Vector{Any}
end
ProjectionModule.print_document(p::RouteProbeLeafProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
function ProjectionModule.read_intent(p::RouteProbeLeafProjection, recursion, change::Intent,
                                      iomap::SimpleIoMap)
    push!(p.log, (iomap.input, change.gesture, change.route))
    Intent(change.gesture, ReplaceSelectionOperation(EmptyReference()))
end

# A container of two leaves, with no reader of its own.
struct RouteProbeBoxProjection <: Projection
    leaf::RouteProbeLeafProjection
end
function ProjectionModule.print_document(p::RouteProbeBoxProjection, recursion, input, ctx)
    first = print_document(p.leaf, recursion, input.first, ctx)
    second = print_document(p.leaf, recursion, input.second, ctx)
    ChildrenIoMap(p, input, input, Any[(0, 0, first), (0, 10, second)])
end

# A transparent wrapper: its child prints the same input.
struct RouteProbeWrapProjection <: Projection
    inner::Projection
end
function ProjectionModule.print_document(p::RouteProbeWrapProjection, recursion, input, ctx)
    inner = print_document(p.inner, recursion, input, ctx)
    ContentIoMap(p, input, get_iomap_output(inner), inner)
end

_route_probe_enter() = MouseEnter(1, 2; time = 0.0)
_route_probe_path(steps...) = extend_reference(EmptyReference(), steps...)

function _route_probe_setup()
    log = Any[]
    box = RouteProbeBox(first = RouteProbeLeaf(name = "first"),
                        second = RouteProbeLeaf(name = "second"))
    projection = RouteProbeBoxProjection(RouteProbeLeafProjection(log))
    (log, box, projection, print_document(projection, projection, box, PrinterContext()))
end

# A room holds a box, and the box holds a leaf. The leaf has no table; the box and
# the room answer a dwell with a layer that collects, and a right click with an
# operation that does not. The log names each table that is read.
@document struct OutProbeLeaf
    name::String = ""
end
@document struct OutProbeBox
    leaf::OutProbeLeaf = OutProbeLeaf()
end
@document struct OutProbeRoom
    box::OutProbeBox = OutProbeBox()
end

# An operation that collects: the names of the parts that answered, inner first.
struct OutProbeLayers <: Operation
    names::Vector{String}
end
OperationModule.is_collecting_operation(::OutProbeLayers) = true
OperationModule.join_collected_operations(inner::OutProbeLayers, outer::OutProbeLayers) =
    OutProbeLayers(vcat(inner.names, outer.names))

const OUT_PROBE_LOG = String[]

function _out_probe_bindings(name)
    GestureBinding[
        GestureBinding(MouseDwellPattern(),
                       (document, gesture) -> (push!(OUT_PROBE_LOG, name); OutProbeLayers([name]));
                       description = "Show the layer of the $name", domain = "test"),
        GestureBinding(MouseClickPattern(:right),
                       (document, gesture) -> (push!(OUT_PROBE_LOG, name);
                                               ReplaceSelectionOperation(EmptyReference()));
                       description = "Select the $name", domain = "test"),
    ]
end
GestureBindingModule.get_document_gesture_bindings_own(::Type{OutProbeBox}) = _out_probe_bindings("box")
GestureBindingModule.get_document_gesture_bindings_own(::Type{OutProbeRoom}) = _out_probe_bindings("room")

# A leaf with no reader of its own, so the default reader asks its table; and a
# container of one child in `field`, with no reader of its own.
struct OutProbeLeafProjection <: Projection end
ProjectionModule.print_document(p::OutProbeLeafProjection, recursion, input, ctx) =
    SimpleIoMap(p, input, input)
struct OutProbeHolderProjection <: Projection
    field::Symbol
    inner::Projection
end
function ProjectionModule.print_document(p::OutProbeHolderProjection, recursion, input, ctx)
    child = print_document(p.inner, recursion, getproperty(input, p.field), ctx)
    ChildrenIoMap(p, input, input, Any[(0, 0, child)])
end

function _out_probe_setup()
    empty!(OUT_PROBE_LOG)
    room = OutProbeRoom(box = OutProbeBox(leaf = OutProbeLeaf(name = "leaf")))
    projection = OutProbeHolderProjection(:box, OutProbeHolderProjection(:leaf, OutProbeLeafProjection()))
    (room, projection, print_document(projection, projection, room, PrinterContext()))
end

_out_probe_read(projection, iomap, gesture, route) =
    read_intent(projection, projection, Intent(gesture, nothing, "", "", route), iomap).operation

function test_routed_change()
@testset "a change with a route" begin
    @testset "a dwell that its part does not answer goes out, and each part that collects adds its layer" begin
        room, projection, iomap = _out_probe_setup()
        route = _route_probe_path(FieldReferenceStep("box"), FieldReferenceStep("leaf"))
        answer = _out_probe_read(projection, iomap, MouseDwell(1, 2; time = 0.0), route)
        # The leaf has no table; the box answers, and the room adds its layer.
        @test answer isa OutProbeLayers
        @test answer.names == ["box", "room"]
        @test OUT_PROBE_LOG == ["box", "room"]
    end

    @testset "the nearest part that answers wins, and an answer that does not collect ends the search" begin
        room, projection, iomap = _out_probe_setup()
        route = _route_probe_path(FieldReferenceStep("box"), FieldReferenceStep("leaf"))
        answer = _out_probe_read(projection, iomap, MouseClick(:right, 1, 2, 1, ModifierKeys(); time = 0.0),
                                 route)
        @test answer isa ReplaceSelectionOperation
        # The box answered for itself: its path is the step to it.
        @test answer.path == _route_probe_path(FieldReferenceStep("box"))
        @test OUT_PROBE_LOG == ["box"]
    end

    @testset "a gesture for a container itself is read with its own table" begin
        room, projection, iomap = _out_probe_setup()
        box_iomap = only(get_child_iomaps(iomap))
        answer = read_routed_intent(box_iomap.projection, projection,
                                    Intent(MouseDwell(1, 2; time = 0.0), nothing, "", "", EmptyReference()),
                                    box_iomap).operation
        @test answer isa OutProbeLayers && answer.names == ["box"]
    end

    @testset "an operation on its way to its place is read by no table" begin
        room, projection, iomap = _out_probe_setup()
        route = _route_probe_path(FieldReferenceStep("box"), FieldReferenceStep("leaf"))
        prepared = ReplaceSelectionOperation(EmptyReference())
        read_intent(projection, projection, Intent(nothing, prepared, "", "", route), iomap)
        @test isempty(OUT_PROBE_LOG)
    end

    @testset "a gesture reaches the child its route names, and the child reads it" begin
        log, box, projection, iomap = _route_probe_setup()
        route = _route_probe_path(FieldReferenceStep("second"))
        change = Intent(_route_probe_enter(), nothing, "", "", route)
        answer = read_intent(projection, projection, change, iomap)
        @test length(log) == 1
        @test log[1][1] === box.second
        @test log[1][2] == _route_probe_enter()
        @test log[1][3] isa EmptyReference
        # The answer comes back rerooted by the step the route took.
        @test answer.operation isa ReplaceSelectionOperation
        @test answer.operation.path == route
    end

    @testset "a route deeper than a leaf gives the leaf the rest of the route" begin
        log, box, projection, iomap = _route_probe_setup()
        route = _route_probe_path(FieldReferenceStep("first"), FieldReferenceStep("name"))
        read_intent(projection, projection, Intent(_route_probe_enter(), nothing, "", "", route), iomap)
        @test length(log) == 1
        @test log[1][1] === box.first
        @test log[1][3] == _route_probe_path(FieldReferenceStep("name"))
    end

    @testset "an operation at its place is the answer, and the place is not read" begin
        log, box, projection, iomap = _route_probe_setup()
        route = _route_probe_path(FieldReferenceStep("second"))
        prepared = ReplaceSelectionOperation(_route_probe_path(FieldReferenceStep("name")))
        answer = read_intent(projection, projection, Intent(nothing, prepared, "", "", route), iomap)
        @test isempty(log)
        @test answer.operation.path ==
              _route_probe_path(FieldReferenceStep("second"), FieldReferenceStep("name"))
    end

    @testset "a gesture for the container itself, or for nothing it prints, gets no answer" begin
        log, box, projection, iomap = _route_probe_setup()
        itself = read_routed_intent(projection, projection,
                                    Intent(_route_probe_enter(), nothing, "", "", EmptyReference()),
                                    iomap)
        @test itself.operation === nothing
        missing_part = _route_probe_path(FieldReferenceStep("missing"))
        nowhere = read_intent(projection, projection,
                              Intent(_route_probe_enter(), nothing, "", "", missing_part), iomap)
        @test nowhere.operation === nothing
        @test isempty(log)
    end

    @testset "a child that prints the input of its container gets the whole route" begin
        log, box, projection, _ = _route_probe_setup()
        wrapper = RouteProbeWrapProjection(projection)
        iomap = print_document(wrapper, wrapper, box, PrinterContext())
        @test get_child_iomaps(iomap) isa AbstractVector
        route = _route_probe_path(FieldReferenceStep("second"))
        answer = read_intent(wrapper, wrapper, Intent(_route_probe_enter(), nothing, "", "", route),
                             iomap)
        @test length(log) == 1 && log[1][1] === box.second
        @test answer.operation.path == route
    end

    @testset "a change with no route is read as before" begin
        log, box, projection, iomap = _route_probe_setup()
        @test get_child_iomaps(SimpleIoMap(nothing, box, box)) === nothing
        read_intent(projection, projection, Intent(_route_probe_enter()), iomap)
        @test isempty(log)
    end
end
end # test_routed_change
