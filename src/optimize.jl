using .Core.Compiler: naive_idoms, IRCode, Argument
using Metatheory.EGraphs
using Metatheory


"""
    perform_rewrites!(ir::IRCode, ci::CC.CodeInfo, rules::Any)

Perform e-graph rewrite optimizations on the given IR code using the specified 
rules.
"""
function perform_rewrites!(
    ir::IRCode, ci::CC.CodeInfo, sv::OptimizationState)

    # Only optimize functions defined in the Main module
    if ci.parent.def.module != Main
        return ir, false
    end

    cfg = ir.cfg

    # Currently, we only support functions with a single block
    if length(cfg.blocks) != 1
        @debug "Skipping function `$(ci.parent.def.name)` with multiple blocks: $(size(cfg.blocks))"
        return ir, false
    end

    made_changes = false

    interp = sv.inlining.interp

    for (i, block) in enumerate(cfg.blocks)
        # Convert the IR block to an expression tree
        irtoexpr = IrToExpr(ir.stmts, block.stmts)
        irexpr = get_root_expr!(irtoexpr)

        # Create an e-graph from the expression tree
        g = EGraph{IRExpr, Nothing}(irexpr)
        # settermtype!(g, IRExpr)

        # Saturate the e-graph using the rewrite rules defined in the macro call
        sat_result = saturate!(g, interp.rules, interp.options.saturation_params)

        # Print the saturation results when configured
        if interp.options.print_sat_info
            println(sat_result)
        end

        # Extract the optimal expression based on the analysis function
        result = extract!(g, interp.options.analysis_ref)

        # Extract the optimized expression from the e-graph
        exprtoir = ExprToIr(ci.parent.def.module, block.stmts)

        # Convert the optimized expression back to IR
        (optim_instr, optim_types) = expr_to_ir!(exprtoir, result)

        # NOTE: This is not the best way to check for changes. Initially,
        #       the cost of the expression was determined but this does
        #       not take into account the CSE functionality.
        length(optim_instr) == length(block.stmts) && continue
        made_changes = true

        if length(optim_instr) > length(block.stmts)
            # TODO: we need to resize in the middle of the instruction stream 
            #       here. However, this case currently shouldn't be possible as 
            #       we use the astsize cost function.
            error("New block is larger than old block: ",
                size(block.stmts), " -> ", size(optim_instr))
        end

        # Patch the optimized instructions back into the IR code
        for (i, instr) in enumerate(optim_instr)
            target_i = i + block.stmts.start - 1

            ir.stmts.stmt[target_i] = instr
            ir.stmts.type[target_i] = optim_types[i]
            ir.stmts.info[target_i] = CC.NoCallInfo()
            ir.stmts.flag[target_i] = CC.IR_FLAG_REFINED
        end

        # Remove any remaining instructions
        for i in length(optim_instr)+1:length(block.stmts)
            target_i = i + block.stmts.start - 1
            ir.stmts.stmt[target_i] = nothing
            ir.stmts.type[target_i] = Nothing
            ir.stmts.info[target_i] = CC.NoCallInfo()
            ir.stmts.flag[target_i] = CC.IR_FLAG_NULL
            ir.stmts.line[target_i] = 0
        end
    end

    println(sv.src.parent.def)
    println(ir)

    # If any changes were made to the IR, we have to rerun type inference to infer 
    # all new method calls. This also makes them susceptible to inlining later on
    # in the pipeline.
    if made_changes
        method_info = CC.MethodInfo(ci)
        world = Base.get_world_counter()
        max_world = typemax(UInt64)
        irstate = CC.IRInterpretationState(interp, method_info, ir, ci.parent, ci.slottypes, world, world, max_world)

       CC.ir_abstract_constant_propagation(interp, irstate)
    end

    return ir, made_changes
end
