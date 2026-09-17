# Fragment of `ProjecturedBuilder` — the command line every binary answers,
# whatever else it answers.
#
# Four flags belong to the build and not to a program: `--build-info` says what
# went in, `--version` says which binary this is, `--help` says which flags
# exist, and `--log-level` says how much the binary says while it runs. A program
# cannot write any of the four, because a program does not know what the build
# put in — and a flag exists only over what the binary holds, which is the build
# function's decision.
#
# `--log-level` is the one of the four a program could have written, and no
# program should have to: every binary logs, and every one of them logged at
# `Info` because that is Julia's default and nothing changed it.
#
# So the builder writes them into the module it generates, beside the constant
# they read.

# Where a description starts, counted from the start of the line, so that a
# person who reads one binary's help text and then another's sees one shape.
const _OPTION_WIDTH = 27

"""
    Usage(description; synopsis, options)

What a binary's `--help` prints.

- `description` — what the binary does, in a sentence or two.
- `synopsis` — what follows the name on the command line, such as
  `"[options] [project directory]"`.
- `options` — the flags this binary reads, as `"--backend=web" => "what it
  does"`. The four the builder answers are added here and must not be listed.

**A build function writes this, and a package cannot.** The flags a binary reads
are the ones its `main` reads, and its `main` is what the build function wrote —
so `--backend` exists when two backends went in and not otherwise.

A build function that writes no `Usage` keeps the command line its program owns:
a program that parses its own command line answers its own `-h` with a text only
it can write, and the builder steps aside.
"""
struct Usage
    description::String
    synopsis::String
    options::Vector{Pair{String,String}}
end

Usage(description::AbstractString; synopsis::AbstractString = "[options]",
      options = Pair{String,String}[]) =
    Usage(String(description), String(synopsis),
          Pair{String,String}[String(first(o)) => String(last(o)) for o in options])

"""
    format_usage(name, usage) -> String

The help text of the binary called `name`.

The builder's own four flags come last, and they are appended here rather than
asked of a build function, so no binary can be built without them.
"""
function format_usage(name::AbstractString, usage::Usage)
    lines = ["Usage: $name" * (isempty(usage.synopsis) ? "" : " " * usage.synopsis), ""]
    isempty(usage.description) || append!(lines, [usage.description, ""])
    options = vcat(usage.options,
                   ["--log-level=<level>" =>
                        "how much the run says: debug, info, warn, error, none",
                    "-h, --help" => "print this text and exit",
                    "-v, --version" => "print the version and exit",
                    "--build-info" => "print what this build was made with and exit"])
    for (flag, what) in options
        push!(lines, "  " * rpad(flag, _OPTION_WIDTH) * what)
    end
    join(lines, "\n") * "\n"
end

"""
    format_version_line(context, name) -> String

What `--version` prints: the name the build chose, and `context.version`.
"""
format_version_line(context::BuildContext, name::AbstractString) = "$name $(context.version)"

"""
    collect_option_flags(usage) -> Vector{String}

Every flag the binary accepts, read from the labels a build function wrote plus
the four the builder answers.

A label that carries a value is kept as its prefix — `"--backend=web"` accepts
`--backend=` and whatever follows it — and a label without one must match whole.
`"-h, --help"` is two flags, so a label splits on its commas.

**This is what makes the help text true.** The flags a binary lists are the flags
it takes, and it refuses the rest instead of reading them as something else.
"""
function collect_option_flags(usage::Usage)
    flags = String[]
    for (label, _) in usage.options
        for token in split(label, ',')
            token = strip(token)
            isempty(token) && continue
            startswith(token, "-") || continue
            # A label may name the value it takes — `-f <file>` — and the flag is
            # the first word of it. A value joined by `=` keeps the `=`, because
            # that is how it arrives on a command line.
            token = first(split(token))
            index = findfirst('=', token)
            push!(flags, index === nothing ? String(token) : String(token[1:index]))
        end
    end
    # `--log-level=` is listed although `julia_main` takes it out of `ARGS`
    # before this matcher is reached. The help text and the matcher are one pair,
    # and a flag in one and not the other is what the pair exists to prevent.
    append!(flags, ["--log-level=", "-h", "--help", "-v", "--version", "--build-info"])
    unique!(flags)
    flags
end
