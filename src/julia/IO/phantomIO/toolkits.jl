using ParticleIO
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

file = PhantomFile(filename)
data = read_data(file)
nothing
