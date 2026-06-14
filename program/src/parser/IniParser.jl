"""
    IniParserModule

Parser for OMNeT++ INI configuration files. Converts INI file text into an
`IniFile` document tree from `IniModule`.

Provides:
- `iniparse(text)` — parse an INI string into an `IniFile`
- `iniparse_file(path)` — read and parse an INI file from disk

Handles line continuation (backslash and indentation), section headings
(`[General]`, `[Config Name]`, `[Name]`), include directives, key-value
entries with quote-aware inline comment extraction, and classification into
`IniConfigOption` (no dots) vs `IniParamAssignment` (dots in key).
"""
module IniParserModule

import ..IniModule: IniFile, IniSection, IniConfigOption, IniParamAssignment, IniComment, IniInclude
export iniparse, iniparse_file

"""
    iniparse(text::AbstractString) -> IniFile

Parse an OMNeT++ INI file string into an `IniFile` document tree.

Handles:
- Comment lines (`#`)
- Section headings (`[General]`, `[Config Name]`, `[Name]`)
- Include directives (`include <path>`)
- Key-value lines (split on first `=`)
- Line continuation (trailing `\\` and indentation)
- Inline comment extraction (quote-aware)
- Classification of entries into `IniConfigOption` (no dots) and
  `IniParamAssignment` (dots in key)

Blank lines are skipped.
"""
function iniparse(text::AbstractString)
    lines = _join_continuation_lines(split(text, '\n'))
    file = IniFile()
    current_section = nothing  # ::Union{Nothing, IniSection}

    for line in lines
        stripped = lstrip(line)

        # blank line
        isempty(stripped) && continue

        # comment line
        if startswith(stripped, '#')
            comment = IniComment(String(stripped[2:end]))
            if current_section === nothing
                push!(file, comment)
            else
                push!(current_section, comment)
            end
            continue
        end

        # section heading
        m = match(r"^\s*\[([^\]]*)\]\s*(#.*)?$", line)
        if m !== nothing
            # finish previous section
            if current_section !== nothing
                push!(file, current_section)
            end
            raw_name = strip(String(m.captures[1]))
            if raw_name == "General"
                current_section = IniSection("General"; is_general=true)
            elseif startswith(raw_name, "Config ")
                current_section = IniSection(String(strip(raw_name[8:end])); is_general=false)
            else
                current_section = IniSection(String(raw_name); is_general=false)
            end
            # trailing comment on section heading line
            if m.captures[2] !== nothing
                trailing = String(m.captures[2][2:end])  # strip leading #
                push!(current_section, IniComment(trailing))
            end
            continue
        end

        # include directive
        if startswith(stripped, "include ")
            path = strip(stripped[9:end])
            # strip optional quotes
            if length(path) >= 2 && path[1] == '"' && path[end] == '"'
                path = path[2:end-1]
            end
            inc = IniInclude(String(path))
            if current_section === nothing
                push!(file, inc)
            else
                push!(current_section, inc)
            end
            continue
        end

        # key-value line
        eq_pos = findfirst('=', line)
        if eq_pos !== nothing
            raw_key = strip(line[1:eq_pos-1])
            raw_val = strip(line[eq_pos+1:end])
            value_str, comment_str = _extract_inline_comment(raw_val)
            entry = if occursin('.', raw_key)
                IniParamAssignment(String(raw_key), String(value_str);
                                   comment=comment_str)
            else
                IniConfigOption(String(raw_key), String(value_str);
                                comment=comment_str)
            end
            if current_section === nothing
                # key-value before first section — wrap in implicit General
                current_section = IniSection("General"; is_general=true)
                push!(current_section, entry)
            else
                push!(current_section, entry)
            end
            continue
        end

        # unrecognised line — treat as comment
        comment = IniComment(String(stripped))
        if current_section === nothing
            push!(file, comment)
        else
            push!(current_section, comment)
        end
    end

    # flush last section
    if current_section !== nothing
        push!(file, current_section)
    end

    return file
end

"""
    iniparse_file(path::AbstractString) -> IniFile

Read an INI file from disk and parse it into an `IniFile` document tree.
Does **not** recursively follow `include` directives.
"""
function iniparse_file(path::AbstractString)
    iniparse(read(path, String))
end

# ── Helpers ──────────────────────────────────────────────────────────────────

# Join continuation lines: backslash continuation and indentation continuation.
function _join_continuation_lines(raw_lines)
    # Phase 1: backslash continuation
    joined = String[]
    i = 1
    while i <= length(raw_lines)
        line = raw_lines[i]
        while endswith(rstrip(line), '\\') && i < length(raw_lines)
            # remove trailing backslash (and any whitespace before it at the end)
            line = rstrip(line)
            line = line[1:prevind(line, lastindex(line))]
            i += 1
            line = line * raw_lines[i]
        end
        push!(joined, line)
        i += 1
    end

    # Phase 2: indentation continuation
    result = String[]
    for line in joined
        if !isempty(line) && (line[1] == ' ' || line[1] == '\t') &&
           !isempty(result) && !startswith(lstrip(line), '#')
            # continuation of previous line
            result[end] = result[end] * " " * strip(line)
        else
            push!(result, line)
        end
    end

    return result
end

# Extract trailing inline comment from a value string (quote-aware).
# Returns (value, comment) where comment is Nothing or String.
function _extract_inline_comment(raw_value::AbstractString)
    in_quotes = false
    prev_char = '\0'
    for (i, ch) in enumerate(raw_value)
        if ch == '"' && prev_char != '\\'
            in_quotes = !in_quotes
        elseif ch == '#' && !in_quotes
            value_part = rstrip(raw_value[1:prevind(raw_value, i)])
            comment_part = String(raw_value[nextind(raw_value, i):end])
            return (String(value_part), comment_part)
        end
        prev_char = ch
    end
    return (String(raw_value), nothing)
end

end # module
