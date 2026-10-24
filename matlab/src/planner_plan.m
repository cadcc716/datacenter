function [u, info] = planner_plan(st, data, ctx)
%PLANNER_PLAN  Replay a pre-computed (open-loop) plan: ctx.plan.y(T x 3), pch, pdis, pgt, hac, qtc, qtd.
t = st.t; p = ctx.plan;
u.y = p.y(t, :); u.z = [0 0 0]; if isfield(p, 'z'), u.z = p.z(t, :); end
u.pch = p.pch(t); u.pdis = p.pdis(t); u.pgt = p.pgt(t);
u.hac = p.hac(t); u.qtc = p.qtc(t); u.qtd = p.qtd(t);
u.qth = 0; if isfield(p, 'qth'), u.qth = p.qth(t); end
u.php = 0; if isfield(p, 'php'), u.php = p.php(t); end
info.ok = true; info.time = 0; info.fallback = false;
end
