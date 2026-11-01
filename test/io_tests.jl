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
#  4. Grouped native fixtures
#     -- Mixed-type repeated tags, metadata sharing, destination reuse, and empty records.
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
    @test file isa PhantomFile{1, 2, (11, 14), (0, 0), Int32, Float64}
    @test data isa PhantomData{1, 2, (11, 14), (0, 0)}
    @test data.metadata === file
    @test ncodeunits(file.file_identifier) == 100
    @test map(block -> block.npart, file.partitions[1].blocks) == (550000, 2)
    @test map(column -> strip(column.name), data.metadata.partitions[1].blocks[1].columns) ==
        ("itype", "x", "y", "z", "vx", "vy", "vz", "dustfrac", "h", "divv", "dt")

    # 2. Raw vectors follow the indexed metadata without copying the metadata.
    dtypes = phantom_dtypes(file)
    for (p, partition) in enumerate(file.partitions), (b, block) in enumerate(partition.blocks)
        @test all(length(values) == block.npart for values in data.partitions[p].blocks[b].columns)
        @test map(eltype, data.partitions[p].blocks[b].columns) == map(column -> dtypes[Int(column.dtype_index)], block.columns)
        @test data.partitions[p].blocks[b].metadata === block
    end

    # 3. Keep inactive particles so analysis and raw data describe the same rows.
    particles, sinks = read_phantom(filename; ignore_inactive = false)
    @test get_npart(particles) == 550000
    @test get_npart(sinks) == 2
    @test isequal(particles[!, :x], data.partitions[1].blocks[1].columns[2])
    @test isequal(sinks[!, :x], data.partitions[1].blocks[2].columns[1])
    @test particles.params[:nparttot] == 550000

    # 4. Independent grouped dumps exercise all default datatypes and MPI partitions.
    mktempdir() do dir
        # Physics tags come only from a valid parenthesized list, never from version or time.
        cases = (("(hydro)", [:hydro]),
                 ("(hydro+dust)", [:hydro, :dust]),
                 ("(hydro+grav+dust)", [:hydro, :grav, :dust]),
                 ("(hydro+1dust+H2chem)", [:hydro, Symbol("1dust"), :H2chem]),
                 ("(mhd+clean+grav+dust)", [:mhd, :clean, :grav, :dust]),
                 ("( hydro + CustomTag + hydro )", [:hydro, :CustomTag, :hydro]),
                 ("", Symbol[]), ("()", Symbol[]), ("(hydro+)", Symbol[]),
                 ("(hydro++dust)", Symbol[]), ("((hydro))", Symbol[]), ("(hydro", Symbol[]))
        for (tag_text, tags) in cases
            identifier = "FT:Phantom:1.4.0:8f94cb0 $tag_text: 11/05/2023 03:29:35.3"
            path = joinpath(dir, "tags.dump")
            grouped_fixture(path, Int32, Float64; identifier)
            tagged = PhantomFile(path)
            @test tagged.file_tags == tags
            @test tagged.file_tags isa Vector{Symbol}
            @test tagged.file_identifier == rpad(identifier, 100)
            push!(tagged.file_tags, :dustgrowth)
            @test tagged.file_identifier == rpad(identifier, 100)
        end

        for TI in (Int32, Int64), TF in (Float32, Float64)
            path = joinpath(dir, "grouped.dump")
            expected = grouped_fixture(path, TI, TF)
            indexed = PhantomFile(path)
            @test indexed isa PhantomFile{2, 4, (8, 1, 0, 0), (2, 1, 0, 1), TI, TF}
            header = indexed.headers.default_integer
            @test header.keys == [rpad("nblocks", 16)]
            @test header.content == TI[2]
            @test header.group_keys == rpad.(["counts", "flags"], 16)
            @test header.group_content == Tuple[(TI(11), TI(12)), (TI(21), TI(22))]
            @test header.group_lengths == [2, 2]
            @test header.group_content isa Vector{Tuple}
            dest = allocate_data(indexed)
            @test dest.metadata === indexed
            refs = all_vectors(dest)
            open(path, "r") do io
                @test read_data!(io, dest) === dest
                @test isopen(io)
                snapshot = map(copy, refs)
                foreach(values -> resize!(values, 0), refs)
                @test read_data!(io, dest) === dest
                @test all(pair -> pair[1] === pair[2], zip(refs, all_vectors(dest)))
                @test isequal(all_vectors(dest), snapshot)
                @test read_partition!(io, dest.partitions[2], indexed) === dest.partitions[2]
                @test read_block!(io, dest.partitions[1].blocks[1], indexed) === dest.partitions[1].blocks[1]
            end
            for p in 1:2, b in 1:4
                block = dest.partitions[p].blocks[b]
                info = indexed.partitions[p].blocks[b]
                @test dest.partitions[p].metadata === indexed.partitions[p]
                @test block.metadata === info
                for (c, (dtype, name, values)) in enumerate(expected[p][b])
                    @test read_column!(Vector{phantom_dtypes(indexed)[dtype]}(), indexed, p, b, c) == values
                end
            end
            gas = dest.partitions[1].blocks[1]
            @test gas.metadata.column_groups[1].name == rpad("dustfrac", 16)
            @test gas.metadata.column_groups[1].dtype_indices == (UInt8(4), UInt8(6), UInt8(6))
            @test map(eltype, gas.column_groups[1]) == (Int32, TF, TF)
            @test isequal(gas.column_groups[1], (expected[1][1][4][3], expected[1][1][6][3], expected[1][1][10][3]))
            @test isempty(dest.partitions[1].blocks[3].columns)
            @test length(dest.partitions[1].blocks[4].column_groups) == 1
            @test !applicable(getindex, dest, 1, 1, 1)
            analysis = read_phantom(path; ignore_inactive = false)
            @test analysis[1].dfdata[!, :dustfrac][1] == tuple((v[1] for v in gas.column_groups[1])...)

            # Identical counts alone do not authorize a different metadata object or vector type.
            other = PhantomFile(path)
            @test_throws ArgumentError read_data!(IOBuffer(), dest, other)
            bad_groups = ((Float64[],), Base.tail(gas.column_groups)...)
            @test_throws DimensionMismatch PhantomBlockData(gas.metadata, gas.columns, bad_groups, phantom_dtypes(indexed))
            wrong = (Int8[], Base.tail(gas.column_groups[1])...)
            @test_throws ArgumentError PhantomBlockData(gas.metadata, gas.columns, (wrong, Base.tail(gas.column_groups)...), phantom_dtypes(indexed))
            different, _ = without_offsets(indexed, dest)
            @test_throws ArgumentError PhantomPartitionData(different.partitions[1], dest.partitions[1].blocks)
            @test_throws ArgumentError PhantomData(different, dest.partitions)
            unbacked = PhantomFile("missing.dump", indexed.file_identifier, indexed.headers, indexed.sections, indexed.partitions)
            @test allocate_data(unbacked).metadata === unbacked
            @test isempty(unbacked.file_tags)
            explicit = typeof(indexed)("", indexed.file_identifier, indexed.headers, indexed.sections, indexed.partitions;
                file_tags = [:hydro, Symbol("1dust")])
            @test explicit.file_tags == [:hydro, Symbol("1dust")]
            @test isempty(typeof(indexed)("", indexed.file_identifier, indexed.headers, indexed.sections, indexed.partitions).file_tags)

            if TI == Int32 && TF == Float64
                # Invalid metadata cannot enter a destination or reach the binary writer.
                info = gas.metadata
                @test_throws ArgumentError PhantomBlockInfo(-1, info.array_counts, info.columns, info.column_groups)
                negative = (-Int32(1), Base.tail(info.array_counts)...)
                @test_throws ArgumentError PhantomBlockInfo(info.npart, negative, info.columns, info.column_groups)
                duplicate = (info.columns[1], info.columns[1], info.columns[3:end]...)
                @test_throws ArgumentError PhantomBlockInfo(info.npart, info.array_counts, duplicate, info.column_groups)
                @test_throws ArgumentError PhantomBlockInfo(info.npart, info.array_counts, info.columns,
                    (info.column_groups[1], info.column_groups[1]))
                collision = PhantomColumnGroupInfo(info.columns[1].name,
                    info.column_groups[1].dtype_indices, info.column_groups[1].data_record_offsets)
                @test_throws ArgumentError PhantomBlockInfo(info.npart, info.array_counts, info.columns,
                    (collision, info.column_groups[2]))
                singleton = PhantomColumnGroupInfo("singleton", (UInt8(6),), (Int64(-1),))
                @test_throws ArgumentError PhantomBlockInfo(0, ntuple(_ -> Int32(0), 8), (), (singleton,))
                invalid = PhantomColumnInfo("invalid", UInt8(9), -1)
                @test_throws ArgumentError PhantomBlockInfo(0, ntuple(_ -> Int32(0), 8), (invalid,), ())
                invalid_group = PhantomColumnGroupInfo("invalid", (UInt8(0), UInt8(6)), (Int64(-1), Int64(-1)))
                @test_throws ArgumentError PhantomBlockInfo(0, ntuple(_ -> Int32(0), 8), (), (invalid_group,))
                @test_throws DimensionMismatch PhantomBlockInfo(info.npart, ntuple(_ -> Int32(0), 8), info.columns, info.column_groups)
                swapped_counts = (info.array_counts[1] + Int32(1), info.array_counts[2] - Int32(1), info.array_counts[3:end]...)
                @test_throws DimensionMismatch PhantomBlockInfo(info.npart, swapped_counts, info.columns, info.column_groups)
                @test_throws MethodError read_block!(IOBuffer(), gas, indexed.partitions[1].blocks[2], phantom_dtypes(indexed))
                @test_throws ArgumentError read_block!(IOBuffer(), gas, different.partitions[1].blocks[1], phantom_dtypes(indexed))
                @test_throws MethodError PhantomPartitionData(indexed.partitions[1], Base.front(dest.partitions[1].blocks))

                # S/R can match while a repeated group's member count differs across partitions.
                info2 = indexed.partitions[2].blocks[1]
                group = info2.column_groups[1]
                longer = PhantomColumnGroupInfo(group.name, (group.dtype_indices..., UInt8(6)),
                    (group.data_record_offsets..., Int64(-1)))
                counts = ntuple(i -> info2.array_counts[i] + Int32(i == 6), 8)
                changed = PhantomBlockInfo(info2.npart, counts, info2.columns, (longer, info2.column_groups[2]))
                changed_partition = PhantomPartitionInfo((changed, Base.tail(indexed.partitions[2].blocks)...))
                @test_throws ArgumentError PhantomFile("", indexed.file_identifier, indexed.headers, indexed.sections,
                    (indexed.partitions[1], changed_partition))
            end
        end
        grouped_fixture(joinpath(dir, "empty.dump"), Int32, Float64; empty_particles = true)
        empty_data = read_data(PhantomFile(joinpath(dir, "empty.dump")))
        @test all(isempty, empty_data.partitions[1].blocks[1].column_groups[1])
    end

end
