# Static compilation with juliac

`juliac --trim` builds a small executable from Julia code. It emits only the
code that it can prove reachable from the entry point. When it meets a call that
it can not resolve, it stops with a verifier error.

This guide states the one rule that decides whether a call resolves, shows what
that rule costs ProjecturEd, and gives four ways to keep an abstract type and
still compile. The probe that measured every number is in
[bench/juliac-trim/](../tool/juliac-trim/).

## The rule

A call on a **closed union** always resolves. A call on an **abstract type**
resolves only while the number of matching methods stays at or below three.

Three is the default value of `max_methods`. Under that limit the optimizer
splits the call into a chain of `isa` tests that ends in
`Core.throw_methoderror`. Over that limit the optimizer gives up. It emits one
dynamic call, the return type falls to `Any`, and the trim verifier stops:

```
Verifier error: unresolved call from statement
  Main.Probe_abstract_4.area(φ ()::Main.Probe_abstract_4.Shape)::Any
```

The probe builds the same program many times. Every version has the same number
of concrete types and the same number of methods. Only the declared type of the
container and of the argument changes.

```
kind                    n=2    n=3    n=4    n=5    n=6   n=16
--------------------------------------------------------------
union                     .      .      .      .      .      .
abstract                  .      .      3      3      3      3
```

`.` means no dynamic call. Real `juliac --output-exe --experimental --trim=safe`
builds agree exactly: `union n=4` builds, `abstract n=3` builds, `abstract n=4`
fails.

The difference is therefore not "union against abstract type" alone. It appears
at the fourth concrete type.

## The rule does not change with the Julia version

Julia 1.12.6 and 1.13.0-rc3 give the same table, the same build results, and the
same verifier message. The parameters that govern the split are equal:

| `Base.Compiler.InferenceParams()` | 1.12.6 | 1.13.0-rc3 |
| --- | --- | --- |
| `max_methods` | 3 | 3 |
| `max_union_splitting` | 4 | 4 |
| `max_apply_union_enum` | 8 | 8 |

Neither version has a sealed type or a final type. Nothing in `Base` declares
that an abstract type has a complete set of subtypes.

## What the rule costs ProjecturEd

Every core abstraction in the kernel is an abstract type with many concrete
subtypes. These are the counts of a loaded `Projectured`:

| Abstract type | Direct subtypes | Concrete |
| --- | --- | --- |
| `Projection` | 410 | 407 |
| `IoMap` | 70 | 70 |
| `Document` | 61 | 1 |
| `Operation` | 54 | 53 |
| `ReferenceStep` | 10 | 10 |
| `Backend` | 1 | 1 |

Every one of these except `Document` and `Backend` is far over the limit of
three. A call that reads such a value out of an abstract container and then
dispatches on it blocks `--trim` today.

## Keep the abstract type: one link definition

One definition links the abstract type to the closed union:

```julia
sealed_union(::Type{Shape}) = Union{Shape1, ..., Shape6}
```

Everything else derives from that link. The derived step is a single type
assert, not a chain of `isa` tests:

```julia
@inline narrow(value::Shape) = value::sealed_union(Shape)
```

Inference folds `sealed_union(Shape)` away, because the method is constant on a
type. The type assert then refines the value to the union, and the ordinary
union split takes over.

The four variants below differ only in where the `narrow` call hides. The probe
measures all four with six concrete types, which is double the limit. All four
give no dynamic call, and the `container` variant builds a real executable.

| variant | where `narrow` hides | what the domain code writes |
| --- | --- | --- |
| `assert` | at the call site | `area(narrow(shape))` |
| `container` | in `getindex` of a wrapper vector | `for shape in shapes` |
| `field` | in a field accessor | `area(shape(cell))` |
| `derived` | a macro writes `narrow` from the link | the same as `assert` |

The `container` variant is the strongest. It names no union and calls no
`narrow`. The field of the struct and the loop keep the abstract type.

### Where this repository would put it

No code in this repository uses the technique yet. When it does, the narrowing
belongs in the two places that nearly every abstract value passes through:

1. The element access of a cell vector.
2. The field accessors that `@document` generates.

A domain package then keeps its abstract types and gains the split for free.

### What it costs

The split code grows linearly, at about six intermediate representation
statements for each concrete type at each call site. Inference stays fast even
at the scale of `Projection`:

| concrete types | statements | inference |
| --- | --- | --- |
| 4 | 100 | 0.07 s |
| 25 | 226 | 0.00 s |
| 100 | 676 | 0.01 s |
| 400 | 2476 | 0.07 s |

A large hierarchy therefore works, but it makes a large function at each call
site. Apply the narrowing where the dispatch is hot, not everywhere.

## A second rule: an error message must hold no interpolation

`--trim` also rejects the string machinery that an interpolation pulls in. This
message fails with two unresolved calls, `Base.print` and `Base._str_sizehint`:

```julia
throw(ErrorException("the seal of $(T) does not list this subtype"))
```

A constant string compiles. The type assert of `narrow` has no such problem,
because the runtime raises its `TypeError`.

## Change the compiler instead

`--trim` compiles a closed world. No new subtype can appear, so every abstract
type is already closed and the compiler may split any call. The probe carries
out that change. Julia 1.13 ships its compiler as a swappable package, so no
rebuild of Julia is needed.

The patch adds a flag and one test to `Compiler`, and raises the limit at a
qualifying call site in `abstract_call_gf_by_type`:

```julia
if SEALED_WORLD[] && sealed_call(argtypes)
    max_methods = SEALED_MAX_METHODS[]
end
```

A call qualifies when one of its argument types is an abstract type other than
`Any`. With the patch, the program that the stock `juliac` rejects builds and
runs:

| program | stock juliac | sealed juliac |
| --- | --- | --- |
| abstract type, 6 subtypes | failed, 8 verifier errors | built, exit code 21, 1 789 112 bytes |
| union, 6 members | built, exit code 21, 1 769 744 bytes | — |

The sealed build is 1.1 percent larger. The extra bytes are the
`throw_methoderror` paths.

This needs no seal annotation and no link definition. The link is only needed
while the compiler stays unchanged.

### Three traps

1. **A limit raised everywhere does not work.** A patch in `get_max_methods`
   covers every call. Inference then tries to split `println(Any...)` across a
   hundred methods and the build does not finish. The limit must rise only at a
   call site that has an abstract argument type other than `Any`.
2. **`widenconst` raises an error on a `Vararg` entry.** `argtypes` is not a
   vector of ordinary types. Skip such an entry with `isvarargtype`.
3. **The compilation roots go to the wrong compiler.**
   `Base.Experimental.entrypoint` pushes into the built-in `Base.Compiler`, not
   the active one. Without a forward, the trim compile has no root. It then
   emits nothing, reports no verifier error, and fails at the link step with
   `undefined reference to main`. A clean verifier report is not proof that the
   program compiled.

## How to choose

1. If the hierarchy is small and the dispatch is hot, seal it at the storage
   boundary. Put the narrowing in the container or in the field accessor.
2. If a message can carry a value, write the value with a separate statement.
   Keep the message constant.
3. If you control the build of the compiler, prefer the compiler change. It
   needs no change to the domain code at all.
