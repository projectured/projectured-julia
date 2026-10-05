# Fragment of `McpLogModule` — the theme of the MCP log.

"""
    McpLogTheme

The texts of the MCP log: its header, the line of a call, an answered call and a
fault, and a quiet text for the rest. `@theme` declares it, so
`ScaledMcpLogTheme` holds each value times its scale, and `McpLogTheme()` is the
default theme. `make_mcp_log_projection` gives the projection its styles with
`get_mcp_log_style`.
"""
@theme struct McpLogTheme
    "The font that the texts of this theme follow: its family, its weight and its size."
    font::StyleFont = StyleFont("Ubuntu", 14)
    "The header that counts the calls."
    heading_text::TextRole = TextRole(:heading; weight = 700)
    "The method, the tool and the time of a call."
    call_text::TextRole = TextRole(:text)
    "The word of a call that was answered."
    answered_text::TextRole = TextRole(:success_text; weight = 700)
    "The word of a call that was a fault."
    fault_text::TextRole = TextRole(:error_text; weight = 700)
    "The answer of a call, and the line that says how much of it is folded."
    muted_text::TextRole = TextRole(:text_muted)
    "The vertical gap between the parts of the log and of a call."
    gap::Int = 6
end
