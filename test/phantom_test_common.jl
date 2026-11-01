######################################################################################

#  Phantom IO -- Shared Integration Fixtures
#  Independent native-record emitter for repeated tags, mixed datatypes, and MPI partitions.
#  No production writer is used to construct the read-test oracle.

######################################################################################
using Test
using ParticleIO

function fixture_record(io, values)
    nbytes = Int32(sizeof(values))
    write(io, nbytes)
    write(io, values)
    write(io, nbytes)
end

function grouped_fixture(path, TI, TF; P = 2, empty_particles = false)
    dtypes = (TI, Int8, Int16, Int32, Int64, TF, Float32, Float64)
    expected = ntuple(P) do p
        n = empty_particles ? 0 : p + 2
        # Columns deliberately interleave repeated tags and singles within dtype 6.
        specifications = ((1, "code", 1), (2, "itype", 1), (3, "short", 2),
            (4, "dustfrac", 3), (5, "id", 4), (6, "dustfrac", 5),
            (6, "x", 6), (6, "tstop", 7), (6, "h", 8),
            (6, "dustfrac", 9), (6, "tstop", 10), (7, "single32", 11), (8, "single64", 12))
        gas = map(specifications) do (dtype, name, value)
            (dtype, rpad(name, 16), dtypes[dtype].(value .+ p .+ (1:n)))
        end
        sink = ((6, rpad("m", 16), TF[5]), (6, rpad("pos", 16), TF[1]), (6, rpad("pos", 16), TF[2]))
        magnetic = ((6, rpad("B", 16), fill(TF(2), n)), (6, rpad("B", 16), fill(TF(3), n)))
        (gas, sink, (), magnetic)
    end
    open(path, "w") do io
        capture = IOBuffer()
        write(capture, TI(60769), TF(60878), TI(60878), TI(1), TI(690706))
        fixture_record(io, take!(capture))
        fixture_record(io, collect(codeunits(rpad("FT:independent-fixture", 100))))
        for group in 1:8
            fixture_record(io, Int32[group == 1 ? 1 : 0])
            if group == 1
                fixture_record(io, collect(codeunits(rpad("nblocks", 16))))
                fixture_record(io, TI[P])
            end
        end
        fixture_record(io, Int32[4P])
        for partition in expected
            for records in partition
                npart = isempty(records) ? 0 : length(first(records)[3])
                counts = ntuple(k -> Int32(count(record -> record[1] == k, records)), 8)
                write(io, Int32(40), Int64(npart))
                foreach(value -> write(io, value), counts)
                write(io, Int32(40))
            end
            for records in partition, (_, name, values) in records
                fixture_record(io, collect(codeunits(name)))
                fixture_record(io, values)
            end
        end
    end
    return expected
end

# Read physical records sequentially, independently of the grouped column reader.
function physical_records(path, file)
    dtypes = phantom_dtypes(file)
    open(path, "r") do io
        map(file.partitions, file.sections.partitions) do partition, offsets
            seek(io, offsets.particle_data)
            map(partition.blocks) do block
                records = []
                for dtype in 1:8, _ in 1:block.array_counts[dtype]
                    @test read(io, Int32) == 16
                    name = String(read(io, 16))
                    @test read(io, Int32) == 16
                    T = dtypes[dtype]
                    @test read(io, Int32) == sizeof(T) * block.npart
                    values = read!(io, Vector{T}(undef, block.npart))
                    @test read(io, Int32) == sizeof(values)
                    push!(records, (dtype, name, values))
                end
                Tuple(records)
            end
        end
    end
end

function all_vectors(data)
    result = Vector[]
    for partition in data.partitions, block in partition.blocks
        append!(result, block.columns)
        for group in block.column_groups
            append!(result, group)
        end
    end
    return result
end

function check_readback(source, source_data, restored, restored_data)
    @test typeof(restored) == typeof(source)
    @test restored_data.metadata === restored
    for field in fieldnames(typeof(source.headers))
        expected = getfield(source.headers, field)
        actual = getfield(restored.headers, field)
        @test actual.keys == expected.keys
        @test isequal(actual.data, expected.data)
    end
    for p in eachindex(source.partitions)
        @test restored_data.partitions[p].metadata === restored.partitions[p]
        for b in eachindex(source.partitions[p].blocks)
            before = source.partitions[p].blocks[b]
            after = restored.partitions[p].blocks[b]
            values = source_data.partitions[p].blocks[b]
            readback = restored_data.partitions[p].blocks[b]
            @test readback.metadata === after
            @test after.npart == before.npart
            @test after.array_counts == before.array_counts
            @test map(c -> (c.name, c.dtype_index), after.columns) == map(c -> (c.name, c.dtype_index), before.columns)
            @test map(g -> (g.name, g.dtype_indices), after.column_groups) == map(g -> (g.name, g.dtype_indices), before.column_groups)
            @test map(eltype, readback.columns) == map(eltype, values.columns)
            @test map(group -> map(eltype, group), readback.column_groups) == map(group -> map(eltype, group), values.column_groups)
            @test isequal(readback.columns, values.columns)
            @test isequal(readback.column_groups, values.column_groups)
        end
    end
    @test startswith(restored.file_identifier, "FT:Phantom:ParticleIO:$(ParticleIO.version()): ")
    @test !occursin(r"[()]", restored.file_identifier)
    @test ncodeunits(restored.file_identifier) == 100
end

# Build new metadata without source offsets, sharing vectors with the read input.
function without_offsets(file, data)
    partitions = map(file.partitions) do partition
        blocks = map(partition.blocks) do block
            columns = map(c -> PhantomColumnInfo(c.name, c.dtype_index, -1), block.columns)
            groups = map(block.column_groups) do group
                PhantomColumnGroupInfo(group.name, group.dtype_indices, map(_ -> Int64(-1), group.data_record_offsets))
            end
            PhantomBlockInfo(block.npart, block.array_counts, columns, groups)
        end
        PhantomPartitionInfo(blocks)
    end
    fresh = PhantomFile("not-a-source-file", file.file_identifier, file.headers, file.sections, partitions)
    dtypes = phantom_dtypes(fresh)
    contents = map(partitions, data.partitions) do partition, source
        blocks = map(partition.blocks, source.blocks) do metadata, original
            PhantomBlockData(metadata, original.columns, original.column_groups, dtypes)
        end
        PhantomPartitionData(partition, blocks)
    end
    return fresh, PhantomData(fresh, contents)
end
