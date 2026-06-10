### Cylindrical coordinate
function _cylindrical(r :: NTuple{3, V}, v :: NTuple{3, V}, rref :: NTuple{3, TF}, vref :: NTuple{3, TF}) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, _ = r
    vx, vy, _ = v
    xref, yref, _ = rref
    vxref, vyref, _ = vref

    s  = similar(x)
    ϕ  = similar(x)
    vs = similar(x)
    vϕ = similar(x)
    @inbounds @simd for i in eachindex(s, ϕ, vs, vϕ)
        Δxi = x[i] - xref
        Δyi = y[i] - yref
        Δvxi = vx[i] - vxref
        Δvyi = vy[i] - vyref
        si, ϕi = _cart2cylin(Δxi, Δyi)
        vsi, vϕi = _vector_cart2cylin(ϕi, Δvxi, Δvyi)

        @inbounds begin
            s[i]  = si; ϕ[i]  = ϕi; vs[i] = vsi; vϕ[i] = vϕi
        end
    end
    return s, ϕ, vs, vϕ
end

"""
    add_cylindrical!(data :: ParticleDataFrame)
Add the cylindrical/polar coordinate (s,ϕ) and corresponding velocity (vs, vϕ) into the data
If `data.params[:Origin_sink_id][]` is set, stores numbered columns such as `s1`, `ϕ1`, `vs1`, and `vϕ1`.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_cylindrical!(data :: ParticleDataFrame)
    x  = data.dfdata.x
    y  = data.dfdata.y
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    TF = eltype(x)
    zref = zero(TF)

    s, ϕ, vs, vϕ = _cylindrical((x, y, x), (vx, vy, vx), (zref, zref, zref), (zref, zref, zref))

    if haskey(data.params, :Origin_sink_id) && (data.params[:Origin_sink_id][] != -1)
        origin_id = data.params[:Origin_sink_id][]
        data[!, "s$(origin_id)"]  = s
        data[!, "ϕ$(origin_id)"]  = ϕ
        data[!, "vs$(origin_id)"] = vs
        data[!, "vϕ$(origin_id)"] = vϕ
    else
        data.dfdata.s  = s
        data.dfdata.ϕ  = ϕ
        data.dfdata.vs = vs
        data.dfdata.vϕ = vϕ
    end
    return nothing
end

"""
    add_cylindrical!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Add cylindrical/polar coordinate and velocity relative to sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position and velocity references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `s1`, `ϕ1`, `vs1`, and `vϕ1` will be stored. |
"""
function add_cylindrical!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    x  = data.dfdata.x
    y  = data.dfdata.y
    z  = data.dfdata.z
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz

    xt = sink_data.dfdata.x
    yt = sink_data.dfdata.y
    zt = sink_data.dfdata.z
    vxt = sink_data.dfdata.vx
    vyt = sink_data.dfdata.vy
    vzt = sink_data.dfdata.vz

    for n in store_sinks
        s, ϕ, vs, vϕ = _cylindrical((x, y, z), (vx, vy, vz), (xt[n], yt[n], zt[n]), (vxt[n], vyt[n], vzt[n]))
        data[!, "s$(n)"]  = s
        data[!, "ϕ$(n)"]  = ϕ
        data[!, "vs$(n)"] = vs
        data[!, "vϕ$(n)"] = vϕ
    end
    return nothing
end
