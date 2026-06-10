### Norm of coordinate and velocity w.r.t. origin
"""
    add_norm!(data :: ParticleDataFrame)
Add the length of position vector and velocity vector in 3D.
If `data.params[:Origin_sink_id][]` is set, stores numbered columns such as `r1` and `vr1`.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_norm!(data :: ParticleDataFrame)
    x = data.dfdata.x; y = data.dfdata.y; z = data.dfdata.z
    vx = data.dfdata.vx; vy = data.dfdata.vy; vz = data.dfdata.vz

    r = Euclidean_distance(x, y, z, (0.0,0.0,0.0))
    vr = Euclidean_distance(vx, vy, vz, (0.0,0.0,0.0))

    if haskey(data.params, :Origin_sink_id) && (data.params[:Origin_sink_id][] != -1)
        origin_id = data.params[:Origin_sink_id][]
        data[!, "r$(origin_id)"] = r
        data[!, "vr$(origin_id)"] = vr
    else
        data.dfdata.r = r
        data.dfdata.vr = vr
    end
    return nothing
end

"""
    add_norm!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Add the relative length of position vector and velocity vector in 3D with respect to sink particles.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
- `sink_data :: ParticleDataFrame`: Sink particle data used as position and velocity references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `store_sinks` | `Int[]` | Indices of sink particles for which numbered columns such as `r1` and `vr1` will be stored. |
"""
function add_norm!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    x = data.dfdata.x; y = data.dfdata.y; z = data.dfdata.z
    vx = data.dfdata.vx; vy = data.dfdata.vy; vz = data.dfdata.vz

    xt = sink_data.dfdata.x
    yt = sink_data.dfdata.y
    zt = sink_data.dfdata.z
    vxt = sink_data.dfdata.vx
    vyt = sink_data.dfdata.vy
    vzt = sink_data.dfdata.vz

    for n in store_sinks
        r = Euclidean_distance(x, y, z, (xt[n], yt[n], zt[n]))
        vr = Euclidean_distance(vx, vy, vz, (vxt[n], vyt[n], vzt[n]))
        data[!, "r$(n)"] = r
        data[!, "vr$(n)"] = vr
    end
    return nothing
end

