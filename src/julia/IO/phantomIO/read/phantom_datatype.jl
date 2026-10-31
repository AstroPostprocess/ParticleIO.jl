"""
    _read_phantom_datatype(io::IO)

Validate the Phantom capture pattern and detect its default integer and real datatypes.
"""
@inline function _read_phantom_datatype(io :: IO)
    # Default real and int
    TI = Int32
    TF = Float32

    # Load from start
    seekstart(io)

    # 4 byte Fortran tag
    ## +4
    nbytes = read(io, Int32)

    # Test Integer
    # integer 1 == 060769
    ## + sizeof(TI)
    int_offset = position(io)
    i1 = read(io, TI)
    if (i1 != 60769)
        seek(io, int_offset)  # rewind based on current file position

        TI = Int64

        i1 = read(io, TI)
        # retry assert
        if i1 != 60769
            throw(ArgumentError("CapturePatternError: i1 mismatch. Is this a Phantom data file?"))
        end
    end

    # Test Real
    # real 1 == integer 2 == 060878
    ## + sizeof(TF)
    ## + sizeof(TI)
    real_offset = position(io)
    r1 = read(io, TF)
    i2 = read(io, TI)
    if ((i2 != 60878) || !(Float32(i2) == r1))
        seek(io, real_offset)  # rewind based on current file position

        TF = Float64
        r1 = read(io, TF)
        i2 = read(io, TI)

        # retry assert
        if ((i2 != 60878) || !(Float64(i2) == r1))
            throw(ArgumentError("CapturePatternError: i1 mismatch. Is this a Phantom data file?"))
        end
    end

    # iversion -- we don't actually check this
    ## + sizeof(TI)
    iversion = read(io, TI)

    # integer 3 == 690706
    ## + sizeof(TI)
    i3 = read(io, TI)
    if i3 != 690706
        throw(ArgumentError("CapturePatternError: i3 mismatch. Is this a Phantom data file?"))
    end

    # 4 byte Fortran tag
    ## +4
    end_nbytes = read(io, Int32)

    expected_nbytes = 4sizeof(TI) + sizeof(TF)
    nbytes == expected_nbytes || throw(DimensionMismatch("CapturePatternError: expected a $expected_nbytes-byte record, got $nbytes bytes. Is this a Phantom data file?"))
    nbytes == end_nbytes || throw(ArgumentError("CapturePatternError: Fortran tags mismatch: leading tag is $nbytes, trailing tag is $end_nbytes. Is this a Phantom data file?"))

    ## Bytes consumed: 8 + 4sizeof(TI) + sizeof(TF)
    ## Current offset: 8 + 4sizeof(TI) + sizeof(TF)
    return TI, TF
end
