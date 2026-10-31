# Standalone low-level tests; requires StaticArrays in the active environment.
module PhantomHeaderWriteTests
using Test
using StaticArrays

const source = joinpath(@__DIR__, "..", "src", "julia", "IO", "phantomIO")
include(joinpath(source, "struct", "PhantomHeaders.jl"))
include(joinpath(source, "struct", "PhantomPartitionOffsets.jl"))
include(joinpath(source, "struct", "PhantomSectionOffsets.jl"))
include(joinpath(source, "struct", "PhantomColumnInfo.jl"))
include(joinpath(source, "struct", "PhantomBlockInfo.jl"))
include(joinpath(source, "struct", "PhantomPartition.jl"))
include(joinpath(source, "struct", "PhantomFile.jl"))
include(joinpath(source, "struct", "PhantomData.jl"))
for name in ("fortran_block", "phantom_datatype", "file_identifier", "global_header",
             "particle_block_metadata", "particle_block_offset")
    include(joinpath(source, "read", name * ".jl"))
end
include(joinpath(source, "write", "fortran_block.jl"))
include(joinpath(source, "write", "file_identifier.jl"))
include(joinpath(source, "write", "global_header.jl"))
using DataFrames
include(joinpath(source, "read_phantom.jl"))
include(joinpath(source, "read", "column.jl"))

padded(key) = key * repeat(" ", 16 - ncodeunits(key))

@testset "File identifier preserves payload bytes" begin
    # Include leading whitespace and a multibyte character; width is measured in bytes.
    content = "  FT:Phantom:" * Char(0x03b1) * "  "
    expected = vcat(collect(codeunits(content)), fill(UInt8(' '), 100 - ncodeunits(content)))
    io = IOBuffer()
    _write_file_identifier(io, 0, content)
    original = take!(io)
    identifier = _read_file_identifier(IOBuffer(original), 0)
    @test ncodeunits(identifier) == 100
    @test collect(codeunits(identifier)) == expected
    @test startswith(identifier, "  FT:Phantom:")
    output = IOBuffer()
    _write_file_identifier(output, 0, identifier)
    @test take!(output) == original
end

@testset "Typed header block writer" begin
    for T in (Int8, Int16, Int32, Int64, Float32, Float64)
        for keys in (String[], ["mass", "mass", "mass_1", "abcdefghijklmnop", "密度"])
            data = T.(1:length(keys))
            header = PhantomHeader{T}(keys, data)
            io = IOBuffer()
            @test _write_global_header_block(io, header) === nothing
            expected = isempty(keys) ? 12 : 28 + (16 + sizeof(T)) * length(keys)
            @test position(io) == expected
            seekstart(io)
            @test read(io, Int32) == 4
            @test read(io, Int32) == length(keys)
            @test read(io, Int32) == 4
            seekstart(io)
            buffers = (UInt8[], UInt8[])
            read_keys, read_data = _read_global_header_block!(io, buffers, T)
            @test read_keys == padded.(keys)
            @test read_data == data
            @test eof(io)
        end
    end
end

@testset "Validation before writing" begin
    for header in (PhantomHeader{Float64}(["x"], Float64[]),)
        io = IOBuffer()
        @test_throws DimensionMismatch _write_global_header_block(io, header)
        @test position(io) == 0
    end
    for key in ("abcdefghijklmnopq", "密度密度密度")
        io = IOBuffer()
        @test_throws ArgumentError _write_global_header_block(io, PhantomHeader([key], [1.0]))
        @test position(io) == 0
    end
end

@testset "Raw names survive indexed reading" begin
    file = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    io = IOBuffer()
    header_fields = (:default_integer, :int8, :int16, :int32, :int64, :default_real, :float32, :float64)
    for field in header_fields
        _write_global_header_block(io, getproperty(file.headers, field))
    end
    TI, _, _, _, _, TF, _, _ = phantom_dtypes(file)
    keys, data = _read_global_header(io, 0, TI, TF)
    for (i, field) in enumerate(header_fields)
        header = getproperty(file.headers, field)
        @test keys[i] == header.keys
        @test isequal(data[i], header.data)
    end
    # Explicit duplicates and a genuine suffixed name must not be guessed apart.
    io = IOBuffer()
    _write_global_header_block(io, PhantomHeader(["mass", "mass", "other_1"], Int32[1, 2, 3]))
    for T in (Int8, Int16, Int32, Int64, Float64, Float32, Float64)
        _write_global_header_block(io, PhantomHeader{T}(String[], T[]))
    end
    keys, data = _read_global_header(io, 0, Int32, Float64)
    @test keys[1] == padded.(["mass", "mass", "other_1"])
    restored = PhantomHeader{Int32}(keys[1], data[1])
    output = IOBuffer()
    _write_global_header_block(output, restored)
    seekstart(output)
    @test first(_read_global_header_block!(output, (UInt8[], UInt8[]), Int32)) == keys[1]
    @test length(_read_global_header(io, 0, Int32, Float64)) == 2
    headers = PhantomHeaders{Int32, Float64}(
        (PhantomHeader{T}(keys[i], data[i]) for (i, T) in
         enumerate((Int32, Int8, Int16, Int32, Int64, Float64, Float32, Float64)))...)
    synthetic = PhantomFile("", "", headers, file.sections, (PhantomPartition(()),))
    params = _collect_header_params(synthetic)
    @test params[:mass_1] == 1
    @test params[:mass_2] == 2
    @test params[:other_1] == 3
    @test synthetic.headers.default_integer.keys == padded.(["mass", "mass", "other_1"])
end
@testset "Name payloads and analysis conversion" begin
    original_keys = [padded("  mass"), padded("  mass"), padded("other")]
    io = IOBuffer()
    _write_global_header_block(io, PhantomHeader(original_keys, [1.0, 2.0, 3.0]))
    original = take!(io)
    keys, values = _read_global_header_block!(IOBuffer(original), (UInt8[], UInt8[]), Float64)
    @test keys == original_keys
    _write_global_header_block(io, PhantomHeader(keys, values))
    @test take!(io) == original

    name = padded("  x")
    io = IOBuffer()
    _write_fortran_block(io, collect(codeunits(name)))
    _write_fortran_block(io, Float64[1, 2])
    blocks = _read_particle_block_offset(io, 0, Int64[2], [(Int32(0), Int32(0), Int32(0),
        Int32(0), Int32(0), Int32(1), Int32(0), Int32(0))], Int32, Float64)
    @test blocks[1].columns[1].name == name
    template = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    file = PhantomFile("", "", template.headers, template.sections, (PhantomPartition(Tuple(blocks)),))
    data = read_data(io, file)
    @test data isa PhantomData{1, 1, (1,)}
    @test data[1][1][1] == [1.0, 2.0]
    @test file.partitions[1].blocks[1].columns[1].name == name
end

end
