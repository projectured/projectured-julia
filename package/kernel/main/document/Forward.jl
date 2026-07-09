# Fragment of `DocumentModule` — the `@forward*` family: helpers that expose a
# nested field's protocol on a wrapper document by generating delegating methods,
# so a compound document that delegates to one field need not hand-write one
# method per forwarded function. Split out of `Document.jl` (the `@document` macro
# and value protocol), it shares the same `DocumentModule` namespace and is
# included right after it — see `DocumentModule.jl`. The forwarded fields are read
# through `getproperty`, so they see the unwrapped value of a `@document` Cell
# field.

# Build one delegating method per function: `f(x::T, args...) =
# f(getproperty(x, :field), args...)`. Shared by `@forward` and the presets.
function _forward_defs(T, field, fns)
    fieldsym = QuoteNode(field)
    defs = map(fns) do f
        :($(esc(f))(x::$(esc(T)), args...; kw...) =
              $(esc(f))(Base.getproperty(x, $fieldsym), args...; kw...))
    end
    Expr(:block, defs...)
end

"""
    @forward T field [f₁, f₂, …]

Generate delegating methods that forward each listed function on `T` to the
value of `T`'s `field`. For example

    @forward Wrapper items [Base.length, Base.getindex]

emits

    Base.length(x::Wrapper, args...; kw...)   = Base.length(x.items, args...; kw...)
    Base.getindex(x::Wrapper, args...; kw...)  = Base.getindex(x.items, args...; kw...)

so a wrapper type can expose its field's protocol (e.g. a backing vector's
interface) without hand-writing one method per function. The field is read
through `getproperty`, so it sees the unwrapped value of a `@document` Cell
field.
"""
macro forward(T, field, fns)
    (fns isa Expr && fns.head === :vect) ||
        error("@forward: third argument must be a vector literal of functions, e.g. [Base.length, Base.size]")
    _forward_defs(T, field, fns.args)
end

# The canonical vector protocol forwarded by `@forward_vector`.
const _VECTOR_PROTOCOL = [:(Base.size), :(Base.length), :(Base.isempty),
    :(Base.firstindex), :(Base.lastindex), :(Base.eachindex),
    :(Base.getindex), :(Base.setindex!), :(Base.iterate),
    :(Base.push!), :(Base.pop!), :(Base.insert!), :(Base.deleteat!)]

"""
    @forward_vector T field

Expose `T` as a vector over its `field` by forwarding the whole vector protocol
(`size`/`length`/`isempty`/`firstindex`/`lastindex`/`eachindex`/`getindex`/
`setindex!`/`iterate`/`push!`/`pop!`/`insert!`/`deleteat!`) to it. A preset of
`@forward` for the common case where `field` (e.g. a `CellVector`) already
implements that protocol.
"""
macro forward_vector(T, field)
    _forward_defs(T, field, _VECTOR_PROTOCOL)
end

"""
    @forward_map T field keyfield valfield EntryCtor

Expose `T` as an ordered associative map stored as `field` (a `CellVector` of
entry documents). Generates `getindex`/`setindex!`/`haskey`/`keys`/`values`/
`get`/`delete!` and a pair-`iterate`, all by linear scan over `field`:

- `keyfield` / `valfield` — the entry's key/value fields (read via `getproperty`).
- `EntryCtor` — called as `EntryCtor(key, value)` to build a fresh entry on insert.

Unlike `@forward_vector` this is not a pure pass-through: the `CellVector` is
integer-indexed and iterates *values*, so the keyed methods translate between a
key and its matching entry. `setindex!` replaces the first matching entry (whole
entry) else appends; `delete!` removes every match.
"""
macro forward_map(T, field, keyfield, valfield, ctor)
    f, k, v = QuoteNode(field), QuoteNode(keyfield), QuoteNode(valfield)
    Te, ctore = esc(T), esc(ctor)
    quote
        Base.haskey(j::$Te, key::AbstractString) =
            any(e -> Base.getproperty(e, $k) == key, Base.getproperty(j, $f))
        Base.keys(j::$Te)   = [Base.getproperty(e, $k) for e in Base.getproperty(j, $f)]
        Base.values(j::$Te) = [Base.getproperty(e, $v) for e in Base.getproperty(j, $f)]

        function Base.getindex(j::$Te, key::AbstractString)
            for e in Base.getproperty(j, $f)
                Base.getproperty(e, $k) == key && return Base.getproperty(e, $v)
            end
            throw(KeyError(key))
        end

        function Base.setindex!(j::$Te, val, key::AbstractString)
            cv = Base.getproperty(j, $f)
            for i in eachindex(cv)
                if Base.getproperty(cv[i], $k) == key
                    cv[i] = $ctore(key, val)
                    return val
                end
            end
            push!(cv, $ctore(key, val))
            return val
        end

        function Base.delete!(j::$Te, key::AbstractString)
            cv = Base.getproperty(j, $f)
            for i in length(cv):-1:1
                Base.getproperty(cv[i], $k) == key && deleteat!(cv, i)
            end
            return j
        end

        Base.get(j::$Te, key::AbstractString, default) =
            haskey(j, key) ? j[key] : default

        function Base.iterate(j::$Te, state=1)
            cv = Base.getproperty(j, $f)
            state > length(cv) && return nothing
            e = cv[state]
            ((Base.getproperty(e, $k), Base.getproperty(e, $v)), state + 1)
        end
    end
end
