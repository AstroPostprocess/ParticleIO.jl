"""Absolute byte offsets of one partition's block metadata and particle data."""
struct PhantomPartitionOffsets
    particle_block_metadata :: Int64
    particle_data           :: Int64
end
