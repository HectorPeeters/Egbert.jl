using Core: OpaqueClosure, SSAValue
using Core.Compiler: naive_idoms, IRCode

const global_ci_cache = CodeCache()

macro custom(ex)
    Meta.isexpr(ex, :call) || error("not a function call")
    f, args... = ex.args

    quote
        f = $(esc(f))
        @assert sizeof(f) == 0 "OpaqueClosures have different semantics wrt. captures, and cannot be used to implement closures with an environment"
        args = ($(esc(args))...,)

        ft = typeof(f)
        types = map(args) do x
            if x isa Symbol || x isa Expr
                typeof(eval(x))
            else
                typeof(x)
            end
        end
        obj = custom_compiler(ft, types)

        obj(args...)
    end
end

function custom_compiler(ft, types)
    tt = Tuple{types...}
    sig = Tuple{ft,types...}
    world = Base.get_world_counter()

    interp = CustomInterpreter(world;
        code_cache=global_ci_cache,
        inf_params=CC.InferenceParams(),
        opt_params=CC.OptimizationParams())

    irs = Base.code_ircode_by_type(sig; interp)
    if isempty(irs)
        throw(MethodError(ft, tt, world))
    end

    show(interp.code_cache)

    ir::IRCode, ret = irs[1]

    println(naive_idoms(ir.cfg.blocks))

    println("IR before (return type $(ret)):\n", ir)

    # Iterate over all instructions
    for instruction in ir.stmts.stmt

        # Check if we have a call instruction
        if instruction isa Expr && instruction.head == :call

            # Check if we have a call to Base.add_int
            if instruction.args[begin] isa GlobalRef &&
               instruction.args[begin].name == Symbol(Base.add_int)

                # Rewrite Base.add_int to Base.sub_int
                # instruction.args[begin] = GlobalRef(Base, :sub_int)
                # println("\tRewritten add_int to sub_int")

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

    println("IR after (return type $(ret)):\n", ir)

    OpaqueClosure(ir)
end
