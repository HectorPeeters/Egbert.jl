macro rewritetarget(func::Expr)
    # If a return type isn't included in the function, the name of the function is nested 
    # one additional level. We need the return type to be explicitly stated as that
    # information is lost when using the `Base.compilerbarrier`.
    if func.args[begin].args[begin] isa Symbol
        return error("Please add a return type to the function")
    end

    # Full signature of function including name and return type
    signature = func.args[begin]
    # Signature of function without return type
    signature_noret = signature.args[begin]

    func_name = signature_noret.args[begin]
    args = signature_noret.args[2:end]
    ret_type = signature.args[2]

    # Return a wrapper around the function that encapsulates the original implementation
    # inside of a `Base.compilerbarrier`.
    return esc(quote
        function $func_name($(args...))::$ret_type
            return Base.compilerbarrier(:type, $(func))($(args...))
        end
    end)
end

# TODO: fix upstream
function unsafe_function_from_type(ft::Type)
    if isdefined(ft, :instance)
        ft.instance
    else
        # HACK: dealing with a closure or something... let's do somthing really invalid,
        #       which works because MethodError doesn't actually use the function
        Ref{ft}()[]
    end
end

function MethodError(ft::Type{<:Function}, tt::Type, world::Integer=typemax(UInt))
    Base.MethodError(unsafe_function_from_type(ft), tt, world)
end

MethodError(ft, tt, world=typemax(UInt)) = Base.MethodError(ft, tt, world)
