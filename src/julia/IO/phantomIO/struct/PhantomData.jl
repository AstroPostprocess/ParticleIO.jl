"""
    PhantomData(file::PhantomFile, partitions::Tuple)
    PhantomData(file::PhantomFile)

Hierarchical particle data sharing the original file, partition, and block metadata.
Access singles through `data.partitions[p].blocks[b].columns[c]`, and repeated columns
through `.column_groups[g][i]`. `S` and `R` are per-block tuples of single/group counts.
The one-argument constructor delegates to `read_data(file)`. Use `allocate_dest(file)`
to create empty destination vectors, which can be populated repeatedly through
`read_data!(dests, file)`.
"""
struct PhantomData{P, B, S, R, F <: PhantomFile{P, B, S, R}}
    partitions :: NTuple{P, PhantomPartitionData{B}}
    metadata   :: F

    function PhantomData(file :: F, partitions :: NTuple{P, PhantomPartitionData{B}}) where {P, B, S, R, F <: PhantomFile{P, B, S, R}}
        dtypes = phantom_dtypes(file)
        for (partition, info) in zip(partitions, file.partitions)
            partition.metadata === info || throw(ArgumentError("Partition data must share the corresponding file metadata"))
            for block in partition.blocks
                _validate_block_vectors(block, dtypes)
            end
        end
        return new{P, B, S, R, F}(partitions, file)
    end
end

PhantomData(file :: PhantomFile) = read_data(file)
