# A fault is easy to see, and it stays small

> **Status:** pending. Written 2026-09-26. Not started. The decisions below are
> proposals; the owner decides them (§6). On 2026-10-02 the owner moved D3, D4
> and D6 to [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md), which decides them.

## 1. The request

After take 7 of screenplay S2 (`plan/pending/feature-video-screenplays.md`), the
owner (2026-09-26): "Seems like the fault handling could be better in some
ways", then "This is for a separate plan. Also add that the first fault of every
category should by printed to the log with exception and all, so it's visible.
Or something like that, think about how can we make a fault easy to see and
still not break the editor of possible".

## 2. The case: take 7

1. The model called `insert_elements!` with a `JsonObject` whose entry was a
   `CellVector`, not a `JsonObjectEntry`. The verb took it, and the call
   answered as a success.
2. From the next frame on, each paint threw "TypeDispatchingProjection: no
   projection registered for type CellVector{Cell, Cell}". The exception came
   out of a child print inside a projection template, while the device read the
   output of the window.
3. The barrier of the device write caught it and counted it as `:device_write`.
   After eight in a row, the editor stopped calling `write_to_devices!`, and the
   window never painted again, also after a repair of the document.
4. A reader threw with the same cause ("[fault] read in editor"), so a key whose
   reader passes the broken node was lost.
5. The console showed one line for the fault. Its traceback was cut by the
   record and cut again by the console logger ("⋯ 630 bytes ⋯"). Nothing on the
   screen said that a fault happened.
6. The model was not told, used its last rounds on other things, and did not
   take the change back.

The recorder hung on step 3. That part is fixed on `s2-video` (d595def8): a
frame that the editor does not paint holds the last picture with a red band that
names the fault, so a take always ends.

## 3. What exists

- **The design**, `documentation/package/fault/fault.md`: the kernel layer
  `fault` records and reports, `ProjecturedFault` shows. A report goes to the
  first tier that works: a mark in the output, the fault log on the screen, the
  console, a sound, nothing. `FaultCatchingProjection` catches around
  `print_document` and inside the cell that reads the output, answers a mark of
  the right domain (`substitute`), and catches in the reader and the reference
  mappers too, so the layer above gets its turn. The store is outside the
  reactive graph, and the key of a record is (site, origin, exception type).
- **Repair**: an operation fault takes the change back, prints again and clears
  a broken selection. Four print faults in a row start the safe mode, which
  shows the fault list; Escape leaves it. Eight faults in a row on a half of the
  device seam stop that half.
- **The application.** Its pipelines have no `FaultCatchingProjection`. Only
  the gallery wraps a window, with `make_fault_tolerant_projection` (one barrier
  at the root and the panel). The shell attaches the session `FaultLog` to the
  store, and the toolbar has a "Fault log" button that opens it as a tab. The
  button does not change when a fault arrives.
- **The console tier.** `report_fault!` logs one `@error` for each record that
  the frame drains: the message as one line, cut at 400 characters, and the
  first 12 lines of the traceback. A long keyword value is cut again by the
  console logger. The same key is reported again at each power of ten of its
  count.
- **Seals.** Seven files of `source/kernel/fault/` are 🔒: `FaultModule.jl`,
  `FaultInterface.jl`, `FaultDefaults.jl`, `FaultRecord.jl`, `FaultStore.jl`,
  `FaultCascade.jl`, `FaultBarrier.jl`. A change to one of them needs the
  owner's word for that file. `FaultPolicy.jl` is ⬜. `editor/FaultBarriers.jl`,
  `editor/SafeMode.jl`, `editor/EditorLoop.jl` and `editor/DocumentEdits.jl`
  are ⬜.

## 4. The problems

- **P1. No barrier in the pipelines of the application.** One bad node takes
  the whole window. [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md) handles it.
- **P2. A printer fault is counted as a device fault** when it throws while the
  device reads the output. The safe mode starts only on `:print`, so it never
  starts, and the device stops after eight. [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md)
  handles it: a fault that a barrier noted is not a device fault.
- **P3. A half of the device that stopped is never tried again.** Its count
  resets only after a call that works, and no call is made. A repaired document
  does not bring the window back.
- **P4. A key is lost when its reader throws.** When the broken node is on the
  path of every key, the person has no way back, not even `Ctrl+Z`.
- **P5. The one who made the change is not told.** A tool call whose edit makes
  the next paint fail answers as a success.
- **P6. The first fault is hard to read.** Its text is cut twice on the
  console, and nothing on the screen says that a fault happened.
- Not in this plan: a document that takes an entry of the wrong type (fault b
  of take 7; the owner, 2026-09-26: "Fix a but not b").

## 5. Proposed decisions

Each one is a proposal of the author, for the owner to decide.

- **D1. The first report of each fault prints in full on the console.** A
  "category" is the key of a record, (site, origin, exception type), because the
  store already treats that as one fault. For a new key the record keeps the
  whole text: `showerror` of the exception with the whole backtrace, as Julia
  prints an uncaught error, with its repeated frames folded as Julia folds them.
  The console tier prints that text once, as part of the message and not as a
  keyword value, so the logger does not cut it. A later report of the key stays
  one line with its count. The log entry keeps the whole text as well, so the
  tooltip of the entry and of a mark shows it. The text is made in
  `record_fault!` where the exception and the backtrace are, and printed in the
  frame drain, not inside the thunk that failed. Sealed files: `FaultRecord.jl`,
  `FaultStore.jl`, `FaultCascade.jl`.
- **D2. A fault shows on the screen without a click.** The "Fault log" button
  of the toolbar shows, in red, the count of faults that the person has not
  seen, until the log is opened. The first report of a new key also puts one
  line in the status line at the bottom of the window ("1 fault: <message>"),
  which stays until the log is opened or the line is dismissed. Nothing of it
  can stop a paint: the button and the line read the log, which the frame writes
  outside every thunk.
- **D3. A fault stays at the node that failed.** Moved to [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md).
- **D4. The renderer of the device skips an element that it can not read.**
  Moved to [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md).
- **D5. A half of the device that stopped is tried again after the document
  changes.** After the next operation that the editor applies, the editor calls
  that half one time. If it throws again, it stays stopped until the next
  change. The safe mode keeps its rule: Escape leaves it.
- **D6. The keys stay alive.** Moved to [a-printer-fault-costs-the-smallest-part.md](../done/a-printer-fault-costs-the-smallest-part.md).
- **D7. The one who made the change is told.** `execute_julia_code` and the
  tools of the MCP server wait for the next frame after the code ran and add
  each new fault of that frame to their answer, with the whole text of D1 and a
  hint ("the window can not paint what this call changed; take it back with
  undo, or fix it"). This is a new mechanism, a wait for one frame in a tool
  call, so it needs the owner's word. The other way is to take back
  automatically an operation whose first paint fails, as an operation fault is
  taken back now. It keeps the window whole, but it hides the edit, and it also
  takes back a good edit that only meets a projection bug. The author's
  recommendation: tell, do not take back.

## 6. Questions for the owner

1. Is a category the key of a record (site, origin, exception type)?
2. On the screen: the count on the button only, or the status line too?
3. D7: tell the model, or take the edit back?
4. Which sealed files may change: `FaultRecord.jl`, `FaultStore.jl`,
   `FaultCascade.jl` for D1, and any other that a step names.

## 7. Steps

To be filled when the owner has decided §6. The order the author proposes:

- [ ] **Step 1: D1**, the whole first report. A test records a new key and
      checks that the console gets the whole traceback once, and one line for
      the next report of the key.
- [ ] **Step 2: D2**, the count on the button and the status line.
- [ ] **Step 3: D5**, a stopped half of the device is tried again.
- [ ] **Step 4: D7**, the actor is told.
- [ ] **Step 5: the documentation**: `fault.md`, `shell.md`, and the
      orientation guide of the assistant.
