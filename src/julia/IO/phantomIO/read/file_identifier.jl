"""
    _read_file_identifier(io::Base.IO, byte_offset::Integer)

Read the 100-byte Phantom file identifier record at `byte_offset`.

Return a `String` preserving all payload bytes, including leading and trailing whitespace.
Use `rstrip` on the returned value when a display without trailing padding is desired.
"""
@inline function _read_file_identifier(io :: Base.IO, byte_offset :: Integer)
    # Allocate buffer for data
    buffer = Vector{UInt8}(undef, 0)

    # Move the cursor to the position
    seek(io, byte_offset)

    # Read the 100 byte file identifier
    ## +108
    resize!(buffer, 100)
    _read_fortran_block!(io, buffer)

    # Transfer the buffer into a string without removing whitespace
    file_identifier = String(buffer)

    ## Bytes consumed: 108
    ## Current offset: byte_offset + 108
    return file_identifier
end
