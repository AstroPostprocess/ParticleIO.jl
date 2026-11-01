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
#  4. Repeated columns and new metadata
#     -- Interleaving, mixed datatypes, empty records, and stable ordering without offsets.
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
            check_readback(source, source_data, restored, restored_data)
            @test source.file_identifier == source_identifier
            particles, sinks = read_phantom(target; ignore_inactive = false)
            @test isequal(particles[!, :x], source_data.partitions[1].blocks[1].columns[2])
            @test isequal(sinks[!, :x], source_data.partitions[1].blocks[2].columns[1])
            file, data = restored, restored_data
        end

        # Interleaved repeated tags must survive in their original physical order.
        for TI in (Int32, Int64), TF in (Float32, Float64)
            input = joinpath(dir, "grouped.dump")
            expected = grouped_fixture(input, TI, TF)
            original = PhantomFile(input)
            original_data = read_data(original)
            file, data = original, original_data
            for generation in 1:2
                target = joinpath(dir, "grouped_$generation.dump")
                @test write_data(target, data; overwrite = true) === nothing
                restored = PhantomFile(target)
                restored_data = read_data(restored)
                check_readback(original, original_data, restored, restored_data)
                @test isequal(physical_records(target, restored), expected)
                file, data = restored, restored_data
            end

            # New metadata without offsets uses stable datatype order and retains group member order.
            fresh, values = without_offsets(original, original_data)
            target = joinpath(dir, "new.dump")
            write_data(target, fresh, values; overwrite = true)
            rebuilt = PhantomFile(target)
            rebuilt_data = read_data(rebuilt)
            check_readback(fresh, values, rebuilt, rebuilt_data)
            first_order = physical_records(target, rebuilt)
            target2 = joinpath(dir, "new_again.dump")
            write_data(target2, fresh, values; overwrite = true)
            @test isequal(first_order, physical_records(target2, PhantomFile(target2)))

            # Validate mutable vector lengths before creating or replacing output.
            before = read(target)
            resize!(values.partitions[1].blocks[1].column_groups[1][1], 0)
            @test_throws DimensionMismatch write_data(target, fresh, values; overwrite = true)
            @test read(target) == before
        end

        # Zero particles and zero columns are different layouts; both survive writing.
        path = joinpath(dir, "empty.dump")
        grouped_fixture(path, Int32, Float64; empty_particles = true)
        file = PhantomFile(path)
        data = read_data(file)
        target = joinpath(dir, "empty_copy.dump")
        write_data(target, file, data)
        restored = PhantomFile(target)
        check_readback(file, data, restored, read_data(restored))
    end
end
