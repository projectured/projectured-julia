# Both build commands take the reactive options

The request of the user (2026-11-02): "projectured and omnet IDE should work the
same way wrt. builds/rebuilds". The builds and the rebuilds already go through
one implementation, `ProjecturedBuilder.build_executable` and
`prepare_program_start!`. The command lines are different:
`bin/build_omnet_ide` takes `--reactive`, `--dev`, `--watch`, `--no-server`,
`--image=`, `--delta-optimization=`, `--compact=` and `--trim`, and
`bin/build_projectured` does not, although `build_executable` takes the
keywords of all of them. The user chose (2026-11-02) that the builder parses
these options once, and that both commands use that parser.

## The design

`ProjecturedBuilder` (`source/tool/builder/BuildCommand.jl`) gets the shared
part of a build command:

- `REACTIVE_BUILD_OPTIONS`: the rows `(key, label, description)` of the
  options of the reactive build and of its store: `--reactive`,
  `--no-reactive`, `--found`, `--dev`, `--watch`, `--refresh-trace`,
  `--no-server`, `--image=`, `--delta-optimization=`, `--compact=`, `--trim`,
  `--status`, `--stop-server`.
- `apply_reactive_build_option!(keywords, argument)`: sets the keywords of
  one such option, and answers what the command does: `:build`, `:status`,
  `:stop_server` or `:watch`; `nothing` for another argument.
- `run_reactive_build_action!(build, action, output, keywords)`: runs
  `:status`, `:stop_server` or `:watch` over the output, and answers the exit
  code. `build` is the build function of the command, called with the
  keywords.

Each command keeps its own options, its help text, the name of its output,
and its distribution. A command line that names two actions is refused.
`build_executable` already refuses a wrong combination of reactive keywords
before it compiles, so the shared part adds no check of its own except for
`--watch` with `--no-compile`.

## Steps

- [x] 1. **The shared part, and the projectured command uses it.** Check:
      `test_builder()`, and `bin/build_projectured --help`.
      **Done 2026-11-02.** `BUILD_OPTIONS` splices `REACTIVE_BUILD_OPTIONS`
      after `--no-prelink`, so the help lists them in one place. The parser
      gives an option to `apply_reactive_build_option!` first, and
      `--distribution`, `--status`, `--stop-server` and `--watch` are the
      actions. `--dev` sets `delta_optimization = 1`, so a
      `--delta-optimization=N` after it wins, as in the omnet command.
      `test_builder()`: 686 pass, 658 before; the naming guard passes; the
      help of `bin/build_projectured` lists the 13 options.
- [x] 2. **The omnet command uses it** and drops its own rows and branches of
      these options. Check: `test/build.jl` with the app files of the IDE
      saved and put back, and `bin/build_omnet_ide --help`.
      **Done 2026-11-02**, omnet-julia. `OPTIONS` takes the shared rows with
      `ALL_BUILDS`, the parser gives an option to
      `apply_reactive_build_option!` and turns its error into the message and
      the usage of the command, and `_run_build` gives every action to
      `run_reactive_build_action!`, so `--status` and `--stop-server` answer
      their exit code and no longer end the process. `test/build.jl`: 64 pass
      and 3 errors, the same as before the change: two tests write
      `build/omnet_ide` while it holds a store, and the stock Julia ships no
      `juliac`. Both scripts give the same answers: `--status` prints the
      store, `--status --watch` and `--compact=10` stop with exit 1 and a
      message, and the omnet parser gives the keywords of the projectured test.
- [x] 3. **The guides**: `builder.md` and `build-guide.md` of projectured,
      and `reactive-build-guide.md` of omnet, name the options once for both
      commands. Then the plan moves to `plan/done/`.
      **Done 2026-11-02.** The front-end table of `build-guide.md` points to
      the table of the reactive options under "Rebuild in seconds", with the
      `--dev --watch` loop. The omnet guide says that `bin/build_projectured`
      takes the same options, and gives the start of the prelinked program.
      Found on the way: on Linux the program holds the founding image and reads
      only an overlay, so `--image=pages` and `--image=whole` would leave it
      with the code of the founding. `_check_reactive_options` refuses them
      there (projectured 2aa7839cf, a fix of step 5 of the plan
      `reactive-prelinked-start.md` of omnet-julia).
