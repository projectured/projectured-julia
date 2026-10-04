# The edits of the editor through its readers, `editor/DocumentEdits.jl`:
# `find_rooted_operation` roots an edit of a part at the deepest place from which
# the readers of the editor carry it to the root.

using Test
using ProjecturedKernel.DeviceModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.IntentModule
using ProjecturedKernel.IoMapModule
using ProjecturedKernel.ProjectionModule
using ProjecturedKernel.ReferenceModule
import ProjecturedKernel.EditorModule
import ProjecturedKernel.EditorModule: Editor, find_rooted_operation
import ProjecturedKernel.OperationModule: ReplaceReferencedValueOperation,
                                          operation_reference, reroot_operation
using ProjecturedKernelExample

@document struct RootedEditLeaf
    value::Int = 0
end

@document struct RootedEditBranch
    leaf::RootedEditLeaf
end

@document struct RootedEditRoot
    branch::RootedEditBranch
end

const _ROUTED_EDIT_STEPS = (FieldReferenceStep("branch"),)

# Follows a route into the field `branch` of its input and no deeper, as the
# reader of a wrapper follows a route into what it wraps. It carries an edit from
# `branch` to the root, and no edit from a place below `branch`.
struct RoutedEditProjection <: Projection end
ProjectionModule.print_document(::RoutedEditProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)
function ProjectionModule.read_intent(::RoutedEditProjection, recursion, change::Intent,
                                      iomap)
    change.route === nothing && return change
    routed = follow_intent_route(change, _ROUTED_EDIT_STEPS...)
    (routed === nothing || !(routed.route isa EmptyReference)) &&
        return Intent(change.gesture, nothing)
    Intent(change.gesture, reroot_operation(routed.operation, _ROUTED_EDIT_STEPS))
end

# Follows no route: the default reader answers no operation for a route.
struct UnroutedEditProjection <: Projection end
ProjectionModule.print_document(::UnroutedEditProjection, recursion, input, ctx) =
    SimpleIoMap(nothing, input, input)

function _rooted_edit_editor(projection)
    document = RootedEditRoot(RootedEditBranch(RootedEditLeaf()))
    editor = Editor(document, projection; backend = HeadlessBackend(), devices = Device[])
    # a reader is only reached once an iomap exists
    EditorModule.run_print_stage!(editor)
    editor
end

function test_editor_document_edits()
@testset "the edits of the editor through its readers" begin
    target = Reference(FieldReferenceStep("branch"), FieldReferenceStep("leaf"),
                       FieldReferenceStep("value"))

    @testset "an edit is rooted at the deepest place that a reader carries" begin
        editor = _rooted_edit_editor(RoutedEditProjection())
        relatives = Any[]
        rooted = find_rooted_operation(editor, target, function (relative)
            push!(relatives, strip_reference_types(relative))
            ReplaceReferencedValueOperation(nothing, relative, 5)
        end)
        # The place `branch.leaf` is tried first, and no reader carries an edit
        # from it; the place `branch` is tried next.
        @test relatives == [Reference(FieldReferenceStep("value")),
                            Reference(FieldReferenceStep("leaf"),
                                      FieldReferenceStep("value"))]
        @test rooted isa ReplaceReferencedValueOperation
        @test strip_reference_types(operation_reference(rooted)) == target
        @test rooted.value == 5
    end

    @testset "no place that a reader carries answers nothing" begin
        editor = _rooted_edit_editor(UnroutedEditProjection())
        rooted = find_rooted_operation(editor, target,
                                       relative -> ReplaceReferencedValueOperation(
                                           nothing, relative, 5))
        @test rooted === nothing
    end
end
end

export test_editor_document_edits
