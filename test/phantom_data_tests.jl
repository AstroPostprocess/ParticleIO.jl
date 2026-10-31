module PhantomDataTests
using Test
using ParticleIO

@testset "PhantomData structure and dispatch" begin
    raw = (((Float64[1, 2], Int32[3, 4]), ()),)
    names = ((("x", "itype"), ()),)
    data = @inferred PhantomData(raw, names)
    @test data isa PhantomData{1, 2, (2, 0)}
    @test isconcretetype(fieldtype(typeof(data), :partitions))
    @test isconcretetype(fieldtype(typeof(data), :column_names))
    @test data.column_names === names
    @test_throws DimensionMismatch PhantomData(raw, ())
    @test_throws DimensionMismatch PhantomData(raw, (((),),))
    @test_throws DimensionMismatch PhantomData(raw, ((("x",), ()),))
    @test_throws ArgumentError PhantomData(raw, (((:x, :itype), ()),))
    @test data[1][1][1] === raw[1][1][1]
    @test data[1, 1, 1] === data[1][1][1]
    @test data[1, 1, 2] === raw[1][1][2]
    @test_throws BoundsError data[2, 1, 1]
    @test_throws BoundsError data[1, 3, 1]
    @test_throws BoundsError data[1, 2, 1]
    data[1][1][1][1] = 5
    @test raw[1][1][1][1] == 5
    @test_throws MethodError PhantomData{1, 2, (99, 0), typeof(raw), typeof(names)}(raw, names)
    @test_throws ArgumentError PhantomData((), ())
    @test_throws ArgumentError PhantomData(([Float64[]],), ())
    @test_throws ArgumentError PhantomData((([Float64[]],),), ())
    @test_throws ArgumentError PhantomData(((Float64[],),), ())
    @test_throws ArgumentError PhantomData((((String[],),),), ())
    @test_throws DimensionMismatch PhantomData((((Float64[],),), ()), ())
    @test_throws DimensionMismatch PhantomData((((Float64[],),), ((Float64[], Float64[]),)), ())

    file = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    valid = read_data(file)
    P, B, C = typeof(file).parameters[1:3]
    @test valid isa PhantomData{P, B, C}
    copied = PhantomData(file, valid.partitions)
    @test copied.column_names == valid.column_names
    @test copied[1][1][1] === valid[1][1][1]
    @test applicable(write_phantom, IOBuffer(), file, valid)
    wrong_p = PhantomData((valid[1], valid[1]), (valid.column_names[1], valid.column_names[1]))
    wrong_b = PhantomData((Base.front(valid[1]),), (Base.front(valid.column_names[1]),))
    wrong_c = PhantomData(((Base.front(valid[1][1]), Base.tail(valid[1])...),),
        ((Base.front(valid.column_names[1][1]), Base.tail(valid.column_names[1])...),))
    for wrong in (wrong_p, wrong_b, wrong_c)
        io = IOBuffer()
        @test !applicable(write_phantom, io, file, wrong)
        @test_throws MethodError write_phantom(io, file, wrong)
        @test position(io) == 0
    end
    @test_throws MethodError write_phantom(IOBuffer(), file, valid.partitions)
    resize!(valid[1][1][1], 0)
    io = IOBuffer()
    @test_throws DimensionMismatch write_phantom(io, file, valid)
    @test position(io) == 0

    block = file.partitions[1].blocks[1]
    @test block.columns isa Tuple
    @test_throws MethodError push!(block.columns, first(block.columns))
    @test_throws MethodError PhantomBlockInfo(block.npart, block.array_counts, collect(block.columns))
    @test_throws DimensionMismatch PhantomBlockInfo(block.npart, block.array_counts, Base.front(block.columns))
end

@testset "read_data preserves raw columns and stream ownership" begin
    template = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    name = rpad("  repeated", 16)
    columns = (PhantomColumnInfo(name, UInt8(4), 0), PhantomColumnInfo(name, UInt8(6), 12))
    counts = (Int32(0), Int32(0), Int32(0), Int32(1), Int32(0), Int32(1), Int32(0), Int32(0))
    block = PhantomBlockInfo(1, counts, columns)
    file = PhantomFile("unused", template.file_identifier, template.headers, template.sections,
        (PhantomPartition((block,)),))
    io = IOBuffer()
    write(io, Int32(4), Int32(3), Int32(4), Int32(8), Float64(-2), Int32(8))
    data = read_data(io, file)
    @test data isa PhantomData{1, 1, (2,)}
    @test data[1][1] isa Tuple{Vector{Int32}, Vector{Float64}}
    @test data[1][1][1] == Int32[3]
    @test data[1][1][2] == Float64[-2]
    @test data.column_names == (((name, name),),)
    @test isopen(io)
    @test position(io) == 28
    @test file.partitions[1].blocks[1].columns[1].name == name
    again = read_data(io, file)
    @test again[1][1][1] !== data[1][1][1]
    @test again[1][1][2] == data[1][1][2]
end
end
