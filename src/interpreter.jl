struct CustomInterpreter <: CC.AbstractInterpreter
    world::UInt

    code_cache::CodeCache
    inf_cache::Vector{CC.InferenceResult}

    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams
end

function CustomInterpreter(world::UInt;
    code_cache::CodeCache,
    inf_params::CC.InferenceParams,
    opt_params::CC.OptimizationParams)
    @assert world <= Base.get_world_counter()

    inf_cache = Vector{CC.InferenceResult}()

    return CustomInterpreter(world,
        code_cache, inf_cache,
        inf_params, opt_params)
end

CC.InferenceParams(interp::CustomInterpreter) = interp.inf_params
CC.OptimizationParams(interp::CustomInterpreter) = interp.opt_params
CC.get_world_counter(interp::CustomInterpreter) = interp.world
CC.get_inference_cache(interp::CustomInterpreter) = interp.inf_cache
CC.code_cache(interp::CustomInterpreter) = WorldView(interp.code_cache, interp.world)
function CC.build_opt_pipeline(::CustomInterpreter)
    pm = CC.PassManager()

    CC.register_pass!(pm, "slot2reg", CC.slot2reg)
    CC.register_pass!(pm, "compact 1", (ir, ci, sv) -> CC.compact!(ir))
    CC.register_pass!(pm, "Inlining", (ir, ci, sv) -> CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds))
    CC.register_pass!(pm, "compact 2", (ir, ci, sv) -> CC.compact!(ir))
    CC.register_pass!(pm, "rewrite", perform_rewrites)
    CC.register_pass!(pm, "SROA", (ir, ci, sv) -> CC.sroa_pass!(ir, sv.inlining))
    CC.register_pass!(pm, "ADCE", (ir, ci, sv) -> CC.adce_pass!(ir, sv.inlining))
    CC.register_pass!(pm, "compact 2", (ir, ci, sv) -> CC.compact!(ir, true))
    CC.register_pass!(pm, "verify 3", function (ir, ci, sv)
        CC.verify_ir(ir, true, false, CC.optimizer_lattice(sv.inlining.interp))
        CC.verify_linetable(ir.linetable)
        return ir
    end)

    return pm
end

CC.lock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing
CC.unlock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing

function CC.add_remark!(::CustomInterpreter, sv::CC.InferenceState, msg)
    @debug "Inference remark during GPU compilation of $(sv.linfo): $msg"
end

CC.may_optimize(interp::CustomInterpreter) = true
CC.may_compress(interp::CustomInterpreter) = true
CC.may_discard_trees(interp::CustomInterpreter) = true
CC.verbose_stmt_info(interp::CustomInterpreter) = false
