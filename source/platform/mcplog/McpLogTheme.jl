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
    "The header that counts the calls."
    heading_text::ThemeText = TextRole(:text_muted; font_role = :section)
    "The method, the tool and the time of a call."
    call_text::ThemeText = TextRole(:text; font_role = :text)
    "The word of a call that was answered."
    answered_text::ThemeText = TextRole(:success_text; font_role = :badge)
    "The word of a call that was a fault."
    fault_text::ThemeText = TextRole(:error_text; font_role = :badge)
    "The answer of a call, and the line that says how much of it is folded."
    muted_text::ThemeText = TextRole(:text_muted; font_role = :quiet)
end
