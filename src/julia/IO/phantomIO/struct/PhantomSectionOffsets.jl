struct PhantomSectionOffsets{N}
    capture_pattern         :: Int64
    file_identifier         :: Int64
    global_header           :: Int64
    partitions              :: NTuple{N, PhantomPartitionOffsets}
end
