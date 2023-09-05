"""
    opt,sol,data = cs_tssos_first(supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe::Vector{Vector{ComplexF64}},
    n, d; numeq=0, foc=100, CS="MF", minimize=false, assign="first", TS="block", merge=false, md=3, solver="Mosek",
    QUIET=false, solve=true, Gram=false, MomentOne=true)

Compute the first step of the CS-TSSOS hierarchy for constrained complex polynomial optimization with
relaxation order `d`. Here the complex polynomial optimization problem is defined by `supp` and `coe`,
corresponding to the supports and coeffients of `pop` respectively.

# Arguments
- `supp`: the supports of the complex polynomial optimization problem.
- `coe`: the coeffients of the complex polynomial optimization problem.
- `d`: the relaxation order of the moment-SOHS hierarchy.
- `numeq`: the number of equality constraints.
"""
function cs_tssos_first(pop, z, n, d; numeq=0, foc=100, nb=0, CS="MF", cliques=[], minimize=false, assign="first", TS="block",
    merge=false, md=3, solver="Mosek", reducebasis=false, QUIET=false, solve=true, tune=false, solution=false,
    ipart=true, Dual=false, balanced=false, MomentOne=false, Gram=false, Mommat=false, cosmo_setting=cosmo_para(), writetofile=false)
    ctype = ipart==true ? ComplexF64 : Float64
    supp,coe = polys_info(pop, z, n, ctype=ctype)
    opt,sol,data = cs_tssos_first(supp, coe, n, d, numeq=numeq, foc=foc, nb=nb, CS=CS, cliques=cliques, minimize=minimize,
    assign=assign, TS=TS, merge=merge, md=md, solver=solver, reducebasis=reducebasis, QUIET=QUIET, solve=solve, tune=tune, 
    solution=solution, ipart=ipart, Dual=Dual, balanced=balanced, MomentOne=MomentOne, Gram=Gram, Mommat=Mommat, 
    cosmo_setting=cosmo_setting, writetofile=writetofile)
    return opt,sol,data
end

function cs_tssos_first(supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe, n, d; numeq=0, RemSig=false, foc=100, nb=0, CS="MF", cliques=[], 
    minimize=false, assign="first", TS="block", merge=false, md=3, solver="Mosek", reducebasis=false, QUIET=false, solve=true, tune=false, 
    solution=false, ipart=true, Dual=false, balanced=false, MomentOne=false, Gram=false, Mommat=false, cosmo_setting=cosmo_para(), writetofile=false)
    println("*********************************** TSSOS ***********************************")
    println("Version 1.0.0, developed by Jie Wang, 2020--2023")
    println("TSSOS is launching...")
    if nb > 0
        supp[1],coe[1] = resort(supp[1], coe[1], nb=nb)
    end
    supp = copy(supp)
    coe = copy(coe)
    m = length(supp) - 1
    ind = [supp[1][i][1]<=supp[1][i][2] for i=1:length(supp[1])]
    supp[1] = supp[1][ind]
    coe[1] = coe[1][ind]
    dg = zeros(Int, m)
    for i = 1:m
        dg[i] = maximum([length(supp[i+1][j][1]) + length(supp[i+1][j][2]) for j=1:length(supp[i+1])])
    end
    if cliques != []
        cql = length(cliques)
        cliquesize = length.(cliques)
    else
        time = @elapsed begin
        cliques,cql,cliquesize = clique_decomp(n, m, dg, supp, order=d, alg=CS, minimize=minimize)
        end
        if CS != false && QUIET == false
            mc = maximum(cliquesize)
            println("Obtained the variable cliques in $time seconds.\nThe maximal size of cliques is $mc.")
        end
    end
    J,ncc = assign_constraint(m, supp, cliques, cql, cliquesize, assign=assign)
    rlorder = init_order(dg, J, cliquesize, cql, foc=foc, order=d)
    if TS != false && QUIET == false
        println("Starting to compute the block structure...")
    end
    time = @elapsed begin
    blocks,cl,blocksize,sb,numb,basis,status = get_cblocks_mix(dg, J, rlorder, m, supp, cliques, cql, cliquesize,
    TS=TS, balanced=balanced, merge=merge, md=md, nb=nb)
    if RemSig == true
        for i = 1:cql
            basis[i][1] = basis[i][1][union(blocks[i][1][blocksize[i][1] .> 1]...)]
        end
        tsupp = copy(supp[1])
        for i = 2:m+1, j = 1:length(supp[i])
            if supp[i][j][1] <= supp[i][j][2]
                push!(tsupp, supp[i][j])
            end
        end
        sort!(tsupp)
        unique!(tsupp)
        ind = [UInt16[] for i=1:cql]
        blocks,cl,blocksize,sb,numb,basis,status = get_cblocks_mix(dg, J, rlorder, m, supp, cliques, cql, cliquesize,
        tsupp=tsupp, basis=basis, sb=ind, numb=ind, blocks=blocks, cl=cl, blocksize=blocksize, TS=TS, merge=merge, md=md, nb=nb)
    end
    if reducebasis == true
        tsupp = get_gsupp(basis, supp, cql, J, ncc, blocks, cl, blocksize, norm=true)
        for i = 1:length(supp[1])
            if supp[1][i][1] == supp[1][i][2]
                push!(tsupp, supp[1][i][1])
            end
        end
        sort!(tsupp)
        unique!(tsupp)
        ltsupp = length(tsupp)
        flag = 0
        for i = 1:cql
            ind = [bfind(tsupp, ltsupp, basis[1][i][j]) != 0 for j=1:length(basis[1][i])]
            if !all(ind)
                basis[1][i] = basis[1][i][ind]
                flag = 1
            end
        end
        if flag == 1
            tsupp = copy(supp[1])
            for i = 2:m+1, j = 1:length(supp[i])
                if supp[i][j][1] <= supp[i][j][2]
                    push!(tsupp, supp[i][j])
                end
            end
            sort!(tsupp)
            unique!(tsupp)
            blocks,cl,blocksize,sb,numb,basis,status = get_cblocks_mix(dg, J, rlorder, m, supp, cliques, cql, cliquesize,
            tsupp=tsupp, basis=basis, blocks=blocks, cl=cl, blocksize=blocksize, sb=sb, numb=numb, TS=TS, merge=merge, md=md)
        end
    end
    end
    if TS != false && QUIET == false
        mb = maximum(maximum.(sb))
        println("Obtained the block structure in $time seconds.\nThe maximal size of blocks is $mb.")
    end
    opt,ksupp,moment,GramMat,SDP_status = blockcpop_mix(n, m, supp, coe, basis, cliques, cql, cliquesize, J, ncc, blocks, cl, blocksize,
    numeq=numeq, QUIET=QUIET, TS=TS, solver=solver, solve=solve, tune=tune, solution=solution, ipart=ipart, MomentOne=MomentOne,
    Gram=Gram, Mommat=Mommat, nb=nb, cosmo_setting=cosmo_setting, Dual=Dual, writetofile=writetofile)
    data = mcpop_data(n, nb, m, numeq, supp, coe, basis, rlorder, ksupp, cql, cliques, cliquesize, J, ncc, sb,
    numb, blocks, cl, blocksize, GramMat, moment, solver, SDP_status, 1e-4, 1)
    return opt,nothing,data
end

function polys_info(pop, z, n; ctype=ComplexF64)
    coe = Vector{Vector{ctype}}(undef, length(pop))
    supp = Vector{Vector{Vector{Vector{UInt16}}}}(undef, length(pop))
    for k in eachindex(pop)
        mon = monomials(pop[k])
        coe[k] = coefficients(pop[k])
        lm = length(mon)
        supp[k] = [[[], []] for i=1:lm]
        for i = 1:lm
            ind = mon[i].z .> 0
            vars = mon[i].vars[ind]
            exp = mon[i].z[ind]
            for j in eachindex(vars)
                l = ncbfind(z, 2n, vars[j])
                if l <= n
                    append!(supp[k][i][1], l*ones(UInt16, exp[j]))
                else
                    append!(supp[k][i][2], (l-n)*ones(UInt16, exp[j]))
                end
            end
        end
    end
    return supp,coe
end

function reduce_unitnorm(a; nb=0)
    a = [copy(a[1]), copy(a[2])]
    i = 1
    while i <= length(a[1])
        if length(a[2]) == 0
            return a
        end
        if a[1][i] <= nb
            loc = bfind(a[2], length(a[2]), a[1][i])
            if loc != 0
                deleteat!(a[1], i)
                deleteat!(a[2], loc)
            else
                i += 1
            end
        else
            return a
        end
    end
    return a
end

function get_gsupp(basis, supp, cql, J, ncc, blocks, cl, blocksize; norm=false, nb=0)
    if norm == true
        gsupp = Vector{UInt16}[]
    else
        gsupp = Vector{Vector{UInt16}}[]
    end
    for i = 1:cql, (j, w) in enumerate(J[i])
        for l = 1:cl[i][j+1], t = 1:blocksize[i][j+1][l], r = t:blocksize[i][j+1][l], s = 1:length(supp[w+1])
            ind1 = blocks[i][j+1][l][t]
            ind2 = blocks[i][j+1][l][r]
            @inbounds bi = [sadd(basis[i][j+1][ind1], supp[w+1][s][1]), sadd(basis[i][j+1][ind2], supp[w+1][s][2])]
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if norm == true
                if bi[1] == bi[2]
                    push!(gsupp, bi[1])
                end
            else
                if bi[1] <= bi[2]
                    push!(gsupp, bi)
                else
                    push!(gsupp, bi[2:-1:1])
                end
            end
        end
    end
    for i ∈ ncc, j = 1:length(supp[i+1])
        if norm == true
            if supp[i+1][j][1] == supp[i+1][j][2]
                push!(gsupp, supp[i+1][j][1])
            end
        else
            if supp[i+1][j][1] <= supp[i+1][j][2]
                push!(gsupp, supp[i+1][j])
            end
        end
    end
    return gsupp
end

function blockcpop_mix(n, m, supp::Vector{Vector{Vector{Vector{UInt16}}}}, coe, basis, cliques, cql, cliquesize, J, ncc, blocks, cl, blocksize; 
    numeq=0, nb=0, QUIET=false, TS="block", solver="Mosek", tune=false, solve=true, Dual=false, solution=false, Gram=false, MomentOne=false, 
    ipart=true, Mommat=false, cosmo_setting=cosmo_para(), writetofile=false)
    tsupp = Vector{Vector{UInt16}}[]
    for i = 1:cql, j = 1:cl[i][1], k = 1:blocksize[i][1][j], r = k:blocksize[i][1][j]
        @inbounds bi = [basis[i][1][blocks[i][1][j][k]], basis[i][1][blocks[i][1][j][r]]]
        if nb > 0
            bi = reduce_unitnorm(bi, nb=nb)
        end
        if bi[1] <= bi[2]
            push!(tsupp, bi)
        else
            push!(tsupp, bi[2:-1:1])
        end
    end
    # wbasis = get_sbasis(Vector(1:n), 2)
    # bs = length(wbasis)
    # for i = 1:n
    #     for j = 1:bs, k = j:bs
    #         bi = [sadd(wbasis[j], [i]), sadd(wbasis[k], [i])]
    #         if nb > 0
    #             bi = reduce_unitnorm(bi, nb=nb)
    #         end
    #         if bi[1] <= bi[2]
    #             push!(tsupp, bi)
    #         else
    #             push!(tsupp, bi[2:-1:1])
    #         end
    #     end
    #     for j = 1:bs, k = 1:bs
    #         bi = [sadd(wbasis[j], [i]), wbasis[k]]
    #         if nb > 0
    #             bi = reduce_unitnorm(bi, nb=nb)
    #         end
    #         if bi[1] <= bi[2]
    #             push!(tsupp, bi)
    #         else
    #             push!(tsupp, bi[2:-1:1])
    #         end
    #     end
    # end
    gsupp = get_gsupp(basis, supp, cql, J, ncc, blocks, cl, blocksize, nb=nb)
    append!(tsupp, gsupp)
    if (MomentOne == true || solution == true) && TS != false
        ksupp = copy(tsupp)
        for i = 1:cql, j = 1:cliquesize[i]
            push!(tsupp, [UInt16[], UInt16[cliques[i][j]]])
            for k = j+1:cliquesize[i]
                bi = [UInt16[cliques[i][j]], UInt16[cliques[i][k]]]
                if nb > 0
                    bi = reduce_unitnorm(bi, nb=nb)
                end
                push!(tsupp, bi)
            end
        end
    end
    sort!(tsupp)
    unique!(tsupp)
    if (MomentOne == true || solution == true) && TS != false
        sort!(ksupp)
        unique!(ksupp)
    else
        ksupp = tsupp
    end
    objv = moment = GramMat = SDP_status= nothing
    if solve == true
        ltsupp = length(tsupp)
        if QUIET == false
            println("Assembling the SDP...")
        end
        if solver == "Mosek"
            if Dual == false
                model = Model(optimizer_with_attributes(Mosek.Optimizer))
            else
                model = Model(dual_optimizer(Mosek.Optimizer))
            end
            if tune == true
                set_optimizer_attributes(model,
                "MSK_DPAR_INTPNT_CO_TOL_MU_RED" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_INFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_REL_GAP" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_DFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_PFEAS" => 1e-7,
                "MSK_DPAR_INTPNT_CO_TOL_NEAR_REL" => 1e6,
                "MSK_IPAR_BI_IGNORE_NUM_ERROR" => 1,
                "MSK_DPAR_BASIS_TOL_X" => 1e-3,
                "MSK_DPAR_BASIS_TOL_S" => 1e-3,
                "MSK_DPAR_BASIS_REL_TOL_S" => 1e-5)
            end
        elseif solver == "COSMO"
            model = Model(optimizer_with_attributes(COSMO.Optimizer, "eps_abs" => cosmo_setting.eps_abs, "eps_rel" => cosmo_setting.eps_rel, "max_iter" => cosmo_setting.max_iter))
        elseif solver == "SDPT3"
            model = Model(optimizer_with_attributes(SDPT3.Optimizer))
        elseif solver == "SDPNAL"
            model = Model(optimizer_with_attributes(SDPNAL.Optimizer))
        else
            @error "The solver is currently not supported!"
            return nothing,nothing,nothing,nothing,nothing
        end
        set_optimizer_attribute(model, MOI.Silent(), QUIET)
        time = @elapsed begin
        rcons = [AffExpr(0) for i=1:ltsupp]
        if ipart == true
            icons = [AffExpr(0) for i=1:ltsupp]
        end
        # bs = length(wbasis)
        # for i = 1:n
        #     hnom = @variable(model, [1:2bs, 1:2bs], PSD)
        #     for j = 1:bs, k = j:bs
        #         bi = [wbasis[j], wbasis[k]]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #         end
        #         @inbounds add_to_expression!(rcons[Locb], hnom[j,k])
        #         bi = [sadd(wbasis[j], [i]), sadd(wbasis[k], [i])]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #         end
        #         @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+bs])
        #     end
        #     for j = 1:bs, k = 1:bs
        #         bi = [sadd(wbasis[j], [i]), wbasis[k]]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #         end
        #         if bi[1] != bi[2]
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j,k+bs])
        #         else
        #             @inbounds add_to_expression!(rcons[Locb], 2, hnom[j,k+bs])
        #         end
        #     end
        # end
        # for i = 1:n
        #     if ipart == true
        #         hnom = @variable(model, [1:6bs, 1:6bs], PSD)
        #     else
        #         hnom = @variable(model, [1:3bs, 1:3bs], PSD)
        #     end
        #     for j = 1:bs, k = j:bs
        #         bi = [wbasis[j], wbasis[k]]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2] && ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], hnom[j,k+2bs]-hnom[k,j+2bs])
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j,k+2bs]-hnom[k,j+2bs])
        #             end
        #         end
        #         if ipart == true
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j,k]+hnom[j+2bs,k+2bs])
        #         else
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j,k])
        #         end
        #         bi = [sadd(wbasis[j], [1]), sadd(wbasis[k], [1])]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2] && ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], hnom[j+bs,k+3bs]-hnom[k+bs,j+3bs])
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j+bs,k+3bs]-hnom[k+bs,j+3bs])
        #             end
        #         end
        #         if ipart == true
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+bs]+hnom[j+3bs,k+3bs])
        #         else
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+bs])
        #         end
        #         bi = [sadd(wbasis[j], [2]), sadd(wbasis[k], [2])]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2] && ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], hnom[j+2bs,k+5bs]-hnom[k+2bs,j+5bs])
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j+2bs,k+5bs]-hnom[k+2bs,j+5bs])
        #             end
        #         end
        #         if ipart == true
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j+2bs,k+2bs]+hnom[j+5bs,k+5bs])
        #         else
        #             @inbounds add_to_expression!(rcons[Locb], hnom[j+2bs,k+2bs])
        #         end
        #     end
        #     for j = 1:bs, k = 1:bs
        #         bi = [sadd(wbasis[j], [1]), wbasis[k]]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2]
        #                 if ipart == true
        #                     @inbounds add_to_expression!(icons[Locb], hnom[j,k+3bs]-hnom[k+bs,j+2bs])
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j,k+bs]+hnom[j+2bs,k+3bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j,k+bs])
        #                 end
        #             else
        #                 if ipart == true
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j,k+bs]+hnom[j+2bs,k+3bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j,k+bs])
        #                 end
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j,k+3bs]-hnom[k+bs,j+2bs])
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j,k+bs]+hnom[j+2bs,k+3bs])
        #             else
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j,k+bs])
        #             end
        #         end
        #     end
        #     for j = 1:bs, k = 1:bs
        #         bi = [sadd(wbasis[j], [2]), wbasis[k]]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2]
        #                 if ipart == true
        #                     @inbounds add_to_expression!(icons[Locb], hnom[j,k+5bs]-hnom[k+2bs,j+3bs])
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j,k+2bs]+hnom[j+3bs,k+5bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j,k+2bs])
        #                 end
        #             else
        #                 if ipart == true
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j,k+2bs]+hnom[j+3bs,k+5bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j,k+2bs])
        #                 end
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j,k+5bs]-hnom[k+2bs,j+3bs])
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j,k+2bs]+hnom[j+3bs,k+5bs])
        #             else
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j,k+2bs])
        #             end
        #         end
        #     end
        #     for j = 1:bs, k = 1:bs
        #         bi = [sadd(wbasis[j], [2]), sadd(wbasis[k], [1])]
        #         if nb > 0
        #             bi = reduce_unitnorm(bi, nb=nb)
        #         end
        #         if bi[1] <= bi[2]
        #             Locb = bfind(tsupp, ltsupp, bi)
        #             if bi[1] != bi[2]
        #                 if ipart == true
        #                     @inbounds add_to_expression!(icons[Locb], hnom[j+bs,k+5bs]-hnom[k+2bs,j+4bs])
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+2bs]+hnom[j+4bs,k+5bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+2bs])
        #                 end
        #             else
        #                 if ipart == true
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j+bs,k+2bs]+hnom[j+4bs,k+5bs])
        #                 else
        #                     @inbounds add_to_expression!(rcons[Locb], 2, hnom[j+bs,k+2bs])
        #                 end
        #             end
        #         else
        #             Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
        #             if ipart == true
        #                 @inbounds add_to_expression!(icons[Locb], -1, hnom[j+bs,k+5bs]-hnom[k+2bs,j+4bs])
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+2bs]+hnom[j+4bs,k+5bs])
        #             else
        #                 @inbounds add_to_expression!(rcons[Locb], hnom[j+bs,k+2bs])
        #             end
        #         end
        #     end
        # end
        pos = Vector{Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}}(undef, cql)
        for i = 1:cql
            if (MomentOne == true || solution == true) && TS != false
                bs = cliquesize[i] + 1
                if ipart == true
                    pos0 = @variable(model, [1:2*bs, 1:2*bs], PSD)
                else
                    pos0 = @variable(model, [1:bs, 1:bs], PSD)
                end
                for t = 1:bs, r = t:bs
                    if t == 1 && r == 1
                        bi = [UInt16[], UInt16[]]
                    elseif t == 1 && r > 1
                        bi = [UInt16[], UInt16[cliques[i][r-1]]]
                    else
                        bi = [UInt16[cliques[i][t-1]], UInt16[cliques[i][r-1]]]
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                    end
                    Locb = bfind(tsupp, ltsupp, bi)
                    if ipart == true
                        @inbounds add_to_expression!(rcons[Locb], pos0[t,r]+pos0[t+bs,r+bs])
                        @inbounds add_to_expression!(icons[Locb], pos0[t,r+bs]-pos0[r,t+bs])
                    else
                        @inbounds add_to_expression!(rcons[Locb], pos0[t,r])
                    end
                end
            end
            pos[i] = Vector{Vector{Union{VariableRef,Symmetric{VariableRef}}}}(undef, 1+length(J[i]))
            pos[i][1] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][1])
            for l = 1:cl[i][1]
                @inbounds bs = blocksize[i][1][l]
                if bs == 1
                    pos[i][1][l] = @variable(model, lower_bound=0)
                    @inbounds bi = [basis[i][1][blocks[i][1][l][1]], basis[i][1][blocks[i][1][l][1]]]
                    if nb > 0
                        bi = reduce_unitnorm(bi, nb=nb)
                    end
                    Locb = bfind(tsupp, ltsupp, bi)
                    @inbounds add_to_expression!(rcons[Locb], pos[i][1][l])
                else
                    if ipart == true
                        pos[i][1][l] = @variable(model, [1:2bs, 1:2bs], PSD)
                    else
                        pos[i][1][l] = @variable(model, [1:bs, 1:bs], PSD)
                    end
                    for t = 1:bs, r = t:bs
                        @inbounds ind1 = blocks[i][1][l][t]
                        @inbounds ind2 = blocks[i][1][l][r]
                        @inbounds bi = [basis[i][1][ind1], basis[i][1][ind2]]
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                        if bi[1] <= bi[2]
                            Locb = bfind(tsupp, ltsupp, bi)
                            if ipart == true && bi[1] != bi[2]
                                @inbounds add_to_expression!(icons[Locb], pos[i][1][l][t,r+bs]-pos[i][1][l][r,t+bs])
                            end
                        else
                            Locb = bfind(tsupp, ltsupp, bi[2:-1:1])
                            if ipart == true
                                @inbounds add_to_expression!(icons[Locb], -1, pos[i][1][l][t,r+bs]-pos[i][1][l][r,t+bs])
                            end
                        end
                        if ipart == true
                            @inbounds add_to_expression!(rcons[Locb], pos[i][1][l][t,r]+pos[i][1][l][t+bs,r+bs])
                        else
                            @inbounds add_to_expression!(rcons[Locb], pos[i][1][l][t,r])
                        end
                    end
                end
            end
        end
        for i in ncc
            if i <= m-numeq
                pos0 = @variable(model, lower_bound=0)
            else
                pos0 = @variable(model)
            end
            for j = 1:length(supp[i+1])
                if supp[i+1][j][1] <= supp[i+1][j][2]
                    Locb = bfind(tsupp, ltsupp, supp[i+1][j])
                    if ipart == true
                        @inbounds add_to_expression!(icons[Locb], imag(coe[i+1][j]), pos0)
                    end
                    @inbounds add_to_expression!(rcons[Locb], real(coe[i+1][j]), pos0)
                end
            end
        end
        for i = 1:cql, (j, w) in enumerate(J[i])
            pos[i][j+1] = Vector{Union{VariableRef,Symmetric{VariableRef}}}(undef, cl[i][j+1])
            for l = 1:cl[i][j+1]
                bs = blocksize[i][j+1][l]
                if bs == 1
                    if w <= m-numeq
                        pos[i][j+1][l] = @variable(model, lower_bound=0)
                    else
                        pos[i][j+1][l] = @variable(model)
                    end
                    ind = blocks[i][j+1][l][1]
                    for s = 1:length(supp[w+1])
                        @inbounds bi = [sadd(basis[i][j+1][ind], supp[w+1][s][1]), sadd(basis[i][j+1][ind], supp[w+1][s][2])]
                        if nb > 0
                            bi = reduce_unitnorm(bi, nb=nb)
                        end
                        if bi[1] <= bi[2]
                            Locb = bfind(tsupp, ltsupp, bi)
                            if ipart == true
                                @inbounds add_to_expression!(icons[Locb], imag(coe[w+1][s]), pos[i][j+1][l])
                            end
                            @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+1][l])
                        end
                    end
                else
                    if w <= m-numeq
                        if ipart == true
                            pos[i][j+1][l] = @variable(model, [1:2bs, 1:2bs], PSD)
                        else
                            pos[i][j+1][l] = @variable(model, [1:bs, 1:bs], PSD)
                        end
                    else
                        if ipart == true
                            pos[i][j+1][l] = @variable(model, [1:2bs, 1:2bs], Symmetric)
                            # pos1 = @variable(model, [1:bs, 1:bs], Symmetric)
                        else
                            pos[i][j+1][l] = @variable(model, [1:bs, 1:bs], Symmetric)
                        end
                    end
                    for t = 1:bs, r = 1:bs
                        ind1 = blocks[i][j+1][l][t]
                        ind2 = blocks[i][j+1][l][r]
                        for s = 1:length(supp[w+1])
                            @inbounds bi = [sadd(basis[i][j+1][ind1], supp[w+1][s][1]), sadd(basis[i][j+1][ind2], supp[w+1][s][2])]
                            if nb > 0
                                bi = reduce_unitnorm(bi, nb=nb)
                            end
                            if bi[1] <= bi[2]
                                Locb = bfind(tsupp, ltsupp, bi)
                                if ipart == true
                                    # if w <= m-numeq
                                        @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+1][l][t,r]+pos[i][j+1][l][t+bs,r+bs])
                                        @inbounds add_to_expression!(rcons[Locb], -imag(coe[w+1][s]), pos[i][j+1][l][t,r+bs]-pos[i][j+1][l][r,t+bs])
                                    # else
                                    #     @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s])*pos[i][j+1][l][t,r]-imag(coe[w+1][s])*pos1[t,r])
                                    # end
                                    if bi[1] != bi[2]
                                        # if w <= m-numeq
                                            @inbounds add_to_expression!(icons[Locb], imag(coe[w+1][s]), pos[i][j+1][l][t,r]+pos[i][j+1][l][t+bs,r+bs])
                                            @inbounds add_to_expression!(icons[Locb], real(coe[w+1][s]), pos[i][j+1][l][t,r+bs]-pos[i][j+1][l][r,t+bs])
                                        # else
                                        #     @inbounds add_to_expression!(icons[Locb], real(coe[w+1][s])*pos1[t,r]+imag(coe[w+1][s])*pos[i][j+1][l][t,r])
                                        # end
                                    end
                                else
                                    @inbounds add_to_expression!(rcons[Locb], real(coe[w+1][s]), pos[i][j+1][l][t,r])
                                end
                            end
                        end
                    end
                end
            end
        end
        rbc = zeros(ltsupp)
        ncons = ltsupp
        itsupp = nothing
        if ipart == true
            ind = [item[1] != item[2] for item in tsupp]
            itsupp = tsupp[ind]
            icons = icons[ind]
            ibc = zeros(length(itsupp))
            ncons += length(itsupp)
        end
        if QUIET == false
            println("There are $ncons affine constraints.")
        end
        for i = 1:length(supp[1])
            Locb = bfind(tsupp, ltsupp, supp[1][i])
            if Locb == 0
               @error "The monomial basis is not enough!"
               return nothing,ksupp,nothing,nothing,nothing
            else
               rbc[Locb] = real(coe[1][i])
               if ipart == true && supp[1][i][1] != supp[1][i][2]
                   Locb = bfind(itsupp, length(itsupp), supp[1][i])
                   ibc[Locb] = imag(coe[1][i])
               end
            end
        end
        @variable(model, lower)
        if Mommat == true
            rcons[1] += lower
            @constraint(model, rcon[i=1:ltsupp], rcons[i]==rbc[i])
            if ipart == true
                @constraint(model, icon[i=1:length(itsupp)], icons[i]==ibc[i])
            end
        else
            @constraint(model, rcons[2:end].==rbc[2:end])
            @constraint(model, rcons[1]+lower==rbc[1])
            if ipart == true
                @constraint(model, icons.==ibc)
            end
        end
        @objective(model, Max, lower)
        end
        if QUIET == false
            println("SDP assembling time: $time seconds.")
            println("Solving the SDP...")
        end
        time = @elapsed begin
        optimize!(model)
        end
        if QUIET == false
            println("SDP solving time: $time seconds.")
        end
        if writetofile != false
            write_to_file(dualize(model), writetofile)
        end
        SDP_status = termination_status(model)
        objv = objective_value(model)
        if SDP_status != MOI.OPTIMAL
           println("termination status: $SDP_status")
           status = primal_status(model)
           println("solution status: $status")
        end
        println("optimum = $objv")
        ctype = ipart==true ? ComplexF64 : Float64
        if Gram == true
            GramMat = Vector{Vector{Vector{Union{ctype,Matrix{ctype}}}}}(undef, cql)
            for i = 1:cql
                GramMat[i] = Vector{Vector{Union{ctype,Matrix{ctype}}}}(undef, 1+length(J[i]))
                for j = 1:1+length(J[i])
                    GramMat[i][j] = Vector{Union{ctype,Matrix{ctype}}}(undef, cl[i][j])
                    for l = 1:cl[i][j]
                        if ipart == true
                            bs = blocksize[i][j][l]
                            temp = value.(pos[i][j][l][1:bs,bs+1:2bs])
                            GramMat[i][j][l] = value.(pos[i][j][l][1:bs,1:bs]+pos[i][j][l][bs+1:2bs,bs+1:2bs]) + im*(temp-temp')
                        else
                            GramMat[i][j][l] = value.(pos[i][j][l])
                        end
                    end
                end
            end
        end
        if Mommat == true
            rmeasure = -dual.(rcon)
            imeasure = nothing
            if ipart == true
                imeasure = -dual.(icon)
            end
            moment = get_cmoment(rmeasure, imeasure, tsupp, itsupp, cql, blocks, cl, blocksize, basis, ipart=ipart, nb=nb)
        end
    end
    return objv,ksupp,moment,GramMat,SDP_status
end

function get_cblocks_mix(dg, J, rlorder, m, supp::Vector{Vector{Vector{Vector{UInt16}}}}, cliques, cql, cliquesize;
    tsupp=[], basis=[], blocks=[], cl=[], blocksize=[], sb=[], numb=[], TS="block", balanced=false, nb=0, merge=false, md=3)
    if isempty(tsupp)
        blocks = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        cl = Vector{Vector{UInt16}}(undef, cql)
        blocksize = Vector{Vector{Vector{UInt16}}}(undef, cql)
        sb = Vector{Vector{UInt16}}(undef, cql)
        numb = Vector{Vector{UInt16}}(undef, cql)
        basis = Vector{Vector{Vector{Vector{UInt16}}}}(undef, cql)
        tsupp = copy(supp[1])
        for i = 2:m+1, j = 1:length(supp[i])
            if supp[i][j][1] <= supp[i][j][2]
                push!(tsupp, supp[i][j])
            end
        end
        sort!(tsupp)
        unique!(tsupp)
        flag = 1
    else
        flag = 0
    end
    status = ones(Int, cql)
    for i = 1:cql
        lc = length(J[i])
        ind = [issubset(union(tsupp[j][1], tsupp[j][2]), cliques[i]) for j in eachindex(tsupp)]
        fsupp = tsupp[ind]
        if flag == 1
            basis[i] = Vector{Vector{Vector{UInt16}}}(undef, lc+1)
            basis[i][1] = get_basis(cliques[i], rlorder[i])
            for s = 1:lc
                basis[i][s+1] = get_basis(cliques[i], rlorder[i]-ceil(Int, dg[J[i][s]]/2))
            end
            blocks[i] = Vector{Vector{Vector{UInt16}}}(undef, lc+1)
            cl[i] = Vector{UInt16}(undef, lc+1)
            blocksize[i] = Vector{Vector{UInt16}}(undef, lc+1)
            sb[i] = Vector{UInt16}(undef, lc+1)
            numb[i] = Vector{UInt16}(undef, lc+1)
            blocks[i],cl[i],blocksize[i],sb[i],numb[i],status[i] = get_cblocks(lc, fsupp, supp[J[i].+1], basis[i], TS=TS, balanced=balanced, QUIET=true,
            merge=merge, md=md, nb=nb)
        else
            blocks[i],cl[i],blocksize[i],sb[i],numb[i],status[i] = get_cblocks(lc, fsupp, supp[J[i].+1], basis[i], blocks=blocks[i], cl=cl[i], blocksize=blocksize[i],
            sb=sb[i], numb=numb[i], TS=TS, balanced=balanced, QUIET=true, merge=merge, md=md, nb=nb)
        end
    end
    return blocks,cl,blocksize,sb,numb,basis,maximum(status)
end

# function assign_constraint(m, supp::Vector{Vector{Vector{Vector{UInt16}}}}, cliques, cql, cliquesize; assign="first")
#     J = [UInt32[] for i=1:cql]
#     ncc = UInt32[]
#     for i = 2:m+1
#         rind = copy(supp[i][1][1])
#         for j = 2:length(supp[i])
#             append!(rind, supp[i][j][1])
#         end
#         unique!(rind)
#         if assign == "first"
#             ind = findfirst(k->issubset(rind, cliques[k]), 1:cql)
#             if ind !== nothing
#                 push!(J[ind], i-1)
#             else
#                 push!(ncc, i-1)
#             end
#         else
#             temp = UInt32[]
#             for j = 1:cql
#                 if issubset(rind, cliques[j])
#                     push!(temp, j)
#                 end
#             end
#             if !isempty(temp)
#                 if assign == "min"
#                     push!(J[temp[argmin(cliquesize[temp])]], i-1)
#                 else
#                     push!(J[temp[argmax(cliquesize[temp])]], i-1)
#                 end
#             else
#                 push!(ncc, i-1)
#             end
#         end
#     end
#     return J,ncc
# end

function assign_constraint(m, supp::Vector{Vector{Vector{Vector{UInt16}}}}, cliques, cql, cliquesize; assign="first")
    J = [UInt32[] for i=1:cql]
    ncc = UInt32[]
    for i = 2:m+1
        rind = copy(supp[i][1][1])
        for j = 2:length(supp[i])
            append!(rind, supp[i][j][1])
        end
        unique!(rind)
        flag = 0
        for j = 1:cql
            if issubset(rind, cliques[j])
                push!(J[j], i-1)
                flag = 1
            end
        end
        if flag == 0
            push!(ncc, i-1)
        end
    end
    return J,ncc
end

function get_basis(var::Vector{UInt16}, d)
    n = length(var)
    lb = binomial(n+d,d)
    basis = Vector{Vector{UInt16}}(undef, lb)
    basis[1] = UInt16[]
    i = 0
    t = 1
    while i < d+1
        t += 1
        if length(basis[t-1])>=i && basis[t-1][end-i+1:end] == var[n]*ones(UInt16, i)
           if i < d
               basis[t] = var[1]*ones(UInt16, i+1)
           end
           i += 1
        else
            j = bfind(var, n, basis[t-1][1])
            basis[t] = copy(basis[t-1])
            ind = findfirst(x->basis[t][x]!=var[j], 1:length(basis[t]))
            if ind === nothing
                ind = length(basis[t])+1
            end
            if j != 1
                basis[t][1:ind-2] = var[1]*ones(UInt16, ind-2)
            end
            basis[t][ind-1] = var[j+1]
        end
    end
    return basis
end

function get_graph(tsupp::Vector{Vector{Vector{UInt16}}}, basis; nb=0, balanced=false)
    lb = length(basis)
    G = SimpleGraph(lb)
    ltsupp = length(tsupp)
    for i = 1:lb, j = i+1:lb
        if balanced == false || length(basis[i]) == length(basis[j])
            bi = [basis[i], basis[j]]
            if nb > 0
                bi = reduce_unitnorm(bi, nb=nb)
            end
            if bi[1] > bi[2]
                bi = bi[2:-1:1]
            end
            if bfind(tsupp, ltsupp, bi) != 0
                add_edge!(G, i, j)
            end
        end
    end
    return G
end

function get_cgraph(tsupp::Vector{Vector{Vector{UInt16}}}, supp, basis; nb=0, balanced=false)
    lb = length(basis)
    ltsupp = length(tsupp)
    G = SimpleGraph(lb)
    for i = 1:lb, j = i+1:lb
        if balanced == false || length(basis[i]) == length(basis[j])
            r = 1
            while r <= length(supp)
                bi = [sadd(basis[i], supp[r][1]), sadd(basis[j], supp[r][2])]
                if nb > 0
                    bi = reduce_unitnorm(bi, nb=nb)
                end
                if bi[1] > bi[2]
                    bi = bi[2:-1:1]
                end
                if bfind(tsupp, ltsupp, bi) != 0
                   break
                else
                    r += 1
                end
            end
            if r <= length(supp)
                add_edge!(G, i, j)
            end
        end
    end
    return G
end

function clique_decomp(n, m, dg, supp::Vector{Vector{Vector{Vector{UInt16}}}}; order="min", alg="MF", minimize=false)
    if alg == false
        cliques = [UInt16[i for i=1:n]]
        cql = 1
        cliquesize = [n]
    else
        G = SimpleGraph(n)
        for i = 1:m+1
            if order == "min" || i == 1 || order == ceil(Int, dg[i-1]/2)
                for j = 1:length(supp[i])
                    add_clique!(G, unique([supp[i][j][1];supp[i][j][2]]))
                end
            else
                temp = copy(supp[i][1][1])
                for j = 2:length(supp[i])
                    append!(temp, supp[i][j][1])
                end
                add_clique!(G, unique(temp))
            end
        end
        if alg == "NC"
            cliques,cql,cliquesize = max_cliques(G)
        else
            cliques,cql,cliquesize = chordal_cliques!(G, method=alg, minimize=minimize)
        end
    end
    uc = unique(cliquesize)
    sizes = [sum(cliquesize.== i) for i in uc]
    println("-----------------------------------------------------------------------------")
    println("The clique sizes of varibles:\n$uc\n$sizes")
    println("-----------------------------------------------------------------------------")
    return cliques,cql,cliquesize
end

function get_cmoment(rmeasure, imeasure, tsupp, itsupp, cql, blocks, cl, blocksize, basis; ipart=true, nb=0)
    moment = Vector{Vector{Matrix{Union{Float64,ComplexF64}}}}(undef, cql)
    for i = 1:cql
        moment[i] = Vector{Matrix{Union{Float64,ComplexF64}}}(undef, cl[i][1])
        for l = 1:cl[i][1]
            bs = blocksize[i][1][l]
            rtemp = zeros(Float64, bs, bs)
            if ipart == true
                itemp = zeros(Float64, bs, bs)
            end
            for t = 1:bs, r = t:bs
                ind1 = blocks[i][1][l][t]
                ind2 = blocks[i][1][l][r]
                bi = [basis[i][1][ind1], basis[i][1][ind2]]
                if nb > 0
                    bi = reduce_unitnorm(bi, nb=nb)
                end
                if ipart == true
                    if bi[1] < bi[2]
                        Locb = bfind(itsupp, length(itsupp), bi)
                        itemp[t,r] = imeasure[Locb]
                    elseif bi[1] > bi[2]
                        Locb = bfind(itsupp, length(itsupp), bi[2:-1:1])
                        itemp[t,r] = -imeasure[Locb]
                    end
                end
                if bi[1] <= bi[2]
                    Locb = bfind(tsupp, length(tsupp), bi)
                else
                    Locb = bfind(tsupp, length(tsupp), bi[2:-1:1])
                end
                rtemp[t,r] = rmeasure[Locb]
            end
            rtemp = (rtemp + rtemp')/2
            if ipart == true
                itemp = (itemp - itemp')/2
                moment[i][l] = rtemp - itemp*im
            else
                moment[i][l] = rtemp
            end
        end
    end
    return moment
end

function resort(supp, coe; nb=0)
    if nb > 0
        supp = reduce_unitnorm.(supp, nb=nb)
    end
    nsupp = copy(supp)
    sort!(nsupp)
    unique!(nsupp)
    l = length(nsupp)
    ncoe = zeros(typeof(coe[1]), l)
    for i in eachindex(supp)
        locb = bfind(nsupp, l, supp[i])
        ncoe[locb] += coe[i]
    end
    return nsupp,ncoe
end

# function sign_type(a::Vector{UInt16})
#     st = UInt8[]
#     if length(a) == 1
#         push!(st, a[1])
#     elseif length(a) > 1
#         r = 1
#         for i = 2:length(a)
#             if a[i] == a[i-1]
#                 r += 1
#             else
#                 if isodd(r)
#                     push!(st, a[i-1])
#                 end
#                 r = 1
#             end
#         end
#         if isodd(r)
#             push!(st, a[end])
#         end
#     end
#     return st
# end
