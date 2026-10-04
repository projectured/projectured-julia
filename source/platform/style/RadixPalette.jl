# Fragment of `StyleModule` — the Radix palette: the 12-step scales of Radix
# Colors, for the light and the dark mode, as data.
#
# The values are the sRGB scales of Radix Colors, `@radix-ui/colors` 3.0.0,
# https://github.com/radix-ui/colors, under the MIT License:
#
# MIT License
#
# Copyright (c) 2021 Radix
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

"""
    RADIX_PALETTE

The palette of Radix Colors: six neutral scales and eight scales of a hue, each
with 12 steps for the light mode and 12 for the dark mode. The hue `blue` is the
Radix scale `indigo`, a deep blue; the neutral `slate` is the default.
"""
const RADIX_PALETTE = TablePalette("radix";
    light = Dict{Symbol,NTuple{12,String}}(
        :slate => ("#fcfcfd", "#f9f9fb", "#f0f0f3", "#e8e8ec", "#e0e1e6", "#d9d9e0",
                  "#cdced6", "#b9bbc6", "#8b8d98", "#80838d", "#60646c", "#1c2024"),
        :gray => ("#fcfcfc", "#f9f9f9", "#f0f0f0", "#e8e8e8", "#e0e0e0", "#d9d9d9",
                 "#cecece", "#bbbbbb", "#8d8d8d", "#838383", "#646464", "#202020"),
        :mauve => ("#fdfcfd", "#faf9fb", "#f2eff3", "#eae7ec", "#e3dfe6", "#dbd8e0",
                  "#d0cdd7", "#bcbac7", "#8e8c99", "#84828e", "#65636d", "#211f26"),
        :sage => ("#fbfdfc", "#f7f9f8", "#eef1f0", "#e6e9e8", "#dfe2e0", "#d7dad9",
                 "#cbcfcd", "#b8bcba", "#868e8b", "#7c8481", "#5f6563", "#1a211e"),
        :olive => ("#fcfdfc", "#f8faf8", "#eff1ef", "#e7e9e7", "#dfe2df", "#d7dad7",
                  "#cccfcc", "#b9bcb8", "#898e87", "#7f847d", "#60655f", "#1d211c"),
        :sand => ("#fdfdfc", "#f9f9f8", "#f1f0ef", "#e9e8e6", "#e2e1de", "#dad9d6",
                 "#cfceca", "#bcbbb5", "#8d8d86", "#82827c", "#63635e", "#21201c"),
        :red => ("#fffcfc", "#fff7f7", "#feebec", "#ffdbdc", "#ffcdce", "#fdbdbe",
                "#f4a9aa", "#eb8e90", "#e5484d", "#dc3e42", "#ce2c31", "#641723"),
        :orange => ("#fefcfb", "#fff7ed", "#ffefd6", "#ffdfb5", "#ffd19a", "#ffc182",
                   "#f5ae73", "#ec9455", "#f76b15", "#ef5f00", "#cc4e00", "#582d1d"),
        :amber => ("#fefdfb", "#fefbe9", "#fff7c2", "#ffee9c", "#fbe577", "#f3d673",
                  "#e9c162", "#e2a336", "#ffc53d", "#ffba18", "#ab6400", "#4f3422"),
        :green => ("#fbfefc", "#f4fbf6", "#e6f6eb", "#d6f1df", "#c4e8d1", "#adddc0",
                  "#8eceaa", "#5bb98b", "#30a46c", "#2b9a66", "#218358", "#193b2d"),
        :teal => ("#fafefd", "#f3fbf9", "#e0f8f3", "#ccf3ea", "#b8eae0", "#a1ded2",
                 "#83cdc1", "#53b9ab", "#12a594", "#0d9b8a", "#008573", "#0d3d38"),
        :indigo => ("#fdfdfe", "#f7f9ff", "#edf2fe", "#e1e9ff", "#d2deff", "#c1d0ff",
                   "#abbdf9", "#8da4ef", "#3e63dd", "#3358d4", "#3a5bc7", "#1f2d5c"),
        :violet => ("#fdfcfe", "#faf8ff", "#f4f0fe", "#ebe4ff", "#e1d9ff", "#d4cafe",
                   "#c2b5f5", "#aa99ec", "#6e56cf", "#654dc4", "#6550b9", "#2f265f"),
        :pink => ("#fffcfe", "#fef7fb", "#fee9f5", "#fbdcef", "#f6cee7", "#efbfdd",
                 "#e7acd0", "#dd93c2", "#d6409f", "#cf3897", "#c2298a", "#651249"),
    ),
    dark = Dict{Symbol,NTuple{12,String}}(
        :slate => ("#111113", "#18191b", "#212225", "#272a2d", "#2e3135", "#363a3f",
                  "#43484e", "#5a6169", "#696e77", "#777b84", "#b0b4ba", "#edeef0"),
        :gray => ("#111111", "#191919", "#222222", "#2a2a2a", "#313131", "#3a3a3a",
                 "#484848", "#606060", "#6e6e6e", "#7b7b7b", "#b4b4b4", "#eeeeee"),
        :mauve => ("#121113", "#1a191b", "#232225", "#2b292d", "#323035", "#3c393f",
                  "#49474e", "#625f69", "#6f6d78", "#7c7a85", "#b5b2bc", "#eeeef0"),
        :sage => ("#101211", "#171918", "#202221", "#272a29", "#2e3130", "#373b39",
                 "#444947", "#5b625f", "#63706b", "#717d79", "#adb5b2", "#eceeed"),
        :olive => ("#111210", "#181917", "#212220", "#282a27", "#2f312e", "#383a36",
                  "#454843", "#5c625b", "#687066", "#767d74", "#afb5ad", "#eceeec"),
        :sand => ("#111110", "#191918", "#222221", "#2a2a28", "#31312e", "#3b3a37",
                 "#494844", "#62605b", "#6f6d66", "#7c7b74", "#b5b3ad", "#eeeeec"),
        :red => ("#191111", "#201314", "#3b1219", "#500f1c", "#611623", "#72232d",
                "#8c333a", "#b54548", "#e5484d", "#ec5d5e", "#ff9592", "#ffd1d9"),
        :orange => ("#17120e", "#1e160f", "#331e0b", "#462100", "#562800", "#66350c",
                   "#7e451d", "#a35829", "#f76b15", "#ff801f", "#ffa057", "#ffe0c2"),
        :amber => ("#16120c", "#1d180f", "#302008", "#3f2700", "#4d3000", "#5c3d05",
                  "#714f19", "#8f6424", "#ffc53d", "#ffd60a", "#ffca16", "#ffe7b3"),
        :green => ("#0e1512", "#121b17", "#132d21", "#113b29", "#174933", "#20573e",
                  "#28684a", "#2f7c57", "#30a46c", "#33b074", "#3dd68c", "#b1f1cb"),
        :teal => ("#0d1514", "#111c1b", "#0d2d2a", "#023b37", "#084843", "#145750",
                 "#1c6961", "#207e73", "#12a594", "#0eb39e", "#0bd8b6", "#adf0dd"),
        :indigo => ("#11131f", "#141726", "#182449", "#1d2e62", "#253974", "#304384",
                   "#3a4f97", "#435db1", "#3e63dd", "#5472e4", "#9eb1ff", "#d6e1ff"),
        :violet => ("#14121f", "#1b1525", "#291f43", "#33255b", "#3c2e69", "#473876",
                   "#56468b", "#6958ad", "#6e56cf", "#7d66d9", "#baa7ff", "#e2ddfe"),
        :pink => ("#191117", "#21121d", "#37172f", "#4b143d", "#591c47", "#692955",
                 "#833869", "#a84885", "#d6409f", "#de51a8", "#ff8dcc", "#fdd1ea"),
    ),
    hues = Dict(:red => :red, :orange => :orange, :amber => :amber, :green => :green,
                :teal => :teal, :blue => :indigo, :violet => :violet, :pink => :pink),
    neutrals = [:slate, :gray, :mauve, :sage, :olive, :sand])

register_palette!(RADIX_PALETTE)
