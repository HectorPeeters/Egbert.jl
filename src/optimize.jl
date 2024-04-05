using .Core.Compiler: naive_idoms, IRCode, Argument
using Metatheory
using Metatheory.EGraphs

const RewriteRule = Any

"""
    instrs(ir::IRCode)

Get the instructions from an IRCode object.
"""
@inline function instrs(ir::IRCode)
    @static if VERSION > v"1.10.0"
        return ir.stmts.stmt
    else
        return ir.stmts.inst
    end
end

"""
    is_call(instr, name)

Check if an instruction is an call instruction with a
specific name.
"""
function is_call(instr, fname)
    return Meta.isexpr(instr, :call) &&
           instr.args[begin] isa GlobalRef &&
           instr.args[begin].name == fname
end

"""
    is_invoke(instr, name)

Check if an instruction is an invoke instruction with a
specific name.
"""
function is_invoke(instr, name)
    return Meta.isexpr(instr, :invoke) &&
           instr.args[begin].def.module == parentmodule(Module()) &&
           instr.args[begin].def.name == name
end

"""
    markdead!(ir::IRCode, id)

Mark an instruction as dead. It will be replaced by a load
of a `nothing` value. This will then later be removed by the
`compact` IR pass.
"""
function markdead!(ir::IRCode, id)
    # TODO: This is still somewhat flawed, computation of arguments
    #       for the removed call might not be necessary.
    instrs(ir)[id] = Main.nothing
    ir.stmts.type[id] = Core.Const(nothing)
end


function EGraphs.egraph_reconstruct_expression(::Type{IRExpr}, op, args; metadata=nothing, exprhead=nothing)
    IRExpr(op, args, metadata)
end

function perform_rewrites!(ir::IRCode, ci::CC.CodeInfo, rules::Any)
    if ci.parent.def.module != Main
        return ir, false
    end

    cfg = CC.compute_basic_blocks(ir.stmts.stmt)

    if length(cfg.blocks) != 1
        @warn "Skipping function with multiple blocks: $(size(cfg.blocks))"
        return ir, false
    end

    # TODO: setting the IR_FLAG_REFINED might result in better code analysis

    made_changes = false

    for (i, block) in enumerate(cfg.blocks)
        @info "Processing block $i"

        irtoexpr = IrToExpr(ir.stmts.stmt, ir.stmts.type, block.stmts)
        irexpr = get_root_expr!(irtoexpr)

        g = EGraph(irexpr; keepmeta=true)
        settermtype!(g, IRExpr)

        saturate!(g, rules)

        result = extract!(g, astsize)

        if result == irexpr
            continue
        end

        made_changes = true

        exprtoir = ExprToIr(ci.parent.def.module, block.stmts)
        (optim_instr, optim_types) = expr_to_ir!(exprtoir, result)

        if length(optim_instr) > length(block.stmts)
            # TODO: we need to resize in the middle of the instruction stream here
            #       However, this case currently shouldn't be possible as we use the
            #       astsize cost function.
            error("New block is larger than old block: ", size(block.stmts), " -> ", size(optim_instr))
        end

        for (i, instr) in enumerate(optim_instr)
            ir.stmts.stmt[i+block.stmts.start-1] = instr
            ir.stmts.type[i+block.stmts.start-1] = optim_types[i]
            ir.stmts.info[i+block.stmts.start-1] = CC.NoCallInfo()
            ir.stmts.flag[i+block.stmts.start-1] = CC.IR_FLAG_NULL
        end

        for i in length(optim_instr)+1:length(block.stmts)
            ir.stmts.stmt[i+block.stmts.start-1] = nothing
            ir.stmts.type[i+block.stmts.start-1] = Any
            ir.stmts.info[i+block.stmts.start-1] = CC.NoCallInfo()
            ir.stmts.flag[i+block.stmts.start-1] = CC.IR_FLAG_NULL
        end

        println(ir)
    end

    return ir, made_changes
end