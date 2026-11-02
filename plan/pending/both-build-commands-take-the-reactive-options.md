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

- [ ] 1. **The shared part, and the projectured command uses it.** Check:
      `test_builder()`, and `bin/build_projectured --help`.
- [ ] 2. **The omnet command uses it** and drops its own rows and branches of
      these options. Check: `test/build.jl` with the app files of the IDE
      saved and put back, and `bin/build_omnet_ide --help`.
- [ ] 3. **The guides**: `builder.md` and `build-guide.md` of projectured,
      and `reactive-build-guide.md` of omnet, name the options once for both
      commands. Then the plan moves to `plan/done/`.
