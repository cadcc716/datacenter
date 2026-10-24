function so = mpc_solver(ctx)
%MPC_SOLVER  Solver options of a rolling-horizon (MPC) step: as ctx.solver, with a MILP time limit of
%   30 s unless one is set. An MPC step normally solves in well under a second; a rare hard
%   branch-and-bound instance then returns its best feasible solution, or the planner falls back to the
%   rule-based action, instead of stalling the closed loop. (Day-ahead models keep the 300-s default.)
so = ctx.solver;
if ~isfield(so, 'tmlim') || isempty(so.tmlim), so.tmlim = 30; end
end
