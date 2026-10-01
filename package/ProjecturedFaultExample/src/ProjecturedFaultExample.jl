"""
    ProjecturedFaultExample

The Fault tier of the example-package DAG: one runnable example per fault
category, so a person can watch each barrier work from the REPL. See
[FaultExamples.jl](../../../example/platform/fault/FaultExamples.jl) for the list.
"""
module ProjecturedFaultExample

using Projectured
using ProjecturedPlatform
# The module aliases the umbrella binds are constants, not exports; the
# extensions below name their generics through them.
import Projectured: ProjectionModule, OperationModule, BackendModule
import ProjecturedExample: Example, run_example, make_example_editor
import ProjecturedPlatform: default_backend
import ProjecturedKernelExample: ScriptedLlm, make_scripted_turn, make_scripted_run,
                                 make_scripted_say

include("../../../example/platform/fault/FaultExamples.jl")

export BROKEN_VALUE,
       make_fault_demo_document_example, make_fault_demo_projection_example,
       BrokenStageProjection, ThrowFromEvaluationOperation, BrokenWriteBackend,
       fault_print_example, fault_read_example, fault_evaluate_example,
       fault_map_example,
       run_fault_device_example, run_fault_tool_example
export Example, run_example

end # module ProjecturedFaultExample
