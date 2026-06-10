### Density
@inline function _density(h :: V, m :: TF, hfact :: TF, ::Val{2}) where {TF <: AbstractFloat, V <: AbstractVector}
    """ Valid only if mb = m (mb is a constant)"""
    ρ = similar(h)
    mhfactd = m * hfact * hfact
    @inbounds @simd for i in eachindex(ρ)
        hi = h[i]
        invhi = inv(hi)
        invhid = invhi * invhi
        ρi = mhfactd * invhid
        ρ[i] = ρi
    end
    return ρ
end

@inline function _density(h :: V, m :: TF, hfact :: TF, ::Val{3}) where {TF <: AbstractFloat, V <: AbstractVector}
    """ Valid only if mb = m (mb is a constant)"""
    ρ = similar(h)
    mhfactd = m * hfact * hfact * hfact
    @inbounds @simd for i in eachindex(ρ)
        hi = h[i]
        invhi = inv(hi)
        invhid = invhi * invhi * invhi
        ρi = mhfactd * invhid
        ρ[i] = ρi
    end
    return ρ
end

"""
    add_rho!(data :: ParticleDataFrame)
Add the local density of disk for each particles.

**Note**: This function is invalid when per-particle masses are used.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`
"""
function add_rho!(data :: ParticleDataFrame)
    if (hasproperty(data.dfdata, "m"))
        @warn("This function assumes all particles share the same mass. It is invalid if per-particle masses are used.")
    end
    if !(haskey(data.params, :mass))
        error("KeyError: Missing required parameter :mass in data.params.")
    end

    particle_mass = data.params[:mass]
    hfact = data.params[:hfact]
    d = get_dim(data)
    TF = typeof(particle_mass)
    h = TF.(data.dfdata.h)
    ρ = _density(h, particle_mass, hfact, Val(d))
    data.dfdata.rho = ρ
    return nothing
end

