# The `--strict-fault-policy` flag

> **Status (2026-09-22): DONE.** All three steps are in place, and
> `test_application()` passes 70 of 70.

A command line flag that makes `bin/projectured` stop at the first fault, with
the full stack, instead of surviving it.

## Motivation

A fault in the running application is caught by the frame barriers and logged
with a traceback that the console logger cuts short. To debug a fault that only
the live window shows, a person wants the program to stop at the first error and
print the whole stack.

The kernel already has the switch: `make_strict_fault_policy()` answers
`FaultPolicy(is_barrier_enabled = false)`, and with it every barrier raises the
exception again. `run_editor!(editor; fault_policy)` takes it. Nothing above
that call passes it on, so the application can not reach it.

## Design

The flag is named after the kernel function it turns on, so the command line
and the code use one word for one thing.

The policy goes down the call chain as a keyword whose default keeps the
behavior that exists:

    run_application_command  --strict-fault-policy → fault_policy = make_strict_fault_policy()
    run_application          fault_policy = FaultPolicy()
    run_window_editor        fault_policy = FaultPolicy()
    run_editor!(backend, …)  fault_policy = FaultPolicy()
    run_editor!(editor; …)   fault_policy = FaultPolicy()   (exists)

`run_application_command` prints the stack of a failure, not only the message.
Without that, a strict run shows less than the fault log does.

`FaultCatchingProjection` does not read the policy. The application pipeline
does not use it, so the flag covers every barrier of `bin/projectured`.

## Steps

- [x] 1. `run_editor!(backend, …)` and `run_window_editor` take `fault_policy`.
  `ScreenModule` did not bind `FaultModule`, so `ProjecturedScreen` binds it
  now, beside the other kernel modules.
- [x] 2. `run_application` takes `fault_policy`; the command line has
  `--strict-fault-policy`; a failure prints its stack.
  [debugging-guide.md](../../documentation/guide/debugging-guide.md) has a
  section "Stop at the first fault" that names the flag and the keyword.
- [x] 3. The command line test covers the flag. It checks that the flag is
  parsed, that `--help` lists it, and that a failure answers 2 and prints a
  `Stacktrace`.

## Facts found during the work

- The flag is checked in the test only as far as the parser and the exit code.
  No test opens a window, so the path from the flag to `editor.fault_policy` is
  checked by the keyword declarations of the three functions.
- The frame barriers are the only catch in `bin/projectured`. The application
  pipeline has no `FaultCatchingProjection`.
