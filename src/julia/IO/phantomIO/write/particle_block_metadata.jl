"""
    _write_particle_block_metadata(io::Base.IO, blocks::Union{Tuple{Vararg{PhantomBlockInfo}}, AbstractVector{PhantomBlockInfo}})

Write one partition's metadata records at the current position.
The enclosing file writer emits the global total array-block count once.
Each metadata payload contains an Int64 particle count and eight Int32 array counts.
"""
@inline function _write_particle_block_metadata(io :: Base.IO, blocks :: Union{Tuple{Vararg{PhantomBlockInfo}}, AbstractVector{PhantomBlockInfo}})
    length(blocks) <= 1_000_000 || throw(ArgumentError("Too many particle blocks"))
    for block in blocks
        # Mixed-type payload: 8 + 8 * 4 = 40 bytes
        tag = Int32(40)
        write(io, tag)
        write(io, block.npart)
        for count in block.array_counts
            write(io, count)
        end
        write(io, tag)
    end

    ## Bytes consumed: 48length(blocks)
    return nothing
end
