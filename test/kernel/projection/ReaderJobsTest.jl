# The two jobs of a stage and the passing of a change to a child. A stage makes an
# operation of a gesture (`read_gesture`) and maps an operation back
# (`map_operation_backward`); the older form of `read_intent` hands each payload
# to the one of the two that reads it, and a 3-argument reader of a projection
# answers before them. A container passes a change to the child that it chose
# with `read_child_intent`: the answer comes back rerooted with its labels, and the
# rules further out answer by the order of an override.

using Test
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.EventModule
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.GestureModule
import ProjecturedKernel.GestureBindingModule
import ProjecturedKernel.GestureBindingModule: GestureBinding, read_gesture
import ProjecturedKernel.OperationModule
import ProjecturedKernel.OperationModule: Operation, CompoundOperation, ReplaceSelectionOperation

# An operation that names what made it.
struct JobProbeOperation <: Operation
    name::String
end
OperationModule.is_self_contained_operation(::JobProbeOperation) = true

# A layer that collects: the names of the levels that answered, the deepest first.
struct JobProbeLayers <: Operation
    names::Vector{String}
end
OperationModule.is_collecting_operation(::JobProbeLayers) = true
OperationModule.join_collected_operations(inner::JobProbeLayers, outer::JobProbeLayers) =
    JobProbeLayers(vcat(inner.names, outer.names))

@document struct JobProbeLeaf
    name::String = ""
end
@document struct JobProbeMid
    leaf::JobProbeLeaf = JobProbeLeaf()
end
@document struct JobProbeBox
    mid::JobProbeMid = JobProbeMid()
end
@document struct JobProbeTabled
    name::String = ""
end

_job_left() = MouseClick(:left, 1, 2; time = 0.0)
_job_right() = MouseClick(:right, 1, 2, 1, ModifierKeys(); time = 0.0)
_job_dwell() = MouseDwell(1, 2; time = 0.0)
_job_select(name) = (document, gesture) -> ReplaceSelectionOperation(EmptyReference())

# The middle document answers a right click and adds a layer to a dwell; the box
# answers a right click, adds a layer to a dwell, and has an override for a left
# click; the tabled document answers a dwell.
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeMid}) = GestureBinding[
    GestureBinding(MouseClickPattern(:right), _job_select("mid"); description = "Select the mid", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture) -> JobProbeLayers(["mid"]);
                   description = "Show the layer of the mid", domain = "test"),
]
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeBox}) = GestureBinding[
    GestureBinding(MouseClickPattern(:right), (document, gesture) -> JobProbeOperation("box");
                   description = "Answer for the box", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture) -> JobProbeLayers(["box"]);
                   description = "Show the layer of the box", domain = "test"),
    GestureBinding(MouseClickPattern(:left), (document, gesture) -> JobProbeOperation("box override");
                   description = "Win over the click of a part", domain = "test", override = true),
]
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeTabled}) = GestureBinding[
    GestureBinding(MouseDwellPattern(), (document, gesture) -> JobProbeOperation("document table");
                   description = "Answer from the document", domain = "test"),
]

# A leaf with no reader of its own.
struct JobProbeLeafProjection <: Projection end
ProjectionModule.print_document(p::JobProbeLeafProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)

# A leaf that maps one kind of operation back, and one that reads a click.
struct JobProbeMapProjection <: Projection end
ProjectionModule.print_document(p::JobProbeMapProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
ProjectionModule.map_operation_backward(::JobProbeMapProjection, iomap, operation::JobProbeOperation) =
    JobProbeOperation("mapped " * operation.name)

struct JobProbeClickProjection <: Projection end
ProjectionModule.print_document(p::JobProbeClickProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
GestureBindingModule.read_gesture(::JobProbeClickProjection, iomap, click::MouseClick; claimed = nothing) =
    JobProbeOperation("click")

# A leaf with an older reader for one kind of operation, and a new method for it.
struct JobProbeOldProjection <: Projection end
ProjectionModule.print_document(p::JobProbeOldProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
ProjectionModule.read_intent(::JobProbeOldProjection, iomap, operation::JobProbeOperation) =
    JobProbeOperation("old")
ProjectionModule.map_operation_backward(::JobProbeOldProjection, iomap, operation::JobProbeOperation) =
    JobProbeOperation("new")

# A leaf with a gesture table of its own.
struct JobProbeTableProjection <: Projection end
ProjectionModule.print_document(p::JobProbeTableProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
ProjectionModule.get_projection_gesture_bindings(::JobProbeTableProjection, iomap) = GestureBinding[
    GestureBinding(MouseClickPattern(:right), (document, gesture) -> JobProbeOperation("projection table");
                   description = "Answer from the projection", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture) -> JobProbeOperation("projection dwell");
                   description = "Dwell from the projection", domain = "test"),
]

# A box that prints its leaf two steps down, and passes each change to it.
struct JobProbeBoxProjection <: Projection
    inner::Projection
end
const _JOB_STEPS = (FieldReferenceStep("mid"), FieldReferenceStep("leaf"))
function ProjectionModule.print_document(p::JobProbeBoxProjection, recursion, input, ctx)
    child = print_document(p.inner, recursion, input.mid.leaf, ctx)
    ChildrenIoMap(p, input, input, Any[(_JOB_STEPS, child)])
end
ProjectionModule.read_intent(p::JobProbeBoxProjection, recursion, change::Intent, iomap::ChildrenIoMap) =
    read_child_intent(p, recursion, change, iomap, only(get_child_iomaps(iomap)), _JOB_STEPS)

# A wrapper whose child prints the same input, with a gesture table of its own.
struct JobProbeWrapProjection <: Projection
    inner::Projection
end
function ProjectionModule.print_document(p::JobProbeWrapProjection, recursion, input, ctx)
    inner = print_document(p.inner, recursion, input, ctx)
    ContentIoMap(p, input, get_iomap_output(inner), inner)
end
ProjectionModule.get_projection_gesture_bindings(::JobProbeWrapProjection, iomap) = GestureBinding[
    GestureBinding(MouseDwellPattern(), (document, gesture) -> JobProbeOperation("wrapper");
                   description = "Dwell from the wrapper", domain = "test"),
]
ProjectionModule.read_intent(p::JobProbeWrapProjection, recursion, change::Intent, iomap::ContentIoMap) =
    read_child_intent(p, recursion, change, iomap, iomap.inner_iomap)

_job_box_iomap(inner) = (p = JobProbeBoxProjection(inner);
                         print_document(p, p, JobProbeBox(mid = JobProbeMid(leaf = JobProbeLeaf(name = "leaf"))),
                                        PrinterContext()))
_job_read(iomap, gesture; description = "", route = nothing) =
    read_intent(get_iomap_projection(iomap), get_iomap_projection(iomap),
                Intent(gesture, nothing, description, "", route), iomap)
_job_names(collection) = [intent.description for intent in collection.intents]

function test_reader_jobs()
@testset "the two jobs of a stage and the passing to a child" begin
    @testset "the older form hands an operation to map_operation_backward and a gesture to read_gesture" begin
        iomap = print_document(JobProbeMapProjection(), nothing, JobProbeLeaf(), PrinterContext())
        @test read_intent(JobProbeMapProjection(), iomap, JobProbeOperation("x")) == JobProbeOperation("mapped x")
        click = print_document(JobProbeClickProjection(), nothing, JobProbeLeaf(), PrinterContext())
        @test read_intent(JobProbeClickProjection(), click, _job_left()) == JobProbeOperation("click")
        # A payload that is neither a gesture nor an operation answers nothing.
        @test read_intent(JobProbeClickProjection(), click, "neither") === nothing
        # The walk reaches the same two methods.
        walked = read_intent(JobProbeMapProjection(), nothing, Intent(nothing, JobProbeOperation("y")), iomap)
        @test walked.operation == JobProbeOperation("mapped y")
    end

    @testset "an older reader of a projection answers before its new method" begin
        iomap = print_document(JobProbeOldProjection(), nothing, JobProbeLeaf(), PrinterContext())
        @test read_intent(JobProbeOldProjection(), iomap, JobProbeOperation("x")) == JobProbeOperation("old")
        @test map_operation_backward(JobProbeOldProjection(), iomap, JobProbeOperation("x")) == JobProbeOperation("new")
        # A member of a compound goes back through the older form too.
        mapped = map_operation_backward(JobProbeLeafProjection(),
                                        print_document(JobProbeLeafProjection(), nothing, JobProbeLeaf(), PrinterContext()),
                                        CompoundOperation(Any[JobProbeOperation("a")]))
        @test mapped isa CompoundOperation && only(mapped.operations) == JobProbeOperation("a")
    end

    @testset "the default of read_gesture asks the table of the projection, then of the document" begin
        p = JobProbeTableProjection()
        iomap = print_document(p, nothing, JobProbeTabled(), PrinterContext())
        @test read_gesture(p, iomap, _job_right()) == JobProbeOperation("projection table")
        @test read_gesture(p, iomap, _job_dwell()) == JobProbeOperation("projection dwell")
        # A projection with no table gives the gesture to the table of its input.
        leaf = print_document(JobProbeLeafProjection(), nothing, JobProbeTabled(), PrinterContext())
        @test read_gesture(JobProbeLeafProjection(), leaf, _job_dwell()) == JobProbeOperation("document table")
        # A collection holds the rows of both, the projection's first.
        rows = _job_names(read_gesture(p, iomap, CollectIntents()))
        @test rows == ["Answer from the projection", "Dwell from the projection", "Answer from the document"]
        # A claim lets only an override answer, and these tables have none.
        @test read_gesture(p, iomap, _job_right(); claimed = JobProbeOperation("claimed")) === nothing
    end

    @testset "a container passes a change to the child it chose and reroots the answer" begin
        iomap = _job_box_iomap(JobProbeClickProjection())
        answer = _job_read(iomap, _job_right(); description = "outer")
        # The child answers the click; no plain rule further out answers then.
        @test answer.operation == JobProbeOperation("click")
        @test answer.description == "outer"
    end

    @testset "an override rule further out wins over the answer of the child" begin
        iomap = _job_box_iomap(JobProbeClickProjection())
        @test _job_read(iomap, _job_left()).operation == JobProbeOperation("box override")
    end

    @testset "when the child declines, the deepest level that answers wins" begin
        iomap = _job_box_iomap(JobProbeLeafProjection())
        answer = _job_read(iomap, _job_right()).operation
        # The middle document answers before the box, and its path is the step to it.
        @test answer isa ReplaceSelectionOperation
        @test collect(get_reference_steps(strip_reference_types(answer.path))) == [FieldReferenceStep("mid")]
    end

    @testset "an answer that collects is joined with the answer of each level out" begin
        iomap = _job_box_iomap(JobProbeLeafProjection())
        answer = _job_read(iomap, _job_dwell()).operation
        @test answer isa JobProbeLayers && answer.names == ["mid", "box"]
    end

    @testset "a collection holds the rows of the child and of each level out" begin
        iomap = _job_box_iomap(JobProbeLeafProjection())
        rows = _job_names(_job_read(iomap, CollectIntents()).operation)
        @test rows == ["Select the mid", "Show the layer of the mid",
                       "Answer for the box", "Show the layer of the box", "Win over the click of a part"]
    end

    @testset "a change with a route reaches the child only on its way" begin
        iomap = _job_box_iomap(JobProbeClickProjection())
        on_way = _job_read(iomap, _job_right(); route = extend_reference(EmptyReference(), _JOB_STEPS...))
        @test on_way.operation == JobProbeOperation("click")
        off_way = _job_read(iomap, _job_right(); route = extend_reference(EmptyReference(), FieldReferenceStep("other")))
        @test off_way.operation === nothing
    end

    @testset "a wrapper of the same input reads only its own table, and the child reads the document" begin
        p = JobProbeWrapProjection(JobProbeLeafProjection())
        iomap = print_document(p, p, JobProbeTabled(), PrinterContext())
        # The child answers from the table of the input; the wrapper adds no answer.
        @test _job_read(iomap, _job_dwell()).operation == JobProbeOperation("document table")
        # The document's rows come once, then the wrapper's.
        @test _job_names(_job_read(iomap, CollectIntents()).operation) ==
              ["Answer from the document", "Dwell from the wrapper"]
    end
end
end
