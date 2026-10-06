# Fragment of `DocumentModule` — the declared type of a field as a contract. The
# setter and the constructor that `@document` emits for the cell layout ask the
# check here, so a value that the declared type of its field does not admit is
# found at the write that makes it. The mode says what the check does with such a
# value: nothing, keep a record of it for an inventory, or throw.

"""
    DeclaredTypeMismatchException(owner, name, declared_type, value)

Thrown when a write gives a field a value that the declared type of the field
does not admit. `owner` is the type of the document, `name` is the field,
`declared_type` is the type that `@document` records for the field, and `value`
is the value of the write.

Its message names the place, the declared type and the type of the value in one
sentence, so that a person and a model can read what went wrong.
"""
struct DeclaredTypeMismatchException <: Exception
    owner::Any
    name::Any
    declared_type::Any
    value::Any
end

function Base.showerror(io::IO, e::DeclaredTypeMismatchException)
    print(io, "DeclaredTypeMismatchException: ", _describe_mismatch_place(e.owner, e.name),
          " is declared ", e.declared_type, ", and the write gives a ",
          _describe_mismatch_type(e.value), ": ", _describe_mismatch_value(e.value))
end

# `JsonBool.value` for a field, `JsonArray[3]` for an element, and the owner alone
# for a place with no name.
function _describe_mismatch_place(owner, name)
    owner_name = string(_describe_mismatch_owner(owner))
    name === nothing && return "a place of " * owner_name
    text = string(name)
    startswith(text, "[") ? owner_name * text : owner_name * "." * text
end

_describe_mismatch_owner(owner::Type) = get_document_schema_name(owner)
_describe_mismatch_owner(owner) = owner

_describe_mismatch_type(value::Document) = get_document_schema_name(typeof(value))
_describe_mismatch_type(value) = typeof(value)

function _describe_mismatch_value(value)
    text = repr(value; context = :limit => true)
    length(text) <= 80 ? text : first(text, 77) * "..."
end

"""
    PendingValue

A value that stands in a field for a value that a later step makes, as a
`Computation` stands for the value that its cell computes. A template rule builds
its output with such stand-ins, and the print replaces each one with the value.
The check of a declared type leaves a `PendingValue` alone.
"""
abstract type PendingValue end

# ── The mode ──────────────────────────────────────────────────────────────────

const _DECLARED_TYPE_CHECK_MODES = (:off, :record, :throw)
const _DECLARED_TYPE_CHECK_MODE = Ref(:off)

"""
    set_declared_type_check_mode!(mode)

Say what the check of a declared type does with a value that the type does not
admit. `:off` checks nothing. `:record` keeps the mismatch, which
[`collect_declared_type_mismatches`](@ref) answers, and lets the write go on.
`:throw` throws a [`DeclaredTypeMismatchException`](@ref). The mode is one for
the whole process.

Use `:record` to make an inventory of the writes that a stricter declaration
would refuse: set it, run the code, and read the records.
"""
function set_declared_type_check_mode!(mode::Symbol)
    mode in _DECLARED_TYPE_CHECK_MODES ||
        throw(ArgumentError("the mode of the declared type check is one of " *
                            "$(join(_DECLARED_TYPE_CHECK_MODES, ", ")), not $mode"))
    _DECLARED_TYPE_CHECK_MODE[] = mode
end

"""
    get_declared_type_check_mode() -> Symbol

The mode that [`set_declared_type_check_mode!`](@ref) set: `:off`, `:record` or
`:throw`.
"""
get_declared_type_check_mode() = _DECLARED_TYPE_CHECK_MODE[]

# ── The records of an inventory ───────────────────────────────────────────────

"""
    DeclaredTypeMismatchRecord

One kind of mismatch that the `:record` mode saw: the `owner` type and the field
`name`, the `declared_type`, the `value_type` of the values that the type did not
admit, how many writes gave such a value (`count`), whether Julia converts such a
value to the declared type with no loss (`is_convertible`), and the stack frames
of the first callers (`callers`, one string for each distinct call site, with its
count).
"""
mutable struct DeclaredTypeMismatchRecord
    owner::Any
    name::Any
    declared_type::Any
    value_type::Any
    count::Int
    is_convertible::Bool
    callers::Dict{String, Int}
end

const _DECLARED_TYPE_MISMATCHES = Dict{Tuple{Any, Any, Any, Any}, DeclaredTypeMismatchRecord}()
const _DECLARED_TYPE_MISMATCH_LOCK = ReentrantLock()

# A record takes the call site of its first writes only, because a stack trace is
# slow and a mismatch in a loop repeats one call site.
const _DECLARED_TYPE_MISMATCH_CALLER_SAMPLES = 20
const _DECLARED_TYPE_MISMATCH_CALLER_FRAMES = 8

"""
    collect_declared_type_mismatches() -> Vector{DeclaredTypeMismatchRecord}

The mismatches that the `:record` mode kept, the most frequent first.
"""
collect_declared_type_mismatches() =
    lock(_DECLARED_TYPE_MISMATCH_LOCK) do
        sort!(collect(values(_DECLARED_TYPE_MISMATCHES)); by = record -> -record.count)
    end

"""
    clear_declared_type_mismatches!()

Forget the mismatches that the `:record` mode kept.
"""
clear_declared_type_mismatches!() =
    lock(_DECLARED_TYPE_MISMATCH_LOCK) do
        empty!(_DECLARED_TYPE_MISMATCHES)
        nothing
    end

function _record_declared_type_mismatch!(owner, name, declared_type, value)
    value_type = _describe_mismatch_type(value)
    key = (owner, name, declared_type, value_type)
    lock(_DECLARED_TYPE_MISMATCH_LOCK) do
        record = get!(_DECLARED_TYPE_MISMATCHES, key) do
            DeclaredTypeMismatchRecord(owner, name, declared_type, value_type, 0,
                                       _is_losslessly_convertible(declared_type, value),
                                       Dict{String, Int}())
        end
        record.count += 1
        if record.count <= _DECLARED_TYPE_MISMATCH_CALLER_SAMPLES
            caller = _describe_mismatch_caller(stacktrace(backtrace()))
            record.callers[caller] = get(record.callers, caller, 0) + 1
        end
    end
    nothing
end

# The frames above the check: the generated setter or constructor first, and then
# the code that wrote the value.
function _describe_mismatch_caller(frames)
    kept = String[]
    for frame in frames
        file = String(frame.file)
        (endswith(file, "DeclaredType.jl") || endswith(file, "lock.jl")) && continue
        push!(kept, string(frame.func, " at ", _shorten_mismatch_path(file), ":", frame.line))
        length(kept) == _DECLARED_TYPE_MISMATCH_CALLER_FRAMES && break
    end
    join(kept, " <- ")
end

function _shorten_mismatch_path(file)
    for marker in ("/source/", "/test/", "/example/", "/package/", "/tool/")
        i = findlast(marker, file)
        i === nothing || return file[first(i) + 1:end]
    end
    file
end

# ── The check ─────────────────────────────────────────────────────────────────

function _report_declared_type_mismatch(mode, owner, name, declared_type, value)
    mode === :throw && throw(DeclaredTypeMismatchException(owner, name, declared_type, value))
    _record_declared_type_mismatch!(owner, name, declared_type, value)
end

"""
    find_declared_field_type(T, name) -> Type or nothing

The type that `@document` records for the field `name` of the cell layout `T`, or
`nothing` when it records none: a hand-written document, or a name that is not a
field of `T`. A field declared `Vector{X}` answers the collection that the cell
layout holds in its place.
"""
function find_declared_field_type(T::Type, name::Symbol)
    declared = _declared_value_types(T)
    declared === nothing && return nothing
    i = Base.fieldindex(T, name, false)
    (i == 0 || i > length(declared)) && return nothing
    declared[i]
end

"""
    find_declared_element_type(collection) -> Type or nothing

The type that each element of `collection` must have, or `nothing` when the
collection declares none. A collection that keeps the element type of its field
answers it.
"""
find_declared_element_type(collection) = nothing

# ── The seam ──────────────────────────────────────────────────────────────────

"""
    convert_to_declared_type(owner, declared_type, value; name = nothing) -> value

The value that a place of `declared_type` admits for `value`. An operation calls
it at its write. `owner` is the document that owns the place: the document of the
field, or for an element of a list the nearest document above the list. Its
domain decides what text becomes. `name` names the place in the message of a
refusal.

1. A value of the declared type passes.
2. A value that Julia converts to the declared type with no loss is converted,
   such as an `Int` for a `Float64` field.
3. Text becomes the insertion of the domain of `owner`, if the declared type
   admits that insertion. The package that declares the domain adds this rule.
4. Anything else is refused with a [`DeclaredTypeMismatchException`](@ref).

Use it, and not the check of a setter, where a person or a model makes the value:
a paste, a drag, a type-in, an operation of the model.
"""
function convert_to_declared_type(owner, declared_type::Type, value; name = nothing)
    value isa declared_type && return value
    converted = _convert_losslessly(declared_type, value)
    converted === _NOT_CONVERTED || return converted
    throw(DeclaredTypeMismatchException(typeof(owner), name, declared_type, value))
end

struct _NotConverted end
const _NOT_CONVERTED = _NotConverted()

function _convert_losslessly(declared_type, value)
    converted = try
        convert(declared_type, value)
    catch
        return _NOT_CONVERTED
    end
    (converted isa declared_type && isequal(converted, value)) ? converted : _NOT_CONVERTED
end

function _is_losslessly_convertible(declared_type, value)
    _convert_losslessly(declared_type, value) !== _NOT_CONVERTED
end

"""
    convert_written_value(owner, declared_type, value; name = nothing) -> value

[`convert_to_declared_type`](@ref) at the write of an operation, under the mode of
the check: a refusal throws in the mode `:throw`, is recorded in the mode
`:record`, and in both `:record` and `:off` the write takes `value` as it is.
"""
function convert_written_value(owner, declared_type::Type, value; name = nothing)
    try
        return convert_to_declared_type(owner, declared_type, value; name)
    catch exception
        exception isa DeclaredTypeMismatchException || rethrow()
        mode = _DECLARED_TYPE_CHECK_MODE[]
        mode === :throw && rethrow()
        mode === :record &&
            _record_declared_type_mismatch!(exception.owner, exception.name,
                                            exception.declared_type, exception.value)
        return value
    end
end

"""
    is_admitted_by_declared_type(owner, declared_type, value) -> Bool

Whether [`convert_to_declared_type`](@ref) admits `value` for a place of
`declared_type` that `owner` owns. A paste asks it to find its target.
"""
function is_admitted_by_declared_type(owner, declared_type::Type, value)
    try
        convert_to_declared_type(owner, declared_type, value)
        true
    catch exception
        exception isa DeclaredTypeMismatchException || rethrow()
        false
    end
end

# The setter of the cell layout calls it before the write. A computation is not a
# value: the cell computes its value later, and a read narrows it. A `PendingValue`
# stands for a value that a later step makes.
function _check_declared_write(document, name::Symbol, value)
    _DECLARED_TYPE_CHECK_MODE[] === :off && return value
    declared_type = find_declared_field_type(typeof(document), name)
    declared_type === nothing && return value
    convert_assigned_value(document, declared_type, value; name)
end

"""
    convert_assigned_value(owner, declared_type, value; name = nothing) -> value

The value that a direct write by program code puts into a place of
`declared_type`, under the mode of the check. A value of the type passes, and so do
a `Computation` and a `PendingValue`. In the mode `:throw`, a value that Julia
converts with no loss is converted (rule 2 of [`convert_to_declared_type`](@ref)),
and any other value throws a [`DeclaredTypeMismatchException`](@ref). In the mode
`:record` the mismatch is recorded, and in `:record` and `:off` the value passes as
it is. Text does not become an insertion here: program code wrote it, not a person.

The setter and the constructor of the cell layout call it for a field, and a
collection that keeps the type of its elements calls it for each element write.
"""
function convert_assigned_value(owner, declared_type::Type, value; name = nothing)
    mode = _DECLARED_TYPE_CHECK_MODE[]
    mode === :off && return value
    (value isa declared_type || value isa Computation || value isa PendingValue) && return value
    if mode === :throw
        converted = _convert_losslessly(declared_type, value)
        converted === _NOT_CONVERTED || return converted
    end
    _report_declared_type_mismatch(mode, owner isa Type ? owner : typeof(owner), name,
                                   declared_type, value)
    value
end

# The constructor of the cell layout calls it with the new document. It checks the
# value that each cell holds now, with no dependency on the cell, and leaves a
# computed cell and a `PendingValue` alone. A later write to a cell that the caller
# gave goes past it.
function _check_constructed_document(document)
    mode = _DECLARED_TYPE_CHECK_MODE[]
    mode === :off && return document
    T = typeof(document)
    declared = _declared_value_types(T)
    declared === nothing && return document
    for i in 1:min(fieldcount(T), length(declared))
        cell = getfield(document, i)
        cell isa AbstractCell || continue
        is_computed_cell(cell) && continue
        value = peek(cell)
        (value isa declared[i] || value isa PendingValue) ||
            _admit_constructed_value!(mode, T, i, cell, declared[i], value)
    end
    document
end

# In the mode `:throw`, a value that Julia converts with no loss goes into its cell
# converted, when the cell can take a write that no other cell sees: a reactive or
# a mutable cell with no dependent. Any other mismatch is reported.
function _admit_constructed_value!(mode, T, i, cell, declared_type, value)
    if mode === :throw && (cell isa ReactiveCell || cell isa MutableCell) &&
       !has_dependent_cells(cell)
        converted = _convert_losslessly(declared_type, value)
        if converted !== _NOT_CONVERTED
            cell[] = converted
            return nothing
        end
    end
    _report_declared_type_mismatch(mode, T, fieldname(T, i), declared_type, value)
end
