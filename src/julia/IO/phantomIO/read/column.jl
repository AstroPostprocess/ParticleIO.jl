"""
    read_column!(io::Base.IO, dest::Vector, file::PhantomFile, partition_index, block_index, column_index)
    read_column!(dest::Vector, file::PhantomFile, partition_index, block_index, column_index)

Read one indexed column into `dest`, resized to the selected block's particle count.
`column_index` is the physical on-disk index across singles and repeated groups, reconstructed from offsets.
The destination element type must exactly match the indexed datatype. All indices are one-based.
The stream overload changes its position and leaves it open; otherwise the source is opened and closed automatically.
For single-partition files only, the partition index may be omitted.
"""
function read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile,
    partition_index :: Integer, block_index :: Integer, column_index :: Integer)
    block = file.partitions[partition_index].blocks[block_index]
    location = _physical_column_locations(block)[column_index]
    column = _column_info(block, location)
    return read_column!(io, dest, column, block.npart, phantom_dtypes(file))
end

# Shared binary core for singles, repeated groups, and physical-column selection.
function read_column!(io :: Base.IO, dest :: Vector, column :: PhantomColumnInfo, npart :: Integer, dtypes :: Tuple)
    T = dtypes[Int(column.dtype_index)]
    eltype(dest) === T || throw(ArgumentError("Column $(column.name) requires destination element type $T"))
    npart >= 0 || throw(ArgumentError("Negative particle count"))
    column.data_record_offset >= 0 || throw(ArgumentError("Column has no readable source offset"))
    resize!(dest, Int(npart))
    seek(io, column.data_record_offset)
    _read_fortran_block!(io, dest)
    return dest
end

function read_column!(dest :: Vector, file :: PhantomFile, p :: Integer, b :: Integer, c :: Integer)
    open(file.filename, "r") do io
        read_column!(io, dest, file, p, b, c)
    end
end

# Unambiguous convenience methods for files with exactly one partition.
read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) =
    read_column!(io, dest, file, 1, b, c)
read_column!(dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) =
    read_column!(dest, file, 1, b, c)

# Retain the internal entry point for existing low-level callers.
_read_column!(args...) = read_column!(args...)

"""
    read_columns!(io::Base.IO, dests::Tuple, file::PhantomFile, partition_index, block_index, column_indices::Tuple)
    read_columns!(dests::Tuple, file::PhantomFile, partition_index, block_index, column_indices::Tuple)

Read selected columns from one partition and block in the requested order.
Each destination must have the exact column element type; tuples must have equal lengths.
Use distinct destination vectors. A later failure may leave earlier destinations modified.
The partition index may be omitted only for a single-partition file.
"""
function read_columns!(io :: Base.IO, dests :: Tuple{Vararg{Vector, K}}, file :: PhantomFile,
    p :: Integer, b :: Integer, indices :: NTuple{K, Int}) where {K}
    for i in eachindex(dests, indices)
        read_column!(io, dests[i], file, p, b, indices[i])
    end
    return dests
end

function read_columns!(dests :: Tuple{Vararg{Vector, K}}, file :: PhantomFile,
    p :: Integer, b :: Integer, indices :: NTuple{K, Int}) where {K}
    open(file.filename, "r") do io
        read_columns!(io, dests, file, p, b, indices)
    end
end

read_columns!(io :: Base.IO, dests :: Tuple, file :: PhantomFile{1}, b :: Integer, indices :: Tuple) =
    read_columns!(io, dests, file, 1, b, indices)
read_columns!(dests :: Tuple, file :: PhantomFile{1}, b :: Integer, indices :: Tuple) =
    read_columns!(dests, file, 1, b, indices)

"""
    allocate_data(file::PhantomFile)

Allocate uninitialized particle vectors and share metadata at every level. No file is opened.
Use `read_data!(io, data)` or `read_data!(data)` to fill the vectors without replacing them.
"""
function allocate_data(file :: PhantomFile{P, B}) where {P, B}
    dtypes = phantom_dtypes(file)
    partitions = ntuple(Val(P)) do p
        info = file.partitions[p]
        blocks = map(info.blocks) do block
            columns = map(column -> Vector{dtypes[Int(column.dtype_index)]}(undef, block.npart), block.columns)
            groups = map(block.column_groups) do group
                map(index -> Vector{dtypes[Int(index)]}(undef, block.npart), group.dtype_indices)
            end
            PhantomBlockData(block, columns, groups, dtypes)
        end
        PhantomPartitionData(info, blocks)
    end
    return PhantomData(file, partitions)
end

"""
    read_block!(io, dest::PhantomBlockData, metadata::PhantomBlockInfo, dtypes)
    read_block!(io, dest::PhantomBlockData, file::PhantomFile)

Fill a block's single and repeated vectors using `read_column!`. Counts match by dispatch;
metadata must be the shared source object. Vectors are resized in place and the stream stays open.
Supply distinct destination vectors for distinct columns.
"""
function read_block!(io :: Base.IO, dest :: PhantomBlockData{S, R}, info :: PhantomBlockInfo{S, R}, dtypes :: Tuple) where {S, R}
    dest.metadata === info || throw(ArgumentError("Destination block metadata does not match source"))
    for (column, values) in zip(info.columns, dest.columns)
        read_column!(io, values, column, info.npart, dtypes)
    end
    for (g, group) in enumerate(info.column_groups), i in eachindex(group.dtype_indices)
        column = PhantomColumnInfo(group.name, group.dtype_indices[i], group.data_record_offsets[i])
        read_column!(io, dest.column_groups[g][i], column, info.npart, dtypes)
    end
    return dest
end

function read_block!(io :: Base.IO, dest :: PhantomBlockData, file :: PhantomFile)
    any(partition -> any(block -> block === dest.metadata, partition.blocks), file.partitions) ||
        throw(ArgumentError("Destination block does not belong to this file"))
    return read_block!(io, dest, dest.metadata, phantom_dtypes(file))
end

"""
    read_partition!(io, dest::PhantomPartitionData, metadata::PhantomPartitionInfo, dtypes)
    read_partition!(io, dest::PhantomPartitionData, file::PhantomFile)

Fill a partition's blocks, reusing their vectors and requiring shared source metadata.
"""
function read_partition!(io :: Base.IO, dest :: PhantomPartitionData{B}, info :: PhantomPartitionInfo{B}, dtypes :: Tuple) where {B}
    dest.metadata === info || throw(ArgumentError("Destination partition metadata does not match source"))
    for (block, metadata) in zip(dest.blocks, info.blocks)
        read_block!(io, block, metadata, dtypes)
    end
    return dest
end

function read_partition!(io :: Base.IO, dest :: PhantomPartitionData, file :: PhantomFile)
    any(info -> info === dest.metadata, file.partitions) || throw(ArgumentError("Destination partition does not belong to this file"))
    return read_partition!(io, dest, dest.metadata, phantom_dtypes(file))
end

"""
    read_data!(io::Base.IO, dest::PhantomData)
    read_data!(dest::PhantomData)

Fill all preallocated vectors using the shared `dest.metadata` file index. Vectors are resized,
not replaced. The stream overload leaves `io` open; the other opens and closes the indexed source.
The stream must contain the dump described by the metadata, including its record offsets.
"""
function read_data!(io :: Base.IO, dest :: PhantomData{P, B, S, R}, file :: PhantomFile{P, B, S, R}) where {P, B, S, R}
    dest.metadata === file || throw(ArgumentError("Destination file metadata does not match source"))
    dtypes = phantom_dtypes(file)
    for (partition, info) in zip(dest.partitions, file.partitions)
        read_partition!(io, partition, info, dtypes)
    end
    return dest
end

read_data!(io :: Base.IO, dest :: PhantomData) = read_data!(io, dest, dest.metadata)

function read_data!(dest :: PhantomData)
    open(dest.metadata.filename, "r") do io
        read_data!(io, dest)
    end
end

"""
    read_data(io::Base.IO, file::PhantomFile)
    read_data(file::PhantomFile)

Allocate and read all raw particle columns. Returns `PhantomData` sharing the original metadata.
Singles are in `data.partitions[p].blocks[b].columns`; repeated tags are in `.column_groups`.
No columns are renamed, filtered, merged, or deduplicated. The stream overload leaves `io` open.
"""
read_data(io :: Base.IO, file :: PhantomFile) = read_data!(io, allocate_data(file))

function read_data(file :: PhantomFile)
    open(file.filename, "r") do io
        read_data(io, file)
    end
end
