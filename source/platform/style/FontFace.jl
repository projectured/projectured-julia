# Fragment of `StyleModule` — the faces of the bundled font families, and the
# lookup that finds the face for a family, a weight and a slant.

"""
    FontFace(family, weight, italic, file)

One face of a font family: its weight on the scale of CSS and OpenType, from 100
to 900, whether its glyphs lean, and the name of the file under `asset/font/`
that holds it. 400 is regular and 700 is bold. An oblique face counts as italic.

The faces of the bundled fonts are fixed; [`find_font_face`](@ref) finds one.
"""
struct FontFace
    family::String
    weight::Int16
    italic::Bool
    file::String
end

# The faces of the font files under `asset/font/`. The weight and the slant of
# each are the ones that the file declares in its OS/2 table, which
# `test_font_face` checks. The family is the name that the file declares, except
# Lucide, which the file names in lower case.
const _FONT_FACES = FontFace[
    FontFace("DejaVu Sans", 400, false, "DejaVuSans.ttf"),
    FontFace("DejaVu Sans", 400, true, "DejaVuSans-Oblique.ttf"),
    FontFace("DejaVu Sans", 700, false, "DejaVuSans-Bold.ttf"),
    FontFace("DejaVu Sans Mono", 400, false, "DejaVuSansMono.ttf"),
    FontFace("DejaVu Sans Mono", 400, true, "DejaVuSansMono-Oblique.ttf"),
    FontFace("DejaVu Sans Mono", 700, false, "DejaVuSansMono-Bold.ttf"),
    FontFace("Inconsolata", 500, false, "Inconsolata.otf"),
    FontFace("Liberation Mono", 400, false, "LiberationMono-Regular.ttf"),
    FontFace("Liberation Mono", 400, true, "LiberationMono-Italic.ttf"),
    FontFace("Liberation Mono", 700, false, "LiberationMono-Bold.ttf"),
    FontFace("Liberation Mono", 700, true, "LiberationMono-BoldItalic.ttf"),
    FontFace("Liberation Sans", 400, false, "LiberationSans-Regular.ttf"),
    FontFace("Liberation Sans", 400, true, "LiberationSans-Italic.ttf"),
    FontFace("Liberation Sans", 700, false, "LiberationSans-Bold.ttf"),
    FontFace("Liberation Sans", 700, true, "LiberationSans-BoldItalic.ttf"),
    FontFace("Liberation Serif", 400, false, "LiberationSerif-Regular.ttf"),
    FontFace("Liberation Serif", 400, true, "LiberationSerif-Italic.ttf"),
    FontFace("Liberation Serif", 700, false, "LiberationSerif-Bold.ttf"),
    FontFace("Liberation Serif", 700, true, "LiberationSerif-BoldItalic.ttf"),
    FontFace("Lucide", 400, false, "lucide.ttf"),
    FontFace("Noto Emoji", 400, false, "NotoEmoji-Regular.ttf"),
    FontFace("Ubuntu", 300, false, "Ubuntu-L.ttf"),
    FontFace("Ubuntu", 300, true, "Ubuntu-LI.ttf"),
    FontFace("Ubuntu", 400, false, "Ubuntu-R.ttf"),
    FontFace("Ubuntu", 400, true, "Ubuntu-RI.ttf"),
    FontFace("Ubuntu", 500, false, "Ubuntu-M.ttf"),
    FontFace("Ubuntu", 500, true, "Ubuntu-MI.ttf"),
    FontFace("Ubuntu", 700, false, "Ubuntu-B.ttf"),
    FontFace("Ubuntu", 700, true, "Ubuntu-BI.ttf"),
    FontFace("Ubuntu Condensed", 400, false, "Ubuntu-C.ttf"),
    FontFace("Ubuntu Mono", 400, false, "UbuntuMono-R.ttf"),
    FontFace("Ubuntu Mono", 400, true, "UbuntuMono-RI.ttf"),
    FontFace("Ubuntu Mono", 700, false, "UbuntuMono-B.ttf"),
    FontFace("Ubuntu Mono", 700, true, "UbuntuMono-BI.ttf"),
]

"""
    find_font_face(family, weight, italic) -> FontFace or nothing

The bundled face that draws text of `family` at `weight` and in the slant that
`italic` asks for. It follows the font matching of CSS: the slant first, then the
weight.

- A face of the slant that `italic` asks for wins over every face of the other
  slant. A family with no italic face draws italic text upright.
- Of the faces of one slant, the weight that `weight` asks for wins. Else, for a
  weight from 400 to 500, the nearest heavier weight up to 500 wins, then the
  nearest lighter weight, then the nearest weight above 500. For a weight below
  400 the nearest lighter weight wins, then the nearest heavier one. For a weight
  above 500 the nearest heavier weight wins, then the nearest lighter one.

The family name matches with no regard to case. `nothing` when no bundled face
has the family.
"""
function find_font_face(family::AbstractString, weight::Integer, italic::Bool)
    index = _find_font_face_index(family, weight, italic)
    index == 0 ? nothing : _FONT_FACES[index]
end

# The index in `_FONT_FACES` of the face that `find_font_face` finds, or 0. The
# index and not the face: a local that holds a face or `nothing` boxes the face
# at each assignment.
function _find_font_face_index(family::AbstractString, weight::Integer, italic::Bool)
    found = 0
    found_rank = (0, 0, 0)
    for (index, face) in pairs(_FONT_FACES)
        _is_same_family(face.family, family) || continue
        rank = (face.italic == italic ? 0 : 1, _rank_font_weight(Int(weight), Int(face.weight))...)
        if found == 0 || rank < found_rank
            found, found_rank = index, rank
        end
    end
    found
end

# The order of `candidate` for the weight `wanted`, by the rule of CSS: a smaller
# tuple wins. The first part is the group of the rule, the second the distance
# inside the group. Both are `Int`, so the rank has one type: a rank of two
# integer types is a union, and the loop of the lookup boxes it.
function _rank_font_weight(wanted::Int, candidate::Int)
    if 400 <= wanted <= 500
        wanted <= candidate <= 500 && return (0, candidate - wanted)
        candidate < wanted && return (1, wanted - candidate)
        return (2, candidate - 500)
    elseif wanted < 400
        candidate <= wanted && return (0, wanted - candidate)
        return (1, candidate - wanted)
    else
        candidate >= wanted && return (0, candidate - wanted)
        return (1, wanted - candidate)
    end
end

# Whether two family names are the same with no regard to case. It allocates
# nothing, so a caller can ask for a face at each string that it measures.
function _is_same_family(a::AbstractString, b::AbstractString)
    ncodeunits(a) == ncodeunits(b) || return false
    for (x, y) in zip(a, b)
        lowercase(x) == lowercase(y) || return false
    end
    true
end

"""
    get_font_families() -> Vector{String}

The families of the bundled faces, each one time, in the order of their names.
"""
get_font_families() = sort!(unique!([face.family for face in _FONT_FACES]))

"""
    get_font_face_path(face) -> String

The path of the file of `face`: its file under `asset/font/`, or under the font
search path when the bundle is on another machine (see [`font_file`](@ref)).
"""
get_font_face_path(face::FontFace) = font_file(joinpath(_FONT_DIR, face.file))

# The family that draws a font whose family has no bundled face.
const _DEFAULT_FONT_FAMILY = "DejaVu Sans"

# The path of the file of each face, in the order of `_FONT_FACES`, as the
# package was built. `font_file` resolves it where the file is opened.
const _FONT_FACE_PATHS = [joinpath(_FONT_DIR, face.file) for face in _FONT_FACES]

"""
    compute_font_path(font) -> String

The path of the file that draws `font`: the file of the bundled face that
[`find_font_face`](@ref) finds for its family, its weight and its slant. A font
whose family has no bundled face draws in DejaVu Sans.

The path is the one of the checkout that built the package;
[`font_file`](@ref) resolves it where a file is opened, so a bundle on another
machine finds its fonts. The measure, the backends and the caches of
fonts key on this path. It allocates nothing.
"""
function compute_font_path(font::StyleFont)
    index = _find_font_face_index(font.family, font.weight, font.italic)
    index == 0 && (index = _find_font_face_index(_DEFAULT_FONT_FAMILY, font.weight, font.italic))
    _FONT_FACE_PATHS[index]
end

# ── Fallback faces ──────────────────────────────────────────────────────────
#
# A face draws only the characters it carries. For a character it lacks, a
# renderer draws with the face that `find_glyph_font_file` names, and
# `FontFileMeasure` measures with the same face, so a line is drawn as wide as it
# was measured.

# The families that draw a character that the face of a font lacks, in order:
# DejaVu Sans Mono carries arrows, check marks, stars, geometric shapes and box
# drawing, and Noto Emoji carries pictographs.
const _FALLBACK_FONT_FAMILIES = ("DejaVu Sans Mono", "Noto Emoji")

const _EMOJI_FONT_PATH = _FONT_FACE_PATHS[_find_font_face_index("Noto Emoji", 400, false)]

"""
    get_fallback_font_files(font) -> Vector{String}

The files that a text set in `font` falls back to, in order. For each fallback
family, DejaVu Sans Mono and then Noto Emoji: its upright face at the weight of
`font`, then its upright regular face, because a bold face can lack a glyph that
the regular face carries. A fallback glyph stands upright in an italic text too.
"""
function get_fallback_font_files(font::StyleFont)
    files = String[]
    for family in _FALLBACK_FONT_FAMILIES, weight in (Int(font.weight), 400)
        path = _FONT_FACE_PATHS[_find_font_face_index(family, weight, false)]
        path in files || push!(files, path)
    end
    files
end

const _FONT_AVAILABLE = Dict{String,Bool}()

_is_font_available(path::AbstractString) =
    get!(() -> isfile(font_file(path)), _FONT_AVAILABLE, String(path))

"""
    find_glyph_font_file(font, character) -> String or nothing

The file of the face that draws `character` in a text set in `font`: the file
that [`compute_font_path`](@ref) gives when its face carries the character, else
the first file of [`get_fallback_font_files`](@ref) that does. `nothing` when no
face carries it, and the caller then draws the character in its own font, which
draws the missing-glyph box. A fallback file that is not installed is skipped.

A character outside the basic plane is nearly always a pictograph, and Noto
Emoji draws it even when the font carries one: DejaVu Sans does, in a style of
its own.
"""
function find_glyph_font_file(font::StyleFont, character::UInt32)
    character > 0xFFFF && _has_file_glyph(_EMOJI_FONT_PATH, character) && return _EMOJI_FONT_PATH
    path = compute_font_path(font)
    has_font_glyph(load_truetype_font(path), character) && return path
    for fallback in get_fallback_font_files(font)
        _has_file_glyph(fallback, character) && return fallback
    end
    nothing
end

_has_file_glyph(path::AbstractString, character::UInt32) =
    _is_font_available(path) && has_font_glyph(load_truetype_font(path), character)
