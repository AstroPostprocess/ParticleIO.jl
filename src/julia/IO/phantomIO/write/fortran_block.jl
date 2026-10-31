@inline function _write_fortran_block(io :: Base.IO, content :: V) where {T <: _PHANTOM_WRITE_TYPE, V <: AbstractVector{T}}
    nbytes = sizeof(content)
    nbytes <= typemax(Int32) || throw(ArgumentError("Record exceeds the Int32 byte-count limit"))

    # 4 byte Fortran tag
    tag = Int32(nbytes)

    ## +4
    write(io, tag)
    ## +sizeof(content)
    write(io, content)
    ## +4
    write(io, tag)

    ## Bytes consumed: 8 + sizeof(content)
    return nothing
end
