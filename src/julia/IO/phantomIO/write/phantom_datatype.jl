"""
    _write_capture_pattern(io::Base.IO, ::Type{TI}, ::Type{TF})

Write the capture pattern for the specified default datatypes, using format version 1.
Record markers are Int32 regardless of TI. Values use native byte order, matching the reader.
"""
@inline function _write_capture_pattern(io :: Base.IO, :: Type{TI}, :: Type{TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    tag = Int32(4sizeof(TI) + sizeof(TF))

    # Mixed-type capture pattern enclosed by 4 byte Fortran tags
    write(io, tag)
    write(io, TI(60769))
    write(io, TF(60878))
    write(io, TI(60878))
    write(io, TI(1))
    write(io, TI(690706))
    write(io, tag)

    ## Bytes consumed: 8 + 4sizeof(TI) + sizeof(TF)
    return nothing
end
