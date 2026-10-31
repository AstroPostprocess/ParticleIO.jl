"""Print a compact structural summary without displaying particle vectors."""
function Base.show(io :: Base.IO, data :: PhantomData{P, B, C}) where {P, B, C}
    print(io, "PhantomData(P=$P, B=$B, C=$C)")
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", data::PhantomData)

Display column indices and names grouped by partition and block, without expanding vectors.
Names are stripped only for display; duplicate names retain separate rows.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", data :: PhantomData{P, B, C}) where {P, B, C}
    printstyled(io, "PhantomData(P=$P, B=$B, C=$C)"; bold = true, color = :cyan)
    for (label, value) in (("P (partitions)", P), ("B (blocks per partition)", B), ("C (columns per block)", C))
        println(io)
        print(io, "  ", rpad(label, 24), ": ", value)
    end
    for (p, partition_names) in enumerate(data.column_names)
        println(io)
        println(io)
        printstyled(io, "  Partition $p"; bold = true, color = :cyan)
        if isempty(partition_names)
            println(io)
            print(io, "    (no blocks)")
        end
        for (b, names) in enumerate(partition_names)
            println(io)
            println(io)
            println(io, "    Block $b: ", length(names), " columns")
            if isempty(names)
                print(io, "      (no columns)")
                continue
            end
            printstyled(io, "      ", rpad("column_index", 14), "name"; bold = true)
            for (c, name) in enumerate(names)
                println(io)
                print(io, "      ", rpad(string(c), 14))
                printstyled(io, strip(name); color = :green)
            end
        end
    end
    return nothing
end

function _show_header_rows(io :: Base.IO, header :: PhantomHeader;
    index_width :: Int = max(1, ndigits(max(length(header.keys), length(header.data)))))
    if isempty(header.keys) && isempty(header.data)
        print(io, "  (empty)")
        return nothing
    end

    name_width = 16
    printstyled(io, "  ", lpad("#", index_width), "  ", rpad("name", name_width), "  value"; bold = true)
    # Keep original order and duplicate names; strip padding only for display.
    for i in 1:max(length(header.keys), length(header.data))
        println(io)
        name = i <= length(header.keys) ? strip(header.keys[i]) : ""
        print(io, "  ", lpad(string(i), index_width), "  ")
        printstyled(io, rpad(name, name_width); color = :green)
        print(io, "  ")
        if i <= length(header.data)
            show(io, header.data[i])
        else
            print(io, "(missing value)")
        end
    end
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", header::PhantomHeader)

Display header names and values side by side in their original order.
Whitespace padding is removed for display only; repeated names remain separate rows.
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
        max(1, ndigits(max(length(header.keys), length(header.data))))
    end
    for field in fieldnames(typeof(headers))
        header = getfield(headers, field)
        println(io)
        println(io)
        printstyled(io, String(field), " (", string(eltype(header.data)), ")"; bold = true, color = :cyan)
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

"""Print a compact summary of a partitioned Phantom file index."""
function Base.show(io :: Base.IO, file :: PhantomFile{P, B, C, TI, TF}) where {P, B, C, TI, TF}
    print(io, "PhantomFile{$P, $B, $C, $TI, $TF}(")
    show(io, file.filename)
    print(io, ", partitions=$P, blocks_per_partition=$B, columns_per_block=$C, default_integer=$TI, default_real=$TF)")
    return nothing
end

function _show_partition_blocks(io :: Base.IO, partition :: PhantomPartition, dtypes = nothing; indent :: String = "  ")
    for (b, block) in enumerate(partition.blocks)
        println(io)
        println(io)
        println(io, indent, "Block $b: ", block.npart, " particles, ", length(block.columns), " columns")
        if isempty(block.columns)
            print(io, indent, "  (no columns)")
            continue
        end
        name_width = max(4, maximum(column -> textwidth(strip(column.name)), block.columns)) + 2
        printstyled(io, indent, "  ", rpad("column_index", 14),
            isnothing(dtypes) ? "name" : rpad("name", name_width) * "datatype"; bold = true)
        for (c, column) in enumerate(block.columns)
            println(io)
            print(io, indent, "  ", rpad(string(c), 14))
            printstyled(io, isnothing(dtypes) ? strip(column.name) : rpad(strip(column.name), name_width); color = :green)
            isnothing(dtypes) || print(io, dtypes[Int(column.dtype_index)])
        end
    end
    return nothing
end

"""Print a compact summary without expanding a partition's column metadata."""
function Base.show(io :: Base.IO, partition :: PhantomPartition{B}) where {B}
    counts = map(block -> length(block.columns), partition.blocks)
    print(io, "PhantomPartition{$B}(blocks=$B, columns_per_block=$counts)")
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", partition::PhantomPartition)

Display the block count, particle counts, and indexed columns in one partition.
Column rows show only their index and name; datatypes are shown in the parent file's display.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", partition :: PhantomPartition{B}) where {B}
    printstyled(io, "PhantomPartition{$B}"; bold = true, color = :cyan)
    println(io)
    print(io, "  B (blocks): ", B)
    if B == 0
        println(io)
        print(io, "  (no blocks)")
    else
        _show_partition_blocks(io, partition)
    end
    return nothing
end

"""
    Base.show(io::Base.IO, ::MIME"text/plain", file::PhantomFile)

Explain all five type parameters, then display indexed columns grouped by partition and block.
Particle values are not loaded.
"""
function Base.show(io :: Base.IO, :: MIME"text/plain", file :: PhantomFile{P, B, C, TI, TF}) where {P, B, C, TI, TF}
    printstyled(io, "PhantomFile{$P, $B, $C, $TI, $TF}"; bold = true, color = :cyan)
    println(io)
    print(io, "  file: ", file.filename)
    for (label, value) in (("P (partitions)", P), ("B (blocks per partition)", B),
                           ("C (columns per block)", C), ("TI (default integer)", TI), ("TF (default real)", TF))
        println(io)
        print(io, "  ", rpad(label, 24), ": ", value)
    end
    dtypes = phantom_dtypes(file)
    for (p, partition) in enumerate(file.partitions)
        println(io)
        println(io)
        printstyled(io, "  Partition $p"; bold = true, color = :cyan)
        _show_partition_blocks(io, partition, dtypes; indent = "    ")
    end
    println(io)
    println(io)
    print(io, "  read_column!(dest, file, partition_index, block_index, column_index)")
    return nothing
end
