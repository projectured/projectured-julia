const _WP_JS = Base.JuliaSyntax

# The functions of `source/platform/widget/` that may build a projection, each with
# the reason. A function that is not in the list and not the constructor of a
# projection type of its own must not call the constructor of a type that is a
# `Projection`.
#
# - `WidgetToGraphics`: the factory builds the one dispatch that holds the printer
#   of each widget, once, when an editor is built.
# - `make_graphics_projection`: the method for a document type builds the
#   projection of that type once for a renderer, not in a print.
# - `make_context_menu_window_projection`: the factory wraps the projection of the
#   content of a window once.
# - `make_object_field_widget_dispatch` and `_nest_value_widget`: they build the
#   rows of a table of rules from the rows of the widgets, once.
const WIDGET_PROJECTION_BUILDERS = Set([
    "WidgetToGraphics", "make_graphics_projection", "make_context_menu_window_projection",
    "make_object_field_widget_dispatch", "_nest_value_widget"])

# The name of the function that a definition `node` defines, or `nothing` for a
# node that defines none.
function _find_defined_function_name(node)
    kind = _WP_JS.kind(node)
    kind in (_WP_JS.K"function", _WP_JS.K"=") || return nothing
    head = first(_WP_JS.children(node))
    while _WP_JS.kind(head) in (_WP_JS.K"::", _WP_JS.K"where")
        head = first(_WP_JS.children(head))
    end
    _WP_JS.kind(head) === _WP_JS.K"call" || return nothing
    callee = first(_WP_JS.children(head))
    _WP_JS.kind(callee) === _WP_JS.K"Identifier" ? String(_WP_JS.sourcetext(callee)) : nothing
end

# Whether the identifier `name` is a type that is a `Projection` in the platform.
function _is_projection_type_name(name::AbstractString)
    symbol = Symbol(name)
    isdefined(ProjecturedPlatform, symbol) || return false
    value = getfield(ProjecturedPlatform, symbol)
    value isa Type && value <: ProjecturedPlatform.Projection
end

# Each call of the constructor of a projection type inside the definition `node`
# of the function `owner`, as `(owner, line, type name)`.
function _find_projection_constructions!(found, node, owner::String, path::String)
    if _WP_JS.kind(node) === _WP_JS.K"call"
        callee = first(_WP_JS.children(node))
        if _WP_JS.kind(callee) === _WP_JS.K"Identifier" &&
           _is_projection_type_name(String(_WP_JS.sourcetext(callee)))
            line = first(_WP_JS.source_location(node))
            push!(found, (path, owner, line, String(_WP_JS.sourcetext(callee))))
        end
    end
    _WP_JS.is_leaf(node) && return found
    for child in _WP_JS.children(node)
        _find_projection_constructions!(found, child, owner, path)
    end
    found
end

# The constructions of a projection inside a function of the file at `path`.
function _find_file_projection_constructions(path::AbstractString)
    tree = _WP_JS.parseall(_WP_JS.SyntaxNode, read(path, String); filename = path)
    found = Tuple{String,String,Int,String}[]
    visit(node) = begin
        _WP_JS.is_leaf(node) && return
        name = _find_defined_function_name(node)
        if name !== nothing
            # The constructor of a projection type builds that type and no other.
            (name in WIDGET_PROJECTION_BUILDERS || _is_projection_type_name(name)) && return
            _find_projection_constructions!(found, node, name, path)
            return
        end
        foreach(visit, _WP_JS.children(node))
    end
    visit(tree)
    found
end

"""
    test_widget_printer_projection()

No function of `source/platform/widget/` calls the constructor of a type that is a
`Projection`, except the constructor of a projection type for itself and the
functions of `WIDGET_PROJECTION_BUILDERS`. A projection is fixed configuration,
and a printer prints a child through `recursion`, so a print makes no projection
and no copy of one. The test reads the syntax tree of each file, so a call, a
field and a word in a comment are told apart.
"""
function test_widget_printer_projection()
    @testset "no widget printer builds a projection" begin
        folder = joinpath(get_package_source_root(ProjecturedPlatform), "widget")
        files = sort!([joinpath(folder, name) for name in readdir(folder) if endswith(name, ".jl")])
        @test !isempty(files)
        found = Tuple{String,String,Int,String}[]
        for file in files
            append!(found, _find_file_projection_constructions(file))
        end
        for (path, owner, line, type) in found
            @info "projection built in a function" file = basename(path) line function_name = owner type
        end
        @test isempty(found)
    end
end
