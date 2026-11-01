"""
    _validate_phantom_output(file::PhantomFile, block_data::PhantomData)

Validate the metadata and nested column vectors before any output is modified.
"""
function _validate_phantom_output(file :: PhantomFile{P, B, C, TI, TF}, block_data :: PhantomData{P, B, C}) where {P, B, C, TI, TF}
    _phantom_partition_count(file.headers) == P || throw(ArgumentError("Header nblocks does not match partition count"))
    Int128(B) * P <= 1_000_000 || throw(ArgumentError("Too many particle blocks"))
    for field in fieldnames(typeof(file.headers))
        _validate_header_block(getfield(file.headers, field))
    end

    dtypes = phantom_dtypes(file)
    for (partition, partition_data) in zip(file.partitions, block_data)
        for (block, columns) in zip(partition.blocks, partition_data)
            index = 1
            for dtype_index in eachindex(dtypes)
                T = dtypes[dtype_index]
                for _ in 1:block.array_counts[dtype_index]
                    column = block.columns[index]
                    content = columns[index]
                    Int(column.dtype_index) == dtype_index ||
                        throw(ArgumentError("Columns must follow the eight datatype groups in order"))
                    ncodeunits(column.name) <= 16 || throw(ArgumentError("Column name exceeds 16 bytes"))
                    content isa AbstractVector{T} || throw(ArgumentError("Column $index requires an AbstractVector{$T}"))
                    Base.require_one_based_indexing(content)
                    length(content) == block.npart || throw(DimensionMismatch("Column length does not match npart"))
                    length(content) <= div(typemax(Int32), sizeof(T)) ||
                        throw(ArgumentError("Column record exceeds the Int32 byte-count limit"))
                    index += 1
                end
            end
        end
    end
    return nothing
end

function _write_data(io :: Base.IO, file :: PhantomFile{P, B, C, TI, TF}, block_data :: PhantomData{P, B, C}, identifier :: String) where {P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    _write_capture_pattern(io, TI, TF)
    _write_file_identifier(io, position(io), identifier)
    _write_global_header(io, file.headers)
    total_blocks = P * B
    _write_fortran_block(io, Int32[total_blocks])
    for (partition, partition_data) in zip(file.partitions, block_data)
        _write_particle_block_metadata(io, partition.blocks)
        for (block, columns) in zip(partition.blocks, partition_data)
            for (column, content) in zip(block.columns, columns)
                _write_column(io, column, content)
            end
        end
    end
    return nothing
end

"""
    write_data(io::Base.IO, file::PhantomFile{P,B,C}, data::PhantomData{P,B,C})
    write_data(filename::AbstractString, file::PhantomFile{P,B,C}, data::PhantomData{P,B,C}; overwrite=false)

Write a Phantom binary dump using metadata from `file` and vectors from `data`.
The structures must match; vector types and lengths are checked before writing.
Headers are written as supplied, with a new ParticleIO version/timestamp identifier.

The stream must be empty and positioned at zero; it is left open. The path overload
writes through a temporary file and requires `overwrite=true` to replace an existing file.
Returns `nothing`; reopen the output with `PhantomFile` to obtain its offsets.

```julia
file = PhantomFile("input.dump")
data = read_data(file)
write_data("output.dump", file, data)
```
"""
function write_data(io :: Base.IO, file :: PhantomFile{P, B, C}, block_data :: PhantomData{P, B, C}) where {P, B, C}
    _validate_phantom_output(file, block_data)
    identifier = _particleio_file_identifier()
    position(io) == 0 && eof(io) || throw(ArgumentError("Output stream must be empty and positioned at zero"))
    _write_data(io, file, block_data, identifier)
    return nothing
end

function write_data(filename :: AbstractString, file :: PhantomFile{P, B, C}, block_data :: PhantomData{P, B, C}; overwrite :: Bool = false) where {P, B, C}
    _validate_phantom_output(file, block_data)
    identifier = _particleio_file_identifier()
    target = abspath(filename)
    isdir(target) && throw(ArgumentError("Output path is a directory"))
    ispath(target) && !overwrite && throw(ArgumentError("Output exists; pass overwrite=true to replace it"))
    temporary, io = mktemp(dirname(target))
    try
        _write_data(io, file, block_data, identifier)
        close(io)
        mv(temporary, target; force = overwrite)
    finally
        isopen(io) && close(io)
        ispath(temporary) && rm(temporary)
    end
    return nothing
end
