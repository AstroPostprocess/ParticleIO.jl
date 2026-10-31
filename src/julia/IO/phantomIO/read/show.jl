"""
    Base.show(io::IO, file::PhantomFile)

Print a compact one-line summary of an indexed Phantom dump file.

# Parameters
- `io::IO`: Output stream receiving the formatted summary.
- `file::PhantomFile`: Indexed Phantom dump file to display.

# Returns
- `Nothing`: The summary is written directly to `io`.
"""
function Base.show(io :: IO, file :: PhantomFile{TI, TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    nblocks = length(file.blocks)
    ncolumns = sum(block -> length(block.columns), file.blocks)

    printstyled(io, "PhantomFile"; bold = true, color = :cyan)
    print(io, "{$TI, $TF}(")
    show(io, file.filename)
    print(io, ", $nblocks blocks, $ncolumns columns)")
    return nothing
end

"""
    Base.show(io::IO, ::MIME"text/plain", file::PhantomFile)

Print a detailed, block-oriented summary of the columns available in an indexed Phantom dump file.

Each particle block displays its `block_index`, particle count, and a table containing the `column_index`, name, and
datatype required to select a column with `read_column!`.

# Parameters
- `io::IO`: Output stream receiving the formatted summary.
- `MIME"text/plain"`: Plain-text display format used by the Julia REPL and compatible frontends.
- `file::PhantomFile`: Indexed Phantom dump file to display.

# Returns
- `Nothing`: The summary is written directly to `io`.

# Notes
This display uses only indexed metadata and never opens the dump file or loads particle values.
"""
function Base.show(io :: IO, :: MIME"text/plain", file :: PhantomFile{TI, TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    dtypes = phantom_dtypes(file)
    nblocks = length(file.blocks)
    ncolumns = sum(block -> length(block.columns), file.blocks)
    index_width = 12
    name_width = 20
    datatype_width = 10

    table_top = "    ┌$(repeat("─", index_width + 2))┬$(repeat("─", name_width + 2))┬$(repeat("─", datatype_width + 2))┐"
    table_middle = "    ├$(repeat("─", index_width + 2))┼$(repeat("─", name_width + 2))┼$(repeat("─", datatype_width + 2))┤"
    table_bottom = "    └$(repeat("─", index_width + 2))┴$(repeat("─", name_width + 2))┴$(repeat("─", datatype_width + 2))┘"

    printstyled(io, "PhantomFile"; bold = true, color = :cyan)
    printstyled(io, "{$TI, $TF}\n"; color = :magenta)

    printstyled(io, "  file: "; bold = true)
    println(io, file.filename)

    print(io, "  ")
    printstyled(io, nblocks; color = :yellow)
    print(io, " blocks, ")
    printstyled(io, ncolumns; color = :yellow)
    println(io, " columns")

    for (block_index, block) in enumerate(file.blocks)
        println(io)

        printstyled(io, "  Block $block_index"; bold = true, color = :cyan)
        print(io, " (block_index = ")
        printstyled(io, block_index; color = :yellow)
        print(io, ") — ")
        printstyled(io, block.npart; color = :yellow)
        println(io, " particles")

        printstyled(io, table_top; color = :cyan)
        println(io)

        printstyled(io, "    │ "; color = :cyan)
        printstyled(io, rpad("column_index", index_width); bold = true)
        printstyled(io, " │ "; color = :cyan)
        printstyled(io, rpad("name", name_width); bold = true)
        printstyled(io, " │ "; color = :cyan)
        printstyled(io, rpad("datatype", datatype_width); bold = true)
        printstyled(io, " │"; color = :cyan)
        println(io)

        printstyled(io, table_middle; color = :cyan)
        println(io)

        for (column_index, column) in enumerate(block.columns)
            dtype = dtypes[Int(column.dtype_index)]

            printstyled(io, "    │ "; color = :cyan)
            printstyled(io, rpad(string(column_index), index_width); color = :yellow)
            printstyled(io, " │ "; color = :cyan)
            printstyled(io, rpad(column.name, name_width); color = :green)
            printstyled(io, " │ "; color = :cyan)
            printstyled(io, rpad(string(dtype), datatype_width); color = :magenta)
            printstyled(io, " │"; color = :cyan)
            println(io)
        end

        printstyled(io, table_bottom; color = :cyan)
        println(io)
    end

    println(io)
    printstyled(io, "  Read with: "; bold = true)
    println(io, "read_column!(dest, file, block_index, column_index)")
    print(io, "             read_columns!(dests, file, block_index, column_indices)")
    return nothing
end
