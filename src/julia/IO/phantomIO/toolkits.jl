using StaticArrays
using DataFrames

# Temporary standalone definition used until the new reader is connected to the IO module
if !isdefined(@__MODULE__, :ParticleDataFrame)
    include(joinpath(@__DIR__, "..", "..", "Particles", "ParticleDataFrame.jl"))
end

# Data structures
include(joinpath(@__DIR__, "struct", "PhantomHeaders.jl"))
include(joinpath(@__DIR__, "struct", "PhantomSectionOffsets.jl"))
include(joinpath(@__DIR__, "struct", "PhantomColumnInfo.jl"))
include(joinpath(@__DIR__, "struct", "PhantomBlockInfo.jl"))
include(joinpath(@__DIR__, "struct", "PhantomFile.jl"))

# Binary readers
include(joinpath(@__DIR__, "read", "fortran_block.jl"))
include(joinpath(@__DIR__, "read", "phantom_datatype.jl"))
include(joinpath(@__DIR__, "read", "file_identifier.jl"))
include(joinpath(@__DIR__, "read", "global_header.jl"))
include(joinpath(@__DIR__, "read", "particle_block_metadata.jl"))
include(joinpath(@__DIR__, "read", "particle_block_offset.jl"))
include(joinpath(@__DIR__, "read", "column.jl"))
include(joinpath(@__DIR__, "read", "show.jl"))
include(joinpath(@__DIR__, "read_phantom_new.jl"))


# Temporary test entry point
filename = normpath(joinpath(
    @__DIR__,
    "..",
    "..",
    "..",
    "..",
    "test",
    "testinput",
    "testdumpfile_00000",
))

phantom_file = PhantomFile(filename)
nothing
