# Fragment of `StyleModule`.
#
# The size of a picture file from the head of the file, with no decode: the
# readers of PNG, BMP, GIF and JPEG over bytes. They use the big-endian readers
# of `TrueType.jl` and read only the bytes of the head: a reader seeks over the
# body of a segment instead of reading it.

# The walk of a GIF or a JPEG gives up at this byte of the file.
const _IMAGE_HEAD_WALK_LIMIT = 1_048_576

const _PNG_SIGNATURE = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

@inline _u16_little(b, o) = UInt16(b[o + 1]) | (UInt16(b[o + 2]) << 8)
@inline _u32_little(b, o) = UInt32(_u16_little(b, o)) | (UInt32(_u16_little(b, o + 2)) << 16)

# The next byte of `io`, or `nothing` at its end.
_read_next_byte(io::IO) = eof(io) ? nothing : read(io, UInt8)

# `(width, height)` when both are positive, otherwise `nothing`.
_make_image_head_size(width::Integer, height::Integer) =
    width > 0 && height > 0 ? (Int(width), Int(height)) : nothing

"""
    read_image_size(path) -> Union{Tuple{Int,Int}, Nothing}

Read the size `(width, height)` that the head of the picture file `path` states, with
no decode. The signature in the first bytes chooses the reader, not the extension:

- PNG: the `IHDR` chunk, 24 bytes.
- BMP: the DIB header, 26 bytes. A header of 40 to 124 bytes with a negative height is a
  picture stored top-down, and its height is the absolute value.
- GIF: the first image descriptor, the size of the first frame and not of the screen. The
  reader skips the global colour table and each extension by its sub-blocks.
- JPEG: the first start-of-frame marker. The reader seeks past the body of every other
  segment.

The answer is `nothing` for a file with none of these signatures, for a head that ends
before the size, for a size of 0, for a JPEG with its start of scan or end of image before
its frame, for a GIF with its trailer before a frame, and for a GIF or a JPEG whose walk
passes byte $(_IMAGE_HEAD_WALK_LIMIT) before it finds the size. A file that can not be
opened throws the `SystemError` of `open`. The function keeps nothing and reads no document.
"""
function read_image_size(path::AbstractString)
    open(path, "r") do io
        head = read(io, 8)
        seekstart(io)
        length(head) >= 8 && head == _PNG_SIGNATURE && return _read_png_size(io)
        length(head) >= 6 && (head[1:6] == codeunits("GIF87a") || head[1:6] == codeunits("GIF89a")) &&
            return _read_gif_size(io)
        length(head) >= 2 && head[1] == UInt8('B') && head[2] == UInt8('M') && return _read_bmp_size(io)
        length(head) >= 2 && head[1] == 0xff && head[2] == 0xd8 && return _read_jpeg_size(io)
        nothing
    end
end

function _read_png_size(io::IO)
    bytes = read(io, 24)
    length(bytes) == 24 && bytes[13:16] == codeunits("IHDR") || return nothing
    _make_image_head_size(_u32(bytes, 16), _u32(bytes, 20))
end

function _read_bmp_size(io::IO)
    bytes = read(io, 26)
    length(bytes) == 26 || return nothing
    header_size = _u32_little(bytes, 14)
    if header_size == 12
        _make_image_head_size(_u16_little(bytes, 18), _u16_little(bytes, 20))
    elseif 40 <= header_size <= 124
        width = reinterpret(Int32, _u32_little(bytes, 18))
        height = reinterpret(Int32, _u32_little(bytes, 22))
        _make_image_head_size(width, abs(Int(height)))
    else
        nothing
    end
end

function _read_gif_size(io::IO)
    screen = read(io, 13)
    length(screen) == 13 || return nothing
    flags = screen[11]
    flags & 0x80 != 0 && skip(io, 3 * 2^((flags & 0x07) + 1))
    while position(io) <= _IMAGE_HEAD_WALK_LIMIT
        introducer = _read_next_byte(io)
        if introducer == 0x2c
            descriptor = read(io, 8)
            length(descriptor) == 8 || return nothing
            return _make_image_head_size(_u16_little(descriptor, 4), _u16_little(descriptor, 6))
        elseif introducer == 0x21
            _read_next_byte(io) === nothing && return nothing
            while true
                block = _read_next_byte(io)
                block === nothing && return nothing
                block == 0x00 && break
                skip(io, block)
            end
        else
            return nothing
        end
    end
    nothing
end

# A start-of-frame marker: C0 to CF without the table marker C4, the JPEG extension C8
# and the arithmetic conditioning CC.
_is_jpeg_frame_marker(marker::UInt8) = 0xc0 <= marker <= 0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc

function _read_jpeg_size(io::IO)
    skip(io, 2)
    while position(io) <= _IMAGE_HEAD_WALK_LIMIT
        byte = _read_next_byte(io)
        byte == 0xff || return nothing
        marker = _read_next_byte(io)
        while marker == 0xff
            marker = _read_next_byte(io)
        end
        marker === nothing && return nothing
        if marker == 0x01 || 0xd0 <= marker <= 0xd8
            continue
        elseif marker == 0xd9 || marker == 0xda || marker == 0x00
            return nothing
        elseif _is_jpeg_frame_marker(marker)
            frame = read(io, 7)
            length(frame) == 7 || return nothing
            return _make_image_head_size(_u16(frame, 5), _u16(frame, 3))
        end
        header = read(io, 2)
        length(header) == 2 || return nothing
        segment_length = Int(_u16(header, 0))
        segment_length >= 2 || return nothing
        skip(io, segment_length - 2)
    end
    nothing
end
