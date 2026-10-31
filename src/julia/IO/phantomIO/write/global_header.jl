function _validate_header_block(header :: PhantomHeader)
    nvars = length(header.data)
    length(header.keys) == nvars || throw(DimensionMismatch("Header keys and data must have equal lengths"))
    nvars <= 1_000_000 || throw(ArgumentError("Invalid header variable count: $nvars"))

    # Validate all names before modifying the stream
    for key in header.keys
        ncodeunits(key) <= 16 || throw(ArgumentError("Header name exceeds 16 bytes: $key"))
    end
    return nothing
end

"""
    _write_global_header_block(io::Base.IO, header::PhantomHeader{T})

Write one typed global-header block at the current stream position and return `nothing`.
Write an `Int32` variable-count record, followed by name and value records only when the count is nonzero.
Each name occupies 16 bytes, padded with spaces. Names come directly from `header.keys`,
which retains original names and duplicates; no lookup-name conversion is applied.

Validate matching vector lengths, the reader's 1,000,000-variable limit, and name byte lengths before writing.
Names read from a file retain their original 16-byte payload, including whitespace.
"""
@inline function _write_global_header_block(io :: Base.IO, header :: PhantomHeader{T}) where {T <: _PHANTOM_TYPE}
    _validate_header_block(header)
    nvars = length(header.data)

    # Allocate fixed-width names padded with spaces
    buffer_keys = fill(UInt8(' '), 16 * nvars)
    for j in eachindex(header.keys)
        key_bytes = codeunits(header.keys[j])
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
        _write_fortran_block(io, header.data)
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
