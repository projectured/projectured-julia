"""
    MemoryModule

What holds the memory of an editor. [`compute_held_memory`](@ref) walks the
objects that a root reaches through strong references, and gives the bytes that
each holder keeps: the objects that every path from the root to them goes
through the holder. [`describe_held_memory`](@ref) gives the same report as text
for the editor of the session.

The walk needs only Base and the cells of the kernel: a field of a cell gives no
step of the path of a holder.
"""
module MemoryModule

using ..CellModule
using ..AgentModule
using ..ToolModule

export MemoryHolder, HeldType, HeldMemory, compute_held_memory, describe_held_memory

include("MemoryGraph.jl")
include("MemoryDominators.jl")
include("HeldMemory.jl")

end # module
