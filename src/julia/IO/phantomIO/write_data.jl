"""
    _validate_phantom_output(file::PhantomFile, block_data::PhantomData)

Validate the metadata and nested column vectors before any output is modified.
"""
function _validate_phantom_output(file :: PhantomFile{P, B, S, R}, data :: PhantomData{P, B, S, R}) where {P, B, S, R}
    data.metadata === file || throw(ArgumentError("Data must share the supplied file metadata"))
    _phantom_partition_count(file.headers) == P || throw(ArgumentError("Header nblocks does not match partition count"))
    Int128(B) * P <= 1_000_000 || throw(ArgumentError("Too many particle blocks"))
    for field in fieldnames(typeof(file.headers))
        _validate_header_block(getfield(file.headers, field))
    end
    dtypes = phantom_dtypes(file)
    for partition in data.partitions, block in partition.blocks
        _validate_block_vectors(block, dtypes)
        for location in _physical_column_locations(block.metadata)
            column = _column_info(block.metadata, location)
            values = _column_vector(block, location)
            ncodeunits(column.name) <= 16 || throw(ArgumentError("Column name exceeds 16 bytes"))
            length(values) <= div(typemax(Int32), sizeof(eltype(values))) ||
                throw(ArgumentError("Column record exceeds the Int32 byte-count limit"))
        end
    end
    return nothing
end

function _write_data(io :: Base.IO, file :: PhantomFile{P, B, S, R, TI, TF}, data :: PhantomData{P, B, S, R}, identifier :: String) where {P, B, S, R, TI, TF}
    _write_capture_pattern(io, TI, TF)
    _write_file_identifier(io, position(io), identifier)
    _write_global_header(io, file.headers)
    _write_fortran_block(io, Int32[P * B])
    for partition in data.partitions
        _write_particle_block_metadata(io, partition.metadata.blocks)
        for block in partition.blocks
            for location in _physical_column_locations(block.metadata)
                _write_column(io, _column_info(block.metadata, location), _column_vector(block, location))
            end
        end
    end
    return nothing
end

"""
    write_data(io::Base.IO, data::PhantomData)
    write_data(filename::AbstractString, data::PhantomData; overwrite=false)

Write a Phantom binary dump using the metadata and particle vectors stored in `data`.

Vector types and lengths are validated before writing. Original offsets restore
the physical column order. Without usable offsets, datatype groups are written
in order, with singles followed by repeated groups within each datatype.
Group member order is preserved; metadata whose group order conflicts with
datatype order cannot be serialized.

Headers are written as supplied. A new `FT:Phantom:ParticleIO:<version> (tags): <timestamp>`
identifier uses the current `data.metadata.file_tags`; empty tags omit the parentheses.
The original `file_identifier` remains unchanged.

The stream must be empty and positioned at zero; it is left open. The path overload
writes through a temporary file and requires `overwrite=true` to replace an existing file.
Both methods return `nothing`; reopen the output with `PhantomFile` to obtain its offsets.

# Parameters
- `io::Base.IO`: Output stream.
- `filename::AbstractString`: Output file path.
- `data::PhantomData`: Particle data and associated metadata to write.

# Keyword Arguments
| Argument | Default | Description |
|----------|---------|-------------|
| `overwrite::Bool` | `false` | Whether to replace an existing output file. |
"""
function write_data(io :: Base.IO, data :: PhantomData)
    file = data.metadata
    _validate_phantom_output(file, data)
    identifier = _particleio_file_identifier(file.file_tags)
    position(io) == 0 && eof(io) || throw(ArgumentError("Output stream must be empty and positioned at zero"))
    _write_data(io, file, data, identifier)
    return nothing
end

function write_data(filename :: AbstractString, data :: PhantomData; overwrite :: Bool = false)
    file = data.metadata
    _validate_phantom_output(file, data)
    identifier = _particleio_file_identifier(file.file_tags)
    target = abspath(filename)
    isdir(target) && throw(ArgumentError("Output path is a directory"))
    ispath(target) && !overwrite && throw(ArgumentError("Output exists; pass overwrite=true to replace it"))
    temporary, io = mktemp(dirname(target))
    try
        _write_data(io, file, data, identifier)
        close(io)
        mv(temporary, target; force = overwrite)
    finally
        isopen(io) && close(io)
        ispath(temporary) && rm(temporary)
    end
    return nothing
end