function _bounded_flag(KE :: V, PEn :: V) where {TF <: AbstractFloat, V <: AbstractVector{TF}}
    bflag = zeros(Bool, length(KE))
    @inbounds @simd for i in eachindex(KE)
        Eni = KE[i] + PEn[i]
        bflag[i] = (Eni < 0)
    end
    return bflag
end

"""
    add_bounded_flag!(data :: ParticleDataFrame; check_sinks::V = [1]) where {V <: AbstractVector{<:Integer}}

Compute and add boundedness flags for each particle relative to one or more sink particles.

A particle is considered *bound* to a sink if its total energy (kinetic + potential) relative to that sink is negative,
i.e. `E_total = KEₙ + PEₙ < 0`.

# Parameters
- `data :: ParticleDataFrame`:
  SPH particle data stored in a `ParticleDataFrame`. Must contain kinetic energy columns `KEₙ` and potential energy columns `PEₙ`.

# Keyword Arguments
| Name | Default | Description |
|------|----------|-------------|
| `check_sinks` | `[1]` | Vector of sink indices (e.g. `[1,2,3]`) for which boundedness flags will be computed. Each will generate a `bflagₙ` column. |

"""
function add_bounded_flag!(data :: ParticleDataFrame; check_sinks :: V = Int[1]) where {V <: AbstractVector{<:Integer}}
    for n in check_sinks
        if !hasproperty(data.dfdata, "PE$(n)")
            error("ArgumentError: Potential Energy to sink $(n) is missing!")
        end
        if !hasproperty(data.dfdata, "KE$(n)")
            error("ArgumentError: Kinetic Energy to sink $(n) is missing!")
        end
    end

    KEs = [data[!, "KE$(n)"] for n in check_sinks]
    PEs = [data[!, "PE$(n)"] for n in check_sinks]
    flags = [_bounded_flag(KEs[k], PEs[k]) for k in eachindex(check_sinks)]

    for (k,n) in enumerate(check_sinks)
        data[!, "bflag$(n)"] = flags[k]
    end
    return nothing
end


