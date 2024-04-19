# This file contains a simple example of the compilerbarrier macro

macro testmacro(func::Expr)
    if func.args[begin].args[begin] isa Symbol
        return error("Please add a returntype to the function")
    end

    func_name = func.args[begin].args[begin].args[begin]
    args = func.args[begin].args[begin].args[2:end]
    ret_type = func.args[begin].args[2]

    return esc(quote
        function $func_name($(args...))::$ret_type
            return Base.compilerbarrier(:type, $(func))($(args...))
        end
    end)
end

@testmacro function add(a::Int, b::Int)::Int
    return a + b
end

@testmacro function sub(a::Int, b::Int)::Int
    return a - b
end

function usecase()
    add(14, sub(13, 12))
end

println(Base.code_ircode(usecase))
