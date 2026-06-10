### Energy
function _kinetic_energy(v :: NTuple{3, V}, m :: TF, vref :: NTuple{3, TF}) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    vx, vy, vz = v
    vxt, vyt, vzt = vref
    KE = similar(vx)
    ml2 = TF(0.5) * m
    @inbounds @simd for i in eachindex(KE)
        Δvxi = vx[i] - vxt
        Δvyi = vy[i] - vyt
        Δvzi = vz[i] - vzt
        vi2 = Δvxi * Δvxi + Δvyi * Δvyi + Δvzi * Δvzi

        KEi = ml2 * vi2
        KE[i] = KEi
    end
    return KE
end

function _kinetic_energy(v :: NTuple{3, V}, m :: V, vref :: NTuple{3, TF}) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    vx, vy, vz = v
    vxt, vyt, vzt = vref
    KE = similar(vx)
    C = TF(0.5)
    @inbounds @simd for i in eachindex(KE)
        Δvxi = vx[i] - vxt
        Δvyi = vy[i] - vyt
        Δvzi = vz[i] - vzt
        mi = m[i]
        vi2 = Δvxi * Δvxi + Δvyi * Δvyi + Δvzi * Δvzi

        KEi = C * mi * vi2
        KE[i] = KEi
    end
    return KE
end


"""
    add_kinetic_energy!(data :: ParticleDataFrame; specific_mass_column::Symbol = :m)

Compute and add the kinetic energy of each particle in `data` for the current frame.
If `data.params[:Origin_sink_id][]` is set, stores numbered columns such as `KE1`.

# Parameters
- `data :: ParticleDataFrame`: SPH particle data stored in `ParticleDataFrame`.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `specific_mass_column` | `:m` | Symbol of the column storing per-particle masses. If missing, a global mass in `data.params[:mass]` will be used instead. |
"""
function add_kinetic_energy!(data :: ParticleDataFrame; specific_mass_column :: Symbol = :m)
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz
    TF = eltype(vx)
    zref = zero(TF)

    if !(hasproperty(data.dfdata, specific_mass_column))
        if (haskey(data.params, :mass))
            mass = TF(data.params[:mass])
            KE = _kinetic_energy((vx, vy, vz), mass, (zref, zref, zref))
        else
            error("ArgumentError: Mass is missing from this data")
        end
    else
        masses = data[!, specific_mass_column]
        KE = _kinetic_energy((vx, vy, vz), masses, (zref, zref, zref))
    end

    if haskey(data.params, :Origin_sink_id) && (data.params[:Origin_sink_id][] != -1)
        origin_id = data.params[:Origin_sink_id][]
        data[!, "KE$(origin_id)"] = KE
    else
        data[!, :KE] = KE
    end
    return nothing
end

"""
    add_kinetic_energy!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; specific_mass_column::Symbol = :m, store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
Compute and add the kinetic energy of all gas particles in `data` with respect to each sink particle in `sink_data`.

# Parameters
- `data :: ParticleDataFrame`: SPH particle data stored in `ParticleDataFrame`.
- `sink_data :: ParticleDataFrame`: Sink particle data used as velocity references.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `specific_mass_column` | `:m` | Symbol of the column storing per-particle masses. If missing, a global mass in `data.params[:mass]` will be used instead. |
| `store_sinks` | `Int[]` | Indices of sink particles for which individual kinetic energy columns (`KEₙ`) will be stored. |
"""
function add_kinetic_energy!(data :: ParticleDataFrame, sink_data :: ParticleDataFrame; specific_mass_column::Symbol = :m, store_sinks :: V = Int[]) where {V <: AbstractVector{<:Integer}}
    vx = data.dfdata.vx
    vy = data.dfdata.vy
    vz = data.dfdata.vz

    vxt = sink_data.dfdata.vx
    vyt = sink_data.dfdata.vy
    vzt = sink_data.dfdata.vz

    TF = eltype(vx)
    num_sink = get_npart(sink_data)

    use_threads = (nthreads() > 1) && (nthreads() ÷ 2 > num_sink)

    if !(hasproperty(data.dfdata, specific_mass_column))
        if (haskey(data.params, :mass))
            mass = TF(data.params[:mass])
            if use_threads
                KEs = Vector{Vector{TF}}(undef, num_sink)
                @threads for n in 1:num_sink
                    KEs[n] = _kinetic_energy((vx, vy, vz), mass, (vxt[n], vyt[n], vzt[n]))
                end
            else
                KEs = [_kinetic_energy((vx, vy, vz), mass, (vxt[n], vyt[n], vzt[n])) for n in 1:num_sink]
            end
            for n in 1:num_sink
                if n in store_sinks
                    data[!, "KE$(n)"] = KEs[n]
                end
            end
        else
            error("ArgumentError: Mass is missing from this data")
        end
    else
        masses = data[!, specific_mass_column]
        if use_threads
            KEs = Vector{Vector{TF}}(undef, num_sink)
            @threads for n in 1:num_sink
                KEs[n] = _kinetic_energy((vx, vy, vz), masses, (vxt[n], vyt[n], vzt[n]))
            end
        else
            KEs = [_kinetic_energy((vx, vy, vz), masses, (vxt[n], vyt[n], vzt[n])) for n in 1:num_sink]
        end
        for n in 1:num_sink
            if n in store_sinks
                data[!, "KE$(n)"] = KEs[n]
            end
        end
    end
    return nothing
end
