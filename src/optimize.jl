using Core.Compiler: naive_idoms, IRCode, Argument

function is_call(instr, fname)
    instr isa Expr || return false
    instr.head == :call || return false
    instr.args[begin] isa GlobalRef || return false
    instr.args[begin].name == fname || return false
    return true
end

function perform_rewrites(ir::IRCode, ci, sv)
    for instruction in ir.stmts.stmt

        if is_call(instruction, Symbol(Base.add_int))
            args = instruction.args[begin+1:end]
            @assert length(args) == 2

            if args[1] isa Argument && args[2] isa Argument
                if args[1].n == args[2].n
                    instruction.args[1] = GlobalRef(Base, :shl_int)
                    instruction.args[3] = 1
                end
            end
        end
    end

    return ir
end
