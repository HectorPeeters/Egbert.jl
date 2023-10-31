using Core: MethodInstance, CodeInstance

const CC = Core.Compiler

struct CodeCache
    dict::IdDict{MethodInstance,Vector{CodeInstance}}

    CodeCache() = new(Dict{MethodInstance,Vector{CodeInstance}}())
end

Base.empty!(cc::CodeCache) = empty!(cc.dict)

function Base.show(cc::CodeCache)
    print("CodeCache with $(mapreduce(length, +, values(cc.dict); init=0)) entries")
    if !isempty(cc.dict)
        print(": ")
        for (mi, cis) in cc.dict
            println()
            print("  ")
            show(mi)

            function worldstr(min, max)
                if min == typemax(UInt)
                    "empty world range"
                elseif max == typemax(UInt)
                    "worlds $(Int(min))+"
                else
                    "worlds $(Int(min)) to $(Int(max))"
                end
            end

            for (_, ci) in enumerate(cis)
                println()
                print("    CodeInstance for ", worldstr(ci.min_world, ci.max_world))
            end
        end
    end
    println("\n")
end

function CC.setindex!(cache::CodeCache, ci::CodeInstance, mi::MethodInstance)
    cis = get!(cache.dict, mi, CodeInstance[])
    push!(cis, ci)
end


## world view of the cache

using Core.Compiler: WorldView

function CC.haskey(wvc::WorldView{CodeCache}, mi::MethodInstance)
    CC.get(wvc, mi, nothing) !== nothing
end

function CC.get(wvc::WorldView{CodeCache}, mi::MethodInstance, default)
    # check the cache
    for ci in get!(wvc.cache.dict, mi, CodeInstance[])
        if ci.min_world <= wvc.worlds.min_world && wvc.worlds.max_world <= ci.max_world
            # TODO: if (code && (code == jl_nothing || jl_ir_flag_inferred((jl_array_t*)code)))
            src = if ci.inferred isa Vector{UInt8}
                ccall(:jl_uncompress_ir, Any, (Any, Ptr{Cvoid}, Any),
                    mi.def, C_NULL, ci.inferred)
            else
                ci.inferred
            end
            return ci
        end
    end

    return default
end

function CC.getindex(wvc::WorldView{CodeCache}, mi::MethodInstance)
    r = CC.get(wvc, mi, nothing)
    r === nothing && throw(KeyError(mi))
    return r::CodeInstance
end

function CC.setindex!(wvc::WorldView{CodeCache}, ci::CodeInstance, mi::MethodInstance)
    src = if ci.inferred isa Vector{UInt8}
        ccall(:jl_uncompress_ir, Any, (Any, Ptr{Cvoid}, Any),
            mi.def, C_NULL, ci.inferred)
    else
        ci.inferred
    end
    CC.setindex!(wvc.cache, ci, mi)
end
