struct PhantomBlockInfo
    npart        :: Int64
    array_counts :: NTuple{8, Int32}
    columns      :: Vector{PhantomColumnInfo}
end
