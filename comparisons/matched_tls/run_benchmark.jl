include(joinpath(@__DIR__,"ssr_drs.jl"))
include(joinpath(@__DIR__,"test_bounds.jl"))
using SHA

function benchmark()
    root=@__DIR__
    rows=[split(line,'\t') for line in readlines(joinpath(root,"cases.tsv"))]
    hashes=Dict(name=>bytes2hex(sha256(read(joinpath(root,name)))) for name in
        ["ssr_drs.jl","verified_bound.jl","common.jl","rotation_sdp_constraints.jl"])
    # Warm all numerical paths separately; controls exercise positive validation.
    run_tests()
    for idx in (1,3)
        folder=joinpath(root,rows[idx][2])
        for mode in ("single","pair");trial(folder,mode);end
        cascade_trial(folder)
        ssr_trial(folder;seconds=60.,maxiter=1)
    end
    println("Warm-up complete");flush(stdout)
    modes=["single","pair","cascade","ssr_drs_rwhe"]
    for (i,row) in enumerate(rows)
        name,relative,motion,n=row;folder=joinpath(root,relative)
        out=joinpath(root,"runs",name*".toml");mkpath(dirname(out))
        isfile(out) && error("Refusing to overwrite existing scored run: "*out)
        runs=Dict{String,Any}[]
        for rep=1:3,mode in circshift(modes,rep-1)
            GC.gc()
            result=mode=="ssr_drs_rwhe" ? ssr_trial(folder;seconds=30.,
                saveprefix=joinpath(root,"slacks",name*"_rep"*string(rep))) :
                mode=="cascade" ? cascade_trial(folder) : trial(folder,mode)
            result["repeat"]=rep;push!(runs,result)
            println(i,"/9 ",name," rep=",rep," ",mode," ",result["status"],
                " ",round(result["total_seconds"];digits=4)," s");flush(stdout)
        end
        report=Dict("name"=>name,"motion"=>motion,"folder"=>relative,"runs"=>runs,
            "source_sha256"=>hashes,
            "protocol_sha256"=>bytes2hex(sha256(read(joinpath(root,"protocol.json")))))
        open(out,"w") do io;TOML.print(io,report;sorted=true);end
    end
end
benchmark()
