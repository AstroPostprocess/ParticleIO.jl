"""
    read_column!(io::Base.IO, dest::Vector, file::PhantomFile, partition_index, block_index, column_index)
    read_column!(dest::Vector, file::PhantomFile, partition_index, block_index, column_index)

Read one indexed column into `dest`, resized to the selected block's particle count.
The destination element type must exactly match the indexed datatype. All indices are one-based.
The stream overload changes its position and leaves it open; otherwise the source is opened and closed automatically.
For single-partition files only, the partition index may be omitted.
"""
function read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile,
    partition_index :: Integer, block_index :: Integer, column_index :: Integer)
    block = file.partitions[partition_index].blocks[block_index]
    column = block.columns[column_index]
    T = phantom_dtypes(file)[Int(column.dtype_index)]
    eltype(dest) === T || throw(ArgumentError("Column $(column.name) requires destination element type $T"))
    resize!(dest, Int(block.npart))
    seek(io, column.data_record_offset)
    _read_fortran_block!(io, dest)
    return dest
end

function read_column!(dest :: Vector, file :: PhantomFile, p :: Integer, b :: Integer, c :: Integer)
    open(file.filename, "r") do io
        read_column!(io, dest, file, p, b, c)
    end
end

# Unambiguous convenience methods for files with exactly one partition.
read_column!(io :: Base.IO, dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) =
    read_column!(io, dest, file, 1, b, c)
read_column!(dest :: Vector, file :: PhantomFile{1}, b :: Integer, c :: Integer) =
    read_column!(dest, file, 1, b, c)

# Retain the internal entry point for existing low-level callers.
_read_column!(args...) = read_column!(args...)

"""
    read_columns!(io::Base.IO, dests::Tuple, file::PhantomFile, partition_index, block_index, column_indices::Tuple)
    read_columns!(dests::Tuple, file::PhantomFile, partition_index, block_index, column_indices::Tuple)

Read selected columns from one partition and block in the requested order.
Each destination must have the exact column element type; tuples must have equal lengths.
Use distinct destination vectors. A later failure may leave earlier destinations modified.
The partition index may be omitted only for a single-partition file.
"""
function read_columns!(io :: Base.IO, dests :: Tuple{Vararg{Vector, K}}, file :: PhantomFile,
    p :: Integer, b :: Integer, indices :: NTuple{K, Int}) where {K}
    for i in eachindex(dests, indices)
        read_column!(io, dests[i], file, p, b, indices[i])
    end
    return dests
end

function read_columns!(dests :: Tuple{Vararg{Vector, K}}, file :: PhantomFile,
    p :: Integer, b :: Integer, indices :: NTuple{K, Int}) where {K}
    open(file.filename, "r") do io
        read_columns!(io, dests, file, p, b, indices)
    end
end

read_columns!(io :: Base.IO, dests :: Tuple, file :: PhantomFile{1}, b :: Integer, indices :: Tuple) =
    read_columns!(io, dests, file, 1, b, indices)
read_columns!(dests :: Tuple, file :: PhantomFile{1}, b :: Integer, indices :: Tuple) =
    read_columns!(dests, file, 1, b, indices)

"""
    read_data(io::Base.IO, file::PhantomFile{P,B,C})
    read_data(file::PhantomFile)

Read all indexed particle columns into raw vectors, preserving partition, block, and column order.

# Parameters
- `io::Base.IO`: Readable, seekable stream containing the indexed dump. Column offsets are absolute;
  the initial stream position does not matter. The stream is left open.
- `file::PhantomFile{P,B,C}`: Indexed metadata specifying partition and block structure, column datatypes,
  particle counts, and record offsets. Without `io`, `file.filename` is opened and closed automatically.

# Returns
- `PhantomData{P,B,C}`: Nested tuples of vectors, indexed as `data[p][b][c]`. Each vector has the exact
  indexed element type and contains all particles in that block. Single-partition files keep all three levels.

# Examples
```julia
file = PhantomFile("dumpfile_00000")
data = read_data(file)
column = data[1][1][1]
write_phantom("copy_00000", file, data)
```

# Notes
No DataFrames are created, and no particles or columns are filtered, merged, or deduplicated.
Original names are stored in `data.column_names[p][b][c]`, including whitespace padding and duplicates.
Names are not used as keys, so repeated names retain separate vectors.
The stream position advances as records are read. Every column is newly allocated; input metadata is unchanged.
"""
function read_data(io :: Base.IO, file :: PhantomFile{P, B, C}) where {P, B, C}
    dtypes = phantom_dtypes(file)
    partitions = ntuple(Val(P)) do p
        ntuple(Val(B)) do b
            ntuple(C[b]) do c
                column = file.partitions[p].blocks[b].columns[c]
                T = dtypes[Int(column.dtype_index)]
                read_column!(io, T[], file, p, b, c)
            end
        end
    end
    return PhantomData(file, partitions)
end

function read_data(file :: PhantomFile)
    open(file.filename, "r") do io
        read_data(io, file)
    end
end
