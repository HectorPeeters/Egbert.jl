function unsafe_function_from_type(ft::Type)
    if isdefined(ft, :instance)
        ft.instance
    else
        # HACK: dealing with a closure or something... let's do somthing really 
        #       invalid, which works because MethodError doesn't actually use
        #       the function
        Ref{ft}()[]
    end
end

"""
  MethodError(ft::Type{<:Function}, tt::Type, world::Integer)

Constructor for Base.Method error used by the interfacing macro.  
"""
function MethodError(
    ft::Type{<:Function},
    tt::Type,
    world::Integer=typemax(UInt)
)
    Base.MethodError(unsafe_function_from_type(ft), tt, world)
end

MethodError(ft, tt, world=typemax(UInt)) = Base.MethodError(ft, tt, world)
