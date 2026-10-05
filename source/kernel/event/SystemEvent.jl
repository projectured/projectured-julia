# Fragment of `EventModule` — the colour settings of the operating system, and the
# event of their change.

"""
    SystemColors(; mode = :light, contrast = :normal, accent = nothing)
    SystemColors(mode, contrast, accent)

The three colour settings of the operating system: `mode` is `:light` or `:dark`,
`contrast` is `:normal` or `:high`, and `accent` is the accent colour as three bytes
(red, green, blue), or `nothing` when the system names none. A system with no
preference is light and normal. The constructor throws an `ArgumentError` for a
mode or a contrast that is not one of these.

A backend finds them with `find_system_colors`, and an appearance that follows
the system takes them.
"""
struct SystemColors
    mode::Symbol
    contrast::Symbol
    accent::Union{Nothing,NTuple{3,UInt8}}
    function SystemColors(mode::Symbol, contrast::Symbol, accent)
        mode in (:light, :dark) ||
            throw(ArgumentError("the mode of the system is :light or :dark, got $(repr(mode))"))
        contrast in (:normal, :high) ||
            throw(ArgumentError("the contrast of the system is :normal or :high, got $(repr(contrast))"))
        new(mode, contrast, accent)
    end
end

SystemColors(; mode::Symbol = :light, contrast::Symbol = :normal,
             accent::Union{Nothing,NTuple{3,UInt8}} = nothing) =
    SystemColors(mode, contrast, accent)

"""
    SystemColorsChange(colors; time)
    SystemColorsChange(colors, time)

The colour settings of the operating system changed to `colors`, a
[`SystemColors`](@ref). A backend reports it in a `WindowInput` with the window id
`:none`, because it belongs to no window, and only when the settings differ from
the ones that it found before.
"""
struct SystemColorsChange <: Event
    colors::SystemColors
    time::Float64
end

SystemColorsChange(colors::SystemColors; time::Real) = SystemColorsChange(colors, Float64(time))
