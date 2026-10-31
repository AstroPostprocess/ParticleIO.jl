"""One MPI partition's fixed-size tuple of array blocks. Offsets are in `file.sections.partitions`."""
struct PhantomPartition{B}
    blocks :: NTuple{B, PhantomBlockInfo}
end

