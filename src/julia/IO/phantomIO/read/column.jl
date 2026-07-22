"""
    _read_column!(io::IO, dest::Vector, file::PhantomFile, block_index::Integer, column_index::Integer)

Read one indexed particle column from an open stream into a validated destination.
"""
function _read_column!(io :: IO, dest :: Vector, file :: PhantomFile, block_index :: Integer, column_index :: Integer)
    block = file.blocks[block_index]
    column = block.columns[column_index]
    dtype = phantom_dtypes(file)[Int(column.dtype_index)]

    eltype(dest) === dtype || throw(ArgumentError("Column $(column.name) requires destination element type $dtype, got $(eltype(dest))."))

    # Resize the destination to the particle count declared by the block metadata
    resize!(dest, Int(block.npart))

    # Move the cursor to the leading tag of the column data record
    seek(io, column.data_record_offset)

    # Read and validate the complete column data record
    ## +8 + sizeof(dtype) * block.npart
    _read_fortran_block!(io, dest)

    ## Current offset: column.data_record_offset + 8 + sizeof(dtype) * block.npart
    return dest
end

"""
    read_column!(io::IO, dest::Vector, file::PhantomFile, block_index::Integer, column_index::Integer)
    read_column!(dest::Vector, file::PhantomFile, block_index::Integer, column_index::Integer)

Read one particle column from an indexed Phantom dump file into a preallocated destination.

The method accepting an open `IO` stream leaves ownership of that stream with the caller and is intended for reading
multiple columns without repeatedly opening the file. The convenience method without `IO` opens `file.filename` and
closes it after the requested column has been read.

# Parameters
- `io::IO`: Open and seekable stream associated with `file`.
- `dest::Vector`: Destination with the column's element type. Its length is resized to the block particle count.
- `file::PhantomFile`: Indexed Phantom dump file.
- `block_index::Integer`: Index of the particle block containing the column.
- `column_index::Integer`: Index of the column within the selected particle block.

# Returns
- `dest::Vector`: The resized destination after it has been filled with the column values.

# Examples
## Example 1: Read one column with automatic file opening and closing.
```julia
block = file.blocks[1]
column = block.columns[2]
dtype = phantom_dtypes(file)[Int(column.dtype_index)]
dest = Vector{dtype}()

read_column!(dest, file, 1, 2)
```

## Example 2: Reuse one open stream when reading multiple columns.
```julia
io = open(file.filename, "r")
try
    read_column!(io, x, file, 1, 2)
    read_column!(io, y, file, 1, 3)
finally
    close(io)
end
```

# Notes
`dest` is resized and modified in place. Its element type must match the indexed column metadata.
"""
function read_column!(io :: IO, dest :: Vector, file :: PhantomFile, block_index :: Integer, column_index :: Integer)
    return _read_column!(
        io,
        dest,
        file,
        block_index,
        column_index,
    )
end

function read_column!(dest :: Vector, file :: PhantomFile, block_index :: Integer, column_index :: Integer)
    io = open(file.filename, "r")

    try
        return read_column!(
            io,
            dest,
            file,
            block_index,
            column_index,
        )
    finally
        close(io)
    end
end

"""
    _read_columns!(io::IO, dests::Tuple{Vararg{Vector,N}}, file::PhantomFile, block_index::Int, column_indices::NTuple{N,Int})

Read indexed particle columns into their corresponding destinations in the requested tuple order.
"""
function _read_columns!(io :: IO, dests :: Tuple{Vararg{Vector, N}}, file :: PhantomFile, block_index :: Int, column_indices :: NTuple{N, Int}) where {N}
    for i in eachindex(dests, column_indices)
        _read_column!(io, dests[i], file, block_index, column_indices[i])
    end

    return dests
end

"""
    read_columns!(io::IO, dests::Tuple{Vararg{Vector,N}}, file::PhantomFile, block_index::Int, column_indices::NTuple{N,Int})
    read_columns!(dests::Tuple{Vararg{Vector,N}}, file::PhantomFile, block_index::Int, column_indices::NTuple{N,Int})

Read multiple particle columns from one block into a tuple of preallocated destinations.

Columns are read in the exact order specified by `column_indices`. For every tuple position `i`, values from
`column_indices[i]` are written into `dests[i]`. The method accepting an open `IO` stream leaves ownership of that
stream with the caller, while the convenience method opens and closes `file.filename` automatically.

# Parameters
- `io::IO`: Open and seekable stream associated with `file`.
- `dests::Tuple{Vararg{Vector,N}}`: Destinations for the requested columns. Each vector may have a different element type.
- `file::PhantomFile`: Indexed Phantom dump file.
- `block_index::Int`: Index of the particle block containing the columns.
- `column_indices::NTuple{N,Int}`: Column indices in the order they should be read.

# Returns
- `dests::Tuple{Vararg{Vector,N}}`: The resized destinations after they have been filled in the requested order.

# Examples
```julia
block = file.blocks[1]
x = Float64[]
z = Float64[]

read_columns!((z, x), file, 1, (4, 2))
```

# Notes
The destination and column-index tuples must have the same length `N`. Each destination's element type is validated
independently, and each vector is resized to the particle count of its corresponding block.
"""
function read_columns!(io :: IO, dests :: Tuple{Vararg{Vector, N}}, file :: PhantomFile, block_index :: Int, column_indices :: NTuple{N, Int}) where {N}
    return _read_columns!(io, dests, file, block_index, column_indices)
end

function read_columns!(dests :: Tuple{Vararg{Vector, N}}, file :: PhantomFile, block_index :: Int, column_indices :: NTuple{N, Int}) where {N}
    io = open(file.filename, "r")

    try
        return read_columns!(io, dests, file, block_index, column_indices)
    finally
        close(io)
    end
end

"""
    _read_all_columns(io::IO, file::PhantomFile)

Read every indexed column from an open stream and return one `DataFrame` per physical particle block.
"""
function _read_all_columns(io :: IO, file :: PhantomFile)
    block_data = Vector{DataFrame}(undef, length(file.blocks))

    for block_index in eachindex(file.blocks)
        block = file.blocks[block_index]
        df = DataFrame()

        # Read columns in their original on-disk order
        for column_index in eachindex(block.columns)
            column = block.columns[column_index]
            dtype = phantom_dtypes(file)[Int(column.dtype_index)]
            dest = Vector{dtype}()

            _read_column!(io, dest, file, block_index, column_index)
            df[!, column.name] = dest
        end

        block_data[block_index] = df
    end

    return block_data
end

"""
    read_all_columns(io::IO, file::PhantomFile)
    read_all_columns(file::PhantomFile)

Read all particle columns from an indexed Phantom dump file.

Columns are loaded in their original block and column order. The method accepting an open `IO` stream leaves
ownership of that stream with the caller. The convenience method opens `file.filename` once and closes it after all
columns have been loaded.

# Parameters
- `io::IO`: Open and seekable stream associated with `file`.
- `file::PhantomFile`: Indexed Phantom dump file.

# Returns
- `Vector{DataFrame}`: One data frame for each physical particle block in the file.

# Examples
```julia
file = PhantomFile("test/testinput/testdumpfile_00000")
blocks = read_all_columns(file)
gas = blocks[1]
sinks = blocks[2]
```

# Notes
This function opens the file at most once. Each returned data frame preserves the indexed column order.
"""
function read_all_columns(io :: IO, file :: PhantomFile)
    return _read_all_columns(io, file)
end

function read_all_columns(file :: PhantomFile)
    io = open(file.filename, "r")

    try
        return read_all_columns(io, file)
    finally
        close(io)
    end
end
