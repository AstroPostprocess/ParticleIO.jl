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
        data = source_data

        # Feed each readback into the next write, comparing both to the source.
        for generation in 1:2
            target = joinpath(dir, "roundtrip_$generation.dump")
            @test write_data(target, data) === nothing

            restored = PhantomFile(target)
            restored_data = read_data(restored)
            check_readback(source, source_data, restored, restored_data)

            @test source.file_identifier == source_identifier

            particles, sinks = read_phantom(target; ignore_inactive = false)
            @test isequal(particles[!, :x], source_data.partitions[1].blocks[1].columns[2])
            @test isequal(sinks[!, :x], source_data.partitions[1].blocks[2].columns[1])

            data = restored_data
        end

        # Interleaved repeated tags must survive in their original physical order.
        for TI in (Int32, Int64), TF in (Float32, Float64)
            input = joinpath(dir, "grouped.dump")
            expected = grouped_fixture(input, TI, TF)
            original = PhantomFile(input)
            original_data = read_data(original)
            data = original_data

            for generation in 1:2
                target = joinpath(dir, "grouped_$generation.dump")
                @test write_data(target, data; overwrite = true) === nothing

                restored = PhantomFile(target)
                restored_data = read_data(restored)
                check_readback(original, original_data, restored, restored_data)

                # Inspect the native header records: singles first, then each repeated group.
                open(target, "r") do io
                    seek(io, restored.sections.global_header)
                    @test read(io, Int32) == 4
                    @test read(io, Int32) == 5
                    @test read(io, Int32) == 4
                    @test read(io, Int32) == 80
                    @test String(read(io, 80)) == join(rpad.(("nblocks", "counts", "counts", "flags", "flags"), 16))
                    @test read(io, Int32) == 80
                    @test read(io, Int32) == 5sizeof(TI)
                    @test read!(io, Vector{TI}(undef, 5)) == TI[2, 11, 12, 21, 22]
                    @test read(io, Int32) == 5sizeof(TI)
                end

                @test isequal(physical_records(target, restored), expected)
                data = restored_data
            end

            # New metadata without offsets uses stable datatype order and retains group member order.
            fresh, values = without_offsets(original, original_data)
            target = joinpath(dir, "new.dump")
            write_data(target, values; overwrite = true)

            rebuilt = PhantomFile(target)
            rebuilt_data = read_data(rebuilt)
            check_readback(fresh, values, rebuilt, rebuilt_data)

            first_order = physical_records(target, rebuilt)
            target2 = joinpath(dir, "new_again.dump")
            write_data(target2, values; overwrite = true)
            @test isequal(first_order, physical_records(target2, PhantomFile(target2)))

            # Validate mutable vector lengths before creating or replacing output.
            before = read(target)
            header = fresh.headers.default_integer

            header.group_lengths[1] += 1
            @test_throws DimensionMismatch write_data(target, values; overwrite = true)
            @test read(target) == before
            header.group_lengths[1] -= 1

            saved_group = header.group_content[1]
            header.group_content[1] = ("invalid", "values")
            @test_throws ArgumentError write_data(target, values; overwrite = true)
            @test read(target) == before
            header.group_content[1] = saved_group

            resize!(values.partitions[1].blocks[1].column_groups[1][1], 0)
            @test_throws DimensionMismatch write_data(target, values; overwrite = true)
            @test read(target) == before
        end

        # User-supplied tags override the original identifier, including an explicitly empty list.
        input = joinpath(dir, "tag_source.dump")
        identifier = "FT:Phantom:1.4.0:8f94cb0 (hydro+grav): 11/05/2023 03:29:35.3"
        grouped_fixture(input, Int32, Float64; identifier)

        indexed = PhantomFile(input)
        original_identifier = indexed.file_identifier

        for tags in (Symbol[], [:hydro, Symbol("1dust"), :H2chem], [:mhd, :clean, :dust], [:CustomTag, :hydro, :CustomTag])
            file = PhantomFile(input, indexed.file_identifier, indexed.headers, indexed.sections, indexed.partitions; file_tags = copy(tags))
            data = read_data(file)
            target = joinpath(dir, "tagged.dump")

            for generation in 1:2
                write_data(target, data; overwrite = true)

                restored = PhantomFile(target)
                check_readback(file, data, restored, read_data(restored))

                @test restored.file_tags == file.file_tags
                @test file.file_identifier == original_identifier
                @test !isempty(file.file_tags) || !occursin('(', restored.file_identifier)
                Symbol("1dust") in file.file_tags && @test occursin("hydro+1dust", restored.file_identifier)

                generation == 1 && push!(file.file_tags, :dustgrowth)
            end

            # The stream writer must use the same current tags.
            stream = IOBuffer()
            write_data(stream, data)

            open(target, "w") do io
                write(io, take!(stream))
            end

            @test PhantomFile(target).file_tags == file.file_tags
        end

        @test isempty(PhantomFile(input, indexed.file_identifier, indexed.headers, indexed.sections, indexed.partitions).file_tags)

        # Invalid tags and oversized UTF-8 identifiers fail before either output is modified.
        data = read_data(indexed)
        target = joinpath(dir, "protected.dump")
        write_data(target, data)
        before = read(target)

        for tag in ("", " ", " hydro", "hydro ", "hydro+dust", "(hydro", "hydro)", "hydro\n", "x"^101, "測"^20)
            empty!(indexed.file_tags)
            push!(indexed.file_tags, Symbol(tag))

            stream = IOBuffer()
            @test_throws ArgumentError write_data(stream, data)
            @test position(stream) == 0
            @test isempty(take!(stream))

            @test_throws ArgumentError write_data(target, data; overwrite = true)
            @test read(target) == before
            @test indexed.file_identifier == original_identifier
        end

        # Zero particles and zero columns are different layouts; both survive writing.
        path = joinpath(dir, "empty.dump")
        grouped_fixture(path, Int32, Float64; empty_particles = true)

        file = PhantomFile(path)
        data = read_data(file)
        target = joinpath(dir, "empty_copy.dump")

        write_data(target, data)

        restored = PhantomFile(target)
        check_readback(file, data, restored, read_data(restored))
    end
end
