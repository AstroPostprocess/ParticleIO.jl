### Eccentricity
function _eccentricity(r :: NTuple{3, V}, v :: NTuple{3, V}, rref :: NTuple{3, TF}, vref :: NTuple{3, TF}, μ :: TF) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, z = r
    vx, vy, vz = v
    xref, yref, zref = rref
    vxref, vyref, vzref = vref

    e  = similar(x)
    invµ = inv(μ)
    @inbounds @simd for i in eachindex(e)
        Δxi = x[i] - xref
        Δyi = y[i] - yref
        Δzi = z[i] - zref
        Δvxi = vx[i] - vxref
        Δvyi = vy[i] - vyref
        Δvzi = vz[i] - vzref

        ri = sqrt(Δxi * Δxi + Δyi * Δyi + Δzi * Δzi)
        vri2 = Δvxi * Δvxi + Δvyi * Δvyi + Δvzi * Δvzi

        ridotvi = Δxi * Δvxi + Δyi * Δvyi + Δzi * Δvzi

        invri = inv(ri)

        ridotvilµ = ridotvi * invµ
        vri2lµminvri = vri2 * invµ - invri


        exi = Δxi * vri2lµminvri - Δvxi * ridotvilµ
        eyi = Δyi * vri2lµminvri - Δvyi * ridotvilµ
        ezi = Δzi * vri2lµminvri - Δvzi * ridotvilµ

        e[i] = sqrt(exi * exi + eyi * eyi + ezi * ezi)
    end
    return e
end

"""
    add_eccentricity!(data :: ParticleDataFrame)
Add the eccentricity for each particle with respect to current origin.
Stores numbered columns such as `e1`, using `data.params[:Origin_sink_id][]` as the sink id.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_eccentricity!(data :: ParticleDataFrame)
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
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz
    TF = eltype(x)
    zref = zero(TF)
    e = _eccentricity((x, y, z), (vx, vy, vz), (zref, zref, zref), (zref, zref, zref), μ)
    origin_id = data.params[:Origin_sink_id][]
    data[!, "e$(origin_id)"] = e
    return nothing
end

"""
    add_eccentricity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Add the eccentricity relative to sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position, velocity, and mass references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `e1` will be stored. |
"""
function add_eccentricity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    G = get_unit_G(data)
    x = data.dfdata.x
    y = data.dfdata.y
    z = data.dfdata.z
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz
    xt = sink_data.dfdata.x
    yt = sink_data.dfdata.y
    zt = sink_data.dfdata.z
    vxt = sink_data.dfdata.vx
    vyt = sink_data.dfdata.vy
    vzt = sink_data.dfdata.vz
    mt = sink_data.dfdata.m

    for n in store_sinks
        μ = G * mt[n]
        e = _eccentricity((x, y, z), (vx, vy, vz), (xt[n], yt[n], zt[n]), (vxt[n], vyt[n], vzt[n]), μ)
        data[!, "e$(n)"] = e
    end
    return nothing
end
