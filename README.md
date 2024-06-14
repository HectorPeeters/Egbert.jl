# TODO - TITLE

This repository contains the e-graph optimization framework developed for my masters thesis at Ghent University.

## Building

Running this optimizer requires a custom build of the Julia compiler. This custom version includes a pass manager which allows for the optimization pipeline to be changed at run time.

This fork of the Julia compiler can be found at [HectorPeeters/julia](https://github.com/HectorPeeters/julia). The required changes are on the `master` branch, while the original commit (`29a58d5`), from which all changes for the pass manager have been made, is marked using the `baseline` tag.

The normal Julia [build instructions](https://github.com/HectorPeeters/julia/tree/master#building-julia) (i.e. running `make`) should be sufficient for compiling this fork.

This custom version can be added to juliaup using the following command:

```bash
juliaup link <name-of-version> <path-to-version>
```

## Tests

All tests of the project are contained within the `test/` folder. Running all of the tests at once can be done using the following command:

```bash
julia +<name-of-version> --project=. test/all.jl
```

Tests can also be run individually using the corresponding filename instead of `test/all.jl`.

## Benchmarks

The benchmarks are stored in the `benches/` folder. Executing a benchmark can be done in the same manner as running the tests. Running the benchmarks from the REPL is not recommended to reduced any caching related performance fluctuations.

All benchmarks run the evaluations for multiple different input sizes and either output a CSV file of the results or print them to the console. One exception is `benches/astsize.jl`, which requires manually changing the size of the input in the code as this generates an expression tree at compile time using a macro.
