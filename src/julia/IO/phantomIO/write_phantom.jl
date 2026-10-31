"""
    _validate_phantom_output(file::PhantomFile, block_data)

Validate the metadata and nested column vectors before any output is modified.
"""
function _validate_phantom_output(file :: PhantomFile{P, B, C, TI, TF}, block_data :: PhantomData{P, B, C}) where {P, B, C, TI, TF}
    ncodeunits(file.file_identifier) <= 100 || throw(ArgumentError("File identifier exceeds 100 bytes"))
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

function _write_phantom(io :: Base.IO, file :: PhantomFile{P, B, C, TI, TF}, block_data :: PhantomData{P, B, C}) where {P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    _write_capture_pattern(io, TI, TF)
    _write_file_identifier(io, position(io), file.file_identifier)
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
    write_phantom(io::Base.IO, file::PhantomFile{P,B,C}, block_data::PhantomData{P,B,C})
    write_phantom(filename::AbstractString, file::PhantomFile{P,B,C}, block_data::PhantomData{P,B,C}; overwrite::Bool=false)

Write metadata and particle columns to a Phantom native binary dump file.

The identifier, typed global headers, and partition metadata come from `file`; particle values come from
`block_data`. The output contains the capture pattern and global records followed by each partition's block
metadata and column records, in their original datatype-group order.

# Parameters
- `io::Base.IO`: Writable, empty, seekable destination stream positioned at byte zero. The stream is left open.
- `filename::AbstractString`: Destination path, used instead of `io`. Its parent directory must already exist.
- `file::PhantomFile{P,B,C}`: File metadata specifying `P` partitions, `B` blocks per partition, and the tuple `C`
  of column counts per block. Default integer and real datatypes are taken from its `TI` and `TF` parameters.
- `block_data::PhantomData{P,B,C}`: Raw particle vectors with the same structure as `file`.
  `block_data[p][b][c]` corresponds to `file.partitions[p].blocks[b].columns[c]`. Each vector must use one-based
  indexing, have the exact indexed element type, and contain the block's `npart` values, including inactive particles.
- `overwrite::Bool = false`: Allow replacement of an existing destination file. Available only for the path overload.

# Returns
- `nothing`: Output has been written. The input metadata and particle vectors are not modified.

# Examples
## Example 1: Write all raw columns to a new dump.
```julia
file = PhantomFile("dumpfile_00000")
data = read_data(file)
write_phantom("copy_00000", file, data)
copy_index = PhantomFile("copy_00000")
```

## Example 2: Replace an existing output file.
```julia
write_phantom("copy_00000", file, data; overwrite = true)
```

## Example 3: Write to an in-memory stream.
```julia
io = IOBuffer()
write_phantom(io, file, data)
bytes = take!(io)
```

# Notes
The `P`, `B`, and `C` parameters must match through method dispatch; incompatible structures produce a
`MethodError`. Tuple structure is checked when the objects are constructed. Vector lengths, element types,
mutable header contents, and binary-format limits are checked before writing.

Output uses native byte order, Int32 Fortran record markers, and capture-pattern version 1. Short names and
identifiers are padded with spaces to their fixed byte widths. Header values are written as supplied;
physical parameters and particle counts are not recomputed from edited vectors.

The path overload writes to a temporary file in the destination directory, closes it, then moves it to the
destination. The stream overload advances the stream position and leaves it open; an I/O failure may leave
partial output in the stream.

Source filenames and indexed offsets are not used to fetch particle values or position output records.
Reopen the written file with `PhantomFile(filename)` to obtain its new offsets. Use `read_data(file)` to
load raw values beforehand; `write_phantom` does not load source data implicitly.
"""
function write_phantom(io :: Base.IO, file :: PhantomFile{P, B, C}, block_data :: PhantomData{P, B, C}) where {P, B, C}
    _validate_phantom_output(file, block_data)
    position(io) == 0 && eof(io) || throw(ArgumentError("Output stream must be empty and positioned at zero"))
    _write_phantom(io, file, block_data)
    return nothing
end

function write_phantom(filename :: AbstractString, file :: PhantomFile{P, B, C}, block_data :: PhantomData{P, B, C}; overwrite :: Bool = false) where {P, B, C}
    _validate_phantom_output(file, block_data)
    target = abspath(filename)
    isdir(target) && throw(ArgumentError("Output path is a directory"))
    ispath(target) && !overwrite && throw(ArgumentError("Output exists; pass overwrite=true to replace it"))
    temporary, io = mktemp(dirname(target))
    try
        _write_phantom(io, file, block_data)
        close(io)
        mv(temporary, target; force = overwrite)
    finally
        isopen(io) && close(io)
        ispath(temporary) && rm(temporary)
    end
    return nothing
end
