"""
    _read_fortran_block!(io::IO, buffer::AbstractVector)

Read one Fortran record into `buffer` and validate its leading and trailing byte-count tags.
"""
@inline function _read_fortran_block!(io :: IO, buffer :: V) where {V <: AbstractVector}
    # 4 byte Fortran tag
    ## +4
    nbytes = read(io, Int32)
    nbytes == sizeof(buffer) || throw(DimensionMismatch("Fortran block size mismatch: expected $(sizeof(buffer)) bytes, got $nbytes."))

    # Read data
    ## +sizeof(buffer)
    read!(io, buffer)

    # 4 byte Fortran tag
    ## +4
    end_nbytes = read(io, Int32)

    nbytes == end_nbytes || throw(ArgumentError("Fortran tags mismatch: leading tag is $nbytes, trailing tag is $end_nbytes."))

    ## Bytes consumed: 8 + sizeof(buffer)
    return nothing
end
