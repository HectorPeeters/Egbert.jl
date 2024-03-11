using .Core.Compiler: OptimizationState, InferenceResult, InferenceState

mutable struct CustomInterpreter <: CC.AbstractInterpreter
    world::UInt

    code_cache::CodeCache
    inf_cache::Vector{CC.InferenceResult}

    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams

    # TODO: this should probably be a set
    frame_cache::Vector{CC.InferenceState}
    opt_pipeline::CC.PassManager
end

function CustomInterpreter(world::UInt;
    code_cache::CodeCache,
    inf_params::CC.InferenceParams,
    opt_params::CC.OptimizationParams)
    @assert world <= Base.get_world_counter()

    inf_cache = Vector{CC.InferenceResult}()

    frame_cache = Vector{CC.InferenceState}()
    opt_pipeline = rewrite_opt_pipeline()

    return CustomInterpreter(
        world,
        code_cache,
        inf_cache,
        inf_params,
        opt_params,
        frame_cache,
        opt_pipeline
    )
end

CC.InferenceParams(interp::CustomInterpreter) = interp.inf_params
CC.OptimizationParams(interp::CustomInterpreter) = interp.opt_params
CC.get_inference_world(interp::CustomInterpreter) = interp.world
CC.get_inference_cache(interp::CustomInterpreter) = interp.inf_cache
CC.code_cache(interp::CustomInterpreter) = WorldView(interp.code_cache, interp.world)
CC.cache_owner(_::CustomInterpreter) = nothing

CC.build_opt_pipeline(interp::CustomInterpreter) = interp.opt_pipeline

CC.lock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing
CC.unlock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing

function CC.add_remark!(::CustomInterpreter, sv::CC.InferenceState, msg)
    @debug "Inference remark during GPU compilation of $(sv.linfo): $msg"
end

CC.may_optimize(interp::CustomInterpreter) = true
CC.may_compress(interp::CustomInterpreter) = false
CC.may_discard_trees(interp::CustomInterpreter) = true
CC.verbose_stmt_info(interp::CustomInterpreter) = false

function CC.typeinf(interp::CustomInterpreter, frame::InferenceState)
    CC.typeinf_nocycle(interp, frame) || return false # frame is now part of a higher cycle

    # with no active ip's, frame is done
    frames = frame.callers_in_cycle
    isempty(frames) && push!(frames, frame)
    valid_worlds = CC.WorldRange()
    for caller in frames
        push!(interp.frame_cache, caller)

        @assert !(caller.dont_work_on_me)
        caller.dont_work_on_me = true
        # might might not fully intersect these earlier, so do that now
        valid_worlds = CC.intersect(caller.valid_worlds, valid_worlds)
    end
    for caller in frames
        caller.valid_worlds = valid_worlds
        CC.finish(caller, caller.interp)
    end

    for caller in frames
        opt = caller.result.src
        if opt isa OptimizationState
            CC.optimize(caller.interp, opt, caller.result)
        end
    end

    # NOTE: The cleanup implementation is removed here. This is handled at the
    #       end of all method optimizations (first pass) in combination with 
    #       the second optimization pass (cleanup).

    empty!(frames)
    return true
end
