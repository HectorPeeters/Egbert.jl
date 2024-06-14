using .Core.Compiler: OptimizationState, InferenceResult, InferenceState
using Metatheory: astsize, SaturationParams

export Options
struct Options
    """
    The cost function used during the e-graph extraction. 
    """
    analysis_ref::Function

    """
    The name of the cost function used during e-graph extraction. This won't be
    needed anymore for the 3.0 version of Metatheory.
    """
    analysis_name::Symbol

    """
    The saturation parameters for the e-graph saturation process. 
    """
    saturation_params::SaturationParams

    """
    The optimization pipeline to use during compilation. The default one can be
    swapped out for one that includes timings for all major parts of the pipeline.
    """
    opt_pipeline::CC.PassManager

    """
    Whether caching should be enabled. This disables both the internal caching of
    the compiled function as well as the closure cache included in this package.
    """
    enable_caching::Bool

    """
    Whether to run the code after compilation. If this flag is false, a closure will
    be returned that can be executed at a later point.
    """
    dont_run::Bool

    """
    Whether to output statistics about the e-graph saturation process.
    """
    print_sat_info::Bool

    """
    Whether to output the generated IR after performing the full optimization pipeline.
    """
    log_ir::Bool

    """
    Whether to print the AST cost before and after every e-graph optimization.
    """
    print_ast_cost::Bool

    function Options(;
        analysis_ref=astsize,
        analysis_name=:astsize,
        saturation_params=SaturationParams(),
        opt_pipeline=build_optimization_pipeline(),
        enable_caching=true,
        dont_run=false,
        print_sat_info=false,
        log_ir=false,
        print_ast_cost=false
    )
        new(
            analysis_ref,
            analysis_name,
            saturation_params,
            opt_pipeline,
            enable_caching,
            dont_run,
            print_sat_info,
            log_ir,
            print_ast_cost
        )
    end
end


struct CustomInterpreterToken end


mutable struct CustomInterpreter <: CC.AbstractInterpreter
    world::UInt

    code_cache::CodeCache
    inf_cache::Vector{CC.InferenceResult}

    inf_params::CC.InferenceParams
    opt_params::CC.OptimizationParams

    frame_cache::Vector{CC.InferenceState}

    """
    The list of rewrite rules to use for this interpreter. 
    """
    rules::Any

    """
    The configuration options for this interpreter.  
    """
    options::Options

    function CustomInterpreter(world::UInt;
        code_cache::CodeCache,
        inf_params::CC.InferenceParams,
        opt_params::CC.OptimizationParams,
        rules,
        options::Options
    )
        @assert world <= Base.get_world_counter()

        inf_cache = Vector{CC.InferenceResult}()
        frame_cache = Vector{CC.InferenceState}()

        return new(
            world,
            code_cache,
            inf_cache,
            inf_params,
            opt_params,
            frame_cache,
            rules,
            options
        )
    end

end

CC.InferenceParams(interp::CustomInterpreter) = interp.inf_params
CC.OptimizationParams(interp::CustomInterpreter) = interp.opt_params
CC.get_inference_world(interp::CustomInterpreter) = interp.world
CC.get_inference_cache(interp::CustomInterpreter) = interp.inf_cache
CC.code_cache(interp::CustomInterpreter) = CC.WorldView(interp.code_cache, interp.world)
CC.cache_owner(::CustomInterpreter) = CustomInterpreterToken

CC.build_opt_pipeline(interp::CustomInterpreter) = interp.options.opt_pipeline

CC.lock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing
CC.unlock_mi_inference(::CustomInterpreter, ::MethodInstance) = nothing

function CC.add_remark!(::CustomInterpreter, sv::CC.InferenceState, msg)
    @debug "Inference remark during compilation of $(sv.linfo): $msg"
end

CC.may_optimize(interp::CustomInterpreter) = true
CC.may_compress(interp::CustomInterpreter) = true
CC.may_discard_trees(interp::CustomInterpreter) = true
CC.verbose_stmt_info(interp::CustomInterpreter) = false
