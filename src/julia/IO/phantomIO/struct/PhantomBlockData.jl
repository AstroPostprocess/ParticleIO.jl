"""
    PhantomBlockData(metadata, columns, column_groups, dtypes)

Particle vectors for one block, sharing its `PhantomBlockInfo`. `dtypes` is the tuple
returned by `phantom_dtypes(file)`. Each repeated-name group is a tuple of vectors;
its members may have different element types. Counts, types, and lengths are checked.
"""
struct PhantomBlockData{S, R}
    columns       :: NTuple{S, Vector}
    column_groups :: NTuple{R, Tuple}
    metadata      :: PhantomBlockInfo{S, R}

    function PhantomBlockData(metadata :: PhantomBlockInfo{S, R}, columns :: NTuple{S, Vector},
        column_groups :: NTuple{R, Tuple}, dtypes :: Tuple) where {S, R}
        for (column, values) in zip(metadata.columns, columns)
            _validate_column_vector(values, column.dtype_index, metadata.npart, dtypes)
        end
        for (group, vectors) in zip(metadata.column_groups, column_groups)
            length(vectors) == length(group.dtype_indices) || throw(DimensionMismatch("Column group size mismatch"))
            for (index, values) in zip(group.dtype_indices, vectors)
                _validate_column_vector(values, index, metadata.npart, dtypes)
            end
        end
        return new{S, R}(columns, column_groups, metadata)
    end
end

function _validate_column_vector(values, dtype_index, npart, dtypes)
    T = dtypes[Int(dtype_index)]
    values isa Vector{T} || throw(ArgumentError("Column requires a Vector{$T}"))
    length(values) == npart || throw(DimensionMismatch("Column length does not match npart"))
    return nothing
end

# Vectors can be resized after construction; writing rechecks their lengths.
function _validate_block_vectors(data :: PhantomBlockData, dtypes)
    info = data.metadata
    for (column, values) in zip(info.columns, data.columns)
        _validate_column_vector(values, column.dtype_index, info.npart, dtypes)
    end
    for (group, vectors) in zip(info.column_groups, data.column_groups)
        for (index, values) in zip(group.dtype_indices, vectors)
            _validate_column_vector(values, index, info.npart, dtypes)
        end
    end
    return nothing
end

_column_vector(data :: PhantomBlockData, location :: Tuple{Int, Int}) =
    location[1] == 0 ? data.columns[location[2]] : data.column_groups[location[1]][location[2]]
