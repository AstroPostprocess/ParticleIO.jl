"""Particle blocks for one partition, sharing the corresponding Info at both levels."""
struct PhantomPartitionData{B}
    blocks   :: NTuple{B, PhantomBlockData}
    metadata :: PhantomPartitionInfo{B}

    function PhantomPartitionData(metadata :: PhantomPartitionInfo{B}, blocks :: NTuple{B, PhantomBlockData}) where {B}
        all(i -> blocks[i].metadata === metadata.blocks[i], 1:B) ||
            throw(ArgumentError("Block data must share the corresponding partition metadata"))
        return new{B}(blocks, metadata)
    end
end
