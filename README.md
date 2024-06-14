# Egbert.jl

<p><img src="https://upload.wikimedia.org/wikipedia/commons/c/ca/Egbert.jpg" height="150px" align="right" valign="middle" vspace="5" hspace="5"/>
Egbert.jl (E-Graph-Based Expression Rewrite Tool) is an optimization framework developed for my masters thesis at Ghent University. It uses e-graphs and equality saturation to optimize a function with a set of rewrite rules.

The optimization process used in this project uses the e-graph implementation found in [Metatheory.jl](https://github.com/JuliaSymbolics/Metatheory.jl/) and lends many ideas and techniques from the [Cranelift](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/README.md) project.
</p>


## Running

Running this optimizer requires a custom build of the Julia compiler. This custom version includes a pass manager which allows for the optimization pipeline to be changed at run time.

This fork of the Julia compiler can be found at [HectorPeeters/julia](https://github.com/HectorPeeters/julia). The required changes are on the [pass-manager](https://github.com/HectorPeeters/julia/tree/pass-manager) branch, while the original commit [29a58d5](https://github.com/HectorPeeters/julia/commit/29a58d5c4a5943774984ba83b2a84f98ff377a73) from which all changes for the pass manager have been made is marked using the [baseline](https://github.com/HectorPeeters/julia/releases/tag/baseline) tag.

The normal Julia [build instructions](https://github.com/HectorPeeters/julia/tree/master#building-julia) (i.e. running `make`) should be sufficient for compiling this fork.

This custom version can be added to juliaup using the following command:

```bash
juliaup link <name-of-version> <path-to-version>
```

### Tests

All tests of the project are contained within the `test/` folder. Running all of the tests at once can be done using the following command:

```bash
julia +<name-of-version> --project=. test/all.jl
```

Tests can also be run individually using the corresponding filename instead of `test/all.jl`.

Observing the generated IR for each test can be done by adding the `log_ir=true` parameter to the `Options` property passed to the `@optimize` macro.

### Benchmarks

The benchmarks are stored in the `benches/` folder. Executing a benchmark can be done in the same manner as running the tests. Running the benchmarks from the REPL is not recommended to reduced any caching related performance fluctuations.

All benchmarks run the evaluations for multiple different input sizes and either output a CSV file of the results or print them to the console. One exception is `benches/astsize.jl`, which requires manually changing the size of the input in the code as this generates an expression tree at compile time using a macro.

### Metatheory 3.0

With the guidance of Alessandro Cheli, one of the developers of Metatheory, I started the conversion to Metatheory 3.0. This version is currently still in beta but ships with many bug fixes and performance improvements. While this resulted in cleaner and more efficient code, the optimizer using Metatheory 3.0 did not reach feature parity in time due to some unresolved issues in the Metatheory library. While the implementation is very unstable, the changes can be found on the `mt3` branch.

## Usage

The main way to interact with the optimizer is through the use of the `@optimize` macro. This macro is used to optimize a specific function call with a set of rewrite rules. It can be used as follows:

```julia
@optimize Options() rules to_optimize()
```

The rules parameter takes a _Metatheory.jl_ theory which is a set of rewrite rules. It follows the same convention as _Metatheory.jl_ with regards to the definition of the rules. The full documentation about the definition of these rewrite rules can be found on the [_Metatheory.jl_ docs](https://juliasymbolics.github.io/Metatheory.jl/dev/rewrite/). A simple example is shown below:

```julia
t = @theory x y z begin 
  add(x, y) --> add(y, x)
  mul(x, 0) --> 0
end

@optimize Options() t to_optimize()
```

The `Options` struct can be used to influence the behaviour of the optimizer. The full list of possible values is shown below:

```julia
struct Options
    """
    The cost function used during the e-graph extraction. 
    """
    analysis_ref::Function

    """
    The name of the cost function used during e-graph extraction. This won't be
    needed anymore for the 3.0 version of Metatheory.
    """
    analysis_name::Symbol

    """
    The saturation parameters for the e-graph saturation process. 
    """
    saturation_params::SaturationParams

    """
    The optimization pipeline to use during compilation. The default one can be
    swapped out for one that includes timings for all major parts of the pipeline.
    """
    opt_pipeline::CC.PassManager

    """
    Whether caching should be enabled. This disables both the internal caching of
    the compiled function as well as the closure cache included in this package.
    """
    enable_caching::Bool

    """
    Whether to run the code after compilation. If this flag is false, a closure will
    be returned that can be executed at a later point.
    """
    dont_run::Bool

    """
    Whether to output statistics about the e-graph saturation process.
    """
    print_sat_info::Bool

    """
    Whether to output the generated IR after performing the full optimization pipeline.
    """
    log_ir::Bool

    """
    Whether to print the AST cost before and after every e-graph optimization.
    """
    print_ast_cost::Bool
end
```

## Limitations

Below is a short list of the limitations of the current implementation:

- No control flow support, only single basic block functions are supported
- Matching on qualified function names is fully not supported (e.g. `Main.test()` or `Base.(:+)(12, 13)`) in the current Metatheory version. This prevents the usage of the built-in operators (e.g. +, -, *, /). Wrapper functions will have to be used instead. Patterns containing qualified function names (e.g. `Main.add(a, b) --> Main.add(b, a)`) will not be matched correctly.
