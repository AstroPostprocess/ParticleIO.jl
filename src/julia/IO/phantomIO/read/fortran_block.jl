"""
    _read_fortran_block!(io::Base.IO, buffer::AbstractVector)

Read one Fortran record into `buffer` and validate its leading and trailing byte-count tags.

The buffer must already have the required size; it is not resized. Tags are read as `Int32` and their byte count
must equal `sizeof(buffer)`. The buffer is modified in place and the function returns `nothing`.
"""
@inline function _read_fortran_block!(io :: Base.IO, buffer :: V) where {V <: AbstractVector}
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
