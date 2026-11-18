# The two jobs of a stage and the passing of a change to a child. A stage makes an
# operation of a gesture (`read_gesture`) and maps an operation back
# (`map_operation_backward`); the older form of `read_intent` hands each payload
# to the one of the two that reads it, and a 3-argument reader of a projection
# answers before them. A container passes a change to the child that it chose
# with `read_child_intent`: the answer comes back rerooted with its labels, and the
# rules of each level out read it by the rule of a level: with no answer the first
# rule that matches answers, and with an answer a rule replaces it only when its
# `override` condition holds for it.

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

# A text edit, as a text stage answers a typed key with one.
struct JobProbeText <: Operation
    text::String
end
OperationModule.is_self_contained_operation(::JobProbeText) = true
_job_is_text(answer) = answer isa JobProbeText

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
_job_select(name) = (document, gesture, _) -> ReplaceSelectionOperation(EmptyReference())

# The rule that the middle document and the box share, as two nested elements of
# XML share theirs: `<` takes the key back from a text edit only, so the answer of
# an inner part that took it stays.
_job_nest_rule() =
    GestureBinding(KeyPressPattern('<'), (document, gesture, _) -> JobProbeOperation("insert in " * _job_level(document));
                   description = "Insert a part", domain = "test", override = _job_is_text)
_job_level(::Any) = "?"

# The middle document answers a right click and adds a layer to a dwell; the box
# answers a right click, adds a layer to a dwell, and has an override for a left
# click; the tabled document answers a dwell. Both the middle document and the box
# have the shared rule of `<`; the middle document takes `>` back from a text edit,
# and the box has a plain rule of `>` and a rule of `!` that builds its operation
# from the answer.
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeMid}) = GestureBinding[
    GestureBinding(MouseClickPattern(:right), _job_select("mid"); description = "Select the mid", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture, _) -> JobProbeLayers(["mid"]);
                   description = "Show the layer of the mid", domain = "test"),
    _job_nest_rule(),
    GestureBinding(KeyPressPattern('>'), (document, gesture, _) -> JobProbeOperation("mid >");
                   description = "Take > from the text", domain = "test", override = _job_is_text),
]
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeBox}) = GestureBinding[
    GestureBinding(MouseClickPattern(:right), (document, gesture, _) -> JobProbeOperation("box");
                   description = "Answer for the box", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture, _) -> JobProbeLayers(["box"]);
                   description = "Show the layer of the box", domain = "test"),
    GestureBinding(MouseClickPattern(:left), (document, gesture, _) -> JobProbeOperation("box override");
                   description = "Win over the click of a part", domain = "test", override = Returns(true)),
    _job_nest_rule(),
    GestureBinding(KeyPressPattern('>'), (document, gesture, _) -> JobProbeOperation("box >");
                   description = "A plain rule of >", domain = "test"),
    GestureBinding(KeyPressPattern('!'), (document, gesture, answer) -> JobProbeOperation("box saw " * answer.text);
                   description = "Build from the answer", domain = "test", override = _job_is_text),
]
_job_level(::JobProbeMid) = "mid"
_job_level(::JobProbeBox) = "box"
GestureBindingModule.get_document_gesture_bindings_own(::Type{JobProbeTabled}) = GestureBinding[
    GestureBinding(MouseDwellPattern(), (document, gesture, _) -> JobProbeOperation("document table");
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

# A leaf that answers each typed key with a text edit, as a text stage does.
struct JobProbeTextProjection <: Projection end
ProjectionModule.print_document(p::JobProbeTextProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
GestureBindingModule.read_gesture(::JobProbeTextProjection, iomap, key::KeyPress; answer = nothing) =
    JobProbeText(string(key.char))

struct JobProbeClickProjection <: Projection end
ProjectionModule.print_document(p::JobProbeClickProjection, recursion, input, ctx) = SimpleIoMap(p, input, input)
GestureBindingModule.read_gesture(::JobProbeClickProjection, iomap, click::MouseClick; answer = nothing) =
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
    GestureBinding(MouseClickPattern(:right), (document, gesture, _) -> JobProbeOperation("projection table");
                   description = "Answer from the projection", domain = "test"),
    GestureBinding(MouseDwellPattern(), (document, gesture, _) -> JobProbeOperation("projection dwell");
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
    GestureBinding(MouseDwellPattern(), (document, gesture, _) -> JobProbeOperation("wrapper");
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
_job_key(char) = KeyPress(char; time = 0.0)

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
        @test read_gesture(p, iomap, _job_right(); answer = JobProbeOperation("claimed")) === nothing
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
        @test rows == ["Select the mid", "Show the layer of the mid", "Insert a part", "Take > from the text",
                       "Answer for the box", "Show the layer of the box", "Win over the click of a part",
                       "Insert a part", "A plain rule of >", "Build from the answer"]
    end

    @testset "the rule of a level" begin
        # The child answers each key with a text edit; the middle document and the
        # box read the answer, the deepest first.
        iomap = _job_box_iomap(JobProbeTextProjection())
        @testset "a plain rule further out never replaces an answer" begin
            @test _job_read(iomap, _job_key('q')).operation == JobProbeText("q")
        end
        @testset "a rule whose condition holds replaces the answer" begin
            @test _job_read(iomap, _job_key('>')).operation == JobProbeOperation("mid >")
        end
        @testset "a plain rule further out keeps the answer of an override nearer" begin
            # The box has a plain rule of `>`, and the middle document took the key.
            @test _job_read(iomap, _job_key('>')).operation != JobProbeOperation("box >")
        end
        @testset "of two parts with the same rule, the inner one keeps the key" begin
            # The middle document takes `<` back from the text; its answer is no text
            # edit, so the condition of the same rule of the box fails.
            @test _job_read(iomap, _job_key('<')).operation == JobProbeOperation("insert in mid")
        end
        @testset "with no answer, the nearest rule that matches answers" begin
            quiet = _job_box_iomap(JobProbeLeafProjection())
            @test _job_read(quiet, _job_key('<')).operation == JobProbeOperation("insert in mid")
            @test _job_read(quiet, _job_key('>')).operation == JobProbeOperation("mid >")
        end
        @testset "a rule can build its operation from the answer" begin
            @test _job_read(iomap, _job_key('!')).operation == JobProbeOperation("box saw !")
        end
        @testset "an unconditional rule replaces any answer" begin
            click = _job_box_iomap(JobProbeClickProjection())
            @test _job_read(click, _job_left()).operation == JobProbeOperation("box override")
        end
    end

    @testset "a change with a route reaches the child only on its way" begin
        iomap = _job_box_iomap(JobProbeClickProjection())
        on_way = _job_read(iomap, _job_right(); route = extend_reference(EmptyReference(), _JOB_STEPS...))
        @test on_way.operation == JobProbeOperation("click")
        off_way = _job_read(iomap, _job_right(); route = extend_reference(EmptyReference(), FieldReferenceStep("other")))
        @test off_way.operation === nothing
    end

    @testset "a container can give the read of the child, and with no child only its own rules answer" begin
        iomap = _job_box_iomap(JobProbeLeafProjection())
        p = get_iomap_projection(iomap)
        child = only(get_child_iomaps(iomap))
        # The read that the container gives answers for the child, and the levels
        # read that answer: no rule of `q` replaces it.
        given = read_child_intent(p, p, Intent(_job_key('q')), iomap, child, _JOB_STEPS;
                                  read_child = (_, _, change, _) -> Intent(change.gesture, JobProbeText("given")))
        @test given.operation == JobProbeText("given")
        # With no child, the box is the part: the middle document does not read, and
        # the plain rule of the box answers.
        @test read_child_intent(p, p, Intent(_job_key('>')), iomap, nothing).operation ==
              JobProbeOperation("box >")
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
