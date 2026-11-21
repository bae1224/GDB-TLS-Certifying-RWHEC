# Cost functions copied from the original real44 experiment.
using LinearAlgebra, DelimitedFiles, TOML, JuMP, COSMO
include(joinpath(@__DIR__, "../../src/rotation_sdp_constraints.jl"))
BLAS.set_num_threads(1)

function posecsv(path)
    rows=readdlm(path,',',Float64); out=Matrix{Float64}[]
    for i in axes(rows,1)
        w,x,y,z=rows[i,1:4]; @assert abs(w*w+x*x+y*y+z*z-1)<1e-7
        R=[1-2y*y-2z*z 2x*y-2z*w 2x*z+2y*w;
           2x*y+2z*w 1-2x*x-2z*z 2y*z-2x*w;
           2x*z-2y*w 2y*z+2x*w 1-2x*x-2y*y]
        push!(out,[R rows[i,5:7];0 0 0 1])
    end
    out
end
pack(X,Y)=[X[1:3,4];Y[1:3,4];vec(X[1:3,1:3]);vec(Y[1:3,1:3]);1.]
function costmat(A,B,wr,wt)
    Mr=hcat(zeros(9,6),kron(Matrix{Float64}(I,3,3),A[1:3,1:3]),-kron(B[1:3,1:3]',Matrix{Float64}(I,3,3)),zeros(9,1))
    Mt=hcat(A[1:3,1:3],-Matrix{Float64}(I,3,3),zeros(3,9),-kron(B[1:3,4]',Matrix{Float64}(I,3,3)),A[1:3,4])
    wr*(Mr'*Mr)+wt*(Mt'*Mt)
end
