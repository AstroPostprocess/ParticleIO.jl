const _PHANTOM_INT_TYPE = Union{Int32, Int64}
const _PHANTOM_REAL_TYPE = Union{Float32, Float64}
const _PHANTOM_TYPE = Union{Int8, Int16, Int32, Int64, Float32, Float64}

struct PhantomHeader{T <: _PHANTOM_TYPE}
    keys :: Vector{String}
    data :: Vector{T}
end

struct PhantomHeaders{TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    default_integer :: PhantomHeader{TI}
    int8            :: PhantomHeader{Int8}
    int16           :: PhantomHeader{Int16}
    int32           :: PhantomHeader{Int32}
    int64           :: PhantomHeader{Int64}
    default_real    :: PhantomHeader{TF}
    float32         :: PhantomHeader{Float32}
    float64         :: PhantomHeader{Float64}
end
