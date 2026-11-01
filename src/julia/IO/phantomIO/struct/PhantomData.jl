"""
    PhantomData(file::PhantomFile, data::Tuple)
    PhantomData(file::PhantomFile)

Raw particle vectors accessed as `data[p, b, c]` or `data[p][b][c]`.
`data` stores the vectors; `metadata` shares `file.partitions` directly, including
column names, padding, and duplicates. Names are accessed through
`data.metadata[p].blocks[b].columns[c].name`.

`P`, `B`, and `C` match the file structure; `T` is the concrete vector-tuple storage type.
The two-argument constructor checks structure without copying vectors or metadata.
The one-argument constructor delegates to `read_data(file)`.
"""
struct PhantomData{P, B, C, T <: Tuple}
    data       :: T
    metadata   :: NTuple{P, PhantomPartition{B}}

    function PhantomData(file :: PhantomFile{P, B, C}, data :: T) where {P, B, C, T <: Tuple}
        length(data) == P || throw(DimensionMismatch("Partition count does not match file metadata"))
        for partition in data
            partition isa Tuple || throw(ArgumentError("Partition blocks must be a tuple"))
            length(partition) == B || throw(DimensionMismatch("Block count does not match file metadata"))
            for (columns, count) in zip(partition, C)
                columns isa Tuple || throw(ArgumentError("Block columns must be a tuple"))
                length(columns) == count || throw(DimensionMismatch("Column count does not match file metadata"))
                all(column -> column isa AbstractVector{<:_PHANTOM_TYPE}, columns) ||
                    throw(ArgumentError("Columns must be numeric vectors of supported Phantom datatypes"))
            end
        end
        return new{P, B, C, T}(data, file.partitions)
    end
end

Base.getindex(data :: PhantomData, p :: Integer) = data.data[p]
Base.getindex(data :: PhantomData, p :: Integer, b :: Integer, c :: Integer) = data.data[p][b][c]
Base.length(data :: PhantomData) = length(data.data)
Base.iterate(data :: PhantomData, state...) = iterate(data.data, state...)

PhantomData(file :: PhantomFile) = read_data(file)
