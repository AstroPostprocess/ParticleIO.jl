"""
    PhantomData(partitions::Tuple, column_names::Tuple)
    PhantomData(file::PhantomFile, partitions::Tuple)
    PhantomData(file::PhantomFile)

Raw particle columns, indexed as `data[p][b][c]` or `data[p, b, c]`. Both return the same vector.
All three collections are tuples;
the leaves are numeric vectors whose values and lengths remain mutable.
The tuple structure determines `P`, `B`, and `C`; callers cannot supply these parameters.
Every partition must have the same block and column counts. `T` preserves the concrete
nested storage type, including each vector's element type. `S` preserves the name tuple type.
`data.column_names[p][b][c]` stores the corresponding String, including original padding and
repeated names. Names are positional metadata, not unique lookup keys.

The file constructor delegates to `read_data(file)` to load every raw column without filtering or merging.
The two-argument file constructor copies names from metadata without loading particle values.
Writing requires a `PhantomFile` with matching `P`, `B`, and `C`; output names still come from that file.

```julia
file = PhantomFile("input.dump")
data = read_data(file)
write_phantom("copy.dump", file, data)

# Or supply tuple collections of existing vectors, without copying their values:
data = PhantomData((((x, y, z), (sink_mass,)),), ((("x", "y", "z"), ("m",)),))
```
"""
struct PhantomData{P, B, C, T <: Tuple, S <: Tuple}
    partitions   :: T
    column_names :: S

    function PhantomData(partitions :: T, column_names :: S) where {T <: Tuple, S <: Tuple}
        P = length(partitions)
        P > 0 || throw(ArgumentError("At least one partition is required"))
        for partition in partitions
            partition isa Tuple || throw(ArgumentError("Partition blocks must be a tuple"))
            for columns in partition
                columns isa Tuple || throw(ArgumentError("Block columns must be a tuple"))
                all(column -> column isa AbstractVector{<:_PHANTOM_TYPE}, columns) ||
                    throw(ArgumentError("Columns must be numeric vectors of supported Phantom datatypes"))
            end
        end
        B = length(first(partitions))
        C = map(length, first(partitions))
        all(partition -> map(length, partition) == C, partitions) || throw(DimensionMismatch("Partitions must have matching block and column counts"))
        length(column_names) == P || throw(DimensionMismatch("Column names must match the partition count"))
        for names in column_names
            names isa Tuple || throw(ArgumentError("Partition column names must be a tuple"))
            length(names) == B || throw(DimensionMismatch("Column names must match the block count"))
            for (block_names, count) in zip(names, C)
                block_names isa Tuple{Vararg{String}} || throw(ArgumentError("Block column names must be a tuple of Strings"))
                length(block_names) == count || throw(DimensionMismatch("Column names must match the column count"))
            end
        end
        return new{P, B, C, T, S}(partitions, column_names)
    end
end

Base.getindex(data :: PhantomData, p :: Integer) = data.partitions[p]
Base.getindex(data :: PhantomData, p :: Integer, b :: Integer, c :: Integer) = data.partitions[p][b][c]
Base.length(data :: PhantomData) = length(data.partitions)
Base.iterate(data :: PhantomData, state...) = iterate(data.partitions, state...)

PhantomData(file :: PhantomFile) = read_data(file)

function PhantomData(file :: PhantomFile, partitions :: Tuple)
    column_names = map(file.partitions) do partition
        map(partition.blocks) do block
            map(column -> column.name, block.columns)
        end
    end
    return PhantomData(partitions, column_names)
end
