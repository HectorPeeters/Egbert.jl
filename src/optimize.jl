using Core.Compiler: naive_idoms, IRCode

function perform_rewrites(ir::IRCode, ci, sv)
    println(naive_idoms(ir.cfg.blocks))

    println("IR before:\n", ir)

    # Iterate over all instructions
    for instruction in ir.stmts.stmt

        # Check if we have a call instruction
        if instruction isa Expr && instruction.head == :call

            # Check if we have a call to Base.add_int
            if instruction.args[begin] isa GlobalRef &&
               instruction.args[begin].name == Symbol(Base.add_int)

                # Rewrite Base.add_int to Base.sub_int
                instruction.args[begin] = GlobalRef(Base, :sub_int)
                println("\tRewritten add_int to sub_int")

                # Determine all argment expressions of this call
                args = instruction.args[begin+1:end]
                for arg in args
                    if arg isa Symbol
                        println("We have a symbol: ", arg)
                    end
                    if arg isa SSAValue
                        arg_instr_stream = ir[arg]
                        arg_instr = arg_instr_stream.data.stmt[arg_instr_stream.idx]

                        println("\tArgument ", arg.id, ": ", arg_instr)
                    end
                end
            end
        end
    end

    println("IR after:\n", ir)
    return ir
end
