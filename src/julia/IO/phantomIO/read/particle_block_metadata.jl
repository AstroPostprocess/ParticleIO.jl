"""
    _read_particle_block_metadata(io::Base.IO, byte_offset::Integer, nblocks::Integer)

Read metadata for one partition with `nblocks` array blocks.
The global total-count record is consumed separately by the file constructor.
"""
@inline function _read_particle_block_metadata(io :: Base.IO, byte_offset :: Integer, nblocks :: Integer)
    0 <= nblocks <= 1_000_000 || throw(ArgumentError("Invalid array-block count: $nblocks"))
    seek(io, byte_offset)

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

    ## Bytes consumed: 48nblocks
    ## Current offset: byte_offset + 48nblocks
    return block_particle_counts, block_array_counts
end
