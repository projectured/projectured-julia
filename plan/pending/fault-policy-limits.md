# The fault policy keeps only what the fault layer reads

> **Status (2026-09-24): IN PROGRESS.** Steps 1 and 2 are done.

`FaultPolicy` in the kernel fault layer holds `device_failure_limit` and
`print_failure_limit`. The fault layer never reads them. Only
`is_editor_degraded` in the editor layer does, and it finds the limit from the
name of a counter: `:print` gets the print limit, and every other counter gets
the device limit. So a layer-1 type names the stages of the editor, and a
counter that is not `:print` falls to a limit that was not written for it.

`format_fault_message` is exported, but no code outside `FaultModule` calls
it. The four other helpers of the record are private for that reason.

## Decisions of the owner (2026-09-24)

- `FaultPolicy.jl`, `FaultModule.jl` and `FaultRecord.jl` are unsealed for this
  plan.
- The limits move to the editor layer, next to the breakers, as one limit for
  each counter. `FaultPolicy` keeps its three switches.
- `format_fault_message` is private.

## Steps

### Step 1 — unseal the three files

Change the marks of `fault/FaultPolicy.jl`, `fault/FaultModule.jl` and
`fault/FaultRecord.jl` in `SEALING.md` to ⬜, with the owner's permission.

### Step 2 — the limits and the helper

- `FaultPolicy.jl`: the policy holds `is_barrier_enabled`, `is_console_enabled`
  and `is_sound_enabled`. Its docstring names no editor stage.
- `FaultBarriers.jl`: an immutable table gives the limit of each counter:
  `:print`, `:device_read` and `:device_write`. `get_consecutive_fault_limit`
  reads it, and `is_editor_degraded` compares the count with it. An unknown
  counter is an error.
- `FaultRecord.jl`: `format_fault_message` is `_format_fault_message`, renamed
  with `julia-rename.jl`, and `FaultModule.jl` no longer exports it.
- The tests: `FaultSafeModeTest.jl` reads the print limit from the editor
  layer, and `FaultRecordTest.jl` reads the message from a record.
- `fault.md` follows the change.

Test: `test_fault()`, `test_fault_record()`, `test_fault_barrier()`,
`test_fault_store()`, `test_fault_report()`, `test_kernel_layering()`,
`test_declared_api()`, `test_naming()`, `test_arguments()`,
`test_documentation()`, `test_export_collisions()`.

### Step 3 — the audit and the plan

Audit the three files again. Move this plan to `plan/done/`.

## Progress

- [x] Step 1
- [x] Step 2 — `test_fault()` 73 pass, `test_fault_record()` 3,
  `test_fault_barrier()` 18, `test_fault_store()` 25, `test_fault_report()` 5,
  `test_fault_defaults()` 10, `test_kernel_layering()` 10, `test_declared_api()`
  111; `test_naming()`, `test_arguments()`, `test_documentation()` and
  `test_export_collisions()` pass. Decisions made while implementing:
  - The limits are one constant table and not a setting of each editor: no
    code set a limit other than the default.
  - The table is a `NamedTuple`, so it is immutable, and an unknown counter is
    an error.
  - `get_consecutive_fault_limit(counter)` is exported by `EditorModule`, and
    pairs with `get_consecutive_fault_count(store, counter)`. The safe-mode test
    reads the print limit through it.
  - `fault.md` says where the limits are now.
- [ ] Step 3
