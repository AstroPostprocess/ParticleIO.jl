"""
    allocate_dest(file::PhantomFile, p::Integer, b::Integer)

Allocate empty destination vectors for a specified block in a Phantom binary dump.

The destination contains two tuples: one for single-column vectors and another for
repeated-column groups. Each vector has the element type specified by the file metadata
and is initially empty. No particle data are read.

# Parameters
- `file::PhantomFile`: Indexed Phantom file providing the column structure and datatypes.
- `p::Integer`: One-based partition index.
- `b::Integer`: One-based block index within the selected partition.

# Returns
- `Tuple`: A pair of tuples containing the single-column vectors and repeated-column groups.
"""
function allocate_dest(file :: PhantomFile, p :: Integer, b :: Integer)
    info = file.partitions[p].blocks[b]
    dtypes = phantom_dtypes(file)

    columns = map(info.columns) do column
        Vector{dtypes[Int(column.dtype_index)]}()
    end

    groups = map(info.column_groups) do group
        map(index -> Vector{dtypes[Int(index)]}(), group.dtype_indices)
    end

    return (columns, groups)
end

"""
    allocate_dest(file::PhantomFile{P,B}, p::Integer) where {P,B}

Allocate empty destination vectors for all blocks in a specified Phantom partition.

Each block destination contains separate tuples for single-column vectors and
repeated-column groups. All vectors are initially empty and use the element types
specified by the file metadata. No particle data are read.

# Parameters
- `file::PhantomFile`: Indexed Phantom file providing the block structures and datatypes.
- `p::Integer`: One-based partition index.

# Returns
- `Tuple`: A tuple containing the destination structures of all blocks in the selected partition.
"""
function allocate_dest(file :: PhantomFile{P,B}, p :: Integer) where {P,B}
    return ntuple(b -> allocate_dest(file, p, b), Val(B))
end


"""
    allocate_dest(file::PhantomFile{P}) where {P}

Allocate empty destination vectors for all partitions and blocks in a Phantom binary dump.

The destination consists of nested tuples containing single-column vectors and
repeated-column groups. Each vector has the element type specified by the file
metadata and is initially empty. No particle data are read.

# Parameters
- `file::PhantomFile`: Indexed Phantom file providing the partition, block, and column structures.

# Returns
- `Tuple`: Nested destination tuples containing empty vectors for all particle columns.
"""
function allocate_dest(file :: PhantomFile{P}) where {P}
    return ntuple(p -> allocate_dest(file, p), Val(P))
end


"""
    read_column!(io::Base.IO, dest::Vector, file::PhantomFile, p::Integer, b::Integer, c::Integer)
    read_column!(dest::Vector, file::PhantomFile, p::Integer, b::Integer, c::Integer)
    read_column!(io::Base.IO, dest::Vector, file::PhantomFile{1}, b::Integer, c::Integer)
    read_column!(dest::Vector, file::PhantomFile{1}, b::Integer, c::Integer)

Read a single particle column from a Phantom binary dump into an existing vector.

The column is selected by its physical order within the block, including single columns
and members of repeated-name groups. The destination element type must match the
column datatype, while its length is automatically adjusted to the particle count
specified by the file metadata.

When an input stream is provided, the function reads from that stream and leaves it open.
Otherwise, the source file is opened and closed automatically. The partition index can
be omitted for files containing exactly one partition.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `dest::Vector`: Destination vector for the column data.
- `file::PhantomFile`: Indexed Phantom file providing the column metadata and byte offsets.
- `p::Integer`: One-based partition index.
- `b::Integer`: One-based block index within the selected partition.
- `c::Integer`: One-based physical column index within the selected block.

# Returns
- `Vector`: The resized and populated destination vector `dest`.
"""
function read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile, p :: Integer, b :: Integer, c :: Integer)
    block = file.partitions[p].blocks[b]
    location = _physical_column_locations(block)[c]
    column = _column_info(block, location)

    T = phantom_dtypes(file)[Int(column.dtype_index)]
    eltype(dest) === T || throw(ArgumentError("Column $(column.name) requires Vector{$T}"))
    block.npart >= 0 || throw(ArgumentError("Negative particle count"))
    column.data_record_offset >= 0 || throw(ArgumentError("Column has no readable source offset"))

    return _read_column!(io, dest, column.data_record_offset, block.npart)
end

# Read a binary column using previously validated metadata.
@inline function _read_column!(io :: Base.IO, dest :: Vector, offset :: Int64, npart :: Int64)
    resize!(dest, Int(npart))
    seek(io, offset)
    _read_fortran_block!(io, dest)
    return dest
end

function read_column!(dest :: Vector, file :: PhantomFile, p :: Integer, b :: Integer, c :: Integer)
    open(file.filename, "r") do io
        read_column!(io, dest, file, p, b, c)
    end
end

# Convenience methods for single-partition files.
read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) = read_column!(io, dest, file, 1, b, c)
read_column!(dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) = read_column!(dest, file, 1, b, c)


"""
    read_columns!(io::Base.IO, dests::NTuple{K,Vector}, file::PhantomFile, p::Integer, b::Integer, indices::NTuple{K,Int}) where {K}
    read_columns!(dests::NTuple{K,Vector}, file::PhantomFile, p::Integer, b::Integer, indices::NTuple{K,Int}) where {K}
    read_columns!(io::Base.IO, dests::NTuple{K,Vector}, file::PhantomFile{1}, b::Integer, indices::NTuple{K,Int}) where {K}
    read_columns!(dests::NTuple{K,Vector}, file::PhantomFile{1}, b::Integer, indices::NTuple{K,Int}) where {K}

Read multiple selected particle columns from a Phantom binary dump into existing vectors.

Columns are selected by their physical indices and read in the order specified by
`indices`. The destination structure and element types are validated before reading.
Each vector is resized to match the particle count specified by the file metadata,
regardless of its initial length.

Each destination vector should be distinct. An I/O error may leave previously
processed vectors modified.

When an input stream is provided, the function reads from that stream and leaves it open.
Otherwise, the source file is opened and closed automatically. The partition index can
be omitted for files containing exactly one partition.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `dests::NTuple{K,Vector}`: Destination vectors corresponding to the selected columns.
- `file::PhantomFile`: Indexed Phantom file providing the column metadata and byte offsets.
- `p::Integer`: One-based partition index.
- `b::Integer`: One-based block index within the selected partition.
- `indices::NTuple{K,Int}`: One-based physical column indices specifying the columns to read.

# Returns
- `NTuple{K,Vector}`: The destination tuple `dests`, containing the resized and populated vectors.
"""
function read_columns!(io :: Base.IO, dests :: NTuple{K,Vector}, file :: PhantomFile, p :: Integer, b :: Integer, indices :: NTuple{K,Int}) where {K}
    block = file.partitions[p].blocks[b]
    locations = _physical_column_locations(block)
    columns = map(i -> _column_info(block, locations[i]), indices)
    dtypes = phantom_dtypes(file)

    # Validate all destinations before reading.
    block.npart >= 0 || throw(ArgumentError("Negative particle count"))

    for (column, values) in zip(columns, dests)
        T = dtypes[Int(column.dtype_index)]
        eltype(values) === T || throw(ArgumentError("Column $(column.name) requires Vector{$T}"))
        column.data_record_offset >= 0 || throw(ArgumentError("Column $(column.name) has no readable source offset"))
    end

    # Read selected columns.
    for (column, values) in zip(columns, dests)
        _read_column!(io, values, column.data_record_offset, block.npart)
    end

    return dests
end

function read_columns!(dests :: NTuple{K,Vector}, file :: PhantomFile, p :: Integer, b :: Integer, indices :: NTuple{K,Int}) where {K}
    open(file.filename, "r") do io
        read_columns!(io, dests, file, p, b, indices)
    end
end

# Convenience methods for single-partition files.
read_columns!(io :: Base.IO, dests :: NTuple{K,Vector}, file :: PhantomFile{1}, b :: Integer, indices :: NTuple{K,Int}) where {K} = read_columns!(io, dests, file, 1, b, indices)
read_columns!(dests :: NTuple{K,Vector}, file :: PhantomFile{1}, b :: Integer, indices :: NTuple{K,Int}) where {K} = read_columns!(dests, file, 1, b, indices)


"""
    read_block!(io::Base.IO, dests::Tuple{NTuple{N,Vector},NTuple{M,Tuple}}, file::PhantomFile, p::Integer, b::Integer) where {N,M}

Read all particle columns from a specified Phantom block into existing destination vectors.

The destination consists of two tuples containing single-column vectors and repeated-column
groups, respectively. Its structure, element types, and column offsets are validated
against the file metadata before reading. Each vector is resized to match the particle
count specified by the file, regardless of its initial length.

The function returns a `PhantomBlockData` containing the populated destination vectors
and their corresponding metadata without copying the particle data. The input stream
remains open.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `dests::Tuple{NTuple{N,Vector},NTuple{M,Tuple}}`: Destination containing `N` single-column vectors and `M` repeated-column groups.
- `file::PhantomFile`: Indexed Phantom file providing the block structure, datatypes, particle count, and byte offsets.
- `p::Integer`: One-based partition index.
- `b::Integer`: One-based block index within the selected partition.

# Returns
- `PhantomBlockData{N,M}`: Populated block data sharing the destination vectors and corresponding metadata.
"""
function read_block!(io :: Base.IO, dests :: Tuple{NTuple{N,Vector},NTuple{M,Tuple}}, file :: PhantomFile, p :: Integer, b :: Integer) where {N,M}
    info = file.partitions[p].blocks[b]
    dtypes = phantom_dtypes(file)
    columns, groups = dests

    # Validate the block structure.
    N == length(info.columns) || throw(DimensionMismatch("Single-column count mismatch"))
    M == length(info.column_groups) || throw(DimensionMismatch("Column-group count mismatch"))
    info.npart >= 0 || throw(ArgumentError("Negative particle count"))

    # Validate single-column destinations.
    for (column, values) in zip(info.columns, columns)
        T = dtypes[Int(column.dtype_index)]
        eltype(values) === T || throw(ArgumentError("Column $(column.name) requires Vector{$T}"))
        column.data_record_offset >= 0 || throw(ArgumentError("Column $(column.name) has no readable source offset"))
    end

    # Validate repeated-column destinations.
    for (group, vectors) in zip(info.column_groups, groups)
        length(vectors) == length(group.dtype_indices) || throw(DimensionMismatch("Column group $(group.name) size mismatch"))

        for (values, dtype_index, offset) in zip(vectors, group.dtype_indices, group.data_record_offsets)
            values isa Vector || throw(ArgumentError("Column group $(group.name) requires Vector destinations"))

            T = dtypes[Int(dtype_index)]
            eltype(values) === T || throw(ArgumentError("Column group $(group.name) requires Vector{$T}"))
            offset >= 0 || throw(ArgumentError("Column group $(group.name) has no readable source offset"))
        end
    end

    # Read single columns.
    for (column, values) in zip(info.columns, columns)
        _read_column!(io, values, column.data_record_offset, info.npart)
    end

    # Read repeated columns.
    for (group, vectors) in zip(info.column_groups, groups)
        for (values, offset) in zip(vectors, group.data_record_offsets)
            _read_column!(io, values, offset, info.npart)
        end
    end

    return PhantomBlockData(info, columns, groups, dtypes)
end


"""
    read_block(io::Base.IO, file::PhantomFile, p::Integer, b::Integer)
    read_block(file::PhantomFile, p::Integer, b::Integer)

Allocate and read all particle columns from a specified block in a Phantom binary dump.

Destination vectors are allocated using `allocate_dest` according to the column structure
and datatypes specified by the file metadata, then populated using `read_block!`.
The resulting `PhantomBlockData` contains the particle vectors and their corresponding
metadata without additional copies.

When an input stream is provided, the function reads from that stream and leaves it open.
Otherwise, the source file is opened and closed automatically.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `file::PhantomFile`: Indexed Phantom file providing the block structure, datatypes, particle count, and byte offsets.
- `p::Integer`: One-based partition index.
- `b::Integer`: One-based block index within the selected partition.

# Returns
- `PhantomBlockData`: The allocated and populated block data with its corresponding metadata.
"""
function read_block(io :: Base.IO, file :: PhantomFile, p :: Integer, b :: Integer)
    dests = allocate_dest(file, p, b)
    return read_block!(io, dests, file, p, b)
end

function read_block(file :: PhantomFile, p :: Integer, b :: Integer)
    open(file.filename, "r") do io
        read_block(io, file, p, b)
    end
end


"""
    read_partition!(io::Base.IO, dests::NTuple{B,Tuple}, file::PhantomFile{P,B}, p::Integer) where {P,B}

Read all particle blocks from a specified Phantom partition into existing destination vectors.

Each destination contains two tuples of single-column vectors and repeated-column groups,
respectively. The number of block destinations is matched to the file by method dispatch,
while their internal structures and element types are validated by `read_block!`.
Destination vectors are resized to match the corresponding particle counts.

The function returns a `PhantomPartitionData` containing the populated block data and
their corresponding metadata without copying the particle arrays. The input stream
remains open. An error during reading may leave previously processed blocks modified.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `dests::NTuple{B,Tuple}`: Tuple of destination structures for the `B` blocks, matched by dispatch.
- `file::PhantomFile`: Indexed Phantom file providing the partition structure, datatypes, particle counts, and byte offsets.
- `p::Integer`: One-based partition index.

# Returns
- `PhantomPartitionData{B}`: Populated partition data containing the block data and corresponding metadata.
"""
function read_partition!(io :: Base.IO, dests :: NTuple{B,Tuple}, file :: PhantomFile{P,B}, p :: Integer) where {P,B}
    info = file.partitions[p]

    blocks = ntuple(Val(B)) do b
        read_block!(io, dests[b], file, p, b)
    end

    return PhantomPartitionData(info, blocks)
end

"""
    read_partition(io::Base.IO, file::PhantomFile, p::Integer)
    read_partition(file::PhantomFile, p::Integer)

Allocate and read all particle blocks from a specified partition in a Phantom binary dump.

Destination vectors are allocated using `allocate_dest` according to the block structures
and datatypes specified by the file metadata, then populated using `read_partition!`.
The resulting `PhantomPartitionData` contains the particle vectors and their corresponding
metadata without additional copies.

When an input stream is provided, the function reads from that stream and leaves it open.
Otherwise, the source file is opened and closed automatically.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `file::PhantomFile`: Indexed Phantom file providing the partition structure, datatypes, particle counts, and byte offsets.
- `p::Integer`: One-based partition index.

# Returns
- `PhantomPartitionData`: The allocated and populated partition data with its corresponding metadata.
"""
function read_partition(io :: Base.IO, file :: PhantomFile, p :: Integer)
    dests = allocate_dest(file, p)
    return read_partition!(io, dests, file, p)
end

function read_partition(file :: PhantomFile, p :: Integer)
    open(file.filename, "r") do io
        read_partition(io, file, p)
    end
end


"""
    read_data!(io::Base.IO, dests::NTuple{P,Tuple}, file::PhantomFile{P}) where {P}
    read_data!(dests::NTuple{P,Tuple}, file::PhantomFile{P}) where {P}

Read all particle data from a Phantom binary dump into existing destination vectors.

The destination consists of nested tuples corresponding to the partitions, blocks,
single columns, and repeated-column groups defined by the file metadata.
Partition counts are matched by method dispatch; remaining destination structures
and element types are validated by the corresponding readers. Each vector is resized to match the particle count
specified by the file, regardless of its initial length.

The function returns a `PhantomData` containing the populated destination vectors
and their corresponding metadata without copying the particle data.

When an input stream is provided, the function reads from that stream and leaves it
open. Otherwise, the source file is opened and closed automatically. An error during
reading may leave previously processed destination vectors modified.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `dests::NTuple{P,Tuple}`: Nested destination tuples containing the particle vectors for all `P` partitions.
- `file::PhantomFile`: Indexed Phantom file providing the complete data structure, datatypes, particle counts, and byte offsets.

# Returns
- `PhantomData`: Populated particle data sharing the destination vectors and corresponding file metadata.
"""
function read_data!(io :: Base.IO, dests :: NTuple{P,Tuple}, file :: PhantomFile{P}) where {P}
    partitions = ntuple(Val(P)) do p
        read_partition!(io, dests[p], file, p)
    end

    return PhantomData(file, partitions)
end

function read_data!(dests :: NTuple{P,Tuple}, file :: PhantomFile{P}) where {P}
    open(file.filename, "r") do io
        read_data!(io, dests, file)
    end
end


"""
    read_data(io::Base.IO, file::PhantomFile)
    read_data(file::PhantomFile)

Allocate and read all particle data from a Phantom binary dump.

Destination vectors are allocated using `allocate_dest` according to the partition,
block, and column structures specified by the file metadata, then populated using
`read_data!`. The resulting `PhantomData` contains the particle vectors and their
corresponding metadata without additional copies.

When an input stream is provided, the function reads from that stream and leaves it
open. Otherwise, the source file is opened and closed automatically.

# Parameters
- `io::Base.IO`: Input stream containing the Phantom binary dump.
- `file::PhantomFile`: Indexed Phantom file providing the complete data structure, datatypes, particle counts, and byte offsets.

# Returns
- `PhantomData`: The allocated and populated particle data with its corresponding metadata.
"""
function read_data(io :: Base.IO, file :: PhantomFile)
    dests = allocate_dest(file)
    return read_data!(io, dests, file)
end

function read_data(file :: PhantomFile)
    open(file.filename, "r") do io
        read_data(io, file)
    end
end