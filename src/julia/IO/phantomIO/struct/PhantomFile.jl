struct PhantomFile{TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    filename        :: String
    file_identifier :: String
    headers         :: PhantomHeaders{TI, TF}
    sections        :: PhantomSectionOffsets
    blocks          :: Vector{PhantomBlockInfo}
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
@inline phantom_dtypes(:: PhantomFile{TI, TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE} = (
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
- `PhantomFile`: File metadata, typed headers, section offsets, particle-block information, and column offsets.

# Examples
```julia
file = PhantomFile("test/testinput/testdumpfile_00000")
file.file_identifier
file.blocks[1].columns
```

# Notes
Particle-array values are not loaded by this constructor. Each `PhantomColumnInfo.data_record_offset` can be used for
selective or deferred loading.
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
    _build_phantom_file(io::IO, filename::String, ::Type{TI}, ::Type{TF})

Build a `PhantomFile{TI,TF}` after its default datatypes have been detected.
"""
function _build_phantom_file(io :: IO, filename :: String, :: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
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

    # Read the number of blocks, particle counts, and datatype array counts
    particle_block_metadata_offset = Int64(position(io))
    ## +12 + 48nblocks
    block_particle_counts, block_array_counts =
        _read_particle_block_metadata(io, particle_block_metadata_offset)

    # Read column names and index their data records without loading values
    particle_data_offset = Int64(position(io))
    blocks = _read_particle_block_offset(
        io,
        particle_data_offset,
        block_particle_counts,
        block_array_counts,
        TI,
        TF,
    )

    # Store the absolute byte offset of each top-level file section
    sections = PhantomSectionOffsets(
        capture_pattern_offset,
        file_identifier_offset,
        global_header_offset,
        particle_block_metadata_offset,
        particle_data_offset,
    )

    ## Particle arrays are indexed but not loaded into memory
    return PhantomFile{TI, TF}(
        filename,
        file_identifier,
        headers,
        sections,
        blocks,
    )
end
