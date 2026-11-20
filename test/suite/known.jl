# ============================================================================
# The known violations of a guard: the violations that main has, each with its
# reason, so that the guard fails only on a new one.
#
# A guard keeps a list of `key => reason` pairs. The key is the text of a
# violation without the line number after its file, so an entry stays true when
# a line above it changes. Each entry excuses one violation with its key. A
# violation that no entry excuses fails the guard, and so does an entry that
# excuses nothing, so the list can not go stale. The test of a guard counts each
# excused violation as broken.
#
# Each guard includes this file when its module does not have it yet, so a guard
# runs on its own and the guards share one module in ProjecturedTest. On its own,
# this file checks nothing.
# ============================================================================

"""
    known_violation_key(violation) -> String

The text of a violation without the line number after its file:
`"source/A.jl:12 f takes …"` becomes `"source/A.jl f takes …"`.
"""
known_violation_key(violation::AbstractString) =
    replace(violation, r"^([^\s:]+):\d+" => s"\1"; count = 1)

"""
    split_known_violations(violations, known; list_name) -> (; new, listed, stale)

Split the violations of a guard by its list `known` of `key => reason` pairs.
`new` holds the violations that no entry excuses, `listed` the excused ones, and
`stale` one message for each entry that excuses no violation, which names the
list `list_name` to remove it from.
"""
function split_known_violations(violations, known; list_name::AbstractString)
    left = String[first(entry) for entry in known]
    new = String[]
    listed = String[]
    for violation in violations
        k = findfirst(==(known_violation_key(violation)), left)
        if k === nothing
            push!(new, violation)
        else
            deleteat!(left, k)
            push!(listed, violation)
        end
    end
    stale = String["$key: is not a violation now; remove it from $list_name" for key in left]
    (; new, listed, stale)
end
