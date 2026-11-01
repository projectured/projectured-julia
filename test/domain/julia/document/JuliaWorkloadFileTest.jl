# The file that the workload of the Julia domain opens holds each kind of Julia
# code that the parser makes, so the image of the package holds the print of each
# kind, and a window that shows new code compiles none.

using ProjecturedJulia.JuliaModule: JuliaModule, JuliaFile, JuliaDocument, JuliaFunction,
                                    JuliaInsertion, JuliaObject, JuliaToplevel, parse_julia
using ProjecturedPlatform.NaturalModule: print_natural_text

# The kinds that the parser never makes, each with what makes it.
const _JULIA_KINDS_OF_AN_EDIT = Dict{Type,String}(
    supertype(JuliaInsertion) =>"the placeholder of a place that an edit leaves empty",
    supertype(JuliaObject) => "a write of a document of another domain into a place of code")

# The kind of each Julia node in `value` and below it: the stem that the C and the
# M layout of its type share.
function _collect_julia_kinds!(kinds::Set{Type}, value, seen::IdDict{Any,Nothing} = IdDict{Any,Nothing}())
    value isa Union{AbstractString,Symbol,Number,Char,Nothing} && return kinds
    haskey(seen, value) && return kinds
    seen[value] = nothing
    if value isa JuliaDocument
        push!(kinds, supertype(typeof(value)))
        foreach(name -> _collect_julia_kinds!(kinds, getproperty(value, name), seen),
                fieldnames(typeof(value)))
    elseif applicable(iterate, value)
        foreach(item -> _collect_julia_kinds!(kinds, item, seen), value)
    end
    kinds
end

# The code of `text` as Julia reads it, with no line number: not in a block, not
# at the top level, and not in a macro call, where `Base.remove_linenums!` keeps it.
_read_julia_code(text::AbstractString) = _strip_julia_line_numbers(Meta.parseall(text))
_strip_julia_line_numbers(x) = x
_strip_julia_line_numbers(x::Expr) =
    Expr(x.head, Any[a isa LineNumberNode ? nothing : _strip_julia_line_numbers(a)
                     for a in x.args if !(a isa LineNumberNode && x.head !== :macrocall)]...)

# Each kind of the domain: the abstract stem of each type of node of `JuliaModule`.
function _collect_julia_domain_kinds()
    kinds = Set{Type}()
    for name in names(JuliaModule; all = true)
        isdefined(JuliaModule, name) || continue
        value = getfield(JuliaModule, name)
        value isa Type && isabstracttype(value) && value !== JuliaDocument &&
            value <: JuliaDocument && push!(kinds, value)
    end
    kinds
end

function test_julia_workload_file()
@testset "the file of the workload holds each kind of Julia code that the parser makes" begin
    file = make_workload_file(JuliaFile)
    @test startswith(file.text, "alice = 1 + 2\n")
    @test occursin(file.shown, "alice")
    domain_kinds = _collect_julia_domain_kinds()
    @test supertype(JuliaFunction) in domain_kinds
    document = parse_julia(file.text)
    # The top level of the file prints its first statement first, with no
    # indentation.
    @test document isa JuliaToplevel && !document.on_one_line
    @test startswith(print_natural_text(document), "alice = 1 + 2\n")
    kinds = _collect_julia_kinds!(Set{Type}(), document)
    # A new kind of the domain goes into the file, or into the list of the kinds
    # that only an edit makes.
    @test setdiff(domain_kinds, kinds, keys(_JULIA_KINDS_OF_AN_EDIT)) == Set{Type}()
    # A kind of the list that the file holds does not belong on the list.
    @test intersect(kinds, keys(_JULIA_KINDS_OF_AN_EDIT)) == Set{Type}()
    # The file prints back to the same code, so the print of each kind in it is
    # code that Julia reads as the file.
    @test _read_julia_code(print_natural_text(parse_julia(file.text))) == _read_julia_code(file.text)
end
end
