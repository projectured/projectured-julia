# ============================================================================
# The style guard — a font, a color and a size come from a theme.
#
# Every place of the code takes its fonts, its colors and its sizes from a theme,
# with a sensible default (decision D4 of the plan of the default look). The guard
# reads the code a person writes, `source/`, and fails on a literal style value
# outside the places that hold such values:
#
#   - a font description, `StyleFont("…`;
#   - a color of numbers, `StyleColor(0.…`, or a color of the palette by its name;
#   - a length with a number other than 0: `Inset(`, `Spacing(`, `Radius(`,
#     `LineWidth(`, `ControlSize(` and `IconSize(`.
#
# The places that hold them are a `@theme` declaration, a preset of a theme (a
# function whose name ends in `_theme`), the palette (`Color.jl`), the registry
# of font faces (`FontFace.jl`), a docstring and a comment. A colour is stricter:
# a theme names a role of the colour theme, so a `@theme` declaration and a
# preset hold no palette colour and no colour of numbers, except in the colour
# theme (`ColorTheme.jl`), which maps the roles to the palette. `color_transparent`
# and `color_default` are no style. A line that holds a value on purpose says why
# with `# @style: <reason>`, on that line or on the line above it: the content of
# a document, a mark that is not the look of the editor, a value that waits for
# a decision. A marker on a line of its own covers the lines below it, up to the
# next blank line. A whole file that waits for a decision of the owner is on the
# list below, with its reason.
#
# **Static.** It reads the files as text and loads nothing, so it runs in about a
# second and needs no environment.
# ============================================================================

"The folders the rule covers: the code a person writes, and not the tests or the examples."
const STYLE_ROOTS = ["source"]

"The files that hold style values: the palette, the Solarized palette, which takes its colours from it, and the registry of font faces."
const STYLE_PLACES = ["source/platform/style/Color.jl", "source/platform/style/FontFace.jl",
                      "source/platform/style/SolarizedPalette.jl"]

"The file whose theme and presets may name a palette colour: the colour theme."
const STYLE_COLOR_PLACES = ["source/platform/style/ColorTheme.jl"]

"The files whose values wait for a decision of the owner, with the reason."
const STYLE_EXEMPT_FILES = Dict{String,String}()

# A length type and the arguments of its call, up to the first parenthesis.
const STYLE_LENGTH = r"\b(?:Inset|Spacing|Radius|LineWidth|ControlSize|IconSize)\(([^()]*)"

"""
    find_palette_names(root) -> Set{String}

The names of the colors of the palette, which `Color.jl` declares as constants,
without `color_transparent` and `color_default`.
"""
function find_palette_names(root::AbstractString)
    text = read(joinpath(root, "source", "platform", "style", "Color.jl"), String)
    names = Set{String}(m.captures[1] for m in eachmatch(r"^const (color_\w+)\s*="m, text))
    setdiff!(names, ["color_transparent", "color_default"])
    names
end

"""
    find_color_problem(code, palette) -> String or nothing

What literal colour the code of one line of a theme holds, or `nothing`.
"""
function find_color_problem(code::AbstractString, palette::Set{String})
    occursin(r"\bStyleColor\(\s*[0-9]", code) && return "a color of numbers"
    for m in eachmatch(r"\bcolor_\w+", code)
        m.match in palette && return "the palette color $(m.match)"
    end
    nothing
end

"""
    find_style_problem(code, palette) -> String or nothing

What literal style value the code of one line holds, or `nothing`.
"""
function find_style_problem(code::AbstractString, palette::Set{String})
    occursin(r"StyleFont\(\s*\"", code) && return "a font description"
    occursin(r"\bStyleColor\(\s*[0-9]", code) && return "a color of numbers"
    for m in eachmatch(r"\bcolor_\w+", code)
        m.match in palette && return "the palette color $(m.match)"
    end
    for m in eachmatch(STYLE_LENGTH, code)
        occursin(r"[1-9]", m.captures[1]) && return "a length with a number"
    end
    nothing
end

# Whether a line at the margin starts the definition of a preset of a theme.
_is_preset_start(line::AbstractString) =
    occursin(r"^(?:function\s+)?\w+_theme\s*\(", line)

"""
    compute_file_style_violations(path, relative, palette) -> Vector{String}

The literal style values of one file outside the places that hold them, as
`file:line: what — the line`.
"""
function compute_file_style_violations(path::AbstractString, relative::AbstractString,
                                       palette::Set{String})
    violations = String[]
    lines = readlines(path)
    in_docstring = false
    in_theme = false
    preset = :none      # :none, :block (to `end` at the margin) or :short (to the margin)
    in_names = false    # inside an `export`, `import` or `using` statement of several lines
    in_marked = false   # below a marker on a line of its own, up to the next blank line
    for (k, line) in enumerate(lines)
        stripped = strip(line)
        if in_marked
            isempty(stripped) ? (in_marked = false) : continue
        end
        if startswith(stripped, "# @style:")
            in_marked = true
            continue
        end
        if in_names || occursin(r"^\s*(export|import|using)\b", line)
            in_names = endswith(rstrip(first(split(line, '#'))), ",")
            continue
        end
        quotes = count("\"\"\"", line)
        if in_docstring
            isodd(quotes) && (in_docstring = false)
            continue
        end
        if isodd(quotes)
            in_docstring = true
            continue
        end
        if startswith(stripped, "@theme struct")
            in_theme = true
            continue
        end
        # In a theme and in a preset, a colour names a role.
        check_color() = relative in STYLE_COLOR_PLACES || occursin("@style:", line) ||
            (problem = find_color_problem(first(split(line, '#')), palette)) === nothing ||
            push!(violations, "$(relative):$(k): $(problem) in a theme — $(stripped)")
        if in_theme
            stripped == "end" && (in_theme = false)
            check_color()
            continue
        end
        if preset === :block
            line == "end" && (preset = :none)
            check_color()
            continue
        elseif preset === :short
            if isempty(stripped) || !startswith(line, " ")
                preset = :none
            else
                check_color()
                continue
            end
        end
        if _is_preset_start(line)
            preset = startswith(line, "function") ? :block : :short
            check_color()
            continue
        end
        occursin("@style:", line) && continue
        k > 1 && occursin("# @style:", lines[k - 1]) && continue
        code = first(split(line, '#'))
        problem = find_style_problem(code, palette)
        problem === nothing ||
            push!(violations, "$(relative):$(k): $(problem) — $(stripped)")
    end
    violations
end

"""
    style_violations(root) -> Vector{String}

Every literal font, color and size of `root` outside the places that hold them,
as lines a reader can act on.
"""
function style_violations(root::AbstractString)
    palette = find_palette_names(root)
    violations = String[]
    for folder in STYLE_ROOTS
        for (directory, _, files) in walkdir(joinpath(root, folder))
            for file in sort(files)
                endswith(file, ".jl") || continue
                path = joinpath(directory, file)
                relative = relpath(path, root)
                (relative in STYLE_PLACES || haskey(STYLE_EXEMPT_FILES, relative)) && continue
                append!(violations, compute_file_style_violations(path, relative, palette))
            end
        end
    end
    violations
end

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/style.jl
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    bad = style_violations(root)
    if isempty(bad)
        println("every font, color and size the guard can read comes from a theme")
    else
        println("$(length(bad)) style violation(s):")
        foreach(v -> println("  ", v), bad)
        exit(1)
    end
end
