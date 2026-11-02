# Fragment of `BuilderModule` — the program that holds its image: the launcher
# of this builder, linked with the object archive of the image into one
# `ET_EXEC`, and the image restored once in the build and written back into the
# program (the prelink).
#
# The launcher of PackageCompiler compiles the parser at every start, and the
# image it loads, `lib/julia/sys.so`, lands at another address at every start,
# so the restore converts every pointer of the image at every start. A program
# that holds its image at one address can keep a restore done once, and a start
# then applies a short list of pointers that a file can not hold.

"""
    LAUNCHER

The C entry of a linked program, in place of the launcher of PackageCompiler.

**The launcher of PackageCompiler compiles the parser at every start.** It
reaches `Base.ARGS` and `Base.PROGRAM_FILE` with `jl_eval_string`, and the first
such call compiles the JuliaSyntax parser to read one line: about 90 ms before
the first instruction of the program. This one uses only the C API on objects
that the image holds, so a start pays the restore of the image and nothing
else.
"""
const LAUNCHER = joinpath(@__DIR__, "launcher.c")

# The link helpers of the compiler, so that the link line below and the one the
# compiler writes for its own launcher agree about the compiler, the include
# directory, the libraries and the rpath.
_compiler_flag(name::Symbol, arguments...) =
    Base.invokelatest(getfield(Base.require(PACKAGE_COMPILER), name), arguments...)

"""
    get_object_archive(output) -> String

Where a build keeps the object archive that the image is made of: beside the
bundle, in `<output>.object/sys-o.a`.

**The program is linked from it.** PackageCompiler links the archive into
`lib/julia/sys.so` and then deletes it; the build asks for it to stay, because
[`link_executable!`](@ref) links the same archive into the program. It stays
beside the bundle and not in it: a start reads none of it, and a distribution
archives the bundle folder whole. It stays on disk so that a relink needs no
rebuild.
"""
get_object_archive(output::AbstractString) = joinpath(abspath(output) * ".object", "sys-o.a")

# Ask `create_app` to leave the object archive of the image at `path`, by the
# name that the loaded compiler knows it under: `sysimage_object_path` writes the
# archive at the path, `keep_object_archive` copies it there when the build
# ends. A compiler that takes neither can not keep it.
function _object_archive_keyword(path::AbstractString)
    # A copy does not make the folder that it writes into.
    mkpath(dirname(abspath(path)))
    names = Base.kwarg_decl(only(methods(getfield(Base.require(PACKAGE_COMPILER),
                                                  :create_app))))
    :sysimage_object_path in names && return (; sysimage_object_path = path)
    :keep_object_archive in names && return (; keep_object_archive = path)
    error("build_executable: this PackageCompiler can not keep the object archive of " *
          "the image, and the build links its program from it")
end

# Whether a build prelinks: a prelink is a build for Linux, for one code
# variant, with a runtime that knows the option.
#
# **A prelink freezes the choice of code variant.** The restore stores the entry
# points of the variant that the machine selects, and a prelink writes them into
# the file. An image compiled for several processors selects at every start, so
# it keeps its restore at start. **A prelink needs a runtime that knows it.** A
# build with a stock Julia gives a program with a slower start and nothing else
# different. A call with `compile = false`, as a script that runs from source
# makes, compiles no image, so it says nothing of it.
function _choose_prelink(prelink::Bool, cpu_target::AbstractString, compile::Bool)
    prelink && Sys.islinux() || return false
    if isempty(cpu_target) || occursin(';', cpu_target)
        @info "build_executable: an image of several code variants keeps its restore at start"
        return false
    end
    if compile && !_has_prelink_option()
        @info "build_executable: this Julia has no --sysimage-prelink, so the program " *
              "restores its image at every start: it is complete and starts slower. The " *
              "branch merged of https://github.com/levy/julia has the option and the " *
              "reactive compiler. --no-prelink asks for this build and says nothing."
        return false
    end
    true
end

# The option table of the running Julia, which is the runtime that the build
# compiles with and the runtime that the program it writes carries. A Julia that
# prelinks declares `--sysimage-prelink` and `--output-prelinked`, and both
# become fields of `Base.JLOptions`.
_has_prelink_option() = :sysimage_prelink in fieldnames(Base.JLOptions)

"""
    compile_linked_app!(project, output, name; force, optimization, debug_info,
                        strip_metadata, cpu_target, incremental, filter_stdlibs,
                        prelink) -> String

Compile `project` into `output` as a program that holds its image: the image
through `create_app` with no executable of PackageCompiler, then
[`link_executable!`](@ref), with `prelink` [`prelink_executable!`](@ref), and
[`strip_bundle!`](@ref). With `prelink`, the image reserves room for the list of
pointers that a start of a prelinked image writes (`--sysimage-prelink=yes`).
"""
function compile_linked_app!(project::AbstractString, output::AbstractString, name::AbstractString;
                             force::Bool = true, optimization::Integer = 3,
                             debug_info::Integer = 1, strip_metadata::Bool = false,
                             cpu_target::AbstractString = "", incremental::Bool = true,
                             filter_stdlibs::Bool = false, prelink::Bool = true)
    arguments = `-O$(optimization) -g$(debug_info)`
    strip_metadata && (arguments = `$arguments --strip-metadata`)
    prelink && (arguments = `$arguments --sysimage-prelink=yes`)
    @info "Compiling $name" incremental prelink
    # Splatted in only when it has a value: `create_app` takes a `String` and
    # refuses `nothing`, so an absent one has to be absent rather than empty.
    _create_app(project, output;
                executables = Pair{String,String}[],
                force = force,
                incremental = incremental,
                filter_stdlibs = filter_stdlibs,
                include_lazy_artifacts = true,
                sysimage_build_args = arguments,
                _object_archive_keyword(get_object_archive(output))...,
                (isempty(cpu_target) ? () : (; cpu_target = String(cpu_target)))...)
    link_executable!(output, name)
    prelink && prelink_executable!(output, name)
    strip_bundle!(output)
    output
end

"""
    REACTIVE_HEADROOM

The bytes that the program of a reactive store reserves after its image: the
headroom of the region of the runtime, 64 MB for the constant data and 256 MB
for the new objects of an overlay. A start of a prelinked program under a chain
writes the overlay there, so the image can stay where the prelink put it. The
runtime names the size that it needs when a program reserves less.
"""
const REACTIVE_HEADROOM = (64 + 256) << 20

"""
    link_executable!(output, name; headroom = false) -> String

Link `bin/<name>` from the launcher and the object archive of the image, as one
program that holds the image.

**An `ET_EXEC`, so that the image has one address.** A restore converts every
pointer in the image for the address that the image landed at, and the same
restore at the same address is the same work, so work done once in the build
can be written into the file. Linux moves a position-independent executable
and every library at each start, and an `ET_EXEC` never, so the image is linked
into the program with `-no-pie`, and not into a library beside it.

The two symbols that the loader looks up by name, `jl_image_unpack` and the
consistency check, must be in the dynamic symbol table of the program for
`dlsym` on its own handle to find them. The `ldflags` of the compiler carry
`--export-dynamic`, which exports the few symbols that the image object and
the launcher define.

With `headroom`, a linker script puts a section with no bytes in the file right
after `.ldata`, the last section of the image, of [`REACTIVE_HEADROOM`](@ref):
the program of a reactive store applies its overlay there.
"""
function link_executable!(output::AbstractString, name::AbstractString; headroom::Bool = false)
    executable = joinpath(output, "bin", String(name))
    mkpath(dirname(executable))
    archive = get_object_archive(output)
    isfile(archive) || error("link_executable!: no object archive at $archive")
    flags = Base.shell_split(join((_compiler_flag(:cflags), _compiler_flag(:ldflags),
                                   _compiler_flag(:ldlibs)), " "))
    tls = getfield(Base.require(PACKAGE_COMPILER), :TLS_SYNTAX)
    reserve = String[]
    if headroom
        script = joinpath(dirname(archive), "headroom.ld")
        write(script, """
            SECTIONS
            {
              .reactive_headroom (NOLOAD) : ALIGN(4096) { . = . + $(REACTIVE_HEADROOM); }
            }
            INSERT AFTER .ldata;
            """)
        reserve = ["-Wl,-T,$script"]
    end
    @info "Linking $executable" archive headroom
    _compiler_flag(:run_compiler,
        `-DJULIA_MAIN=\"$(get_app_module_name(name)).julia_main\" $tls
         $(_compiler_flag(:bitflag)) $(_compiler_flag(:march)) -no-pie
         -o $executable $LAUNCHER
         -Wl,--whole-archive $archive -Wl,--no-whole-archive $reserve
         $(_compiler_flag(:rpath_executable)) $flags`)
    executable
end

"""
    prelink_executable!(output, name) -> String

Restore the image once, at the address that the linker gave it, and write the
restored image back into `bin/<name>`.

**A restore done once at the final address stays done.** The restore turns
every relocation id in the image into a pointer, and in an `ET_EXEC` most of
those pointers are the same at every start: the runtime writes them into the
file, keeps a list of the ones that are not, and a start of the written image
applies that list and nothing else of the relocation work.

The runtime does the work itself when `--output-prelinked` names a file: it
restores, writes a copy of the running program with the restored image into
that file, and stops. Linux refuses to open a running program for writing, so
the copy is written beside the program and moved over it. A runtime that does
not know the option refuses the command line, and this function then stops; a
build never reaches it on such a runtime, because `build_executable` reads the
option table first and turns the prelink off.
"""
function prelink_executable!(output::AbstractString, name::AbstractString)
    executable = joinpath(output, "bin", String(name))
    prelinked = executable * ".prelinked"
    rm(prelinked; force = true)
    @info "Prelinking $executable"
    run(Cmd(`$executable --julia-args --output-prelinked=$prelinked`;
            dir = dirname(executable)))
    isfile(prelinked) ||
        error("prelink_executable!: the runtime wrote no $prelinked, so it has no prelink")
    mv(prelinked, executable; force = true)
    executable
end

"""
    strip_bundle!(output) -> Nothing

Move out of the bundle what no start reads.

**The image is inside the program**, and `lib/julia/sys.so` is that image a
second time. It goes beside the bundle, into the folder that holds the object
archive, where `julia --sysimage=` can still name it. `bin/julia` is removed:
it is the program that loads `lib/julia/sys.so`, and it can not start without
it. What stays is the program, the libraries that it links against, and its
depot.
"""
function strip_bundle!(output::AbstractString)
    image = joinpath(output, "lib", "julia", "sys.so")
    if isfile(image)
        beside = joinpath(dirname(get_object_archive(output)), "sys.so")
        @info "Moving $image beside the bundle" to = beside size = Base.format_bytes(filesize(image))
        mkpath(dirname(beside))
        mv(image, beside; force = true)
    end
    program = joinpath(output, "bin", "julia")
    if isfile(program)
        @info "Removing $program, which loads the image that moved"
        rm(program)
    end
    nothing
end
