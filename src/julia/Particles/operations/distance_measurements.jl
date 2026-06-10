## Distance measurements
"""
    get_rnorm_ref(data :: ParticleDataFrame, reference_position::NTuple{3, Float64})
Get the array of distance between particles and the reference_position.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `reference_position::NTuple{3, Float64}`: The reference point to estimate the distance.

# Returns
- `Vector`: The array of distance between particles and the reference_position.
"""
function get_rnorm_ref(data :: ParticleDataFrame, reference_position::NTuple{3, TF}) where {TF <: AbstractFloat}
    x = data.dfdata.x; y = data.dfdata.y; z = data.dfdata.z
    rnorm :: Vector{TF} = Euclidean_distance(x, y, z, reference_position)
    return rnorm
end

"""
    get_snorm_ref(data :: ParticleDataFrame, reference_position::NTuple{2, TF})
Get the array of distance between particles and the reference_position ON THE XY-PLANE PROJECTION.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `reference_position::NTuple{2, TF}`: The reference point to estimate the distance.

# Returns
- `Vector`: The array of distance between particles and the reference_position ON THE XY-PLANE PROJECTION.
"""
function get_snorm_ref(data :: ParticleDataFrame, reference_position::NTuple{2, TF}) where {TF <: AbstractFloat}
    x = data.dfdata.x; y = data.dfdata.y
    rnorm :: Vector{TF} = Euclidean_distance(x, y, reference_position)
    return rnorm
end

"""
    get_rnorm(data :: ParticleDataFrame)
Get the array of distance between particles and the origin.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`

# Returns
- `Vector`: The array of distance between particles and the origin.
"""
function get_rnorm(data :: ParticleDataFrame)
    return get_rnorm_ref(data, (0.0, 0.0, 0.0))
end

"""
    get_snorm(data :: ParticleDataFrame)
Get the array of distance between particles and the origin ON THE XY-PLANE PROJECTION.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`

# Returns
- `Vector`: The array of distance between particles and the origin ON THE XY-PLANE PROJECTION.
"""
function get_snorm(data :: ParticleDataFrame)
    return get_snorm_ref(data, (0.0, 0.0))
end

