const _WG_JS = Base.JuliaSyntax

# The keywords of a layout or a widget that give a space. A gap or a padding is a
# role of the widget theme, so a builder reads it from there and writes no number.
const WIDGET_SPACE_KEYWORDS = Set(["gap", "horizontal_gap", "vertical_gap", "padding", "margin"])

# Whether the node `node` is a number other than 0, or a call of `Inset` or
# `Spacing` that holds one.
function _is_nonzero_number_literal(node)
    kind = _WG_JS.kind(node)
    if kind in (_WG_JS.K"Integer", _WG_JS.K"Float")
        return !(String(_WG_JS.sourcetext(node)) in ("0", "0.0"))
    end
    kind === _WG_JS.K"call" || return false
    parts = _WG_JS.children(node)
    String(_WG_JS.sourcetext(first(parts))) in ("Inset", "Spacing") &&
        any(_is_nonzero_number_literal, parts[2:end])
end

# Whether the callee `name` is a layout or a widget.
_is_layout_or_widget_name(name::AbstractString) = occursin(r"^(Widget\w*|\w*Layout|LayoutConstraint)$", name)

# Each keyword of a call of a layout or a widget in the file at `path` that sets a
# space to a number other than 0, as `(path, line, callee, keyword and value)`.
function _find_file_literal_spaces(path::AbstractString)
    tree = _WG_JS.parseall(_WG_JS.SyntaxNode, read(path, String); filename = path)
    found = Tuple{String,Int,String,String}[]
    check(argument, callee) = begin
        _WG_JS.kind(argument) === _WG_JS.K"=" || return
        name, value = _WG_JS.children(argument)
        String(_WG_JS.sourcetext(name)) in WIDGET_SPACE_KEYWORDS && _is_nonzero_number_literal(value) &&
            push!(found, (path, first(_WG_JS.source_location(argument)), callee, String(_WG_JS.sourcetext(argument))))
    end
    visit(node) = begin
        _WG_JS.is_leaf(node) && return
        if _WG_JS.kind(node) === _WG_JS.K"call"
            parts = _WG_JS.children(node)
            callee = _WG_JS.kind(first(parts)) === _WG_JS.K"Identifier" ? String(_WG_JS.sourcetext(first(parts))) : ""
            if _is_layout_or_widget_name(callee)
                for argument in parts[2:end]
                    if _WG_JS.kind(argument) === _WG_JS.K"parameters"
                        foreach(keyword -> check(keyword, callee), _WG_JS.children(argument))
                    else
                        check(argument, callee)
                    end
                end
            end
        end
        foreach(visit, _WG_JS.children(node))
    end
    visit(tree)
    found
end

"""
    test_widget_gap_role()

No call of a layout or a widget in `source/platform` gives `gap`, `horizontal_gap`,
`vertical_gap`, `padding` or `margin` a number other than 0. A gap and a padding
are roles of the widget theme, so a builder reads the role and a change of the
theme changes every place that uses it. The test reads the syntax tree of each
file, so a call, a keyword and a word in a comment are told apart.
"""
function test_widget_gap_role()
    @testset "no layout or widget of the platform has a literal space" begin
        root = get_package_source_root(ProjecturedPlatform)
        files = String[]
        for (folder, _, names) in walkdir(root), name in names
            endswith(name, ".jl") && push!(files, joinpath(folder, name))
        end
        sort!(files)
        @test !isempty(files)
        found = Tuple{String,Int,String,String}[]
        for file in files
            append!(found, _find_file_literal_spaces(file))
        end
        for (path, line, callee, text) in found
            @info "literal space in a call" file = relpath(path, root) line callee text
        end
        @test isempty(found)
    end
end
