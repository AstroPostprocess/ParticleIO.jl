function _validate_header_block(header :: PhantomHeader{T}) where {T}
    length(header.keys) == length(header.content) || throw(DimensionMismatch("Header keys and content must have equal lengths"))
    length(header.group_keys) == length(header.group_content) == length(header.group_lengths) ||
        throw(DimensionMismatch("Header group fields must have equal lengths"))
    for (values, n) in zip(header.group_content, header.group_lengths)
        length(values) == n && n >= 2 || throw(DimensionMismatch("Invalid header group length"))
        all(value -> value isa T, values) || throw(ArgumentError("Header group values must have type $T"))
    end
    names = vcat(header.keys, header.group_keys)
    allunique(names) || throw(ArgumentError("Header single and group names must be unique and disjoint"))
    nvars = length(header.content) + sum(header.group_lengths)
    nvars <= 1_000_000 || throw(ArgumentError("Invalid header variable count: $nvars"))

    # Validate all names before modifying the stream
    for key in names
        ncodeunits(key) <= 16 || throw(ArgumentError("Header name exceeds 16 bytes: $key"))
    end
    return nothing
end

"""
    _write_global_header_block(io::Base.IO, header::PhantomHeader{T})

Write one typed global-header block at the current stream position and return `nothing`.
Write an `Int32` variable-count record, followed by name and value records only when the count is nonzero.
Singles are written first, followed by groups in member order. Raw names are padded to 16 bytes.
Validate counts, group types and name widths before writing.
"""
@inline function _write_global_header_block(io :: Base.IO, header :: PhantomHeader{T}) where {T <: _PHANTOM_TYPE}
    _validate_header_block(header)
    nvars = length(header.content) + sum(header.group_lengths)

    # Allocate fixed-width names padded with spaces
    buffer_keys = fill(UInt8(' '), 16 * nvars)
    buffer_data = Vector{T}(undef, nvars)
    for (j, (key, value)) in enumerate(_header_entries(header))
        buffer_data[j] = value
        key_bytes = codeunits(key)
        i = 16(j - 1) + 1
        copyto!(buffer_keys, i, key_bytes, 1, length(key_bytes))
    end

    # Write number of variables
    ## +12
    _write_fortran_block(io, Int32[nvars])

    if nvars > 0
        # Write names
        ## +8 + 16 * nvars
        _write_fortran_block(io, buffer_keys)

        # Write typed values
        ## +8 + sizeof(T) * nvars
        _write_fortran_block(io, buffer_data)
    end

    ## Bytes consumed:
    ## - nvars == 0: 12
    ## - nvars > 0: 28 + (16 + sizeof(T)) * nvars
    return nothing
end

"""
    _write_global_header(io::Base.IO, headers::PhantomHeaders)

Write all eight typed header groups in format order at the current stream position.
Validate all groups before writing. Empty groups still receive a zero-count record.
"""
function _write_global_header(io :: Base.IO, headers :: PhantomHeaders)
    for field in fieldnames(typeof(headers))
        _validate_header_block(getfield(headers, field))
    end
    for field in fieldnames(typeof(headers))
        _write_global_header_block(io, getfield(headers, field))
    end
    return nothing
end
