
"""
    logir(ir, ci, sv)

Log the IR code of a function if it is in the Main module.
"""
function logir(ir, _, sv)
    sv.inlining.interp.options.log_ir || return (ir, false)

    # Only log functions in the Main module
    if nameof(sv.src.parent.def.module) == :Main
        println("Function: ", sv.src.parent.def)
        println(ir)
    end

    return ir |> pass_changed
end

"""
    pass_changed(x)

Helper function to indicate that a pass has changed the IR code.
"""
pass_changed(x) = (x, true)

function pass_group(pm::CC.PassManager)
    return (ir::IRCode, ci::CC.CodeInfo, sv::OptimizationState) -> CC.run_passes(pm, ir, ci, sv)
end

function register_first_standard_pipeline!(pm::CC.PassManager)
    # Perform initial conversion to IRCode
    CC.register_pass!(pm, "slot2reg", CC.slot2reg)
    CC.register_condpass!(pm, "compact 1", (ir, _, _) ->
        CC.compact!(ir) |> pass_changed)

    # Perform first pass of normal optimization pipeline
    CC.register_pass!(pm, "inlining", (ir, ci, sv) ->
        CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds))
    CC.register_pass!(pm, "compact 2", (ir, _, _) ->
        CC.compact!(ir) |> pass_changed)
    CC.register_pass!(pm, "SROA", (ir, _, sv) ->
        CC.sroa_pass!(ir, sv.inlining) |> pass_changed)
    CC.register_pass!(pm, "ADCE", (ir, _, sv) ->
        CC.adce_pass!(ir, sv.inlining))
    CC.register_condpass!(pm, "compact 3", (ir, _, _) ->
        CC.compact!(ir, true) |> pass_changed)
end

function rewrite_fixedpoint_pass(ir, ci, sv)
    # Perform rewrite optimizations
    ir, rewrote = perform_rewrites!(ir, ci, sv)
    if rewrote
        ir = CC.compact!(ir, true)
    end

    # Clean up calls to wrapper methods
    ir, cleanedup = cleanup_wrappers!(ir, ci, sv)

    # Perform inlining and compact if we were able to clean up
    if rewrote || cleanedup
        ir, _ = CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds)
        ir = CC.compact!(ir)
    end

    return ir, (rewrote || cleanedup)
end

function register_second_standard_pipeline!(pm::CC.PassManager)
    CC.register_condpass!(pm, "SROA", (ir, _, sv) ->
        CC.sroa_pass!(ir, sv.inlining) |> pass_changed)
    CC.register_condpass!(pm, "ADCE", (ir, _, sv) ->
        CC.adce_pass!(ir, sv.inlining))
    CC.register_condpass!(pm, "compact 4", (ir, _, _) ->
        CC.compact!(ir, true) |> pass_changed)
end

function build_optimization_pipeline()
    pm = CC.PassManager()

    register_first_standard_pipeline!(pm)
    CC.register_fixedpointpass!(pm, "fixed point", rewrite_fixedpoint_pass)
    register_second_standard_pipeline!(pm)

    # Log the result of the optimizations
    CC.register_pass!(pm, "log", logir)

    if CC.is_asserts()
        CC.register_pass!(pm, "verify", (ir, _, sv) -> begin
            CC.verify_ir(ir, true, false,
                CC.optimizer_lattice(sv.inlining.interp))
            CC.verify_linetable(ir.linetable)
            return ir |> pass_changed
        end)
    end

    pm
end

const TIME = OrderedDict{String,Tuple{Float64,Int}}()

function time(name, x)
    function (ir, ci, sv)
        result = @timed x(ir, ci, sv)

        if !haskey(TIME, name)
            TIME[name] = (0.0, 0)
        end

        e = TIME[name]
        TIME[name] = (e[1] + result.time, e[2] + 1)

        result.value
    end
end

function print_pipeline_timings()
    for (name, (time, count)) in TIME
        println(name, ": ", time / count, " (", count, " runs)")
    end
end

function clear_pipeline_timings()
    empty!(TIME)
end

function build_timing_optimization_pipeline()
    pm = CC.PassManager()

    CC.register_pass!(pm, "standard opt pipeline",
        time("default1", pass_group(
            let pm = CC.PassManager()
                register_first_standard_pipeline!(pm)
                pm
            end
        ))
    )

    CC.register_fixedpointpass!(pm, "fixed point",
        time("fixedpoint", rewrite_fixedpoint_pass))

    CC.register_pass!(pm, "standard opt pipeline",
        time("default2", pass_group(
            let pm = CC.PassManager()
                register_second_standard_pipeline!(pm)
                pm
            end
        ))
    )

    # Log the result of the optimizations
    CC.register_pass!(pm, "log", logir)

    if CC.is_asserts()
        CC.register_pass!(pm, "verify", (ir, _, sv) -> begin
            CC.verify_ir(ir, true, false,
                CC.optimizer_lattice(sv.inlining.interp))
            CC.verify_linetable(ir.linetable)
            return ir |> pass_changed
        end)
    end

    return pm
end
