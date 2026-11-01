######################################################################################

#  Test: Phantom IO -- Complete Dump Writing and Readback
#  What this file tests
#  Writes the bundled dump and verifies each output through the public read APIs:
#  1. Raw-data round trip
#     -- Structure, element types, particle vectors, and shared metadata.
#  2. Header and block metadata
#     -- Header names and values, column names, particle counts, and datatype groups.
#  3. Output provenance and analysis tables
#     -- ParticleIO identifier with preserved source metadata; coordinates match
#        the original raw data after loading the written file for analysis.
#  Test data
#  -- testinput/testdumpfile_00000 is the reference for both output generations.
#     Temporary output files are removed when the test finishes.

######################################################################################
using Test
using ParticleIO

# ============================== Test body =================================== #

@testset "Phantom write -- verify through repeated reads" begin
    source = PhantomFile(joinpath(@__DIR__, "testinput", "testdumpfile_00000"))
    source_data = read_data(source)
    source_identifier = source.file_identifier

    mktempdir() do dir
        file, data = source, source_data
        # Feed each readback into the next write, comparing both to the source.
        for generation in 1:2
            target = joinpath(dir, "roundtrip_$generation.dump")
            @test write_data(target, file, data) === nothing
            restored = PhantomFile(target)
            restored_data = read_data(restored)

            # 1. Compare the complete raw data, including vector element types.
            @test typeof(restored) == typeof(source)
            @test restored_data.metadata === restored.partitions
            @test map(partition -> map(block -> map(eltype, block), partition), restored_data.data) ==
                map(partition -> map(block -> map(eltype, block), partition), source_data.data)
            @test isequal(restored_data.data, source_data.data)

            # 2. Preserve header entries and block metadata in their original order.
            for field in fieldnames(typeof(source.headers))
                expected = getfield(source.headers, field)
                actual = getfield(restored.headers, field)
                @test actual.keys == expected.keys
                @test isequal(actual.data, expected.data)
            end
            for (p, partition) in enumerate(source.partitions), (b, block) in enumerate(partition.blocks)
                actual = restored.partitions[p].blocks[b]
                @test map(column -> column.name, actual.columns) == map(column -> column.name, block.columns)
                @test actual.npart == block.npart
                @test actual.array_counts == block.array_counts
                @test map(column -> column.dtype_index, actual.columns) ==
                    map(column -> column.dtype_index, block.columns)
            end

            # 3. Output identifies ParticleIO; the source identifier stays unchanged.
            @test startswith(restored.file_identifier, "FT:ParticleIO:$(ParticleIO.version()): ")
            @test !occursin(r"[()]", restored.file_identifier)
            @test ncodeunits(restored.file_identifier) == 100
            @test source.file_identifier == source_identifier

            # Verify that the analysis reader also accepts the written dump.
            particles, sinks = read_phantom(target; ignore_inactive = false)
            @test isequal(particles[!, :x], source_data[1, 1, 2])
            @test isequal(sinks[!, :x], source_data[1, 2, 1])
            file, data = restored, restored_data
        end
    end
end
