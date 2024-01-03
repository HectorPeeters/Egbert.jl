using .Core.Compiler: naive_idoms, IRCode, Argument

function is_call(instr, fname)
    return instr isa Expr &&
           instr.head == :call &&
           instr.args[begin] isa GlobalRef &&
           instr.args[begin].name == fname
end

function perform_rewrites(ir::IRCode)
    instructions =
        @static if VERSION > v"1.10.0"
            ir.stmts.stmt
        else
            ir.stmts.inst
        end

    for instruction in instructions

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
