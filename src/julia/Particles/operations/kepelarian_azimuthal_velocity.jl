### Kepelarian azimuthal velocity (vϕk) and the relative azimuthal velocity (vϕ - vϕk)
function _Kepelarian_azimuthal_velocity(s :: V, vϕ :: V, μ :: TF) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    vϕk = similar(s)
    vrelϕ = similar(s)
    sqrtμ = sqrt(μ)
    @inbounds @simd for i in eachindex(vϕk, vrelϕ)
        si = s[i]; vϕi = vϕ[i]
        vϕki = sqrtμ * sqrt(inv(si))
        vrelϕi = vϕi - vϕki
        @inbounds begin
            vrelϕ[i] = vrelϕi
            vϕk[i] = vϕki
        end

    end
    return vϕk, vrelϕ
end

"""
    add_Kepelarian_azimuthal_velocity!(data :: ParticleDataFrame)
Add the Kepelarian azimuthal velocity for each particles.
Stores numbered columns such as `vϕk1` and `vrelϕ1`, using `data.params[:Origin_sink_id][]` as the sink id.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_Kepelarian_azimuthal_velocity!(data :: ParticleDataFrame)
    if !(haskey(data.params, :Origin_sink_id)) || (data.params[:Origin_sink_id][] == -1)
        error(
            "OriginLocatedError: Wrong origin located. Please use COM2star!() to transfer the coordinate.",
        )
    end
    origin_id = data.params[:Origin_sink_id][]
    if !(hasproperty(data.dfdata, Symbol("s$(origin_id)")))
        add_cylindrical!(data)
    end
    G = get_unit_G(data)
    M1 = data.params[:Origin_sink_mass][]
    μ = G * M1
    s = data[!, "s$(origin_id)"]
    vϕ = data[!, "vϕ$(origin_id)"]
    vϕk, vrelϕ = _Kepelarian_azimuthal_velocity(s, vϕ, μ)
    data[!, "vϕk$(origin_id)"] = vϕk
    data[!, "vrelϕ$(origin_id)"] = vrelϕ
    return nothing
end

"""
    add_Kepelarian_azimuthal_velocity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Add the cylindrical coordinate and Kepelarian azimuthal velocity relative to sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position, velocity, and mass references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `s1`, `vϕk1`, and `vrelϕ1` will be stored. |
"""
function add_Kepelarian_azimuthal_velocity!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
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
        s, ϕ, vs, vϕ = _cylindrical((x, y, z), (vx, vy, vz), (xt[n], yt[n], zt[n]), (vxt[n], vyt[n], vzt[n]))
        vϕk, vrelϕ = _Kepelarian_azimuthal_velocity(s, vϕ, μ)
        data[!, "s$(n)"] = s
        data[!, "ϕ$(n)"] = ϕ
        data[!, "vs$(n)"] = vs
        data[!, "vϕ$(n)"] = vϕ
        data[!, "vϕk$(n)"] = vϕk
        data[!, "vrelϕ$(n)"] = vrelϕ
    end
    return nothing
end

