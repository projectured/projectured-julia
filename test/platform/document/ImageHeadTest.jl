# The size of a picture file from the head of the file (`read_image_size`): each
# file is written byte by byte, and the reader answers `(width, height)` or
# `nothing`. A path that does not exist throws the `SystemError` of `open`.

using Test
using ProjecturedPlatform

_ih_big16(n) = UInt8[(n >> 8) & 0xff, n & 0xff]
_ih_big32(n) = UInt8[(n >> 24) & 0xff, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
_ih_little16(n) = UInt8[n & 0xff, (n >> 8) & 0xff]
_ih_little32(n) = UInt8[n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff, (n >> 24) & 0xff]

function _ih_png(width, height)
    vcat(UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], _ih_big32(13), codeunits("IHDR"),
         _ih_big32(width), _ih_big32(height), UInt8[8, 6, 0, 0, 0], _ih_big32(0))
end

# A BMP with a header of 40 bytes. A negative `height` is stored top-down.
function _ih_bmp(width, height)
    vcat(codeunits("BM"), _ih_little32(54), _ih_little32(0), _ih_little32(54),
         _ih_little32(40), _ih_little32(width), _ih_little32(height % UInt32), _ih_little16(1), _ih_little16(24),
         zeros(UInt8, 24))
end

function _ih_bmp_core(width, height)
    vcat(codeunits("BM"), _ih_little32(26), _ih_little32(0), _ih_little32(26),
         _ih_little32(12), _ih_little16(width), _ih_little16(height), _ih_little16(1), _ih_little16(24))
end

# A GIF with a screen of 20 by 10, a global table of 4 colours, a graphic control
# extension, a comment of 300 bytes in two sub-blocks, and a first frame of 5 by 4.
function _ih_gif(; frames = true)
    bytes = vcat(codeunits("GIF89a"), _ih_little16(20), _ih_little16(10), UInt8[0x81, 0, 0], zeros(UInt8, 12))
    frames || return vcat(bytes, UInt8[0x3b])
    vcat(bytes, UInt8[0x21, 0xf9, 4, 0, 0, 0, 0, 0],
         UInt8[0x21, 0xfe, 255], fill(UInt8('c'), 255), UInt8[45], fill(UInt8('c'), 45), UInt8[0],
         UInt8[0x2c], _ih_little16(2), _ih_little16(3), _ih_little16(5), _ih_little16(4), UInt8[0],
         UInt8[2, 2, 0x44, 0x01, 0], UInt8[0x3b])
end

_ih_jpeg_segment(marker, body) = vcat(UInt8[0xff, marker], _ih_big16(length(body) + 2), body)
_ih_jpeg_frame(marker, width, height) =
    _ih_jpeg_segment(marker, vcat(UInt8[8], _ih_big16(height), _ih_big16(width), UInt8[3], zeros(UInt8, 9)))

# A JPEG with `app1_count` APP1 segments of 65 535 bytes, fill bytes before a
# marker, a quantization table, and `frame` as its frame.
function _ih_jpeg(frame; app1_count = 3)
    vcat(UInt8[0xff, 0xd8], _ih_jpeg_segment(0xe0, zeros(UInt8, 14)),
         reduce(vcat, [_ih_jpeg_segment(0xe1, zeros(UInt8, 65533)) for _ in 1:app1_count]; init = UInt8[]),
         UInt8[0xff, 0xff, 0xff], _ih_jpeg_segment(0xdb, zeros(UInt8, 65)), frame)
end

function test_image_head()
    @testset "the size of a picture file comes from its head" begin
        directory = mktempdir()
        size_of(bytes) = (path = joinpath(directory, "picture.bin"); write(path, bytes); read_image_size(path))
        @testset "PNG" begin
            @test size_of(_ih_png(640, 480)) == (640, 480)
            @test size_of(_ih_png(0, 480)) === nothing
            @test size_of(_ih_png(640, 480)[1:20]) === nothing
        end
        @testset "BMP" begin
            @test size_of(_ih_bmp(7, 5)) == (7, 5)
            @test size_of(_ih_bmp(7, -5)) == (7, 5)
            @test size_of(_ih_bmp_core(7, 5)) == (7, 5)
        end
        @testset "GIF" begin
            @test size_of(_ih_gif()) == (5, 4)
            @test size_of(_ih_gif(frames = false)) === nothing
        end
        @testset "JPEG" begin
            @test size_of(_ih_jpeg(_ih_jpeg_frame(0xc0, 1000, 600))) == (1000, 600)
            @test size_of(_ih_jpeg(_ih_jpeg_frame(0xc2, 1000, 600))) == (1000, 600)
            @test size_of(_ih_jpeg(vcat(_ih_jpeg_segment(0xda, zeros(UInt8, 10)), _ih_jpeg_frame(0xc0, 1000, 600)))) === nothing
            @test size_of(_ih_jpeg(_ih_jpeg_frame(0xc0, 1000, 0))) === nothing
            @test size_of(_ih_jpeg(_ih_jpeg_frame(0xc0, 1000, 600); app1_count = 17)) === nothing
        end
        @testset "no picture" begin
            @test size_of(codeunits("hello world")) === nothing
            @test size_of(UInt8[0x89, 0x50, 0x4e]) === nothing
            @test size_of(vcat(codeunits("RIFF"), _ih_little32(30), codeunits("WEBPVP8 "), zeros(UInt8, 18))) === nothing
            @test_throws SystemError read_image_size(joinpath(directory, "absent.png"))
        end
        # The extension chooses nothing: the signature does.
        path = joinpath(directory, "a.png")
        write(path, "one")
        @test read_image_size(path) === nothing
        write(path, _ih_bmp(7, 5))
        @test read_image_size(path) == (7, 5)
    end
end
