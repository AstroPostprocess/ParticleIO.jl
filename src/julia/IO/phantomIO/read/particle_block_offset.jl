"""
    _read_particle_block_offset(io::IO, byte_offset, block_particle_counts, block_array_counts, ::Type{TI}, ::Type{TF})

Read column names and record their data offsets while skipping particle values.
"""
@inline function _read_particle_block_offset(io :: IO, byte_offset :: Integer, block_particle_counts :: Vector{Int64}, block_array_counts :: Vector{NTuple{8, Int32}}, :: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    length(block_particle_counts) == length(block_array_counts) || throw(DimensionMismatch("Particle counts and array counts contain different numbers of blocks."))

    # Allocate a reusable buffer for the 16 character column names
    name_buffer = Vector{UInt8}(undef, 16)

    # Move the cursor to the beginning of the particle data
    seek(io, byte_offset)

    # Phantom stores arrays in the same 8 datatype groups as the global header
    dtypes = phantom_dtypes(TI, TF)

    # Collect the column metadata for each particle block
    nblocks = length(block_particle_counts)
    blocks = Vector{PhantomBlockInfo}(undef, nblocks)

    @inbounds for block_index in eachindex(blocks)
        npart = block_particle_counts[block_index]
        npart >= 0 || throw(ArgumentError("Invalid particle count in block $block_index: $npart"))

        array_counts = block_array_counts[block_index]
        all(narray -> narray >= 0, array_counts) || throw(ArgumentError("Invalid array count in block $block_index: $array_counts"))

        # Allocate exactly the number of columns declared by the block metadata
        ncolumns = sum(Int, array_counts)
        columns = Vector{PhantomColumnInfo}(undef, ncolumns)
        column_index = 1

        # Run through all datatype groups in their on-disk order
        for dtype_index in eachindex(dtypes, array_counts)
            dtype = dtypes[dtype_index]
            narray = array_counts[dtype_index]

            for _ in 1:narray
                # Read the 16 character column name record
                ## +24 = 4 byte tag + 16 byte name + 4 byte tag
                _read_fortran_block!(io, name_buffer)
                name = strip(String(copy(name_buffer)))

                # Save the offset of the leading tag for the column data record
                data_record_offset = Int64(position(io))

                # Read the 4 byte leading tag without loading the particle values
                ## +4
                nbytes = read(io, Int32)
                expected_nbytes = Int64(sizeof(dtype)) * npart
                nbytes == expected_nbytes || throw(DimensionMismatch("Column $name in block $block_index should contain $expected_nbytes bytes, got $nbytes."))

                # Skip the particle values
                ## +sizeof(dtype) * npart
                seek(io, position(io) + nbytes)

                # Read the 4 byte trailing tag
                ## +4
                end_nbytes = read(io, Int32)
                nbytes == end_nbytes || throw(ArgumentError("Fortran tags mismatch for column $name in block $block_index: leading tag is $nbytes, trailing tag is $end_nbytes."))

                columns[column_index] = PhantomColumnInfo(
                    name,
                    UInt8(dtype_index),
                    data_record_offset,
                )
                column_index += 1

                ## Bytes consumed per column: 32 + sizeof(dtype) * npart
                ## Current offset: beginning of the next column name record
            end
        end

        blocks[block_index] = PhantomBlockInfo(
            npart,
            array_counts,
            columns,
        )
    end

    ## Bytes consumed:
    ## sum(array_counts[i][j] * (32 + sizeof(dtypes[j]) * block_particle_counts[i])
    ##     for i in eachindex(block_particle_counts), j in eachindex(dtypes))
    ## Current offset: byte_offset + bytes consumed
    return blocks
end
