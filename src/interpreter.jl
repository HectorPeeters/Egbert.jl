using .Core.Compiler: OptimizationState, InferenceResult, InferenceState

mutable struct CustomInterpreter <: CC.AbstractInterpreter
    world::UInt

    code_cache::CodeCache
    inf_cache::Vector{CC.InferenceResult}

    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams

    frame_cache::Vector{CC.InferenceState}
    opt_pipeline::Function

    rules::Any
end

function CustomInterpreter(world::UInt;
    code_cache::CodeCache,
    inf_params::CC.InferenceParams,
    opt_params::CC.OptimizationParams,
    rules)
    @assert world <= Base.get_world_counter()

    inf_cache = Vector{CC.InferenceResult}()

    frame_cache = Vector{CC.InferenceState}()
    opt_pipeline = optimization_pipeline

    return CustomInterpreter(
        world,
        code_cache,
        inf_cache,
        inf_params,
        opt_params,
        frame_cache,
        opt_pipeline,
        rules
    )
end

CC.InferenceParams(interp::CustomInterpreter) = interp.inf_params
CC.OptimizationParams(interp::CustomInterpreter) = interp.opt_params
CC.get_inference_world(interp::CustomInterpreter) = interp.world
CC.get_inference_cache(interp::CustomInterpreter) = interp.inf_cache
CC.code_cache(interp::CustomInterpreter) = CC.WorldView(interp.code_cache, interp.world)
CC.cache_owner(_::CustomInterpreter) = nothing

CC.build_opt_pipeline(interp::CustomInterpreter) = interp.opt_pipeline(interp)

CC.lock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing
CC.unlock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing

function CC.add_remark!(::CustomInterpreter, sv::CC.InferenceState, msg)
    @debug "Inference remark during GPU compilation of $(sv.linfo): $msg"
end

CC.may_optimize(interp::CustomInterpreter) = true
CC.may_compress(interp::CustomInterpreter) = false
CC.may_discard_trees(interp::CustomInterpreter) = true
CC.verbose_stmt_info(interp::CustomInterpreter) = false
