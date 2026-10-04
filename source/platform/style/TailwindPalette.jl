# Fragment of `StyleModule` — the Tailwind palette: the 11 shades of the
# colours of Tailwind CSS, resampled to the 12 steps of a palette.
#
# The shades are the default colour palette of Tailwind CSS, `tailwindcss` 3.4.17,
# https://tailwindcss.com, under the MIT License:
#
# MIT License
#
# Copyright (c) Tailwind Labs, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# The 11 shades of each colour, from 50 to 950, and the hue of the Radix
# palette whose lightness each step of its ramp takes.
const _TAILWIND_SHADES = (
    slate = (:neutral, ["#f8fafc", "#f1f5f9", "#e2e8f0", "#cbd5e1", "#94a3b8", "#64748b",
                         "#475569", "#334155", "#1e293b", "#0f172a", "#020617"]),
    gray = (:neutral, ["#f9fafb", "#f3f4f6", "#e5e7eb", "#d1d5db", "#9ca3af", "#6b7280",
                        "#4b5563", "#374151", "#1f2937", "#111827", "#030712"]),
    zinc = (:neutral, ["#fafafa", "#f4f4f5", "#e4e4e7", "#d4d4d8", "#a1a1aa", "#71717a",
                        "#52525b", "#3f3f46", "#27272a", "#18181b", "#09090b"]),
    neutral = (:neutral, ["#fafafa", "#f5f5f5", "#e5e5e5", "#d4d4d4", "#a3a3a3", "#737373",
                           "#525252", "#404040", "#262626", "#171717", "#0a0a0a"]),
    stone = (:neutral, ["#fafaf9", "#f5f5f4", "#e7e5e4", "#d6d3d1", "#a8a29e", "#78716c",
                         "#57534e", "#44403c", "#292524", "#1c1917", "#0c0a09"]),
    red = (:red, ["#fef2f2", "#fee2e2", "#fecaca", "#fca5a5", "#f87171", "#ef4444",
                       "#dc2626", "#b91c1c", "#991b1b", "#7f1d1d", "#450a0a"]),
    orange = (:orange, ["#fff7ed", "#ffedd5", "#fed7aa", "#fdba74", "#fb923c", "#f97316",
                          "#ea580c", "#c2410c", "#9a3412", "#7c2d12", "#431407"]),
    amber = (:amber, ["#fffbeb", "#fef3c7", "#fde68a", "#fcd34d", "#fbbf24", "#f59e0b",
                         "#d97706", "#b45309", "#92400e", "#78350f", "#451a03"]),
    emerald = (:green, ["#ecfdf5", "#d1fae5", "#a7f3d0", "#6ee7b7", "#34d399", "#10b981",
                           "#059669", "#047857", "#065f46", "#064e3b", "#022c22"]),
    teal = (:teal, ["#f0fdfa", "#ccfbf1", "#99f6e4", "#5eead4", "#2dd4bf", "#14b8a6",
                        "#0d9488", "#0f766e", "#115e59", "#134e4a", "#042f2e"]),
    blue = (:blue, ["#eff6ff", "#dbeafe", "#bfdbfe", "#93c5fd", "#60a5fa", "#3b82f6",
                        "#2563eb", "#1d4ed8", "#1e40af", "#1e3a8a", "#172554"]),
    violet = (:violet, ["#f5f3ff", "#ede9fe", "#ddd6fe", "#c4b5fd", "#a78bfa", "#8b5cf6",
                          "#7c3aed", "#6d28d9", "#5b21b6", "#4c1d95", "#2e1065"]),
    pink = (:pink, ["#fdf2f8", "#fce7f3", "#fbcfe8", "#f9a8d4", "#f472b6", "#ec4899",
                        "#db2777", "#be185d", "#9d174d", "#831843", "#500724"]),
)

"""
    TAILWIND_PALETTE

The palette of Tailwind CSS: five neutral colours and eight colours of a hue, each
with its 11 shades resampled in OKLab to the lightness of the 12 steps of the
Radix palette, for the light and for the dark mode. The hue `green` is the
Tailwind colour `emerald`; the neutral `slate` is the default.
"""
const TAILWIND_PALETTE = TablePalette("tailwind";
    light = Dict(name => make_resampled_ramp(shades, hue, :light) for (name, (hue, shades)) in pairs(_TAILWIND_SHADES)),
    dark = Dict(name => make_resampled_ramp(shades, hue, :dark) for (name, (hue, shades)) in pairs(_TAILWIND_SHADES)),
    hues = Dict(:red => :red, :orange => :orange, :amber => :amber, :green => :emerald,
                :teal => :teal, :blue => :blue, :violet => :violet, :pink => :pink),
    neutrals = [:slate, :gray, :zinc, :neutral, :stone])

register_palette!(TAILWIND_PALETTE)
