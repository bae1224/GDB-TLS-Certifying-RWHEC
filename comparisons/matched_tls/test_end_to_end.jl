# Separate integration controls; never included among the scored nine cases.
isdefined(@__MODULE__,:ssr_trial) || include(joinpath(@__DIR__,"ssr_drs.jl"))
using Test
function integration_controls()
    root=joinpath(@__DIR__,"controls");mkpath(root)
    source=joinpath(@__DIR__,"cases","holdout_broad_n44_eta4_s00","A.csv")
    poses=readdlm(source,',',Float64)[1:6,:]
    folders=String[]
    for (name,offset) in [("zero_optimum",0.),("nonoptimal_candidate",0.1)]
        folder=joinpath(root,name);mkpath(folder);push!(folders,folder)
        X=Matrix{Float64}(I,4,4);X[1,4]=offset
        for field in ("A","B");writedlm(joinpath(folder,field*".csv"),poses,',');end
        writedlm(joinpath(folder,"X_candidate.csv"),X,',')
        writedlm(joinpath(folder,"Y_candidate.csv"),Matrix{Float64}(I,4,4),',')
        open(joinpath(folder,"metadata.toml"),"w") do io
            TOML.print(io,Dict("N"=>6,"rot_weight"=>5000.,"translation_weight"=>1/0.003^2,"tau2"=>16.))
        end
    end
    # Compilation excluded. A deliberately short iteration cap is sufficient
    # for the exact zero-cost case and cannot make the wrong candidate optimal.
    ssr_trial(folders[1];seconds=60.,maxiter=1)
    good=ssr_trial(folders[1];seconds=10.,maxiter=2)
    bad=ssr_trial(folders[2];seconds=10.,maxiter=2)
    @testset "DRS integration and nonoptimal candidate" begin
        @test good["status"]=="numerically_certified"
        @test 0<=good["relative_gap"]<=1e-6
        @test good["lower"]<=good["upper"]
        @test bad["status"]!="numerically_certified"
        @test bad["relative_gap"]>1e-3
    end
    open(joinpath(@__DIR__,"integration_tests.toml"),"w") do io
        TOML.print(io,Dict("passed"=>true,"known_optimum"=>0.,
            "zero_cost_candidate"=>good,"wrong_candidate"=>bad,
            "included_in_table_3"=>false);sorted=true)
    end
end
integration_controls()
