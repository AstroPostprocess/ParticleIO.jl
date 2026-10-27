"""
IO

I/O utilities for particle data structures.

This module provides a unified interface for reading particle-based simulation
data, including:

- Phantom binary dump files (particle-based data)

The module aggregates lower-level I/O implementations and re-exports all
public-facing functions for external use.

# Included Components

## Phantom Binary I/O
- Reading Phantom binary dump files

Implemented in:
- `phantomIO/read_phantom.jl`

"""
module IO

using .Threads
using DataFrames
using StaticArrays: MVector
using ParticleIO.Particles


# IO for data structure
## Read Phantom Binary dumpfiles
# Data structures
include(joinpath(@__DIR__, "phantomIO", "struct", "PhantomHeaders.jl"))
include(joinpath(@__DIR__, "phantomIO", "struct", "PhantomSectionOffsets.jl"))
include(joinpath(@__DIR__, "phantomIO", "struct", "PhantomColumnInfo.jl"))
include(joinpath(@__DIR__, "phantomIO", "struct", "PhantomBlockInfo.jl"))
include(joinpath(@__DIR__, "phantomIO", "struct", "PhantomFile.jl"))

# Binary readers
include(joinpath(@__DIR__, "phantomIO", "read", "fortran_block.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "phantom_datatype.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "file_identifier.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "global_header.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "particle_block_metadata.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "particle_block_offset.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "column.jl"))
include(joinpath(@__DIR__, "phantomIO", "read", "show.jl"))
include(joinpath(@__DIR__, "phantomIO", "read_phantom.jl"))

# Export function, marco, const...
for name in filter(s -> !startswith(string(s), "#"), names(@__MODULE__, all = true))
    if !startswith(String(name), "_") && (name != :eval) && (name != :include)
        @eval export $name
    end
end
end
