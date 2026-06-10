# Specific angular momentum (lx, ly, lz, l)
function _specific_angular_momentum(r :: NTuple{3, V}, v :: NTuple{3, V}, rref :: NTuple{3, TF}, vref :: NTuple{3, TF}) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, z = r
    vx, vy, vz = v

    xref, yref, zref = rref
    vxref, vyref, vzref = vref

    lx  = similar(x)
    ly  = similar(y)
    lz  = similar(z)
    l   = similar(x)

    @inbounds @simd for i in eachindex(lx, ly, lz, l)
        xi = x[i]; yi = y[i]; zi = z[i]; vxi = vx[i]; vyi = vy[i]; vzi = vz[i]

        Δxi = xi - xref
        Δyi = yi - yref
        Δzi = zi - zref

        Δvxi = vxi - vxref
        Δvyi = vyi - vyref
        Δvzi = vzi - vzref

        lxi = Δyi * Δvzi - Δzi * Δvyi
        lyi = Δzi * Δvxi - Δxi * Δvzi
        lzi = Δxi * Δvyi - Δyi * Δvxi
        li  = sqrt(lxi * lxi + lyi * lyi + lzi * lzi)

        @inbounds begin
            lx[i] = lxi; ly[i] = lyi; lz[i] = lzi; l[i] = li
        end
    end
    return lx, ly, lz, l
end

"""
    add_specific_angular_momentum!(data :: ParticleDataFrame)

Compute and add the specific angular momentum vector **l = r × v** for each particle in the current frame.
If `data.params[:Origin_sink_id][]` is set, stores numbered columns such as `lx1`, `ly1`, `lz1`, and `lnorm1`.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_specific_angular_momentum!(data :: ParticleDataFrame)
    x = data.dfdata.x
    y = data.dfdata.y
    z = data.dfdata.z
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz
    TF = eltype(x)
    zref = zero(TF)
    lx, ly, lz, l = _specific_angular_momentum((x, y, z), (vx, vy, vz), (zref, zref, zref), (zref, zref, zref))
    if haskey(data.params, :Origin_sink_id) && (data.params[:Origin_sink_id][] != -1)
        origin_id = data.params[:Origin_sink_id][]
        data[!, "lx$(origin_id)"] = lx
        data[!, "ly$(origin_id)"] = ly
        data[!, "lz$(origin_id)"] = lz
        data[!, "lnorm$(origin_id)"] = l
    else
        data.dfdata.lx = lx
        data.dfdata.ly = ly
        data.dfdata.lz = lz
        data.dfdata.lnorm = l
    end
    return nothing
end

"""
    add_specific_angular_momentum!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Compute and add the specific angular momentum vector relative to sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position and velocity references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `lx1`, `ly1`, `lz1`, and `lnorm1` will be stored. |
"""
function add_specific_angular_momentum!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
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

    for n in store_sinks
        lx, ly, lz, l = _specific_angular_momentum((x, y, z), (vx, vy, vz), (xt[n], yt[n], zt[n]), (vxt[n], vyt[n], vzt[n]))
        data[!, "lx$(n)"] = lx
        data[!, "ly$(n)"] = ly
        data[!, "lz$(n)"] = lz
        data[!, "lnorm$(n)"] = l
    end
    return nothing
end
