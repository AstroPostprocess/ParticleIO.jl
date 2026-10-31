"""
    _rename_duplicates!(keys::Vector{String})

Rename duplicate header keys in place by appending their occurrence number.
"""
function _rename_duplicates!(keys :: Vector{String})
    counts = Dict{String, Int}()

    for key in keys
        counts[key] = get(counts, key, 0) + 1
    end

    occurrences = Dict{String, Int}()

    for i in eachindex(keys)
        key = keys[i]

        if counts[key] > 1
            n = get(occurrences, key, 0) + 1
            occurrences[key] = n
            keys[i] = "$(key)_$(n)"
        end
    end

    return nothing
end

"""
    _read_global_header_block!(io::IO, buffers, ::Type{T})

Read one typed Phantom global-header block and return its keys and values.
"""
@inline function _read_global_header_block!(io :: IO, buffers :: NTuple{2, Vector{UInt8}}, :: Type{T}) where {T <: _PHANTOM_TYPE}
    # Allocate buffer for the variable count
    buffer = MVector{4, UInt8}(undef)
    buffer_keys = buffers[1]
    buffer_data = buffers[2]

    # Read number of variable
    ## +12
    _read_fortran_block!(io, buffer)
    nvars_raw = reinterpret(reshape, Int32, buffer)[]
    0 <= nvars_raw <= 1_000_000 || throw(ArgumentError("Invalid header variable count: $nvars_raw"))
    nvars = Int(nvars_raw)

    # Collect key and data in header
    keys = Vector{String}(undef, nvars)
    data = Vector{T}(undef, nvars)
    if nvars > 0
        # each tag is 16 characters in length
        # Keys
        resize!(buffer_keys, 16 * nvars)
        ## + 8 + 16 * nvars
        _read_fortran_block!(io, buffer_keys)

        # data
        resize!(buffer_data, sizeof(T) * nvars)
        ## + 8 + sizeof(T) * nvars
        _read_fortran_block!(io, buffer_data)

        # fill in values
        @inbounds for j in eachindex(keys)
            i = 16(j - 1) + 1
            keys[j] = strip(String(@view buffer_keys[i:i+15]))
        end
        copyto!(data, reinterpret(T, buffer_data))
    end

    ## Bytes consumed:
    ## - nvars == 0: 12
    ## - nvars > 0: 28 + (16 + sizeof(T)) * nvars
    return keys, data
end

"""
    _read_global_header(io::IO, byte_offset::Integer, ::Type{TI}, ::Type{TF})

Read all eight typed Phantom global-header blocks beginning at `byte_offset`.
"""
@inline function _read_global_header(io :: IO, byte_offset :: Integer, :: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    # Allocate buffers for keys and data
    buffers = ntuple(_ -> Vector{UInt8}(undef, 0), 2)

    # Move the cursor to the position
    seek(io, byte_offset)

    # Phantom has 8 blocks for headers
    dtypes = (TI, Int8, Int16, Int32, Int64, TF, Float32, Float64)

    # Run through all data types
    blocks = map(dtypes) do dtype
        keys, data = _read_global_header_block!(io, buffers, dtype)
        _rename_duplicates!(keys)
        return keys, data
    end
    dtypes_keys = map(first, blocks)
    dtypes_data = map(last, blocks)

    ## Bytes consumed:
    ## sum(12 + (nvars[i] > 0 ? 16 + (16 + sizeof(dtypes[i])) * nvars[i] : 0)
    ##     for i in eachindex(dtypes))
    ## Current offset: byte_offset + bytes consumed
    return dtypes_keys, dtypes_data
end
