# ── Device layer — the input/output devices and their batch I/O seam ───────
# The ordered include list of the device layer; a fragment of ProjecturedKernel.
# DeviceModule declares the `Device` contract — `read_from_devices` /
# `write_to_devices`, which a concrete backend implements — and the concrete
# devices an editor is given (`Keyboard`, `Mouse`, `Screen`), one fragment each.
#
# A device is *where events come from*; it interprets none of them, so this layer
# names no document, no operation, and no backend type.
include("DeviceModule.jl")
