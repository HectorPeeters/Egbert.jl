using .Core: MethodInstance, CodeInstance

const CC = Core.Compiler

"""
Code cache used by the custom abstract interpreter. It stores relations between
MethodInstances and their corresponding CodeInstances. 
"""
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


function CC.haskey(wvc::CC.WorldView{CodeCache}, mi::MethodInstance)
    CC.get(wvc, mi, nothing) !== nothing
end

function CC.get(wvc::CC.WorldView{CodeCache}, mi::MethodInstance, default)
    # Check if it is present in the cache
    for ci in get!(wvc.cache.dict, mi, CodeInstance[])

        # For ever CodeInstance, filter the ones with a valid world
        if ci.min_world > wvc.worlds.min_world || wvc.worlds.max_world > ci.max_world
            continue
        end

        # Uncompress the IR if necessary
        src = if ci.inferred isa Vector{UInt8}
            ccall(:jl_uncompress_ir, Any, (Any, Ptr{Cvoid}, Any),
                mi.def, C_NULL, ci.inferred)
        else
            ci.inferred
        end

        return ci
    end

    return default
end

function CC.getindex(wvc::CC.WorldView{CodeCache}, mi::MethodInstance)
    r = CC.get(wvc, mi, nothing)
    r === nothing && throw(KeyError(mi))
    return r::CodeInstance
end

function CC.setindex!(wvc::CC.WorldView{CodeCache}, ci::CodeInstance, mi::MethodInstance)
    # Uncompress IR if necessary
    src = if ci.inferred isa Vector{UInt8}
        ccall(:jl_uncompress_ir, Any, (Any, Ptr{Cvoid}, Any),
            mi.def, C_NULL, ci.inferred)
    else
        ci.inferred
    end

    CC.setindex!(wvc.cache, ci, mi)
end
