@inline function _write_file_identifier(io :: Base.IO, byte_offset :: Integer, content :: String)
    # Encode the file identifier as bytes
    content_bytes = codeunits(content)
    nbytes = length(content_bytes)
    nbytes <= 100 || throw(ArgumentError("File identifier exceeds 100 bytes"))

    # Allocate a 100 byte buffer padded with spaces
    buffer = fill(UInt8(' '), 100)
    copyto!(buffer, 1, content_bytes, 1, nbytes)

    # Move the cursor to the position
    seek(io, byte_offset)

    # Write the 100 byte file identifier
    ## +108
    _write_fortran_block(io, buffer)

    ## Bytes consumed: 108
    ## Current offset: byte_offset + 108
    return nothing
end
