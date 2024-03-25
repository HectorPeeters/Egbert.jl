function logir(ir, _, sv)
    # Only log functions in the Main module
    if nameof(sv.src.parent.def.module) == :Main
        println("Function: ", sv.src.parent.def)
        println(ir)
    end

    return ir |> pass_changed
end

function logstacktrace(ir, _, _)
    println("\n\nStacktrace:")
    for entry in stacktrace()
        println(entry)
    end
    return ir |> pass_changed
end

pass_changed(x) = (x, true)

function rewrite_opt_pipeline()
    pm = CC.PassManager()

    CC.register_pass!(pm, "to ircode", (_, ci, sv) -> CC.convert_to_ircode(ci, sv) |> pass_changed)
    CC.register_pass!(pm, "slot2reg", (ir, ci, sv) -> CC.slot2reg(ir, ci, sv) |> pass_changed)
    CC.register_pass!(pm, "compact 1", (ir, _, _) -> CC.compact!(ir) |> pass_changed)

    CC.register_pass!(pm, "inlining", (ir, ci, sv) -> CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds) |> pass_changed)
    CC.register_pass!(pm, "compact 2", (ir, _, _) -> CC.compact!(ir) |> pass_changed)

    CC.register_pass!(pm, "SROA", (ir, _, sv) -> CC.sroa_pass!(ir, sv.inlining) |> pass_changed)
    CC.register_pass!(pm, "ADCE", (ir, _, sv) -> CC.adce_pass!(ir, sv.inlining))
    CC.register_condpass!(pm, "compact 3", (ir, _, _) -> CC.compact!(ir, true) |> pass_changed)

    CC.register_fixedpointpass!(pm, "rewrite", function (ir, ci, sv)
        ir, changed = perform_rewrites!(ir)
        if changed
            ir = CC.compact!(ir)
        end
        return ir, changed
    end)

    CC.register_pass!(pm, "inlining", (ir, ci, sv) -> CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds) |> pass_changed)
    CC.register_pass!(pm, "compact 2", (ir, _, _) -> CC.compact!(ir) |> pass_changed)

    CC.register_pass!(pm, "log", logir)

    # TODO: remove || true
    if CC.is_asserts() || true
        CC.register_pass!(pm, "verify", (ir, _, sv) -> begin
            CC.verify_ir(ir, true, false, CC.optimizer_lattice(sv.inlining.interp))
            CC.verify_linetable(ir.linetable)
            return ir |> pass_changed
        end)
    end

    return pm
end

function cleanup_opt_pipeline()
    pm = CC.PassManager()

    CC.register_pass!(pm, "to ircode", (_, _, sv) -> sv.ir |> pass_changed)

    CC.register_pass!(pm, "strip compbarrier", (ir, _, _) -> strip_compbarrier!(ir))

    # TODO: all these passes don't have to run if strip_compbarrier! did nothing
    CC.register_condpass!(pm, "compact 1", (ir, _, _) -> CC.compact!(ir) |> pass_changed)
    CC.register_pass!(pm, "inlining", (ir, ci, sv) -> CC.ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds) |> pass_changed)
    CC.register_pass!(pm, "compact 2", (ir, _, _) -> CC.compact!(ir) |> pass_changed)
    CC.register_pass!(pm, "SROA", (ir, _, sv) -> CC.sroa_pass!(ir, sv.inlining) |> pass_changed)
    CC.register_pass!(pm, "ADCE", (ir, _, sv) -> CC.adce_pass!(ir, sv.inlining))
    CC.register_condpass!(pm, "compact 3", (ir, _, _) -> CC.compact!(ir, true) |> pass_changed)

    CC.register_pass!(pm, "log", logir)

    # TODO: remove || true
    if CC.is_asserts() || true
        CC.register_pass!(pm, "verify", (ir, _, sv) -> begin
            CC.verify_ir(ir, true, false, CC.optimizer_lattice(sv.inlining.interp))
            CC.verify_linetable(ir.linetable)
            return ir |> pass_changed
        end)
    end

    return pm
end
