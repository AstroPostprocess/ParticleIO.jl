using StaticArrays

struct PhantomDefaultTypes{TI <: Integer, TF <: AbstractFloat} end

default_int_type(:: PhantomDefaultTypes{TI}) where {TI <: Integer} = TI
default_real_type(:: PhantomDefaultTypes{TI, TF}) where {TI <: Integer, TF <: AbstractFloat} = TF

mutable struct PhantomOffsetTable
    
end

const _PHANTOM_TYPE = Union{Int8, Int16, Int32, Int64, Float32, Float64}

function _rename_duplicates!(keys :: Vector{String})
    counts = Dict{String, Int}()

    for key in keys
        counts[key] = get(counts, key, 0) + 1
    end

    occurrences = Dict{String, Int}()

    for i in eachindex(keys)
        key = keys[i]

        if counts[key] > 1
            n = get(occurrences, key, 0) + 1
            occurrences[key] = n
            keys[i] = "$(key)_$(n)"
        end
    end

    return nothing
end

@inline function _read_fortran_block!(io :: IO, buffer :: V) where {V <: AbstractVector{UInt8}}
    # Allocate block tag validation
    start_tag = MVector{4, UInt8}(undef)
    end_tag   = MVector{4, UInt8}(undef)

    # 4 byte Fortran tag
    ## +4
    read!(io, start_tag)

    # Read data
    ## +sizeof(buffer)
    read!(io, buffer)
   
    # 4 byte Fortran tag
    ## +4
    read!(io, end_tag)

    if (start_tag != end_tag)
        error("Fortran tags mismatch.")
    end

    ## Bytes consumed: 8 + sizeof(buffer)
    return nothing
end

@inline function _read_header_block!(io :: IO, buffers :: NTuple{2, Vector{UInt8}}, :: Type{T}) where {T <: _PHANTOM_TYPE}
    # Allocate buffer for the variable count
    buffer = MVector{4, UInt8}(undef)
    buffer_keys = buffers[1]
    buffer_data = buffers[2]

    # Read number of variable
    ## +12
    _read_fortran_block!(io, buffer)
    nvars_raw = reinterpret(reshape, Int32, buffer)[]
    0 <= nvars_raw <= 1_000_000 || error("Invalid header variable count: $nvars_raw")
    nvars = Int(nvars_raw)

    # Collect key and data in header
    keys = Vector{String}(undef, nvars)
    data = Vector{T}(undef, nvars)
    if nvars > 0
        # each tag is 16 characters in length
        # Keys
        resize!(buffer_keys, 16 * nvars)
        ## + 8 + 16 * nvars
        _read_fortran_block!(io, buffer_keys)

        # data
        resize!(buffer_data, sizeof(T) * nvars)
        ## + 8 + sizeof(T) * nvars
        _read_fortran_block!(io, buffer_data)

        # fill in values
        @inbounds for j in eachindex(keys)
            i = 16(j - 1) + 1 
            keys[j] = strip(String(@view buffer_keys[i:i+15]))
        end
        copyto!(data, reinterpret(T, buffer_data))
    end

    ## Bytes consumed: 28 + (16 + sizeof(T)) * nvars
    return keys, data
end

@inline function _read_phantom_datatype(io :: IO)
    # Allocate block tag validation
    start_tag = MVector{4, UInt8}(undef)
    end_tag   = MVector{4, UInt8}(undef)

    # Default real and int
    TI = Int32
    TF = Float32

    # Load from start
    seekstart(io)

    # 4 byte Fortran tag
    ## +4
    read!(io, start_tag)

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
            error("CapturePatternError: i1 mismatch. Is this a Phantom data file?")
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
            error("CapturePatternError: i1 mismatch. Is this a Phantom data file?")
        end
    end

    # iversion -- we don't actually check this
    ## + sizeof(TI)
    iversion = read(io, TI)

    # integer 3 == 690706
    ## + sizeof(TI)
    i3 = read(io, TI)
    if (i3 != 690706)
        error("CapturePatternError: i3 mismatch. Is this a Phantom data file?")
    end

    # 4 byte Fortran tag
    ## +4
    read!(io, end_tag)

    # assert tags equal
    if (start_tag != end_tag)
        error("CapturePatternError: Fortran tags mismatch. Is this a Phantom data file?")
    end

    ## Bytes consumed: 8 + 4sizeof(TI) + sizeof(TF)
    ## Current offset: 8 + 4sizeof(TI) + sizeof(TF)
    return PhantomDefaultTypes{TI, TF}()
end

@inline function _read_file_identifier(io :: IO, :: PhantomDefaultTypes{TI, TF}) where {TI <: Integer, TF <: AbstractFloat}
    # Allocate buffer for data
    buffer = Vector{UInt8}(undef, 100)
    
    # Offset of file identifier
    offset = 8 + 4sizeof(TI) + sizeof(TF)

    # Move the cursor to that position
    seek(io, offset)

    # Read the 100 character file identifier
    ## +108
    _read_fortran_block!(io, buffer)

    # Note that buffer will be transferred into string, so no GC will kick in.
    file_identifier = strip(String(buffer))

    ## Bytes consumed: 108
    ## Current offset: 116 + 4sizeof(TI) + sizeof(TF)
    return file_identifier
end

@inline function _read_header(io :: IO, :: PhantomDefaultTypes{TI, TF}) where {TI <: Integer, TF <: AbstractFloat}
    # Allocate buffers for keys and data
    buffers = ntuple(_ -> Vector{UInt8}(undef, 0), 2)

    # Offset of header
    offset = 116 + 4sizeof(TI) + sizeof(TF)

    # Move the cursor to that position
    seek(io, offset)

    # Phantom has 8 blocks for headers
    dtypes = (TI, Int8, Int16, Int32, Int64, TF, Float32, Float64)

    # Run through all data types
    ## + 8 * (28 + (16 + sizeof(T)) * length(dtype_keys[i]))
    blocks = map(dtypes) do dtype
        keys, data = _read_header_block!(io, buffers, dtype)
        _rename_duplicates!(keys)
        return keys, data
    end
    dtypes_keys = map(first, blocks)
    dtypes_data = map(last, blocks)

    ## Bytes consumed: 8 * (28 + (16 + sizeof(T)) * length(dtype_keys[i]))
    ## Current offset:
    ## 340 + 4sizeof(TI) + sizeof(TF) +
    ## sum((16 + sizeof(dtypes[i])) * dtype_nvars[i] for i in eachindex(dtypes))
    return dtypes_keys, dtypes_data
end


TI = Int32
TF = Float64

testoff = 116 + 4sizeof(TI) + sizeof(TF)

filename = ".\\test\\testinput\\testdumpfile_00000"
io = open(filename, "r")
pdt = _read_phantom_datatype(io)
file_identifier = _read_file_identifier(io, pdt)

println("Before header", position(io))

dtype_header_keys, dtype_header_data = _read_header_block!(io, (Vector{UInt8}(undef, 0), Vector{UInt8}(undef, 0)), TI)
_rename_duplicates!(dtype_header_keys)