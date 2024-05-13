using Metatheory

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
