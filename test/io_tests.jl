######################################################################################

#  Test: Phantom IO -- Complete Dump Reading
#  What this file tests
#  Reads the bundled dump through the public metadata, raw-data, and analysis APIs:
#  1. File structure
#     -- Partition, block, and column counts; identifier width and particle counts.
#  2. Raw particle data
#     -- Column order, element types, vector lengths, and shared metadata.
#  3. Analysis tables
#     -- Particle counts and coordinates agree with the unfiltered raw columns.
#  Test data
#  -- testinput/testdumpfile_00000: one partition with 550000 ordinary particles
#     and two sink particles.

######################################################################################
using Test
using ParticleIO

# ============================== Test body =================================== #

@testset "Phantom read -- complete dump" begin
    filename = joinpath(@__DIR__, "testinput", "testdumpfile_00000")
    file = PhantomFile(filename)
    data = read_data(file)

    # 1. File structure and expected column order.
    @test file isa PhantomFile{1, 2, (11, 14), Int32, Float64}
    @test data isa PhantomData{1, 2, (11, 14)}
    @test data.metadata === file.partitions
    @test ncodeunits(file.file_identifier) == 100
    @test map(block -> block.npart, file.partitions[1].blocks) == (550000, 2)
    @test map(column -> strip(column.name), data.metadata[1].blocks[1].columns) ==
        ("itype", "x", "y", "z", "vx", "vy", "vz", "dustfrac", "h", "divv", "dt")

    # 2. Raw vectors follow the indexed metadata without copying the metadata.
    dtypes = phantom_dtypes(file)
    for (p, partition) in enumerate(file.partitions), (b, block) in enumerate(partition.blocks)
        @test all(length(values) == block.npart for values in data[p][b])
        @test map(eltype, data[p][b]) == map(column -> dtypes[Int(column.dtype_index)], block.columns)
        @test data.metadata[p].blocks[b] === block
    end

    # 3. Keep inactive particles so analysis and raw data describe the same rows.
    particles, sinks = read_phantom(filename; ignore_inactive = false)
    @test get_npart(particles) == 550000
    @test get_npart(sinks) == 2
    @test isequal(particles[!, :x], data[1, 1, 2])
    @test isequal(sinks[!, :x], data[1, 2, 1])
    @test particles.params[:nparttot] == 550000
end
