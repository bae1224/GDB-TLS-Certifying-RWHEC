# Use the original unmodified timed certification calls.
include(joinpath(@__DIR__, "lib/cascade.jl"))
length(ARGS) == 2 || error("Usage: evaluate.jl diagnostics|timings OUTPUT_DIR")
const OUTPUT = abspath(ARGS[2])
using Random

function diagnostic(folder)
    data=prepare(folder);a=anchor(data)
    r=Dict{String,Any}("case"=>basename(folder),"N"=>length(data.q),
        "tau2"=>TOML.parsefile(joinpath(folder,"metadata.toml"))["tau2"],
        "full_support"=>data.full,"q"=>data.q,"max_q"=>maximum(data.q),
        "ls_cost"=>sum(data.q),"tls_cost"=>data.U,"kept"=>sum(data.q .< 1))
    if isnothing(a)
        r["failure_class"]="anchor_unavailable";return r
    end
    out=joinpath(OUTPUT,"diagnostics",basename(folder));mkpath(out)
    writedlm(joinpath(out,"S.csv"),a.S,',')
    r["beta"]=a.beta;r["lower"]=a.gamma;r["sdp_status"]=a.status
    r["min_H_eigenvalue"]=eigmin(Symmetric(a.S[1:24,1:24]))
    r["H_positive"]=true
    gap=sum(data.q)-a.gamma
    r["relative_ls_gap"]=gap/max(1.,sum(data.q))
    r["gap_pass"]=-1e-6<=r["relative_ls_gap"]<=1e-6
    r["constraint_identity_error"]=abs(dot(data.x,(sum(data.Qs)-a.S)*data.x)-a.beta)
    # Non-full-support cases are applicability controls, not bound failures.
    if !data.full
        r["failure_class"]="not_full_support"
        for mode in ["single","pair","cascade"];r[mode*"_certified"]=false;end
        return r
    end
    Linv=inv(a.F.L)
    Vs=[Matrix(Symmetric(Linv*Q[1:24,1:24]*Linv')) for Q in data.Qs]
    rho=max.(0.,[dot(a.x0,Q*a.x0) for Q in data.Qs]);rho .+= pad(maximum(rho))
    kappas=[eigmax(Symmetric(v))+1e-9 for v in Vs]
    pairvals=Float64[];pairrho=Float64[]
    for j=2:length(data.q),i=1:j-1
        push!(pairvals,eigmax(Symmetric(Vs[i]+Vs[j]))+1e-9)
        push!(pairrho,rho[i]+rho[j])
    end
    kmax=min(length(data.q),floor(Int,data.U+1e-7));r["kmax"]=kmax
    budgets=[k-gap for k=1:kmax];r["budgets"]=budgets
    r["budget_positive"]=all(budgets .> 0)
    single=Float64[];pair=Float64[]
    for (k,b) in enumerate(budgets)
        @assert b>0
        w=kappas+rho/b
        push!(single,sum(sort(w;rev=true)[1:k]))
        push!(pair,(k÷2)*maximum(pairvals+pairrho/b)+(k%2)*maximum(w))
    end
    for (mode,scores) in [("single",single),("pair",pair),("cascade",min.(single,pair))]
        r[mode*"_scores"]=scores
        r[mode*"_certified"]=r["gap_pass"] && r["budget_positive"] && all(scores .< 1-1e-7)
    end
    r["failure_class"]=!r["gap_pass"] ? "ls_gap" : !r["budget_positive"] ? "nonpositive_budget" :
        r["cascade_certified"] ? (kmax==0 ? "ls_only_no_deletions_needed" : "certified") : "group_bound_inconclusive"
    r
end

function main(action)
    rows=[split(line,'\t') for line in readlines(joinpath(OUTPUT,"cases.tsv"))]
    if action=="diagnostics"
        for (i,row) in enumerate(rows)
            name,folder,cutoff,timed=row
            path=joinpath(OUTPUT,"diagnostics",name,"result.toml")
            isfile(path) && continue
            mkpath(dirname(path));r=diagnostic(folder)
            open(path,"w") do io;TOML.print(io,r;sorted=true);end
            if i%10==0 || timed=="1";println(i,"/",length(rows)," ",name," ",r["failure_class"]);flush(stdout);end
        end
    elseif action=="timings"
        target=joinpath(OUTPUT,"timings.toml")
        isfile(target) && error("Existing timing batch preserved; use a new study folder for a rerun.")
        timed=filter(row->row[4]=="1",rows);modes=["single","pair","cascade"]
        run(folder,mode)=mode=="cascade" ? cascade_trial(folder) : trial(folder,mode)
        # Cover all branches before measurement, including k=0 and inapplicable.
        for row in timed,mode in modes;run(row[2],mode);end
        GC.gc();rng=MersenneTwister(2026111904);runs=Dict{String,Any}[]
        for rep=1:9
            order=shuffle(rng,collect(eachindex(timed)))
            for (j,idx) in enumerate(order),mode in circshift(modes,rep+j-2)
                row=timed[idx];r=run(row[2],mode)
                r["tau2"]=parse(Float64,row[3]);r["repeat"]=rep;r["order_index"]=j
                push!(runs,r)
            end
            println("timing repeat ",rep,"/9 complete");flush(stdout)
        end
        open(target,"w") do io;TOML.print(io,Dict("runs"=>runs,"julia_version"=>string(VERSION),"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads());sorted=true);end
    else
        error("Use diagnostics or timings")
    end
end
main(ARGS[1])
