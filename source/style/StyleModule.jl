"""
    StyleModule

Color style value type and named color constants. Colors are stored as
normalized Float64 components in [0, 1].
"""
module StyleModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!

export StyleColor, make_style_color,
       is_color_equal, is_color_transparent, color_interpolate, color_lighten, color_darken,
       color_lighten_selection, color_darken_selection,
       color_default,
       color_black, color_white, color_transparent, color_red, color_green, color_blue,
       color_yellow, color_purple, color_cyan,
       color_gray0, color_gray15, color_gray31, color_gray47, color_gray63,
       color_gray79, color_gray95, color_gray111, color_gray127,
       color_gray143, color_gray159, color_gray175, color_gray191,
       color_gray207, color_gray223, color_gray239, color_gray255,
       color_solarized_gray, color_solarized_yellow, color_solarized_orange,
       color_solarized_red, color_solarized_magenta, color_solarized_violet,
       color_solarized_blue, color_solarized_cyan, color_solarized_green,
       color_solarized_background_darker, color_solarized_background_dark,
       color_solarized_background_light, color_solarized_background_lighter,
       color_solarized_content_darker, color_solarized_content_dark,
       color_solarized_content_light, color_solarized_content_lighter,
       color_completion_hint,
       color_pastel_turquoise, color_pastel_green_sea,
       color_pastel_emerland, color_pastel_nephritis,
       color_pastel_peter_river, color_pastel_belize_hole,
       color_pastel_amethyst, color_pastel_wisteria,
       color_pastel_wet_asphalt, color_pastel_midnight_blue,
       color_pastel_sun_flower, color_pastel_orange,
       color_pastel_carrot, color_pastel_pumpkin,
       color_pastel_alizarin, color_pastel_pomegranate,
       color_pastel_clouds, color_pastel_silver,
       color_pastel_concrete, color_pastel_asbestos,
       color_zinc_50, color_zinc_100, color_zinc_200, color_zinc_300,
       color_zinc_400, color_zinc_500, color_zinc_600, color_zinc_700,
       color_zinc_800, color_zinc_900, color_zinc_950,
       color_slate_50, color_slate_100, color_slate_200, color_slate_300,
       color_slate_400, color_slate_500, color_slate_600, color_slate_700,
       color_slate_800, color_slate_900, color_slate_950,
       color_indigo_50, color_indigo_100, color_indigo_200, color_indigo_300,
       color_indigo_400, color_indigo_500, color_indigo_600, color_indigo_700,
       color_indigo_800, color_indigo_900, color_indigo_950,
       color_destructive, color_destructive_fg
export StyleFont, make_style_font, _FONT_ZOOM, font_logical_size, font_device_size,
       step_zoom, adjust_font_zoom!, _FONT_DIR,
       font_inconsolata_regular_18,
       font_ubuntu_monospace_regular_14, font_ubuntu_monospace_italic_14, font_ubuntu_monospace_bold_14,
       font_ubuntu_monospace_regular_16, font_ubuntu_monospace_italic_16, font_ubuntu_monospace_bold_16,
       font_ubuntu_monospace_regular_18, font_ubuntu_monospace_italic_18, font_ubuntu_monospace_bold_18,
       font_ubuntu_monospace_regular_20, font_ubuntu_monospace_italic_20, font_ubuntu_monospace_bold_20,
       font_ubuntu_monospace_regular_22, font_ubuntu_monospace_italic_22, font_ubuntu_monospace_bold_22,
       font_ubuntu_monospace_regular_24, font_ubuntu_monospace_italic_24, font_ubuntu_monospace_bold_24,
       font_ubuntu_monospace_regular_36, font_ubuntu_monospace_italic_36, font_ubuntu_monospace_bold_36,
       font_ubuntu_monospace_regular_48, font_ubuntu_monospace_italic_48, font_ubuntu_monospace_bold_48,
       font_ubuntu_regular_14, font_ubuntu_italic_14, font_ubuntu_bold_14,
       font_ubuntu_regular_16, font_ubuntu_italic_16, font_ubuntu_bold_16,
       font_ubuntu_regular_18, font_ubuntu_italic_18, font_ubuntu_bold_18,
       font_ubuntu_regular_20, font_ubuntu_italic_20, font_ubuntu_bold_20,
       font_ubuntu_regular_22, font_ubuntu_italic_22, font_ubuntu_bold_22,
       font_ubuntu_regular_24, font_ubuntu_italic_24, font_ubuntu_bold_24,
       font_ubuntu_regular_36, font_ubuntu_italic_36, font_ubuntu_bold_36,
       font_liberation_sans_regular_14, font_liberation_sans_italic_14, font_liberation_sans_bold_14,
       font_liberation_sans_regular_16, font_liberation_sans_italic_16, font_liberation_sans_bold_16,
       font_liberation_sans_regular_18, font_liberation_sans_italic_18, font_liberation_sans_bold_18,
       font_liberation_sans_regular_20, font_liberation_sans_italic_20, font_liberation_sans_bold_20,
       font_liberation_sans_regular_22, font_liberation_sans_italic_22, font_liberation_sans_bold_22,
       font_liberation_sans_regular_24, font_liberation_sans_italic_24, font_liberation_sans_bold_24,
       font_liberation_sans_regular_30, font_liberation_sans_italic_30, font_liberation_sans_bold_30,
       font_liberation_sans_regular_36, font_liberation_sans_italic_36, font_liberation_sans_bold_36,
       font_liberation_serif_regular_14, font_liberation_serif_italic_14, font_liberation_serif_bold_14,
       font_liberation_serif_regular_16, font_liberation_serif_italic_16, font_liberation_serif_bold_16,
       font_liberation_serif_regular_18, font_liberation_serif_italic_18, font_liberation_serif_bold_18,
       font_liberation_serif_regular_20, font_liberation_serif_italic_20, font_liberation_serif_bold_20,
       font_liberation_serif_regular_22, font_liberation_serif_italic_22, font_liberation_serif_bold_22,
       font_liberation_serif_regular_24, font_liberation_serif_italic_24, font_liberation_serif_bold_24,
       font_liberation_serif_regular_30, font_liberation_serif_italic_30, font_liberation_serif_bold_30,
       font_liberation_serif_regular_36, font_liberation_serif_italic_36, font_liberation_serif_bold_36,
       font_liberation_serif_regular_42, font_liberation_serif_italic_42, font_liberation_serif_bold_42,
       font_dejavu_monospace_regular_14, font_dejavu_monospace_italic_14, font_dejavu_monospace_bold_14,
       font_dejavu_monospace_regular_16, font_dejavu_monospace_italic_16, font_dejavu_monospace_bold_16,
       font_dejavu_monospace_regular_18, font_dejavu_monospace_italic_18, font_dejavu_monospace_bold_18,
       font_dejavu_monospace_regular_20, font_dejavu_monospace_italic_20, font_dejavu_monospace_bold_20,
       font_dejavu_monospace_regular_22, font_dejavu_monospace_italic_22, font_dejavu_monospace_bold_22,
       font_dejavu_monospace_regular_24, font_dejavu_monospace_italic_24, font_dejavu_monospace_bold_24,
       font_dejavu_monospace_regular_36, font_dejavu_monospace_italic_36, font_dejavu_monospace_bold_36,
       font_dejavu_monospace_regular_48, font_dejavu_monospace_italic_48, font_dejavu_monospace_bold_48,
       font_dejavu_sans_regular_14, font_dejavu_sans_italic_14, font_dejavu_sans_bold_14,
       font_dejavu_sans_regular_16, font_dejavu_sans_italic_16, font_dejavu_sans_bold_16,
       font_dejavu_sans_regular_18, font_dejavu_sans_italic_18, font_dejavu_sans_bold_18,
       font_dejavu_sans_regular_20, font_dejavu_sans_italic_20, font_dejavu_sans_bold_20,
       font_dejavu_sans_regular_22, font_dejavu_sans_italic_22, font_dejavu_sans_bold_22,
       font_dejavu_sans_regular_24, font_dejavu_sans_italic_24, font_dejavu_sans_bold_24,
       font_dejavu_sans_regular_36, font_dejavu_sans_italic_36, font_dejavu_sans_bold_36,
       font_lucide_icons_20
export measure_truetype_text, font_ascent, font_descent, font_line_height,
       font_x_height, font_cap_height, font_glyph_bounds, font_file,
       get_fallback_font_files, find_glyph_font_file, has_font_glyph,
       is_presentation_selector
export Inset, Point2D, inset_default,
       inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right,
       AffineTransform, affine_identity, make_affine_translate, make_affine_scale,
       apply_affine_transform, compute_affine_inverse, is_affine_axis_aligned
export ImageDocument, set_cell_computation!
export StyleStroke, make_style_stroke
export StyleText, make_style_text
export TextMeasure, FontMetrics, StringBox, measure_string, get_font_metrics,
       compute_caret_offsets, FontFileMeasure, FixedMeasure, compute_text_extent,
       PlacedGlyph, compute_placed_glyphs
export LineSpacing, SingleSpacing, MultipleSpacing, ExactSpacing, AtLeastSpacing,
       compute_line_distance, compute_baseline_offset, LineBox, compute_line_box
export TrueTypeFont, load_truetype_font, get_glyph_id, get_glyph_advance_1000,
       get_ascent_pixels, measure_text_width, get_kerning, get_vertical_metrics


include("Color.jl")
include("Font.jl")
include("TrueType.jl")
include("TextMeasure.jl")
include("LineSpacing.jl")
include("Geometry.jl")
include("Image.jl")
include("StyleStroke.jl")
include("StyleText.jl")

end # module
