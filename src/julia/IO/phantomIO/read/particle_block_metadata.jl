"""
    _read_particle_block_metadata(io::IO, byte_offset::Integer)

Read particle counts and per-datatype array counts for every particle block.
"""
@inline function _read_particle_block_metadata(io :: IO, byte_offset :: Integer)
    # Allocate buffers for data
    buffer = MVector{4, UInt8}(undef)

    # Move the cursor to the position
    seek(io, byte_offset)

    # Read number of particle blocks
    ## +12
    _read_fortran_block!(io, buffer)
    nblocks_raw = reinterpret(reshape, Int32, buffer)[]
    0 <= nblocks_raw <= 1_000_000 || throw(ArgumentError("Invalid particle block count: $nblocks_raw"))
    nblocks = Int(nblocks_raw)

    # Read the array header for each blocks
    block_particle_counts = zeros(Int64, nblocks)
    block_array_counts = Vector{NTuple{8, Int32}}(undef, nblocks)

    # Run through all blocks
    # Each block should have 40 bytes
    expected_nbytes = sizeof(Int64) + 8sizeof(Int32)
    @inbounds for i in eachindex(block_particle_counts, block_array_counts)
        # 4 byte Fortran tag
        ## +4
        nbytes = read(io, Int32)
        nbytes == expected_nbytes || throw(DimensionMismatch("Expected $expected_nbytes-byte block metadata, got $nbytes"))

        # Read number of particles
        ## +8
        block_particle_counts[i] = read(io, Int64)

        # Read number of arrays for each datatype
        ## +32
        block_array_counts[i] = ntuple(_ -> read(io, Int32), Val(8))

        # 4 byte Fortran tag
        ## +4
        end_nbytes = read(io, Int32)

        nbytes == end_nbytes || throw(ArgumentError("Fortran tags mismatch: leading tag is $nbytes, trailing tag is $end_nbytes."))
    end

    ## Bytes consumed: 12 + 48nblocks
    ## Current offset: byte_offset + 12 + 48nblocks
    return block_particle_counts, block_array_counts
end
