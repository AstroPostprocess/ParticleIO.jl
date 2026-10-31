"""
    _write_column(io::Base.IO, column::PhantomColumnInfo, content::AbstractVector)

Write a 16-byte name record followed by a particle-value record at the current position.
Preserve existing name padding; pad shorter names with spaces. The source data_record_offset is ignored.
The enclosing writer validates content against the block's datatype and particle count.
"""
@inline function _write_column(io :: Base.IO, column :: PhantomColumnInfo, content :: V) where {T <: _PHANTOM_TYPE, V <: AbstractVector{T}}
    nbytes = ncodeunits(column.name)
    nbytes <= 16 || throw(ArgumentError("Column name exceeds 16 bytes"))
    length(content) <= div(typemax(Int32), sizeof(T)) ||
        throw(ArgumentError("Column record exceeds the Int32 byte-count limit"))

    buffer = fill(UInt8(' '), 16)
    copyto!(buffer, 1, codeunits(column.name), 1, nbytes)
    _write_fortran_block(io, buffer)
    _write_fortran_block(io, content)

    ## Bytes consumed: 32 + sizeof(content)
    return nothing
end
