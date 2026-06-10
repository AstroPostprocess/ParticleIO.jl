@inline function _massoftype_key(itype :: Integer) :: Symbol
    return itype == 1 ? :massoftype : Symbol("massoftype_$(itype)")
end

@inline function _massoftype(data :: ParticleDataFrame, itype :: Integer) :: Float64
    haskey(data.params, :ntypes) || throw(KeyError(:ntypes))
    haskey(data.params, :massoftype) || throw(KeyError(:massoftype))

    ntypes = Int(data.params[:ntypes])
    1 <= itype <= ntypes || throw(ArgumentError("itype must be in 1:$(ntypes)."))

    key = _massoftype_key(itype)
    haskey(data.params, key) || throw(KeyError(key))
    return Float64(data.params[key])
end

"""
    add_mass!(data :: ParticleDataFrame; column_name :: Symbol = :m)

Add a particle mass column from `data.params[:massoftype]` and related type-specific mass keys.

# Parameters
- `data :: ParticleDataFrame`: The SPH data that is stored in `ParticleDataFrame`

# Keyword Arguments
| Name | Default | Description |
|------|---------|-------------|
| `column_name` | `:m` | Column name used to store particle masses. |
"""
function add_mass!(data :: ParticleDataFrame; column_name :: Symbol = :m)
    masses = Vector{Float64}(undef, get_npart(data))

    if hasproperty(data.dfdata, :itype)
        itypes = data[!, :itype]
        @inbounds for i in eachindex(masses, itypes)
            itype = Int(itypes[i])
            masses[i] = _massoftype(data, itype)
        end
    else
        itype = if haskey(data.params, :itype) && (data.params[:itype] isa Integer)
            Int(data.params[:itype])
        elseif Int(data.params[:ntypes]) == 1
            1
        else
            throw(ArgumentError("Particle type is missing. Add an itype column or set data.params[:itype]."))
        end

        fill!(masses, _massoftype(data, itype))
    end

    data[!, column_name] = masses
    return nothing
end
