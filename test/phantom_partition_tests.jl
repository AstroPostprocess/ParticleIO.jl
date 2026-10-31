module PhantomPartitionTests
using Test
using ParticleIO

# Independently emit the partition layout, rather than using write_phantom to generate its own oracle.
function record(io, values)
    n = Int32(sizeof(values))
    write(io, n)
    write(io, values)
    write(io, n)
end

function fixture(path, N, B; declared_partitions=N, declared_blocks=N*B)
    offsets = Tuple{Int64, Int64}[]
    open(path, "w") do io
        write(io, Int32(24), Int32(60769), Float64(60878), Int32(60878), Int32(1), Int32(690706), Int32(24))
        record(io, collect(codeunits(rpad("FT:partition-test", 100))))
        record(io, Int32[1])
        record(io, collect(codeunits(rpad("nblocks", 16))))
        record(io, Int32[declared_partitions])
        for _ in 2:8
            record(io, Int32[0])
        end
        record(io, Int32[declared_blocks])
        for p in 1:N
            metadata = Int64(position(io))
            counts = B == 2 ? [2, 1] : [2, 1, 0, 1]
            sizes = B == 2 ? [p, 1] : [p, 1, 0, p]
            for b in 1:B
                write(io, Int32(40), Int64(sizes[b]))
                for k in 1:8
                    write(io, Int32(k == 6 ? counts[b] : 0))
                end
                write(io, Int32(40))
            end
            push!(offsets, (metadata, Int64(position(io))))
            for b in 1:B
                names = b == 1 ? ("x", "h") : b == 2 ? ("m",) : b == 3 ? () : ("Bx",)
                for name in names
                    record(io, collect(codeunits(rpad(name, 16))))
                    values = name == "x" ? Float64.(10p .+ (1:p)) :
                             name == "h" ? ones(p) : name == "m" ? [5.0] : fill(Float64(p), p)
                    record(io, values)
                end
            end
        end
    end
    return offsets
end

@testset "Partition indexing, selection, writing, and analysis" begin
    mktempdir() do dir
        for N in (1, 2, 3), B in (2, 4)
            path = joinpath(dir, "partitions.dump")
            offsets = fixture(path, N, B)
            file = PhantomFile(path)
            @test file isa PhantomFile{N}
            C = B == 2 ? (2, 1) : (2, 1, 0, 1)
            @test file isa PhantomFile{N, B, C, Int32, Float64}
            @test_throws DimensionMismatch PhantomFile{N, B, (99,), Int32, Float64}(
                path, file.file_identifier, file.headers, file.sections, file.partitions)
            @test file.sections isa PhantomSectionOffsets{N}
            @test file.partitions isa NTuple{N, PhantomPartition{B}}
            @test isconcretetype(fieldtype(typeof(file), :partitions))
            @test_throws MethodError PhantomFile{N, B + 1, C, Int32, Float64}(
                path, file.file_identifier, file.headers, file.sections, file.partitions)
            if N > 1
                shorter = PhantomPartition(Base.front(file.partitions[end].blocks))
                mixed = (Base.front(file.partitions)..., shorter)
                @test_throws MethodError PhantomFile(path, file.file_identifier,
                    file.headers, file.sections, mixed)
            end
            @test file.sections.partitions isa NTuple{N, PhantomPartitionOffsets}
            @test fieldnames(typeof(file.sections)) == (:capture_pattern, :file_identifier, :global_header, :partitions)
            @test length(file.partitions) == N
            for p in 1:N
                @test file.partitions[p].blocks isa NTuple{B, PhantomBlockInfo}
                @test file.sections.partitions[p].particle_block_metadata == offsets[p][1]
                @test file.sections.partitions[p].particle_data == offsets[p][2]
                @test read_column!(Float64[], file, p, 1, 1) == Float64.(10p .+ (1:p))
                x, h = Float64[], Float64[]
                @test read_columns!((h, x), file, p, 1, (2, 1)) === (h, x)
                @test h == ones(p)
                @test x == Float64.(10p .+ (1:p))
            end
            data = read_data(file)
            @test data.partitions isa Tuple
            @test length(data[N][1][1]) == N
            @test data isa PhantomData{N, B, C}
            output = IOBuffer()
            write_phantom(output, file, data)
            @test take!(output) == read(path)
            @test file.partitions[1].blocks[1].columns isa Tuple
            wrong_columns = PhantomData(ntuple(_ -> ((Float64[],),), N), ntuple(_ -> (("x",),), N))
            untouched = IOBuffer()
            @test_throws MethodError write_phantom(untouched, file, wrong_columns)
            @test position(untouched) == 0
            analysis = read_phantom(path)
            @test size(analysis[1].dfdata, 1) == sum(1:N)
            @test size(analysis[2].dfdata, 1) == 1
            @test B != 4 || "Bx" in names(analysis[1])
            shown = sprint(show, MIME"text/plain"(), file.sections)
            @test occursin("partition $N", shown)
            @test occursin("Partition $N", sprint(show, MIME"text/plain"(), file))
            if N > 1
                @test_throws MethodError read_column!(Float64[], file, 1, 1)
                @test_throws MethodError write_phantom(IOBuffer(), file, PhantomData((data[1],), (data.column_names[1],)))
                original = file.headers.default_integer.data[1]
                file.headers.default_integer.data[1] = 1
                @test_throws ArgumentError write_phantom(IOBuffer(), file, data)
                file.headers.default_integer.data[1] = original
                @test_throws MethodError PhantomFile(path, file.file_identifier,
                    file.headers, PhantomSectionOffsets(0, 32, 140, (file.sections.partitions[1],)), file.partitions)
            end
        end
    end
end

@testset "Reject malformed partition declarations" begin
    mktempdir() do dir
        path = joinpath(dir, "invalid.dump")
        fixture(path, 2, 2; declared_partitions=0)
        @test_throws ArgumentError PhantomFile(path)
        fixture(path, 2, 2; declared_blocks=3)
        @test_throws ArgumentError PhantomFile(path)
        fixture(path, 2, 2)
        open(path, "r+") do io
            truncate(io, filesize(path) - 4)
        end
        @test_throws EOFError PhantomFile(path)
    end
end
end
