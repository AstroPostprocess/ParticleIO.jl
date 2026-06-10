### Kepelarian angular velocity (Ωk)
function _Kepelarian_angular_velocity(r :: NTuple{3, V}, rref :: NTuple{3, TF}, μ :: TF) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, z = r
    xref, yref, zref = rref
    Ωk = similar(x)
    sqrtμ = sqrt(μ)
    @inbounds @simd for i in eachindex(Ωk)
        Δxi = x[i] - xref
        Δyi = y[i] - yref
        Δzi = z[i] - zref
        ri = sqrt(Δxi * Δxi + Δyi * Δyi + Δzi * Δzi)
        invri3 = inv(ri * ri * ri)
        Ωki = sqrtμ * sqrt(invri3)
        Ωk[i] = Ωki
    end
    return Ωk
end

"""
    add_Kepelarian_angular_velocity!(data :: ParticleDataFrame)
Add the Kepelarian angular velocity for each particles.
Stores numbered columns such as `Ωk1`, using `data.params[:Origin_sink_id][]` as the sink id.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_Kepelarian_angular_velocity!(data :: ParticleDataFrame)
    if !(haskey(data.params, :Origin_sink_id)) || (data.params[:Origin_sink_id][] == -1)
        error(
            "OriginLocatedError: Wrong origin located. Please use COM2star!() to transfer the coordinate.",
        )
    end
    G = get_unit_G(data)
    M1 = data.params[:Origin_sink_mass][]
    μ = G * M1
    x = data.dfdata.x
    y = data.dfdata.y
    z = data.dfdata.z
    TF = eltype(x)
    zref = zero(TF)
    Ωk = _Kepelarian_angular_velocity((x, y, z), (zref, zref, zref), μ)
    origin_id = data.params[:Origin_sink_id][]
    data[!, "Ωk$(origin_id)"] = Ωk
    return nothing
end

"""
    add_Kepelarian_angular_velocity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Add Keplerian angular velocity in the frame centered at sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position and mass references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `Ωk1` will be stored. |
"""
function add_Kepelarian_angular_velocity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    G = get_unit_G(data)
    x = data.dfdata.x
    y = data.dfdata.y
    z = data.dfdata.z
    xt = sink_data.dfdata.x
    yt = sink_data.dfdata.y
    zt = sink_data.dfdata.z
    mt = sink_data.dfdata.m

    for n in store_sinks
        μ = G * mt[n]
        Ωk = _Kepelarian_angular_velocity((x, y, z), (xt[n], yt[n], zt[n]), μ)
        data[!, "Ωk$(n)"] = Ωk
    end
    return nothing
end
