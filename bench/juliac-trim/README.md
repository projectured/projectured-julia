# juliac trim probe

Development-only measurements that back
[documentation/static-compilation.md](../../documentation/static-compilation.md).
Nothing here is a dependency of anything that ships. The probe is standalone
Julia. It does not load `Projectured`.

The probe answers three questions:

1. When does `juliac --trim` refuse a call on an abstract type, and when does it
   accept the same call on a closed union?
2. Can a library hide the difference, so that the domain code keeps the abstract
   type?
3. Does a small change to the compiler remove the limitation?

## Run it

`probe.jl` builds the same program once for each way to give the argument its
type, then counts the dynamic calls in the whole call graph.

    julia probe.jl inspect            # the fast part, a sweep over 2..6 types
    julia probe.jl inspect 2 16       # the same sweep over a range you choose
    julia probe.jl build-all          # the slow part, real juliac builds
    julia probe.jl build union 4      # one juliac build
    julia probe.jl source abstract 4  # print the generated program

`hide.jl` measures the four ways to hide the narrowing behind one link
definition.

    julia hide.jl                     # the fast part
    julia hide.jl build container     # one real juliac build

`mutable_check.jl` repeats the first sweep with `mutable struct` members, to
show that the result does not come from the inline storage of a bits union.

## The compiler change

`sealed.sh` and `sealed_patch.py` patch the compiler so that `--trim` treats
every abstract type as closed. This part needs Julia 1.13, which ships the
compiler as a swappable package. No rebuild of Julia is needed.

    ./sealed.sh setup     # copy and patch the Compiler package and juliac
    ./sealed.sh build     # build the abstract six subtype program with it
    ./sealed.sh compare   # build the same program with the stock juliac

`setup` writes `SealedCompiler2/`, `sealed-juliac2/` and `env2/` next to the
scripts. All three are working copies. Delete them to start again.

## Add another version of Julia

The probe finds `juliac` next to the Julia that runs it, so `julia +1.13
probe.jl inspect` measures 1.13 with no other change.
