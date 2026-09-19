# Fragment of `GraphModule`.
#
# The layouters' own random number generator, ported from the original's
# `src/common/lcgrandom.h` and `.cc`.
#
# Both ported layouters need random numbers — one to scatter its start positions,
# the other to draw most of its own parameters — and both must answer the same
# picture twice. A shared session generator cannot promise that, because whoever
# else drew from it in between changes the answer. So a layouter carries its own
# generator and its own seed, exactly as `GraphLayouter::setSeed` does, and a seed
# plus a graph is a picture.
#
# This is the minimal standard generator of Park and Miller: `seed = 16807 * seed
# mod (2^31 - 1)`, evaluated by Schrage's method so that it never overflows.
"The largest seed the generator accepts: `2^31 - 2`."
const GLRAND_MAX = Int32(0x7ffffffe)

"""
    LcgRandom(seed = 1)

A generator on `[0, 1)`. `seed` must be in `1:GLRAND_MAX`; the window of the original seeds a module
type with 1 the first time it lays that type out, so 1 is the default here too.

Constructing one consumes three values, which is what `LCGRandom::setSeed` does:
a small seed otherwise leaks into the first few draws.
"""
mutable struct LcgRandom
    seed::Int32

    function LcgRandom(seed::Integer = 1)
        random = new(Int32(1))
        set_seed!(random, seed)
        random
    end
end

"""
    set_seed!(random, seed) -> random

Restart `random` at `seed`, then consume three values.
"""
function set_seed!(random::LcgRandom, seed::Integer)
    (1 <= seed <= GLRAND_MAX) || throw(ArgumentError(
        "LcgRandom: invalid seed $seed, expected 1:$(GLRAND_MAX)."))
    random.seed = Int32(seed)
    draw_uniform01!(random); draw_uniform01!(random); draw_uniform01!(random)
    random
end

"""
    draw_uniform01!(random) -> Float64

The next value, in `[0, 1)`.
"""
function draw_uniform01!(random::LcgRandom)
    a = 16807; q = 127773; r = 2836
    seed = Int64(random.seed)
    seed = a * (seed % q) - r * div(seed, q)
    seed <= 0 && (seed += Int64(GLRAND_MAX) + 1)
    random.seed = Int32(seed)
    seed / (Float64(GLRAND_MAX) + 1)
end

"""
    draw_uniform!(random, a, b) -> Float64

The next value, mapped onto `[a, b)`.
"""
draw_uniform!(random::LcgRandom, a::Real, b::Real) = a + draw_uniform01!(random) * (b - a)

"""
    draw!(random, range) -> Int

The next value, mapped onto `0:range-1`.
"""
draw!(random::LcgRandom, range::Integer) = floor(Int, range * draw_uniform01!(random))

"""
    run_lcg_self_test() -> Int32

Ten thousand draws from seed 1, and the seed they leave behind. the original runs
this the first time the generator is used and expects 1043618065; a port that
answers anything else is not the same generator, and every ported layout would
be a different picture. A test asserts it rather than a constructor.
"""
function run_lcg_self_test()
    random = LcgRandom(1)
    random.seed = Int32(1)          # the self test starts raw, with nothing consumed
    for _ in 1:10000
        draw_uniform01!(random)
    end
    random.seed
end
