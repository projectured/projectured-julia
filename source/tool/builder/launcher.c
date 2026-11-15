// ============================================================================
// The C entry of a compiled program: start the image, hand over the arguments,
// call `julia_main`, exit with its code.
//
// **No call enters the parser.** The stock PackageCompiler launcher reaches
// `Base.ARGS` and `Base.PROGRAM_FILE` with `jl_eval_string`, and the first
// such call compiles the JuliaSyntax parser to read one line: about 90 ms
// before the program's first instruction, on every start. This entry uses only
// the C API on objects the image already holds — the arrays, the bindings, and
// the `julia_main` method the workload compiled — so the start pays the image
// restore and nothing else.
//
// **The image is this executable.** The build links the image's object
// archive into the program, and links the program as an `ET_EXEC`, so the
// image sits at the address the linker gave it, at every start, and a
// restore done once can stay done. The loader finds the image through the
// handle of the running program. `jl_options.image_file` then names the
// directory of the executable, because the running program's link map has no
// name; nothing in a compiled program reads it after the restore.
//
// `JULIA_MAIN` is `<Module>.julia_main`, defined on the compiler command line
// by the build, the same way PackageCompiler defines it.
// ============================================================================

#include <dlfcn.h>
#include <errno.h>
#include <libgen.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "julia.h"
#include "uv.h"

#ifdef NEW_DEFINE_FAST_TLS_SYNTAX
JULIA_DEFINE_FAST_TLS
#else
JULIA_DEFINE_FAST_TLS()
#endif

// ---------------------------------------------------------------------------
// The stub table: one fixed address in this program for each entry point of
// the runtime that the image points at.
//
// **The image is restored once, in the build, and the restore writes a pointer
// into the image for every entry point it names.** Those entry points —
// `jl_fptr_args` and its four companions, and the 67 builtin functions — live
// in `libjulia-internal`, which the loader puts at a new address at every
// start, so their pointers cannot be written into the file. There are 29,000
// of them, spread over 8,500 pages of the image, and writing them costs 8 ms
// of copy-on-write at each start.
//
// A stub is a jump through a pointer. The stubs are in this program, which is
// an `ET_EXEC` at one address, so the image points at the stubs and the file
// holds those pointers. The runtime fills `jl_prelink_stub_targets` at each
// start, which is 72 stores into one page, and finds the table by these three
// symbols. A program without them keeps its restore.
//
// The cost is one indirect jump on a call that goes through such a slot, which
// is a dynamic dispatch. A call into the image's own code does not pass here.
// ---------------------------------------------------------------------------

#define JL_PRELINK_STUB_COUNT 128
#define JL_PRELINK_STUB_STRIDE 16

void *jl_prelink_stub_targets[JL_PRELINK_STUB_COUNT];
const size_t jl_prelink_stub_count = JL_PRELINK_STUB_COUNT;
const size_t jl_prelink_stub_stride = JL_PRELINK_STUB_STRIDE;

#if defined(__x86_64__)
__asm__(
    ".text\n"
    ".balign 16\n"
    ".globl jl_prelink_stubs\n"
    ".type jl_prelink_stubs, @function\n"
    "jl_prelink_stubs:\n"
    ".set jl_prelink_stub_index, 0\n"
    ".rept 128\n"
    "  .balign 16\n"
    "  jmp *jl_prelink_stub_targets+jl_prelink_stub_index*8(%rip)\n"
    "  .set jl_prelink_stub_index, jl_prelink_stub_index + 1\n"
    ".endr\n"
    ".size jl_prelink_stubs, .-jl_prelink_stubs\n");
#endif

// Print the pending exception and stop. `showerror` is fetched before the
// exception is read, because a call clears the pending exception.
static void fail_with_exception(const char *what) {
    jl_value_t *showerror = jl_get_function(jl_base_module, "showerror");
    jl_value_t *exception = jl_exception_occurred();
    JL_GC_PUSH1(&exception);
    fprintf(stderr, "ERROR: %s failed\n", what);
    jl_call2(showerror, jl_stderr_obj(), exception);
    jl_printf(jl_stderr_stream(), "\n");
    JL_GC_POP();
    jl_atexit_hook(1);
    exit(1);
}

// The depot and the load path of a bundled program are under its own root,
// and the environment is read by `jl_init`, so this runs before it.
static void set_depot_load_path(const char *root_dir) {
    static const char *share = "/share/julia";
    const char *names[2] = {"JULIA_DEPOT_PATH", "JULIA_LOAD_PATH"};
    for (int i = 0; i < 2; i++) {
        const char *current = getenv(names[i]);
        size_t current_length = current == NULL ? 0 : strlen(current);
        char *value = calloc(current_length + strlen(root_dir) + strlen(share) + 2, 1);
        if (current_length > 0) {
            strcat(value, current);
            strcat(value, ":");
        }
        strcat(value, root_dir);
        strcat(value, share);
        setenv(names[i], value, 1);
        free(value);
    }
}

// `Base.ARGS` gets the program arguments and `Base.PROGRAM_FILE` the program
// name, as `Base._start` sets them for a script. The image may hold a stale
// `Base.ARGS`, so it is emptied first.
//
// **The assignment runs in the latest world.** The task that `jl_init` leaves
// behind sits in the first world, where `Base.PROGRAM_FILE` is not declared
// yet, and an assignment there is refused. `jl_call` moves to the latest world
// for the same reason; this does it by hand because no call is made.
static void set_program_arguments(int argc, char **argv) {
    jl_array_t *args = (jl_array_t *)jl_get_global(jl_base_module, jl_symbol("ARGS"));
    jl_array_del_end(args, jl_array_nrows(args));
    jl_array_grow_end(args, argc - 1);
    jl_value_t *string = NULL;
    JL_GC_PUSH1(&string);
    for (int i = 1; i < argc; i++) {
        string = jl_cstr_to_string(argv[i]);
        jl_array_ptr_set(args, i - 1, string);
    }
    string = jl_cstr_to_string(argv[0]);
    jl_task_t *task = jl_current_task;
    size_t world = task->world_age;
    task->world_age = jl_get_world_counter();
    JL_TRY {
        jl_set_global(jl_base_module, jl_symbol("PROGRAM_FILE"), string);
    }
    JL_CATCH {
        task->ptls->previous_exception = jl_current_exception(task);
    }
    task->world_age = world;
    JL_GC_POP();
    if (jl_exception_occurred())
        fail_with_exception("setting Base.PROGRAM_FILE");
}

// `JULIA_MAIN` names the function through its module: `Main.<Module>.julia_main`.
static jl_value_t *find_julia_main(void) {
    const char *name = JULIA_MAIN;
    const char *dot = strrchr(name, '.');
    jl_module_t *module = jl_main_module;
    if (dot != NULL) {
        char module_name[256];
        size_t length = (size_t)(dot - name);
        if (length >= sizeof(module_name)) {
            fprintf(stderr, "ERROR: module name too long in " JULIA_MAIN "\n");
            exit(1);
        }
        memcpy(module_name, name, length);
        module_name[length] = '\0';
        module = (jl_module_t *)jl_get_global(jl_main_module, jl_symbol(module_name));
        if (module == NULL || !jl_is_module(module)) {
            fprintf(stderr, "ERROR: no module Main.%s in the image\n", module_name);
            exit(1);
        }
        name = dot + 1;
    }
    jl_value_t *function = jl_get_function(module, name);
    if (function == NULL) {
        fprintf(stderr, "ERROR: no function " JULIA_MAIN " in the image\n");
        exit(1);
    }
    return function;
}

int main(int argc, char *argv[]) {
    argv = uv_setup_args(argc, argv);

    // The arguments after `--julia-args` are the runtime's, not the program's.
    int program_argc = argc;
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "--julia-args") == 0) {
            program_argc = i;
            break;
        }
    }
    int julia_argc = argc - program_argc;
    if (julia_argc > 0) {
        argv[program_argc] = argv[0];
        char **julia_argv = &argv[program_argc];
        jl_parse_opts(&julia_argc, &julia_argv);
    }

    char exe_path[PATH_MAX];
    size_t path_size = sizeof(exe_path);
    if (uv_exepath(exe_path, &path_size)) {
        fprintf(stderr, "ERROR: cannot find the path of this executable\n");
        return 1;
    }
    set_depot_load_path(dirname(dirname(exe_path)));

    void *self = dlopen(NULL, RTLD_NOW | RTLD_NOLOAD | RTLD_LOCAL);
    if (self == NULL) {
        fprintf(stderr, "ERROR: cannot open this executable as a library: %s\n", dlerror());
        return 1;
    }
    jl_init_with_image_handle(self);
    jl_set_ARGS(program_argc, argv);
    set_program_arguments(program_argc, argv);

    jl_value_t *julia_main = find_julia_main();
    jl_value_t *result = jl_call0(julia_main);
    if (jl_exception_occurred())
        fail_with_exception(JULIA_MAIN);

    int32_t retcode;
    if (result != NULL && jl_typeis(result, jl_int32_type)) {
        retcode = jl_unbox_int32(result);
    } else {
        fprintf(stderr, "ERROR: expected a Cint return value from " JULIA_MAIN "\n");
        retcode = 1;
    }
    jl_atexit_hook(retcode);
    return retcode;
}
