"""
    _read_file_identifier(io::IO, byte_offset::Integer)

Read the 100-character Phantom file identifier record at `byte_offset`.
"""
@inline function _read_file_identifier(io :: IO, byte_offset :: Integer)
    # Allocate buffer for data
    buffer = Vector{UInt8}(undef, 0)

    # Move the cursor to the position
    seek(io, byte_offset)

    # Read the 100 character file identifier
    ## +108
    resize!(buffer, 100)
    _read_fortran_block!(io, buffer)

    # Note that buffer will be transferred into string, so no GC will kick in.
    file_identifier = strip(String(buffer))

    ## Bytes consumed: 108
    ## Current offset: byte_offset + 108
    return file_identifier
end
