"""
    PhantomBlockInfo(npart, array_counts, columns, column_groups)

Immutable block metadata. `S` counts single columns; `R` counts repeated-name groups.
Names are compared exactly, including padding. Group members retain their file occurrence order.
"""
struct PhantomBlockInfo{S, R}
    npart         :: Int64
    array_counts  :: NTuple{8, Int32}
    columns       :: NTuple{S, PhantomColumnInfo}
    column_groups :: NTuple{R, PhantomColumnGroupInfo}

    function PhantomBlockInfo(npart :: Integer, array_counts :: NTuple{8, Int32},
        columns :: NTuple{S, PhantomColumnInfo},
        column_groups :: NTuple{R, PhantomColumnGroupInfo}) where {S, R}
        npart >= 0 || throw(ArgumentError("Negative particle count"))
        all(n -> n >= 0, array_counts) || throw(ArgumentError("Negative array count"))
        names = (map(column -> column.name, columns)..., map(group -> group.name, column_groups)...)
        all(i -> all(j -> names[i] != names[j], 1:i-1), eachindex(names)) ||
            throw(ArgumentError("Single column and group names must be unique and disjoint"))
        all(group -> length(group.dtype_indices) >= 2, column_groups) ||
            throw(ArgumentError("A column group must contain at least two columns"))
        actual = zeros(Int64, 8)
        for column in columns
            1 <= column.dtype_index <= 8 || throw(ArgumentError("Invalid column datatype index"))
            actual[Int(column.dtype_index)] += 1
        end
        for group in column_groups, dtype_index in group.dtype_indices
            1 <= dtype_index <= 8 || throw(ArgumentError("Invalid group datatype index"))
            actual[Int(dtype_index)] += 1
        end
        ncolumns = S + sum(group -> length(group.dtype_indices), column_groups; init = 0)
        ncolumns == sum(Int64, array_counts) || throw(DimensionMismatch("Column count does not match block metadata"))
        Tuple(actual) == array_counts || throw(DimensionMismatch("Column datatype counts do not match array_counts"))
        return new{S, R}(npart, array_counts, columns, column_groups)
    end
end

# Group raw tags without renaming them; each list follows first occurrence order.
function _group_column_metadata(columns :: Vector{PhantomColumnInfo})
    singles = PhantomColumnInfo[]
    groups = PhantomColumnGroupInfo[]
    for (i, column) in enumerate(columns)
        any(j -> columns[j].name == column.name, 1:i-1) && continue
        matching = filter(other -> other.name == column.name, columns)
        if length(matching) == 1
            push!(singles, column)
        else
            push!(groups, PhantomColumnGroupInfo(column.name,
                Tuple(other.dtype_index for other in matching),
                Tuple(other.data_record_offset for other in matching)))
        end
    end
    return Tuple(singles), Tuple(groups)
end

# A location is (0, single_index) or (group_index, member_index). It is temporary,
# not stored on metadata. Original offsets restore interleaving across names.
function _column_info(block :: PhantomBlockInfo, location :: Tuple{Int, Int})
    g, i = location
    g == 0 && return block.columns[i]
    group = block.column_groups[g]
    return PhantomColumnInfo(group.name, group.dtype_indices[i], group.data_record_offsets[i])
end

function _physical_column_locations(block :: PhantomBlockInfo)
    locations = Tuple{Int, Int}[(0, i) for i in eachindex(block.columns)]
    for (g, group) in enumerate(block.column_groups), i in eachindex(group.dtype_indices)
        push!(locations, (g, i))
    end
    offsets = map(location -> _column_info(block, location).data_record_offset, locations)
    if all(offset -> offset >= 0, offsets) && allunique(offsets)
        sort!(locations; by = location -> _column_info(block, location).data_record_offset)
    else
        # New metadata: datatype group first, then singles and groups in tuple order.
        sort!(locations; by = location -> _column_info(block, location).dtype_index, alg = Base.Sort.MergeSort)
    end
    issorted(map(location -> _column_info(block, location).dtype_index, locations)) ||
        throw(ArgumentError("Column offsets conflict with Phantom datatype-group order"))
    for g in eachindex(block.column_groups)
        members = [i for (group, i) in locations if group == g]
        issorted(members) || throw(ArgumentError("Column group order conflicts with serialization order"))
    end
    return locations
end
