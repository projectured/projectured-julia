# Fragment of `FileSystemModule` — the rules of a `.gitignore` file, read with no
# git, and the test of a path against the rules of the folders above it.
#
# The rules are those of git: a blank line and a line that starts with `#` are no
# rule; `!` makes a rule take a path back; a `/` at the end matches only a folder;
# a `/` at the start or in the middle ties the rule to the folder of the file,
# else it matches a name at any depth; `*` matches any characters but `/`, `?` one
# character but `/`, `[…]` one character of a set, and `**` any folders. A
# backslash takes the next character as it is. The last rule that matches a path
# decides, and a rule of a deeper folder comes after the rules above it.

"""
    GitIgnoreRule(pattern, is_negated, is_folder_only)

One rule of a `.gitignore` file: `pattern`, the expression that a path relative
to the folder of the file matches; `is_negated`, a rule that takes a path back;
and `is_folder_only`, a rule that matches only a folder.
"""
struct GitIgnoreRule
    pattern::Regex
    is_negated::Bool
    is_folder_only::Bool
end

"""
    read_gitignore_rules(text) -> Vector{GitIgnoreRule}

The rules of the text of a `.gitignore` file, in their order.
"""
function read_gitignore_rules(text::AbstractString)
    rules = GitIgnoreRule[]
    for line in eachline(IOBuffer(text))
        rule = _read_gitignore_line(line)
        rule === nothing || push!(rules, rule)
    end
    rules
end

function _read_gitignore_line(line::AbstractString)
    line = _strip_gitignore_spaces(rstrip(line, '\r'))
    (isempty(line) || startswith(line, '#')) && return nothing
    is_negated = startswith(line, '!')
    is_negated && (line = line[nextind(line, 1):end])
    (startswith(line, "\\#") || startswith(line, "\\!")) && (line = line[2:end])
    is_folder_only = endswith(line, '/') && !endswith(line, "\\/")
    is_folder_only && (line = line[1:prevind(line, lastindex(line))])
    isempty(line) && return nothing
    # A slash at the start or in the middle ties the rule to the folder of the file.
    is_anchored = occursin('/', line)
    startswith(line, '/') && (line = line[2:end])
    body = _make_gitignore_expression(line)
    GitIgnoreRule(Regex((is_anchored ? "^" : "^(?:.*/)?") * body * "\$"), is_negated, is_folder_only)
end

# A space at the end of a line is no part of the rule, unless a backslash keeps it.
function _strip_gitignore_spaces(line::AbstractString)
    stripped = rstrip(line, ' ')
    length(stripped) < length(line) && endswith(stripped, '\\') ? stripped[1:(end - 1)] * " " : stripped
end

# The regular expression of the glob `glob`.
function _make_gitignore_expression(glob::AbstractString)
    characters = collect(glob)
    out = IOBuffer()
    index = 1
    while index <= length(characters)
        character = characters[index]
        if character == '*'
            if index < length(characters) && characters[index + 1] == '*'
                # `**/` is any folders, `/**` at the end is everything inside.
                at_start = index == 1 || characters[index - 1] == '/'
                next = index + 2
                if at_start && next <= length(characters) && characters[next] == '/'
                    print(out, "(?:.*/)?")
                    index = next + 1
                    continue
                elseif at_start && next > length(characters)
                    print(out, ".*")
                    index = next
                    continue
                end
                print(out, "[^/]*")
                index = next
                continue
            end
            print(out, "[^/]*")
        elseif character == '?'
            print(out, "[^/]")
        elseif character == '['
            closing = findnext(==(']'), characters, index + 1)
            if closing === nothing
                print(out, "\\[")
            else
                set = characters[(index + 1):(closing - 1)]
                negated = !isempty(set) && set[1] in ('!', '^')
                negated && (set = set[2:end])
                print(out, negated ? "[^" : "[")
                for member in set
                    print(out, member in ('\\', ']', '[', '^') ? "\\" * member : member)
                end
                print(out, "]")
                index = closing
            end
        elseif character == '\\' && index < length(characters)
            index += 1
            print(out, _escape_expression_character(characters[index]))
        else
            print(out, _escape_expression_character(character))
        end
        index += 1
    end
    String(take!(out))
end

_escape_expression_character(character::Char) =
    character in ".^\$|()[]{}*+?\\/" ? "\\" * character : string(character)

"""
    is_gitignored(rule_sets, path, is_folder) -> Bool

Whether the rules ignore `path`, a path with `/` between its folders relative to
the root of the read, of a folder when `is_folder`. `rule_sets` holds a pair of
the folder of a `.gitignore` file, relative to the root as well (`""` for the
root itself), and its rules, from the root down; a path is matched relative to
the folder of each file that is above it, and the last rule that matches decides.
"""
function is_gitignored(rule_sets, path::AbstractString, is_folder::Bool)
    ignored = false
    for (folder, rules) in rule_sets
        relative = isempty(folder) ? path :
                   startswith(path, folder * "/") ? path[(ncodeunits(folder) + 2):end] : continue
        for rule in rules
            (rule.is_folder_only && !is_folder) && continue
            occursin(rule.pattern, relative) && (ignored = !rule.is_negated)
        end
    end
    ignored
end
