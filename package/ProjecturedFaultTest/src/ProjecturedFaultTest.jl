"""
    ProjecturedFaultTest

The Fault tier of the test-package DAG: the suite whose fixtures are fault
reports, the catching barrier and the log panel.

Aggregated by `test_fault()`.
"""
module ProjecturedFaultTest

using Test
using ProjecturedCollection
using ProjecturedFault
using ProjecturedFaultExample
using ProjecturedKernel
using ProjecturedKernelExample
using ProjecturedProjection
using ProjecturedSyntax
using ProjecturedText

export test_fault, test_fault_store, test_fault_report, test_fault_catching,
       test_fault_safe_mode, test_fault_tolerant_projection

include("../../../test/fault/FaultStoreTest.jl")
include("../../../test/fault/FaultCatchingTest.jl")
include("../../../test/fault/FaultSafeModeTest.jl")

test_fault() = @testset "ProjecturedFault" begin
    test_fault_store()
    test_fault_report()
    test_fault_catching()
    test_fault_safe_mode()
    test_fault_tolerant_projection()
end

end # module ProjecturedFaultTest
