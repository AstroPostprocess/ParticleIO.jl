const _PHANTOM_INT_TYPE = Union{Int32, Int64}
const _PHANTOM_REAL_TYPE = Union{Float32, Float64}
const _PHANTOM_TYPE = Union{Int8, Int16, Int32, Int64, Float32, Float64}
const _PHANTOM_WRITE_TYPE = Union{Int8, Int16, Int32, Int64, Float32, Float64, UInt8}

"""
Typed header singles (`keys`, `content`) and repeated names (`group_keys`, `group_content`).
`group_lengths` stores each tuple's length. Raw names and group member order are preserved;
writing emits singles first, then groups, without retaining their original interleaving.
"""
struct PhantomHeader{T <: _PHANTOM_TYPE}
    keys          :: Vector{String}
    content       :: Vector{T}
    group_keys    :: Vector{String}
    group_content :: Vector{Tuple}
    group_lengths :: Vector{Int}
end

# Split temporary reader vectors by exact raw name, preserving first-occurrence order.
function PhantomHeader{T}(keys :: Vector{String}, values :: Vector{T}) where {T <: _PHANTOM_TYPE}
    length(keys) == length(values) || throw(DimensionMismatch("Header keys and values must have equal lengths"))
    single_keys = String[]
    content = T[]
    group_keys = String[]
    group_content = Tuple[]
    group_lengths = Int[]
    for (i, key) in enumerate(keys)
        any(==(key), @view keys[1:i-1]) && continue
        indices = findall(==(key), keys)
        if length(indices) == 1
            push!(single_keys, key)
            push!(content, values[i])
        else
            push!(group_keys, key)
            push!(group_content, Tuple(values[j] for j in indices))
            push!(group_lengths, length(indices))
        end
    end
    return PhantomHeader{T}(single_keys, content, group_keys, group_content, group_lengths)
end

# Serialize singles first, then each group in member order.
function _header_entries(header :: PhantomHeader)
    singles = zip(header.keys, header.content)
    groups = ((key, value) for (key, values) in zip(header.group_keys, header.group_content) for value in values)
    return Iterators.flatten((singles, groups))
end

struct PhantomHeaders{TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    default_integer :: PhantomHeader{TI}
    int8            :: PhantomHeader{Int8}
    int16           :: PhantomHeader{Int16}
    int32           :: PhantomHeader{Int32}
    int64           :: PhantomHeader{Int64}
    default_real    :: PhantomHeader{TF}
    float32         :: PhantomHeader{Float32}
    float64         :: PhantomHeader{Float64}
end
