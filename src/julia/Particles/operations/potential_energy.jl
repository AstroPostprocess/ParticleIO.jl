function _potential_energy(r :: NTuple{3, V}, m :: TF, rref :: NTuple{3, TF}, μ :: TF) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, z = r
    xt, yt, zt = rref
    C = - μ * m
    PE = similar(x)
    @inbounds @simd for i in eachindex(PE)
        xi = x[i]; yi = y[i]; zi = z[i];
        Δxi = xi - xt
        Δyi = yi - yt
        Δzi = zi - zt
        Δr = sqrt(Δxi * Δxi + Δyi * Δyi + Δzi * Δzi)
        PEi = C * inv(Δr)
        PE[i] = PEi
    end
    return PE
end

function _potential_energy(r :: NTuple{3, V}, m :: V, rref :: NTuple{3, TF}, μ :: TF) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    x, y, z = r
    xt, yt, zt = rref
    PE = similar(x)
    @inbounds @simd for i in eachindex(PE)
        xi = x[i]; yi = y[i]; zi = z[i];
        mi = m[i]
        Δxi = xi - xt
        Δyi = yi - yt
        Δzi = zi - zt
        Δr = sqrt(Δxi * Δxi + Δyi * Δyi + Δzi * Δzi)
        PEi = - μ * mi * inv(Δr)
        PE[i] = PEi
    end
    return PE
end

"""
    add_potential_energy!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; specific_mass_column::Symbol = :m, store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}

Compute and add the gravitational potential energy of all gas particles in `data` with respect to each sink particle in `sink_data`.

# Parameters
- `data :: ParticleDataFrame`: SPH particle data stored in `ParticleDataFrame`.
- `sink_data :: ParticleDataFrame`: Sink particle data used as potential sources.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `specific_mass_column` | `:m` | Symbol of the column storing per-particle masses. If missing, a global mass in `data.params[:mass]` will be used instead. |
| `store_sinks` | `Int[]` | Indices of sink particles for which individual potential energy columns (`PEₙ`) will be stored. If empty, only the total potential energy (`PEtot`) is added. |


"""
function add_potential_energy!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; specific_mass_column::Symbol = :m, store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    x = data.dfdata.x
    y = data.dfdata.y
    z = data.dfdata.z

    xt = sink_data.dfdata.x
    yt = sink_data.dfdata.y
    zt = sink_data.dfdata.z
    mt = sink_data.dfdata.m

    TF = eltype(x)

    G = get_unit_G(data)
    num_part = get_npart(data)
    num_sink = get_npart(sink_data)

    use_threads = (nthreads() > 1) && (nthreads() ÷ 2 > num_sink)

    if !(hasproperty(data.dfdata, specific_mass_column))
        if (haskey(data.params, :mass))
            mass = TF(data.params[:mass])
            if use_threads
                PEs = Vector{Vector{TF}}(undef, num_sink)
                @threads for n in 1:num_sink
                    PEs[n] = _potential_energy((x, y, z), mass, (xt[n], yt[n], zt[n]), G * mt[n])
                end
            else
                PEs = [_potential_energy((x, y, z), mass, (xt[n], yt[n], zt[n]), G * mt[n]) for n in 1:num_sink]
            end
            PEtot = zeros(TF, num_part)
            for n in 1:num_sink
                @inbounds @simd for i in 1:num_part
                    PEtot[i] += PEs[n][i]
                end
            end
            data.dfdata.PEtot = PEtot
            for n in 1:num_sink
                if n in store_sinks
                    data[!, "PE$(n)"] = PEs[n]
                end
            end
        else
            error("ArgumentError: Mass is missing from this data")
        end
    else
        masses = data[!, specific_mass_column]
        if use_threads
            PEs = Vector{Vector{TF}}(undef, num_sink)
            @threads for n in 1:num_sink
                PEs[n] = _potential_energy((x, y, z), masses, (xt[n], yt[n], zt[n]), G * mt[n])
            end
        else
            PEs = [_potential_energy((x, y, z), masses, (xt[n], yt[n], zt[n]), G * mt[n]) for n in 1:num_sink]
        end
        PEtot = zeros(TF, num_part)
        for n in 1:num_sink
            @inbounds @simd for i in 1:num_part
                PEtot[i] += PEs[n][i]
            end
        end
        data.dfdata.PEtot = PEtot
        for n in 1:num_sink
            if n in store_sinks
                data[!, "PE$(n)"] = PEs[n]
            end
        end
    end
    return nothing
end
