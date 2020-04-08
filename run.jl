using RetroCap, NewPkgEval, DataFrames, Serialization

julia = v"1.4.0"
julia_reference = VersionNumber("$(julia)-reference")
julia_comparison = VersionNumber("$(julia)-comparison")

regpath = NewPkgEval.registry_dir("General")

ninstances = Sys.CPU_THREADS ÷ 3 * 2

url = "https://github.com/maleadt/retrocap_report/blob/master"

function main()
    # reset the registry
    run(`git -C $regpath checkout master`)
    run(`git -C $regpath pull`)

    # get reference evaluation
    data_reference = NewPkgEval.run([julia]; update_registry=false, ninstances=ninstances)
    serialize("data_reference.jls", data_reference)

    # add bounds
    run(ignorestatus(`git -C $regpath branch -D tb/retrocap`))
    run(`git -C $regpath checkout -b tb/retrocap`)
    RetroCap.add_caps(RetroCap.MonotonicUpperBound(), RetroCap.CapLatestVersion(), regpath)
    run(`git -C $regpath add -A`)
    run(`git -C $regpath commit -m "Use RetroCap.jl to add monotonic \"caps\" (upper-bounded compat entries) to all packages"`)

    # get comparison evaluation
    data_comparison = NewPkgEval.run([julia]; update_registry=false, ninstances=ninstances)
    serialize("data_comparison.jls", data_comparison)

    # merge
    data_reference.julia = julia_reference
    data_comparison.julia = julia_comparison
    data = vcat(data_reference, data_comparison)
    serialize("data.jls", data)
    rm("data_reference.jls")
    rm("data_comparison.jls")

    # clean
    for file in readdir(@__DIR__)
        endswith(file, ".log") && rm(file)
    end
    rm("report.md"; force=true)
    rm("data.jls.xz"; force=true)

    # compress data
    run(`xz -z data.jls`)

    # generate report
    only(x) = (@assert size(x, 1) == 1; first(x))
    open("report.md", "w") do io
        for group in groupby(data, :name; skipmissing=true)
            package = only(unique(group.name))
            reference = only(group[group.julia .== julia_reference, :])
            comparison = only(group[group.julia .== julia_comparison, :])

            if reference.status != comparison.status
                println(io, "- $package: was [$(reference.status)]($url/$package.reference.log) ($(reference.reason)), now [$(comparison.status)]($url/$package.comparison.log) ($(comparison.reason))")
                write("$package.reference.log", reference.log)
                write("$package.comparison.log", comparison.log)
            end
        end
    end

    # commit
    run(`git add -A`)
    run(`git commit -m "Generate new report."`)

    return
end

isinteractive() || main()
