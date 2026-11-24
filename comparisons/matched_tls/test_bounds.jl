isdefined(@__MODULE__,:ssr_trial) || include(joinpath(@__DIR__,"ssr_drs.jl"))
using Test,Random

function run_tests()
    Random.seed!(20261124)
    results=Dict{String,Any}()
    @testset "Product enclosures against 2048-bit arithmetic" begin
        for (m,k,n) in [(5,7,6),(7,31,9),(1,3,2)]
            A=randn(m,k).*10. .^rand(-120:120,m,k)
            B=randn(k,n).*10. .^rand(-120:120,k,n)
            enclosure=product_box(A,B)
            setprecision(BigFloat,2048) do
                exact=BigFloat.(A)*BigFloat.(B)
                for j=1:n,i=1:m
                    @test BigFloat(enclosure[i,j].lo)<=exact[i,j]<=BigFloat(enclosure[i,j].hi)
                end
            end
        end
        A=reshape([nextfloat(0.),floatmin(Float64),0.,-floatmin(Float64)],2,2)
        B=[0.5 -0.5;0.0 0.0];box=product_box(A,B)
        setprecision(BigFloat,2048) do
            exact=BigFloat.(A)*BigFloat.(B)
            @test all(BigFloat(box[i,j].lo)<=exact[i,j]<=BigFloat(box[i,j].hi) for i=1:2,j=1:2)
        end
    end
    @testset "Nonzero TLS optimum and corrupted certificates" begin
        # q(x)=||t||^2+1/16*(||RX||_F^2+||RY||_F^2).
        # Its TLS optimum is exactly 3/8; on F<=3/8, t=0, ||phi||^2=14.
        n=1;K=2;Q=zeros(25,25)
        for j=1:6;Q[j,j]=1.;end
        for j=7:24;Q[j,j]=1/16;end
        G=hcat(vec.(manifold())...)
        ctx=(;n,U=3/8,Qbox=[IV.(Q)],norm_squared_bound=14.,G,Gpinv=pinv(G))
        alpha=3/8-2.0^-24;B=zeros(50,50)
        for j=1:6
            B[j,j]=B[j+25,j+25]=B[j,j+25]=B[j+25,j]=1/4
        end
        B[25,25]=B[50,50]=(1-3/8)/4
        B[25,50]=B[50,25]=-(1-3/8)/4
        B[25,25]+=2.0^-24
        good=verified_positive_bound(B,ctx,alpha,0.)
        @test good.checked
        @test 3/8-1e-6<good.lower<=3/8
        bad=verified_positive_bound(B,ctx,alpha+0.01,0.)
        @test bad.affine_correction>1e-5
        @test bad.lower<=3/8
        # Nullspace residue is assessed on the FULL matrix, not discarded.
        perturb=copy(B);perturb[1,25]+=1e-7;perturb[25,1]+=1e-7
        corrupted=verified_positive_bound(perturb,ctx,alpha,0.)
        @test corrupted.affine_correction>1e-9
        @test corrupted.psd_correction>good.psd_correction
        @test corrupted.lower<good.lower
        unavailable=merge(ctx,(norm_squared_bound=Inf,))
        @test verified_positive_bound(B,unavailable,alpha,0.).lower==0.
        @test !verified_positive_bound(B,unavailable,alpha,0.).checked
        results["nonzero_known_optimum"]=3/8
        results["nonzero_control_lower"]=good.lower
        results["corrupted_affine_lower"]=bad.lower
        results["tiny_cross_term_lower"]=corrupted.lower
    end
    @testset "Tiny linear term on an unbounded direction" begin
        epsilon=1e-7
        @test 2epsilon*(-1e12)<-1000
        B=zeros(25,25);B[1,25]=B[25,1]=epsilon
        @test psd_residual_upper(B,0.,1)>=epsilon
    end
    @testset "All fixed matched inputs admit a derived sublevel bound" begin
        reports=Dict{String,Any}[]
        for line in readlines(joinpath(@__DIR__,"cases.tsv"))
            name,relative,motion,n=split(line,'\t');folder=joinpath(@__DIR__,relative)
            d=prepare(folder);ctx=certificate_context(folder,d)
            @test isfinite(ctx.translation_bound)
            @test all(ctx.left_inverse_errors .< 1)
            @test abs(ctx.U-d.U)<1e-7
            @test ctx.candidate_rotation_change<1e-12
            push!(reports,Dict("case"=>name,"upper"=>ctx.U,
                "sublevel_translation_bound"=>ctx.translation_bound,
                "sublevel_norm_squared_bound"=>ctx.norm_squared_bound,
                "partition_groups"=>ctx.groups,"largest_left_inverse_error"=>maximum(ctx.left_inverse_errors)))
        end
        results["sublevel_cases"]=reports
    end
    results["passed"]=true
    results["scope"]="Analytical positive/negative controls and fixed-input enclosures; excluded from Table 3. No physical-accuracy claim."
    open(joinpath(@__DIR__,"tests.toml"),"w") do io;TOML.print(io,results;sorted=true);end
end
if abspath(PROGRAM_FILE)==@__FILE__;run_tests();end
