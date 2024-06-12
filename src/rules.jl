using Metatheory

export and, or, not
@rewritetarget and(a, b)::Bool = a && b
@rewritetarget or(a, b)::Bool = a || b
@rewritetarget not(a)::Bool = !a

export logical_identities
logical_identities = @theory a b c begin
    and(a, true) --> a
    or(a, false) --> a

    and(a, false) --> false
    or(a, true) --> true

    and(a, a) --> a
    or(a, a) --> a

    not(not(a)) --> a

    and(a, b) --> and(b, a)
    or(a, b) --> or(b, a)

    and(a, and(b, c)) == and(and(a, b), c)
    or(a, or(b, c)) == or(or(a, b), c)

    and(a, or(b, c)) == or(and(a, b), and(b, c))
    or(a, and(b, c)) == and(or(a, b), or(b, c))

    not(and(a, b)) == or(not(a), not(b))
    not(or(a, b)) == and(not(a), not(b))

    and(a, or(a, b)) --> a
    or(a, and(a, b)) --> a

    and(a, not(a)) --> false
    or(a, not(a)) --> true
end

export band, bor, bnot, bxor, bnot, bnand
@rewritetarget band(a, b)::Integer = a & b
@rewritetarget bor(a, b)::Integer = a | b
@rewritetarget bnot(a)::Integer = ~a
@rewritetarget bxor(a, b)::Integer = a ⊻ b
@rewritetarget bnor(a, b)::Integer = a ⊽ b
@rewritetarget bnand(a, b)::Integer = a ⊼ b

export bitwise_identities
bitwise_identities = @theory a b c begin
    bor(a, 0) --> a
    band(a, 0) --> 0

    band(a, a) --> a
    bor(a, a) --> a

    bnot(bnot(a)) --> a

    band(a, b) --> band(b, a)
    bor(a, b) --> bor(b, a)
    bxor(a, b) --> bxor(b, a)
end

export add, sub, mul, pow
@rewritetarget add(a::Integer, b::Integer)::Integer = a + b
@rewritetarget sub(a::Integer, b::Integer)::Integer = a - b
@rewritetarget mul(a::Integer, b::Integer)::Integer = a * b
@rewritetarget div(a::Integer, b::Integer)::Integer = a ÷ b
@rewritetarget pow(a::Integer, b::Integer)::Integer = a ^ b

export math_identities
math_identities = @theory a b c begin
    add(a, b) --> add(b, a)
    mul(a, b) --> mul(b, a)

    add(a, add(b, c)) == add(add(a, b), c)
    mul(a, mul(b, c)) == mul(mul(a, b), c)

    sub(a, b) == add(a, mul(-1, b))

    add(a, 0) --> a
    mul(a, 0) => 0
    mul(a, 1) --> a

    add(a, a) == mul(2, a)
    sub(a, a) => 0

    mul(a, add(b, c)) == add(mul(a, b), mul(a, c))

    mul(pow(a, b), pow(a, c)) == pow(a, add(b, c))

    pow(a, 1) --> a
    pow(a, 2) == mul(a, a)

    mul(a, div(1, a)) --> a

    # Constant folding rules
    add(a::Integer, b::Integer) => a + b
    sub(a::Integer, b::Integer) => a - b
    mul(a::Integer, b::Integer) => a * b
    div(a::Integer, b::Integer) => a / b
    pow(a::Integer, b::Integer) => a^b
end

export rules
rules = logical_identities ∪ bitwise_identities ∪ math_identities
