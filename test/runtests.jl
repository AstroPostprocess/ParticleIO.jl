######################################################################################

#  ParticleIO.jl - Test Suite Entry Point
#  Run with:  julia --project=. test/runtests.jl
#             or: include("test/runtests.jl") from the REPL
#  Ordering convention
#  1. Phantom reading  (complete dump, raw columns, analysis tables)
#  2. Phantom writing (write and read back through two generations)

######################################################################################
using Test
using ParticleIO

# ========================== Phantom reading ================================= #

include("phantom_test_common.jl")
include("io_tests.jl")

# ========================== Phantom writing ================================= #

include("phantom_write_tests.jl")
