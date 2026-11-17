alice = 1 + 2
# A module with each kind of Julia code that the editor shows.
module Sample

using Base: show
import Base.length
export Point, area

#= A comment of
   two lines. =#

const LIMIT = 10

abstract type Shape end

"""
A point of the plane.
"""
struct Point{T} <: Shape
    x::T
    y::T
end

const Points = Vector{Point{T}} where {T}

function area end

function area(p::Point{T}; scale = 1.5) where {T<:Real}
    total = p.x * p.y * scale  # the area
    return -total
end

describe(::Point) = "point"
double(f, xs...) = f.(xs)

let names = (:a, 'b', "c $(LIMIT) d", nothing, true, [1, 2.5]), entry = (; count = 2, label = "two")
    for (index, value) in enumerate(names)
        index > 3 && break
        isodd(index) ? println(value) : continue
    end
    while false
    end
    if entry.count == 1
        @show entry
    elseif entry.count == 2
        squares = [x^2 for x in 1:LIMIT if iseven(x)]
    else
        begin
            nothing
        end
    end
    try
        map(names) do name
            name
        end
    catch exception
        rethrow()
    end
    x -> x + 1
    (x; y = 1) -> x + y
    words = Vector{String}(undef, 1)[1:end]; first(words)
end

end

ready = true; done = false
