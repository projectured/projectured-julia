"""Apply the sealed world patch to the copied Compiler package and juliac."""
import sys
here, share = sys.argv[1], sys.argv[2]

def patch(path, old, new, count=1):
    s = open(path).read()
    assert old in s, f"anchor not found in {path}"
    open(path, "w").write(s.replace(old, new, count))

# 1. The seal itself: a flag, a limit, and the test for a qualifying call site.
patch(f"{here}/SealedCompiler2/src/inferencestate.jl",
"function get_max_methods(interp::AbstractInterpreter, @nospecialize(f), sv::AbsIntState)",
"""# --- sealed world probe -------------------------------------------------------
const SEALED_WORLD = Ref(false)
const SEALED_MAX_METHODS = Ref(100)

# A call qualifies when one of its argument types is an abstract type other than
# `Any`. `Any` never qualifies. If it did, inference would try to split every
# generic call in Base and the build would not finish.
function sealed_call(argtypes::Vector{Any})
    for i = 2:length(argtypes)
        a = argtypes[i]
        # A `Vararg` entry is not an ordinary lattice element and `widenconst`
        # raises an error on it.
        isvarargtype(a) && continue
        t = widenconst(a)
        t === Any && continue
        isa(t, DataType) || continue
        Base.isabstracttype(t) && return true
    end
    return false
end
# ------------------------------------------------------------------------------

function get_max_methods(interp::AbstractInterpreter, @nospecialize(f), sv::AbsIntState)""")

# 2. Raise the limit at a qualifying call site only.
patch(f"{here}/SealedCompiler2/src/abstractinterpretation.jl",
"    matches = find_method_matches(interp, argtypes, atype; max_methods)",
"""    # --- sealed world probe ---------------------------------------------------
    if SEALED_WORLD[] && sealed_call(argtypes)
        max_methods = SEALED_MAX_METHODS[]
    end
    # --------------------------------------------------------------------------
    matches = find_method_matches(interp, argtypes, atype; max_methods)""")

# 3. juliac: fix the include that pointed outside the copied directory.
patch(f"{here}/sealed-juliac2/juliac.jl",
'include(joinpath(@__DIR__, "..", "julia-config.jl"))',
f'include("{share}/julia-config.jl")')

# 4. The buildscript: install the compiler, turn the seal on, and forward the
#    compilation roots. Without the forward the trim compile has no root, emits
#    nothing, reports no verifier error, and the link fails on a missing `main`.
patch(f"{here}/sealed-juliac2/juliac-buildscript.jl",
"let include_result = Base.include(Main, ARGS[1])",
"""using Compiler
Compiler.activate!(; reflection = true, codegen = true)
Compiler.SEALED_WORLD[] = true
Core.eval(Base.Compiler, quote
    add_entrypoint(types::Type) = $(Compiler).add_entrypoint(types)
end)

let include_result = Base.include(Main, ARGS[1])""")

patch(f"{here}/sealed-juliac2/juliac-buildscript.jl",
"Core.Compiler._verify_trim_world_age[] = Base.get_world_counter()",
"""Core.Compiler._verify_trim_world_age[] = Base.get_world_counter()
Compiler._verify_trim_world_age[] = Base.get_world_counter()""")

print("sealed patch applied")
