using .Core.Compiler: naive_idoms, IRCode, Argument

function is_call(instr, fname)
    return Meta.isexpr(instr, :call) &&
           instr.args[begin] isa GlobalRef &&
           instr.args[begin].name == fname
end

function is_invoke(instr, name)
    return Meta.isexpr(instr, :invoke) &&
           instr.args[begin].def.module == parentmodule(Module()) &&
           instr.args[begin].def.name == name
end

function perform_rewrites(ir::IRCode)
    instructions =
        @static if VERSION > v"1.10.0"
            ir.stmts.stmt
        else
            ir.stmts.inst
        end

    println(ir)

    for instruction in instructions
        if is_invoke(instruction, Symbol(:add))
            println("Found add invocation")
            arg1 = instruction.args[3]
            arg2 = instruction.args[4]

            if arg2 isa SSAValue
                instruction2 = instructions[arg2.id]
                if is_invoke(instruction2, Symbol(:mul))
                    println("Found add-mul invocation")

                    println(instruction.args[begin])
                    # instruction.args[begin] = GlobalRef(Main, :add_mul)
                    # instruction.args[2] = GlobalRef(Main, :add_mul)
                    # instruction.args[4] = instruction2.args[3]
                    # push!(instruction.args, instruction2.args[4])
                    println("Rewrote to add_mul")
                end
            end
        end

        if is_call(instruction, Symbol(Base.add_int))
            args = instruction.args[begin+1:end]
            @assert length(args) == 2

            if args[1] isa Argument && args[2] isa Argument
                if args[1].n == args[2].n
                    instruction.args[1] = GlobalRef(Base, :shl_int)
                    instruction.args[3] = 1
                    println("Performing rewrite on $(instruction)")
                end
            end
        end
    end

    println(ir)

    return ir
end
