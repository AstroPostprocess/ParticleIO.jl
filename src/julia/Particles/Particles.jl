"""
Particles

Core particle data abstractions for Partia.

This module defines the canonical particle-level data structures and
associated utilities used throughout Partia. It provides a
DataFrame-backed representation of SPH particle data together with
helper routines for constructing and augmenting particle quantities.

# Scope and Responsibilities

The module provides:

## Particle Data Container
- `ParticleDataFrame`, a structured wrapper around `DataFrames.DataFrame`
  tailored for SPH particle data
- Standardised column conventions for particle properties
  (e.g. position, velocity, mass, density)

Implemented in:
- `ParticleDataFrame.jl`

## Quantity Construction Utilities
- Functions for adding derived or auxiliary particle quantities
- Designed to operate in-place on `ParticleDataFrame` objects
- Supports statistical operations where appropriate

Implemented in:
- `operations/*.jl`
"""
module Particles

using Base.Threads
using DataFrames
using Statistics
using Partia.Tools: _cart2cylin, _vector_cart2cylin

# ParticleDataFrame & operations
include(joinpath(@__DIR__, "ParticleDataFrame.jl"))
include(joinpath(@__DIR__, "operations", "distance_measurements.jl"))
include(joinpath(@__DIR__, "operations", "coordinate_shift.jl"))
include(joinpath(@__DIR__, "operations", "mass.jl"))
include(joinpath(@__DIR__, "operations", "density.jl"))
include(joinpath(@__DIR__, "operations", "norm.jl"))
include(joinpath(@__DIR__, "operations", "kinetic_energy.jl"))
include(joinpath(@__DIR__, "operations", "potential_energy.jl"))
include(joinpath(@__DIR__, "operations", "bounded_flag.jl"))
include(joinpath(@__DIR__, "operations", "cylindrical.jl"))
include(joinpath(@__DIR__, "operations", "kepelarian_azimuthal_velocity.jl"))
include(joinpath(@__DIR__, "operations", "kepelarian_angular_velocity.jl"))
include(joinpath(@__DIR__, "operations", "eccentricity.jl"))
include(joinpath(@__DIR__, "operations", "specific_angular_momentum.jl"))


# Export function, marco, const...
for name in filter(s -> !startswith(string(s), "#"), names(@__MODULE__, all = true))
    if !startswith(String(name), "_") && (name != :eval) && (name != :include)
        @eval export $name
    end
end
end
