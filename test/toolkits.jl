using StructArrays
using TypedTables

struct ParticleTable
    


end


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