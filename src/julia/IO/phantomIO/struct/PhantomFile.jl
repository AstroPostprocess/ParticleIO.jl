"""
    PhantomFile{P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}

Indexed metadata container for a Phantom native binary dump file.

Stores the file identifier, typed global headers, and the ordered partition/block/column
structure together with byte offsets for deferred particle-data access. Particle values
are stored separately in `PhantomData`, loaded through `read_data(file)`.

# Type Parameters
- `P` : Number of partitions in the file. Must be positive.
- `B` : Number of array blocks in each partition.
- `C` : Tuple of column counts per block, shared by all partitions. `length(C) == B`,
  and `C[b]` is the number of columns in block `b`; for example, `(11, 14)` for two blocks.
- `TI <: _PHANTOM_INT_TYPE` : Default integer datatype, either `Int32` or `Int64`.
- `TF <: _PHANTOM_REAL_TYPE` : Default real datatype, either `Float32` or `Float64`.

# Fields
- `filename :: String` : Source path used when loading particle values without an explicit stream.
  Stored as supplied, without conversion to an absolute path.
- `file_identifier :: String` : File identifier. File indexing preserves the full 100-byte payload,
  including whitespace padding.
- `headers :: PhantomHeaders{TI, TF}` : Eight typed global-header groups, preserving raw names,
  repeated entries, and their order within each group.
- `sections :: PhantomSectionOffsets{P}` : Absolute, zero-based byte offsets for the capture pattern,
  file identifier, global header, and each partition's metadata and particle-data sections.
- `partitions :: NTuple{P, PhantomPartition{B}}` : Ordered partitions. Each contains `B` blocks;
  `partitions[p].blocks[b].columns[c]` gives the name, datatype-group index, and data-record offset
  of column `c`. Each block also stores its particle count and eight datatype-group array counts.

# Notes
Partition and block counts are fixed by tuple storage. Column metadata are also tuples;
construction checks their lengths against `C`. Particle counts may differ between partitions.
The struct is immutable, but the vectors inside its header groups remain mutable.

`TI` and `TF` describe only the default datatype groups. Use `phantom_dtypes(file)` together
with a column's `dtype_index` to resolve its actual element type.
"""
struct PhantomFile{P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    filename        :: String
    file_identifier :: String
    headers         :: PhantomHeaders{TI, TF}
    sections        :: PhantomSectionOffsets{P}
    partitions      :: NTuple{P, PhantomPartition{B}}

    function PhantomFile{P, B, C, TI, TF}(filename :: String, identifier :: String, headers :: PhantomHeaders{TI, TF}, sections :: PhantomSectionOffsets{P}, partitions :: NTuple{P, PhantomPartition{B}}) where {P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
        # C describes the column count of each block, in file order.
        C isa Tuple && all(n -> n isa Int && n >= 0, C) || throw(ArgumentError("Column counts must be a tuple of nonnegative Int values"))
        P > 0 || throw(ArgumentError("At least one partition is required"))
        B == length(C) || throw(DimensionMismatch("Block count does not match $C"))
        for partition in partitions
            for (block, count) in zip(partition.blocks, C)
                length(block.columns) == count || throw(DimensionMismatch("Partition column counts do not match $C"))
            end
        end
        return new{P, B, C, TI, TF}(filename, identifier, headers, sections, partitions)
    end
end

"""
    PhantomFile(filename :: String, identifier :: String, headers :: PhantomHeaders{TI, TF}, sections :: PhantomSectionOffsets{P}, partitions :: NTuple{P, PhantomPartition{B}})

Construct a file index from existing metadata without opening or reading a file.

# Parameters
- `filename :: String` : Source path for subsequent particle-data reads.
- `identifier :: String` : File identifier to store.
- `headers :: PhantomHeaders{TI, TF}` : Typed global-header groups.
- `sections :: PhantomSectionOffsets{P}` : Global and per-partition byte offsets.
- `partitions :: NTuple{P, PhantomPartition{B}}` : Ordered block and column metadata.

# Returns
- `PhantomFile{P, B, C, TI, TF}` : Index with `C` inferred from the first partition's column counts.

# Notes
Every partition must have the same per-block column counts. Metadata are retained without
deep copying; this constructor does not verify that offsets or header values describe the source file.
"""
function PhantomFile(filename :: String, identifier :: String, headers :: PhantomHeaders{TI, TF}, sections :: PhantomSectionOffsets{P}, partitions :: NTuple{P, PhantomPartition{B}}) where {P, B, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    P > 0 || throw(ArgumentError("At least one partition is required"))
    counts = Tuple(length(block.columns) for block in first(partitions).blocks)
    return PhantomFile{P, B, counts, TI, TF}(filename, identifier, headers, sections, partitions)
end

"""
    phantom_dtypes(file::PhantomFile)
    phantom_dtypes(::Type{TI}, ::Type{TF})

Return the eight datatypes used by the typed header and particle-array blocks in a Phantom dump file.

The first and sixth entries are the default integer and real datatypes detected from the file capture pattern. The
remaining entries correspond to the explicit-width datatypes defined by the Phantom binary format.

# Parameters
- `file::PhantomFile`: Indexed Phantom file containing the detected default datatypes.
- `TI::Type`: Default integer datatype, either `Int32` or `Int64`.
- `TF::Type`: Default real datatype, either `Float32` or `Float64`.

# Returns
- `Tuple`: Datatypes in the order `(TI, Int8, Int16, Int32, Int64, TF, Float32, Float64)`.

# Notes
The tuple order matches `PhantomBlockInfo.array_counts` and `PhantomColumnInfo.dtype_index`.
"""
@inline phantom_dtypes(:: PhantomFile{P, B, C, TI, TF}) where {P, B, C, TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE} = (
    TI,
    Int8,
    Int16,
    Int32,
    Int64,
    TF,
    Float32,
    Float64,
)

@inline phantom_dtypes(:: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE} = (
    TI,
    Int8,
    Int16,
    Int32,
    Int64,
    TF,
    Float32,
    Float64,
)

"""
    PhantomFile(filename::AbstractString)

Open and index a Phantom native binary dump file without loading its particle-array values.

The constructor validates the capture pattern and Fortran record tags, reads the file identifier and typed global
headers, and records the name, datatype, and data offset of every particle column. The file is closed before the
constructed object is returned.

# Parameters
- `filename::AbstractString`: Path of the Phantom dump file to index.

# Returns
- `PhantomFile{P, B, C, TI, TF}`: Indexed metadata with structure and default datatypes inferred from the file.

# Examples
```julia
file = PhantomFile("test/testinput/testdumpfile_00000")
file.file_identifier
file.partitions[1].blocks[1].columns
data = read_data(file)
data[1, 1, 1]
```

# Notes
Particle-array values are not loaded by this constructor. Each `PhantomColumnInfo.data_record_offset` can be used for
selective or deferred loading.
The global-header parameter `nblocks` supplies `P`; if absent, one partition is assumed.
The total array-block count must be divisible by `P`, and all partitions must agree on `C`.
"""
function PhantomFile(filename :: AbstractString)
    filename_string = String(filename)
    io = open(filename_string, "r")

    try
        # Detect the default integer and real datatypes
        TI, TF = _read_phantom_datatype(io)

        # Continue construction behind a function barrier specialized for TI and TF
        return _build_phantom_file(io, filename_string, TI, TF)
    finally
        close(io)
    end
end

"""
    _build_phantom_file(io::Base.IO, filename::String, ::Type{TI}, ::Type{TF})

Build a `PhantomFile{P,B,C,TI,TF}` after its default datatypes have been detected.
`P` is the partition count, `B` is the block count per partition, and `C` is the tuple
of column counts per block, shared by every partition.
"""
function _build_phantom_file(io :: Base.IO, filename :: String, :: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    # Capture pattern always starts at the beginning of the file
    capture_pattern_offset = Int64(0)

    # The datatype record has already been read by _read_phantom_datatype
    ## Bytes consumed: 8 + 4sizeof(TI) + sizeof(TF)
    ## Current offset: 8 + 4sizeof(TI) + sizeof(TF)

    # Read the 100 character file identifier
    file_identifier_offset = Int64(position(io))
    ## +108
    file_identifier = _read_file_identifier(io, file_identifier_offset)

    # Read the 8 typed global header blocks
    global_header_offset = Int64(position(io))
    header_keys, header_data = _read_global_header(
        io,
        global_header_offset,
        TI,
        TF,
    )

    headers = PhantomHeaders{TI, TF}(
        PhantomHeader{TI}(header_keys[1], header_data[1]),
        PhantomHeader{Int8}(header_keys[2], header_data[2]),
        PhantomHeader{Int16}(header_keys[3], header_data[3]),
        PhantomHeader{Int32}(header_keys[4], header_data[4]),
        PhantomHeader{Int64}(header_keys[5], header_data[5]),
        PhantomHeader{TF}(header_keys[6], header_data[6]),
        PhantomHeader{Float32}(header_keys[7], header_data[7]),
        PhantomHeader{Float64}(header_keys[8], header_data[8]),
    )

    # One total array-block count precedes all partitions.
    buffer = Int32[0]
    _read_fortran_block!(io, buffer)
    total_blocks = Int(buffer[1])
    0 <= total_blocks <= 1_000_000 || throw(ArgumentError("Invalid total array-block count: $total_blocks"))
    npartitions = _phantom_partition_count(headers)
    total_blocks % npartitions == 0 || throw(ArgumentError("Array-block count is not divisible by partition count"))
    blocks_per_partition = div(total_blocks, npartitions)
    return _index_phantom_partitions(io, filename, file_identifier, headers,
        capture_pattern_offset, file_identifier_offset, global_header_offset,
        blocks_per_partition, Val(npartitions))
end

"""
    _phantom_partition_count(headers::PhantomHeaders)

Read the positive integer `nblocks` parameter without changing raw names.
Absent `nblocks` defaults to one partition for legacy single-partition inputs.
Ambiguous or invalid declarations are rejected.
"""
function _phantom_partition_count(headers :: PhantomHeaders)
    values = Any[]
    for field in fieldnames(typeof(headers))
        header = getfield(headers, field)
        for (key, value) in zip(header.keys, header.data)
            strip(key) == "nblocks" && push!(values, value)
        end
    end
    isempty(values) && return 1
    length(values) == 1 || throw(ArgumentError("Ambiguous nblocks header"))
    n = only(values)
    n isa Integer && 1 <= n <= 1_000_000 || throw(ArgumentError("Invalid partition count: $n"))
    return Int(n)
end

function _index_phantom_partitions(io :: Base.IO, filename :: String, identifier :: String,
    headers :: PhantomHeaders{TI, TF}, capture_offset :: Int64, identifier_offset :: Int64,
    header_offset :: Int64, blocks_per_partition :: Int, :: Val{P}) where {TI, TF, P}
    indexed = ntuple(Val(P)) do _
        metadata_offset = Int64(position(io))
        counts, arrays = _read_particle_block_metadata(io, metadata_offset, blocks_per_partition)
        data_offset = Int64(position(io))
        blocks = _read_particle_block_offset(io, data_offset, counts, arrays, TI, TF)
        return PhantomPartition(Tuple(blocks)), PhantomPartitionOffsets(metadata_offset, data_offset)
    end
    partitions = map(first, indexed)
    sections = PhantomSectionOffsets{P}(capture_offset, identifier_offset, header_offset, map(last, indexed))
    return PhantomFile(filename, identifier, headers, sections, partitions)
end
