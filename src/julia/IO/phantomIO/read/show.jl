function _show_header_rows(io :: Base.IO, header :: PhantomHeader;
    index_width :: Int = max(1, ndigits(max(length(header.keys), length(header.group_keys)))))
    for (label, keys, values, color) in (("content", header.keys, header.content, :blue),
                                       ("group_content", header.group_keys, header.group_content, :magenta))
        label == "group_content" && println(io)
        printstyled(io, "  ", label; bold = true, color = color)
        isempty(keys) && print(io, " (empty)")
        for (i, key) in enumerate(keys)
            println(io)
            print(io, "    ", lpad(string(i), index_width), "  ")
            printstyled(io, rpad(strip(key), 16); color = :green)
            print(io, "  ")
            show(io, values[i])
        end
    end
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", header::PhantomHeader)

Display single values and repeated-name tuples in separate sections.
Whitespace padding is removed for display only.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", header :: PhantomHeader{T}) where {T <: _PHANTOM_TYPE}
    printstyled(io, "PhantomHeader{$T}"; bold = true, color = :cyan)
    println(io)
    _show_header_rows(io, header)
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", headers::PhantomHeaders)

Display all eight typed header groups with a fixed 16-character name column and a shared index width.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", headers :: PhantomHeaders{TI, TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    printstyled(io, "PhantomHeaders{$TI, $TF}"; bold = true, color = :cyan)
    index_width = maximum(fieldnames(typeof(headers))) do field
        header = getfield(headers, field)
        max(1, ndigits(max(length(header.keys), length(header.group_keys))))
    end
    for field in fieldnames(typeof(headers))
        header = getfield(headers, field)
        println(io)
        println(io)
        printstyled(io, String(field), " (", string(eltype(header.content)), ")"; bold = true, color = :cyan)
        println(io)
        _show_header_rows(io, header; index_width = index_width)
    end
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", sections::PhantomSectionOffsets)

Display file-level and per-partition absolute byte offsets.
Partition metadata offsets point to the first metadata record, after the single global block-count record.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", sections :: PhantomSectionOffsets)
    printstyled(io, "PhantomSectionOffsets"; bold = true, color = :cyan)
    print(io, " (byte offsets)")
    for field in (:capture_pattern, :file_identifier, :global_header)
        println(io)
        print(io, "  ", rpad(String(field), 16), ": ", getfield(sections, field))
    end
    for (p, offsets) in enumerate(sections.partitions)
        println(io)
        println(io)
        printstyled(io, "  partition $p"; bold = true, color = :cyan)
        for field in fieldnames(PhantomPartitionOffsets)
            println(io)
            print(io, "    ", rpad(String(field), 23), ": ")
            printstyled(io, getfield(offsets, field); color = :yellow)
        end
    end
    return nothing
end

function _show_structure_parameters(io :: Base.IO, P, B, S, R)
    for (label, value) in (("P (partitions)", P), ("B (blocks per partition)", B),
                           ("S (single columns)", S), ("R (column groups)", R))
        println(io)
        print(io, "  ", rpad(label, 24), ": ", value)
    end
    return nothing
end

# Display the two namespaces separately; group indices do not count physical columns.
function _show_block_columns(io :: Base.IO, block :: PhantomBlockInfo, dtypes = nothing; indent :: String = "      ")
    println(io)
    printstyled(io, indent, "columns"; bold = true, color = :blue)
    isempty(block.columns) && print(io, " (empty)")
    for (c, column) in enumerate(block.columns)
        println(io)
        print(io, indent, "  ", rpad(string(c), 6))
        printstyled(io, rpad(strip(column.name), 16); color = :green)
        isnothing(dtypes) || print(io, "  ", dtypes[Int(column.dtype_index)])
    end
    println(io)
    printstyled(io, indent, "column_groups"; bold = true, color = :magenta)
    isempty(block.column_groups) && print(io, " (empty)")
    for (g, group) in enumerate(block.column_groups)
        println(io)
        print(io, indent, "  ", rpad(string(g), 6))
        printstyled(io, rpad(strip(group.name), 16); color = :green)
        print(io, "  ", length(group.dtype_indices), " columns")
        if !isnothing(dtypes)
            for (i, index) in enumerate(group.dtype_indices)
                println(io)
                print(io, indent, "    ", i, " ", dtypes[Int(index)])
            end
        end
    end
    return nothing
end

function _show_partition_blocks(io :: Base.IO, partition :: PhantomPartitionInfo, dtypes = nothing; indent :: String = "  ")
    for (b, block) in enumerate(partition.blocks)
        println(io)
        println(io)
        printstyled(io, indent, "Block $b"; bold = true, color = :yellow)
        print(io, ": ", block.npart, " particles, ", length(block.columns),
            " singles, ", length(block.column_groups), " groups")
        _show_block_columns(io, block, dtypes; indent = indent * "  ")
    end
    return nothing
end

Base.show(io :: Base.IO, partition :: PhantomPartitionInfo{B}) where {B} = print(io, "PhantomPartitionInfo{$B}($B blocks)")

function Base.show(io :: Base.IO, :: MIME"text/plain", partition :: PhantomPartitionInfo{B}) where {B}
    printstyled(io, "PhantomPartitionInfo{$B}"; bold = true, color = :cyan)
    _show_partition_blocks(io, partition)
    B == 0 && print(io, " (no blocks)")
    return nothing
end

function Base.show(io :: Base.IO, file :: PhantomFile{P, B, S, R, TI, TF}) where {P, B, S, R, TI, TF}
    print(io, "PhantomFile{$P, $B, $S, $R, $TI, $TF}(")
    show(io, file.filename)
    print(io, ")")
    return nothing
end

"""Display type parameters and grouped column metadata without loading particle values."""
function Base.show(io :: Base.IO, :: MIME"text/plain", file :: PhantomFile{P, B, S, R, TI, TF}) where {P, B, S, R, TI, TF}
    printstyled(io, "PhantomFile{$P, $B, $S, $R, $TI, $TF}"; bold = true, color = :cyan)
    println(io)
    print(io, "  file: ", file.filename)
    _show_structure_parameters(io, P, B, S, R)
    for (label, value) in (("TI (default integer)", TI), ("TF (default real)", TF))
        println(io)
        print(io, "  ", rpad(label, 24), ": ", value)
    end
    for (p, partition) in enumerate(file.partitions)
        println(io)
        println(io)
        printstyled(io, "  Partition $p"; bold = true, color = :cyan)
        _show_partition_blocks(io, partition, phantom_dtypes(file); indent = "    ")
    end
    return nothing
end

Base.show(io :: Base.IO, data :: PhantomData{P, B, S, R}) where {P, B, S, R} =
    print(io, "PhantomData(P=$P, B=$B, S=$S, R=$R)")

"""Display single/group locations without expanding vectors or repeating the source filename."""
function Base.show(io :: Base.IO, :: MIME"text/plain", data :: PhantomData{P, B, S, R}) where {P, B, S, R}
    printstyled(io, "PhantomData(P=$P, B=$B, S=$S, R=$R)"; bold = true, color = :cyan)
    _show_structure_parameters(io, P, B, S, R)
    for (p, partition) in enumerate(data.partitions)
        println(io)
        println(io)
        printstyled(io, "  Partition $p"; bold = true, color = :cyan)
        _show_partition_blocks(io, partition.metadata; indent = "    ")
    end
    return nothing
end

Base.show(io :: Base.IO, data :: PhantomPartitionData{B}) where {B} = print(io, "PhantomPartitionData{$B}($B blocks)")
Base.show(io :: Base.IO, data :: PhantomBlockData{S, R}) where {S, R} = print(io, "PhantomBlockData{$S, $R}($S singles, $R groups)")

function Base.show(io :: Base.IO, :: MIME"text/plain", data :: PhantomPartitionData{B}) where {B}
    printstyled(io, "PhantomPartitionData{$B}"; bold = true, color = :cyan)
    _show_partition_blocks(io, data.metadata)
    return nothing
end

function Base.show(io :: Base.IO, :: MIME"text/plain", data :: PhantomBlockData{S, R}) where {S, R}
    printstyled(io, "PhantomBlockData{$S, $R}"; bold = true, color = :cyan)
    _show_block_columns(io, data.metadata; indent = "  ")
    return nothing
end
