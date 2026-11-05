using StructArrays
using TypedTables

abstract type AbstractPartType end

struct PhantomPartType{I} <: AbstractPartType end
struct GadgetoPartType{I} <: AbstractPartType end

abstract type AbstractParticleColumn{T <: Number} end

struct ParticleColumn{T <: Number, V <: AbstractVector{T}, M} <: AbstractParticleColumn{T}
    data     :: V
    metadata :: M
end

struct ParticleMultiColumn{N, T <: Number, V <: AbstractVector{T}, M} <: AbstractParticleColumn{T}
    data     :: NTuple{N,V}
    metadata :: M
end

abstract type AbstractParticleColumnMetadata end

mutable struct PhantomColumnMetadata{DI} <: AbstractParticleColumnMetadata
    block       :: Int
    dtype_index :: DI
end

mutable struct GadgetColumnMetadata <: AbstractParticleColumnMetadata
    
end


struct ParticleTable{PT <: AbstractPartType}
    


end


parttype(::ParticleTable{PhantomPartType{I}}) where {I} = I
parttype(::ParticleTable{GadgetPartType{I}}) where {I} = I

simulation(::ParticleTable{<:PhantomPartType}) = :Phantom
simulation(::ParticleTable{<:GadgetPartType}) = :Gadget

N = 10000

x = rand(N)
y = rand(N)
z = rand(N)

h = rand(Float32, N)

dustfrac = ntuple(_ -> rand(N), 5)
dustfrac_structarray = StructArray(dustfrac)


column_name = Symbol[:x, :y, :z, :h, :dustfrac]
column_data = (x, y, z, h, dustfrac_structarray)

table = FlexTable(NamedTuple{Tuple(column_name)}(column_data))