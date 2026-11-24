# Post-run audit. Excluded from every reported runtime. It exercises the full
# residual validator on one saved iterate from each case even if the screen
# rejected it. Zero fallback results are checked separately for all repetitions.
include(joinpath(@__DIR__,"ssr_drs.jl"))
function audit_saved()
    reports=Dict{String,Any}[]
    for line in readlines(joinpath(@__DIR__,"cases.tsv"))
        name,relative,motion,n=split(line,'\t');folder=joinpath(@__DIR__,relative)
        saved=TOML.parsefile(joinpath(@__DIR__,"runs",name*".toml"))
        runs=filter(r->r["mode"]=="ssr_drs_rwhe",saved["runs"])
        for r in runs
            @assert r["lower"]>=0
            @assert r["lower"]==0 || r["positive_bound_validation_performed"]
            @assert r["status"]!="numerically_certified" || 0<=r["relative_gap"]<=1e-6
        end
        r=only(filter(r->r["repeat"]==1,runs));K=r["N"]+1
        prefix=joinpath(@__DIR__,"slacks",name*"_rep1")
        S=reshape(reinterpret(Float64,read(prefix*"_slack.f64")),25K,25K)
        W=readdlm(prefix*"_W.csv",',',Float64)
        ctx=certificate_context(folder,prepare(folder))
        v=verified_positive_bound(physical_slack(S,W),ctx,r["target"],r["bounded_shift"])
        @assert v.checked
        @assert 0<=v.lower<=ctx.U
        @assert r["lower"]==0 || v.lower>=r["lower"]-1e-12
        push!(reports,Dict("case"=>name,"repeat"=>1,"verified_lower"=>v.lower,
            "affine_error_upper"=>v.affine_correction,"full_slack_psd_error_upper"=>v.psd_correction,
            "sublevel_norm_squared_bound"=>ctx.norm_squared_bound,
            "schur_shift_proposal"=>r["bounded_shift"]))
        println(name," lower=",v.lower," affine=",v.affine_correction," PSD=",v.psd_correction);flush(stdout)
    end
    open(joinpath(@__DIR__,"saved_audit.toml"),"w") do io
        TOML.print(io,Dict("passed"=>true,"reported_runs_checked"=>27,
            "full_validations"=>reports,"timing_includes_this_audit"=>false);sorted=true)
    end
end
audit_saved()
