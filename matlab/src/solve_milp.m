function sol = solve_milp(P, opts)
%SOLVE_MILP  Solve  min f'x  s.t. Aineq x <= bineq, Aeq x = beq, lb <= x <= ub, x(intcon) integer.
%   Back ends (chosen automatically, or via opts.solver):
%     'gurobi'  - Gurobi MATLAB interface (if on the path)
%     'matlab'  - Optimization Toolbox linprog / intlinprog
%     'glpk'    - GNU Octave built-in glpk
%   sol.x, sol.fval, sol.ok (true if optimal, or a feasible MILP solution at the time limit),
%   sol.marg_ineq / sol.marg_eq = d(objective)/d(rhs) for LPs (empty for MILPs), sol.solver, sol.time,
%   sol.timelimit (true if a MILP stopped at opts.tmlim seconds with its best feasible solution;
%   default 300 s, so that a rare hard branch-and-bound instance cannot stall a long experiment).
if nargin < 2, opts = struct(); end
if ~isfield(opts, 'solver') || isempty(opts.solver), opts.solver = pick_solver(); end
if ~isfield(opts, 'duals'), opts.duals = false; end
if ~isfield(opts, 'tmlim') || isempty(opts.tmlim), opts.tmlim = 300; end
n = numel(P.f);
lb = P.lb; ub = P.ub;
tic0 = tic;
sol.x = []; sol.fval = NaN; sol.ok = false; sol.marg_ineq = []; sol.marg_eq = []; sol.timelimit = false;
sol.solver = opts.solver;
isMIP = ~isempty(P.intcon);
switch opts.solver
    case 'gurobi'
        model.obj = full(P.f); model.A = [P.Aineq; P.Aeq];
        model.rhs = full([P.bineq; P.beq]);
        model.sense = [repmat('<', size(P.Aineq,1), 1); repmat('=', size(P.Aeq,1), 1)];
        model.lb = full(lb); model.ub = full(ub);
        vt = repmat('C', n, 1); vt(P.intcon) = 'B'; model.vtype = vt; model.modelsense = 'min';
        prm.OutputFlag = 0; prm.TimeLimit = opts.tmlim;
        r = gurobi(model, prm);
        if strcmp(r.status, 'TIME_LIMIT') && isfield(r, 'x') && ~isempty(r.x)
            sol.x = r.x; sol.fval = r.objval; sol.ok = true; sol.timelimit = true;
        end
        if strcmp(r.status, 'OPTIMAL')
            sol.x = r.x; sol.fval = r.objval; sol.ok = true;
            if ~isMIP && isfield(r, 'pi')
                ni = size(P.Aineq,1);
                sol.marg_ineq = r.pi(1:ni); sol.marg_eq = r.pi(ni+1:end);
            end
        end
    case 'matlab'
        if isMIP
            o = optimoptions('intlinprog', 'Display', 'off', 'MaxTime', opts.tmlim);
            [x, fv, ef] = intlinprog(P.f, P.intcon, P.Aineq, P.bineq, P.Aeq, P.beq, lb, ub, o);
            if ef > 0, sol.x = x; sol.fval = fv; sol.ok = true; end
            if ef == 2, sol.timelimit = true; end
        else
            o = optimoptions('linprog', 'Display', 'off');
            [x, fv, ef, ~, lam] = linprog(P.f, P.Aineq, P.bineq, P.Aeq, P.beq, lb, ub, o);
            if ef > 0
                sol.x = x; sol.fval = fv; sol.ok = true;
                sol.marg_ineq = -lam.ineqlin; sol.marg_eq = -lam.eqlin;
            end
        end
    case 'glpk'
        A = [P.Aineq; P.Aeq]; b = full([P.bineq; P.beq]);
        ctype = [repmat('U', size(P.Aineq,1), 1); repmat('S', size(P.Aeq,1), 1)];
        vtype = repmat('C', n, 1); vtype(P.intcon) = 'I';
        lbg = full(lb); ubg = full(ub);
        prm.msglev = 0;
        if isMIP, prm.presol = 1; prm.tmlim = round(1000 * opts.tmlim); end
        if size(A,1) == 0, A = sparse(1, n); b = 0; ctype = 'U'; end
        [x, fv, err, extra] = glpk(full(P.f), A, b, lbg, ubg, ctype, vtype, 1, prm);
        if isMIP && err == 9 && extra.status == 2                 % time limit: keep the best feasible solution
            sol.x = x; sol.fval = fv; sol.ok = true; sol.timelimit = true;
        end
        if err == 0 && (extra.status == 5 || extra.status == 2 && ~isMIP)
            sol.x = x; sol.fval = fv; sol.ok = (extra.status == 5);
            if ~isMIP && isfield(extra, 'lambda')
                ni = size(P.Aineq,1);
                lam = extra.lambda(:);
                if numel(lam) == size(A,1)
                    sol.marg_ineq = lam(1:ni); sol.marg_eq = lam(ni+1:end);
                end
            end
        end
    otherwise
        error('solve_milp:solver', 'unknown solver %s', opts.solver);
end
sol.time = toc(tic0);
end

function s = pick_solver()
persistent cached
if ~isempty(cached), s = cached; return; end
if exist('OCTAVE_VERSION', 'builtin')
    s = 'glpk';
elseif exist('gurobi', 'file') == 2 || exist('gurobi', 'file') == 3
    s = 'gurobi';
elseif exist('intlinprog', 'file')
    s = 'matlab';
else
    error('solve_milp:nosolver', 'No LP/MILP solver found (need Optimization Toolbox, Gurobi, or Octave glpk).');
end
cached = s;
end
