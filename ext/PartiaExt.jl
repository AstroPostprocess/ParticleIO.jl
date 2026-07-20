module PartiaExt

using ParticleIO: ParticleDataFrame, MassFromColumn, MassFromParams, get_npart
using Partia.KernelInterpolation: AbstractSPHKernel, M5_spline
import Partia

include(joinpath(@__DIR__, "PartiaExt", "build_input.jl"))

end
