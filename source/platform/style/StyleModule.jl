"""
    StyleModule

Color style value type and named color constants, the palettes and the colour
theme, the fonts, the geometry, the themes and the appearance. Colors are stored
as normalized Float64 components in [0, 1].
"""
module StyleModule

using ..CellModule
using ..DocumentModule
using ..ReferenceModule
using ..SettingsModule

import TOML

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!
import ..SerializationModule: is_pred_constructible

export StyleColor, make_style_color, format_style_color, convert_text_to_style_color,
       is_color_equal, is_color_transparent, color_interpolate, color_lighten, color_darken,
       compute_relative_luminance, compute_contrast_ratio,
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
export PaletteColor, ColorRole, ThemeColor, format_theme_color
export PALETTE_HUES, Palette, TablePalette, get_palette_name, get_palette_neutrals,
       find_palette_ramp, DEFAULT_PALETTE_NAME, register_palette!, find_palette,
       get_palette_names, compute_palette_color
export RADIX_PALETTE
export StyleFont, make_style_font, font_logical_size, font_device_size, step_factor,
       _FONT_DIR
export font_ascent, font_descent, font_line_height,
       font_x_height, font_cap_height, font_glyph_bounds, font_file,
       get_fallback_font_files, find_glyph_font_file, has_font_glyph,
       is_presentation_selector
export FontFace, find_font_face, get_font_families, get_font_weights, get_font_face_path,
       compute_font_path, with_font_size
export Inset, Point2D, inset_default,
       inset_size, inset_width, inset_height,
       inset_top_left, inset_top_right, inset_bottom_left, inset_bottom_right,
       AffineTransform, affine_identity, make_affine_translate, make_affine_scale,
       apply_affine_transform, compute_affine_inverse, is_affine_axis_aligned
export ImageDocument, set_cell_computation!
export StyleStroke, make_style_stroke
export StyleText, make_style_text
export FontRole, TextRole, apply_font_role, get_role_base
export Theme, ScaledTheme, ThemeLength, Spacing, Radius, LineWidth, ControlSize, IconSize,
       scale_length, convert_theme_value, @theme, make_scaled_theme, get_theme_field_names,
       get_theme_type, get_theme_presets, find_theme_field_text, get_theme_field_texts,
       get_base_theme, get_theme_appearance, make_theme_cell, get_theme_defaults,
       make_style_field, make_theme_values_field,
       get_appearance_file, save_appearance!, load_appearance!
export COLOR_MODES, COLOR_CONTRASTS, Appearance, scale_theme_value, get_scaled_theme!,
       set_theme!, get_theme, get_theme_value, get_theme_values
export ColorTheme, COLOR_VARIANTS, get_color_variant, make_color_theme, make_color_themes,
       get_color_theme, resolve_theme_color
export TextMeasure, FontMetrics, StringBox, measure_string, get_font_metrics,
       compute_caret_offsets, FontFileMeasure, FixedMeasure, compute_text_extent,
       PlacedGlyph, compute_placed_glyphs
export LineSpacing, SingleSpacing, MultipleSpacing, ExactSpacing, AtLeastSpacing,
       compute_line_distance, compute_baseline_offset, compute_line_metrics,
       compute_line_baseline, LineBox, compute_line_box
export TrueTypeFont, load_truetype_font, get_glyph_id, get_glyph_advance_1000,
       get_ascent_pixels, measure_text_width, get_kerning, get_vertical_metrics


include("Color.jl")
include("ThemeColor.jl")
include("Palette.jl")
include("RadixPalette.jl")
include("Font.jl")
include("TrueType.jl")
include("FontFace.jl")
include("TextMeasure.jl")
include("LineSpacing.jl")
include("Geometry.jl")
include("Image.jl")
include("StyleStroke.jl")
include("StyleText.jl")
include("FontRole.jl")
include("Theme.jl")
include("Appearance.jl")
include("ColorTheme.jl")

end # module
