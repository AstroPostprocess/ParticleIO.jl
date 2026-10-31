"""Immutable block metadata. Column and array counts are checked once at construction."""
struct PhantomBlockInfo
    npart        :: Int64
    array_counts :: NTuple{8, Int32}
    columns      :: Tuple{Vararg{PhantomColumnInfo}}

    function PhantomBlockInfo(npart :: Integer, array_counts :: NTuple{8, Int32}, columns :: Tuple{Vararg{PhantomColumnInfo}})
        npart >= 0 || throw(ArgumentError("Negative particle count"))
        all(n -> n >= 0, array_counts) || throw(ArgumentError("Negative array count"))
        length(columns) == sum(Int64, array_counts) || throw(DimensionMismatch("Column count does not match block metadata"))
        return new(npart, array_counts, columns)
    end
end
