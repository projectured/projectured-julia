# Fragment of `DeviceModule` — the device contract: the supertype of every device.

"""
    Device

The supertype of every input and output device: `Display`, `Keyboard` and
`Mouse`. A device holds the physical properties of its hardware. A backend
writes the properties that it finds into the device, so each device is mutable.
"""
abstract type Device end
