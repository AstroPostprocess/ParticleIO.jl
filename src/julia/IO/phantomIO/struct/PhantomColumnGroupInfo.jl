"""One repeated raw tag, with per-member datatype indices and record offsets in occurrence order."""
struct PhantomColumnGroupInfo{N}
    name                :: String
    dtype_indices       :: NTuple{N,UInt8}
    data_record_offsets :: NTuple{N,Int64}

end