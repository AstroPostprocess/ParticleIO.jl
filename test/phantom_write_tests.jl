# Standalone writer checks, without requiring the unfinished package entry point.
include("phantom_header_write_tests.jl")
module PhantomWriteTests
using Test
using ..PhantomHeaderWriteTests
const R = PhantomHeaderWriteTests
for name in (:PhantomData, :PhantomFile, :PhantomHeader, :PhantomHeaders, :PhantomBlockInfo,
             :PhantomColumnInfo, :PhantomSectionOffsets, :PhantomPartitionOffsets, :PhantomPartition, :phantom_dtypes,
             :_PHANTOM_INT_TYPE, :_PHANTOM_REAL_TYPE, :_PHANTOM_TYPE,
             :_write_fortran_block, :_write_file_identifier, :_write_global_header,
             :_validate_header_block, :_phantom_partition_count)
    @eval const $name = getfield(R, $(QuoteNode(name)))
end
for name in ("phantom_datatype", "particle_block_metadata", "column")
    include(joinpath(R.source, "write", name * ".jl"))
end
include(joinpath(R.source, "write_phantom.jl"))

load_vectors(file) = PhantomData(file)

@testset "Full fixture round trip" begin
    file = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    values = load_vectors(file)
    mktempdir() do dir
        target = joinpath(dir, "roundtrip.dump")
        @test write_phantom(target, file, values) === nothing
        @test read(target) == read(file.filename)
        restored = PhantomFile(target)
        @test restored.file_identifier == file.file_identifier
        @test isequal(load_vectors(restored).partitions, values.partitions)
        @test load_vectors(restored).column_names == values.column_names
        @test_throws ArgumentError write_phantom(target, file, values)
        @test read(target) == read(file.filename)
        @test write_phantom(target, file, values; overwrite=true) === nothing
        # Invalid data must not replace an existing file, even when overwrite is authorized.
        @test_throws MethodError write_phantom(target, file, PhantomData(((),), ((),)); overwrite=true)
        @test read(target) == read(file.filename)
        @test readdir(dir) == ["roundtrip.dump"]
    end
    io = IOBuffer()
    @test write_phantom(io, file, values) === nothing
    @test isopen(io)
    @test take!(io) == read(file.filename)
    @test_throws ArgumentError write_phantom(IOBuffer(UInt8[1]), file, values)
end

@testset "Datatype combinations and empty records" begin
    for TI in (Int32, Int64), TF in (Float32, Float64)
        dtypes = phantom_dtypes(TI, TF)
        headers = PhantomHeaders{TI, TF}((PhantomHeader{T}(String[], T[]) for T in dtypes)...)
        # Include every group even when its element type matches another group.
        columns = [PhantomColumnInfo(R.padded("  col$i"), UInt8(i), -1) for i in 1:8]
        blocks = (PhantomBlockInfo(2, ntuple(_ -> Int32(1), 8), Tuple(columns)),
                  PhantomBlockInfo(0, ntuple(_ -> Int32(1), 8), Tuple(columns)),
                  PhantomBlockInfo(0, ntuple(_ -> Int32(0), 8), ()))
        file = PhantomFile("unused", "FT:test", headers,
            PhantomSectionOffsets(-1, -1, -1, (PhantomPartitionOffsets(-1, -1),)), (PhantomPartition(blocks),))
        values = (map(T -> T[1, 2], dtypes), map(T -> T[], dtypes), ())
        mktempdir() do dir
            target = joinpath(dir, "typed.dump")
            write_phantom(target, file, PhantomData(file, (values,)))
            restored = PhantomFile(target)
            @test phantom_dtypes(restored) == phantom_dtypes(TI, TF)
            @test restored.partitions[1].blocks[1].array_counts == blocks[1].array_counts
            @test restored.partitions[1].blocks[2].npart == 0
            @test isempty(restored.partitions[1].blocks[3].columns)
            @test restored.partitions[1].blocks[1].columns[1].name == columns[1].name
            readback = load_vectors(restored)
            @test readback[1][1] == values[1]
            @test readback[1][2] == values[2]
            @test isempty(readback[1][3])
            io = IOBuffer()
            write_phantom(io, restored, readback)
            @test take!(io) == read(target)
        end
        io = IOBuffer()
        bad = deepcopy(values)
        resize!(bad[1][1], 1)
        @test_throws DimensionMismatch write_phantom(io, file, PhantomData(file, (bad,)))
        @test position(io) == 0
        bad = deepcopy(values)
        bad = ((Float64[1, 2], Base.tail(bad[1])...), Base.tail(bad)...)
        @test_throws ArgumentError write_phantom(io, file, PhantomData(file, (bad,)))
        @test position(io) == 0
        bad_columns = copy(columns)
        bad_columns[1] = PhantomColumnInfo("x", UInt8(2), 0)
        bad_file = PhantomFile("", "FT:test", headers, file.sections,
            (PhantomPartition((PhantomBlockInfo(2, blocks[1].array_counts, Tuple(bad_columns)),)),))
        @test_throws ArgumentError write_phantom(io, bad_file, PhantomData(bad_file, ((values[1],),)))
        @test position(io) == 0
    end
end
end
