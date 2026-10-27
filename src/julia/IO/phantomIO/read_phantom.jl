"""
    _collect_header_params(file::PhantomFile)

Collect typed Phantom headers and compatibility metadata into a parameter dictionary.
"""
function _collect_header_params(file :: PhantomFile{TI, TF}) where {TI <: _PHANTOM_INT_TYPE, TF <: _PHANTOM_REAL_TYPE}
    header_blocks = (
        file.headers.default_integer,
        file.headers.int8,
        file.headers.int16,
        file.headers.int32,
        file.headers.int64,
        file.headers.default_real,
        file.headers.float32,
        file.headers.float64,
    )

    header_vars = Dict{Symbol, Any}()
    for header in header_blocks
        for i in eachindex(header.keys, header.data)
            header_vars[Symbol(header.keys[i])] = header.data[i]
        end
    end

    # Preserve metadata fields provided by the original reader
    header_vars[:default_Int] = TI
    header_vars[:default_Real] = TF
    header_vars[:file_identifier] = file.file_identifier
    header_vars[:COM_coordinate] = Float64[0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    header_vars[:Origin_sink_id] = Ref{Int64}(-1)
    header_vars[:Origin_sink_mass] = Ref{Float64}(NaN64)

    return header_vars
end

"""
    _merge_physical_blocks(block_data::Vector{DataFrame})

Merge non-sink physical blocks and preserve the second physical block as sink data.

Non-sink blocks are combined by assigning columns, not by appending rows. Later columns with the same name replace
earlier ones; columns retained in the same table must have compatible lengths. Return `(df, df_sinks)`.
"""
function _merge_physical_blocks(block_data :: Vector{DataFrame})
    df = DataFrame()
    df_sinks = DataFrame()

    for block_index in eachindex(block_data)
        block = block_data[block_index]

        # Preserve the original reader's assumption that block 2 contains sinks
        if block_index == 2
            df_sinks = block
        else
            for name in names(block)
                df[!, name] = block[!, name]
            end
        end
    end

    return df, df_sinks
end

"""
    read_phantom(filename::String; separate_types::Symbol=:sinks, ignore_inactive::Bool=true)

Read data from a Phantom native binary dump file.

The file is first indexed as a `PhantomFile`, then all particle columns are loaded with `read_all_columns`. Global
header values are stored in each returned `ParticleDataFrame.params` dictionary.

# Parameters
- `filename::String`: Path of the Phantom dump file to read.
- `separate_types::Symbol = :sinks`: Particle separation mode. `:sinks` returns ordinary and sink particles separately,
  when the sink table is nonempty. `:all` additionally groups ordinary particles by `itype` when that column contains
  multiple distinct values. Any other symbol concatenates the merged ordinary table and sink table by rows, using
  the union of their columns and filling absent values with `missing`.
- `ignore_inactive::Bool = true`: Keep only ordinary particles with `h > 0`, excluding zero as well as negative
  smoothing lengths. Sink particles are not filtered.

# Returns
- `Vector{ParticleDataFrame}`: For `:sinks` or `:all`, ordinary particle table(s), followed by a sink table when
  nonempty. Other symbols return a single combined table. A separate sink table is not guaranteed to be present.

# Examples
## Example 1: Separate ordinary particles and sinks in a dump containing sinks.
```julia
particles, sinks = read_phantom("dumpfile_00000")
```

## Example 2: Separate all particle types using `itype`.
```julia
particle_types = read_phantom("dumpfile_00000"; separate_types = :all)
```

# Notes
The second physical particle block is treated as sink data to preserve the behavior of the original reader.
Other physical blocks are merged by columns, with later same-name columns replacing earlier ones.
When `:all` creates multiple type groups, columns containing any `missing` values are removed from each group.
Only that grouping branch assigns a per-type `params[:mass]`; otherwise the ordinary or combined table stores
`nothing` for `:mass`.
"""
function read_phantom(filename :: String; separate_types :: Symbol = :sinks, ignore_inactive :: Bool = true)
    file = PhantomFile(filename)
    block_data = read_all_columns(file)
    df, df_sinks = _merge_physical_blocks(block_data)
    header_vars = _collect_header_params(file)

    # Ignore particles with negative smoothing length when requested
    if ignore_inactive
        df = df[df[!, :h] .> 0, :]
    end

    # Separate ordinary particles by itype when multiple types are present
    if (separate_types == :all) && hasproperty(df, :itype) && (length(unique(df.itype)) > 1)
        df_list = ParticleDataFrame[]
        for group in groupby(df, :itype)
            itype = Int(group[!, :itype][1])
            mass_key = (itype == 1) && haskey(header_vars, :massoftype) ? :massoftype : Symbol("massoftype_$(itype)")
            group_clean = select(group, [column for column in names(group) if !any(ismissing, group[!, column])])
            params_group = merge(header_vars, Dict(:mass => header_vars[mass_key]))
            params_group[:itype] = itype
            push!(df_list, ParticleDataFrame(group_clean, params_group))
        end

        if !isempty(df_sinks)
            push!(df_list, ParticleDataFrame(df_sinks, header_vars))
        end
        return df_list
    end

    # Keep sink particles in their own ParticleDataFrame when requested
    if ((separate_types == :sinks) || (separate_types == :all)) && !isempty(df_sinks)
        params = merge(header_vars, Dict(:mass => nothing))
        params[:itype] = NaN
        return ParticleDataFrame[ParticleDataFrame(df, params), ParticleDataFrame(df_sinks, header_vars)]
    end

    # Otherwise combine all physical particle blocks into one ParticleDataFrame
    combined_df = vcat(df, df_sinks, cols = :union)
    params = merge(header_vars, Dict(:mass => nothing))
    params[:itype] = nothing
    return ParticleDataFrame[ParticleDataFrame(combined_df, params)]
end
