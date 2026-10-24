function [L2, S] = job_replay(L, ctx, J, jo)
%JOB_REPLAY  Execute a fluid schedule with discrete rigid gang jobs (job-level check of the fluid model).
%   L   : log of a closed-loop run (L.y = busy deferrable GPUs per class and step of the fluid plant)
%   ctx : case context (par, inp.real.flex, ev, base)
%   J   : job population from JOB_GEN whose undisturbed occupancy follows ctx.inp.real.flex
%   jo  : job-level options (defaults in brackets)
%     t_save  [1]   checkpoint written just before a planned pause: progress lost (min, GPUs busy)
%     t_rs    [5]   restart overhead after a resume (min; GPUs busy, no progress)
%     t_minp  [15]  minimum pause (min)
%     ck_mode ['on_pause'] or 'periodic': no checkpoint at the pause, the progress since the last periodic
%                   checkpoint is lost (uniform on [0, t_ck])
%     t_ck    [30]  periodic checkpoint interval (min)
%     hyst    [30]  laxity bonus of running jobs (min), avoids needless pause / resume cycles
%     seed    [7]   generator seed for periodic checkpoint losses
%   The fluid deviation from nominal of each class in each 15-min step, y_c - flex_c, is added to the
%   job-level nominal occupancy of that class in every minute of the step to give per-class targets. Jobs are ranked by laxity
%   (completion deadline = nominal end + L_c, minus now, minus the run time still needed). A job that
%   would miss its deadline if held for this step runs regardless of the target. The others are
%   admitted in laxity order while they fit their class target, then the remaining gap of the total is
%   backfilled with jobs of any class. Inside called DR events and their rebound windows the total
%   target is never exceeded; elsewhere a job is admitted when that brings the total closer to the
%   target. Jobs are rigid: a job runs on its whole gang at nominal speed or not at all, so delayed work
%   is only worked off when the job passes its nominal end.
%   L2  : log with the job-level IT power, grid power (the electric chiller serves the cooling
%         difference; storage and gas engine as in the fluid run), backlog and overdue work, so that
%         EVALUATE_RUN settles the job-level execution.
%   S   : statistics (tracking, overheads, service-level, power steps), see the end of the file.
if nargin < 4, jo = struct(); end
t_save = getf(jo, 't_save', 1); t_rs = getf(jo, 't_rs', 5); t_minp = getf(jo, 't_minp', 15);
ckp = strcmp(getf(jo, 'ck_mode', 'on_pause'), 'periodic'); t_ck = getf(jo, 't_ck', 30);
hyst = getf(jo, 'hyst', 30); xr = getf(jo, 'seed', 7);
par = ctx.par; d = sys_derived(par); dt = par.dt; ns = round(60 * dt);
T = numel(L.pg); flex = ctx.inp.real.flex(1:T, :); ev = ctx.ev;
Lc = round(60 * par.it.lag_h(:)');
cls = J.cls(:); g = J.g(:); s = J.s(:); dd = J.d(:); e = J.e(:); n = numel(g);
dl = e + Lc(cls)';                                  % completion deadlines (min)
tie = 1e-3 * mod((1:n)' * 0.6180339887498949, 1);   % deterministic tie-breaker
%% job-level nominal occupancy per class (per minute and step); targets per minute = nominal
%  occupancy of the minute + planned deviation of the step
NM = zeros(ns * T, 3); Nc = zeros(T, 3);
for c = 1:3
    k = cls == c;
    a = max(s(k), 0); b = min(e(k), ns * T);
    v = accumarray(a + 1, g(k), [ns * T + 1, 1]) - accumarray(b + 1, g(k), [ns * T + 1, 1]);
    v = cumsum(v); NM(:, c) = v(1:ns * T);
    Nc(:, c) = mean(reshape(NM(:, c), ns, T), 1)';
end
stp = kron((1:T)', ones(ns, 1));
Ym = max(NM + L.y(stp, :) - flex(stp, :), 0);
Y = sum(Ym, 2);
fl = false(T, 1);                                   % never exceed the target in events / rebound windows
for k = 1:numel(ev)
    if isfield(ev, 'called') && ~ev(k).called, continue; end
    fl(ev(k).s:ev(k).e) = true; w = ev(k).win(ev(k).win <= T); fl(w) = true;
end
%% state: 0 future, 1 waiting (released, never run), 2 running, 3 paused, 4 done
st = zeros(n, 1); rem = dd; ovh = zeros(n, 1); tp = -Inf(n, 1); npz = zeros(n, 1);
pre = s < 0; st(pre) = 2; rem(pre) = e(pre);        % running on schedule at 00:00
busy = zeros(ns * T, 1); busyc = zeros(T, 3);
B = zeros(T, 3); OV = zeros(T, 1);
lagmax = zeros(n, 1);                               % largest lag of each job (min)
ovh_gm = 0; lost_gm = 0;
for t = 1:T
    t0 = (t - 1) * ns;
    st(st == 0 & s <= t0) = 1;
    %% decision at the step boundary
    act = find(st >= 1 & st <= 3);
    sa = st(act); run = sa == 2; wai = sa == 1; pau = sa == 3;
    lax = dl(act) - t0 - rem(act) - ovh(act);
    need = ns * ones(numel(act), 1);                 % lag added if the job is held during this step
    lck = t_save; if ckp, lck = t_ck; end            % worst-case progress lost at a pause
    need(run) = lck + t_rs + max(t_minp, ns); need(pau) = t_rs + ns;
    forced = lax - need < 0;
    elig = ~forced & (run | wai | (pau & t0 - tp(act) >= t_minp));
    key = lax - t_rs * pau - hyst * run + tie(act);
    sel = forced;
    bc = accumarray(cls(act(sel)), g(act(sel)), [3 1])';
    cand = find(elig); [~, o] = sort(key(cand)); cand = cand(o);
    left = true(numel(cand), 1);
    for q = 1:numel(cand)                            % stage 1: per-class targets
        j = act(cand(q)); c = cls(j);
        if bc(c) + g(j) <= Ym(t0 + 1, c) + 1e-9, sel(cand(q)) = true; bc(c) = bc(c) + g(j); left(q) = false; end
    end
    btot = sum(bc); slack = 0.5 * ~fl(t);
    for q = find(left)'                               % stage 2: backfill the total
        j = act(cand(q));
        if btot + (1 - slack) * g(j) <= Y(t0 + 1) + 1e-9, sel(cand(q)) = true; btot = btot + g(j); end
    end
    jp = act(run & ~sel);                            % pause (checkpoint first)
    if ~isempty(jp)
        st(jp) = 3; tp(jp) = t0; npz(jp) = npz(jp) + 1;
        if ckp, [u, xr] = lcg_rand(xr, numel(jp)); loss = u * t_ck; else, loss = t_save * ones(numel(jp), 1); end
        loss = min(loss, dd(jp) - rem(jp));          % cannot lose more than the progress made
        rem(jp) = rem(jp) + loss; lost_gm = lost_gm + sum(g(jp) .* loss);
    end
    jr = act(pau & sel); st(jr) = 2; ovh(jr) = ovh(jr) + t_rs; ovh_gm = ovh_gm + t_rs * sum(g(jr));
    st(act(wai & sel)) = 2;
    %% minutes of the step
    for k = 0:ns - 1
        tau = t0 + k;
        if k > 0
            st(st == 0 & s <= tau) = 1;
            on = st == 2; cur = sum(g(on));
            cand = find(st == 1 | (st == 3 & tau - tp >= t_minp) | (st == 3 & dl - tau - rem - ovh - t_rs < 1));
            if ~isempty(cand)
                isp = st(cand) == 3;
                lx = dl(cand) - tau - rem(cand) - ovh(cand) - t_rs * isp;
                frc = lx < 1;
                [~, o] = sort(lx + tie(cand));
                for q = o(:)'
                    j = cand(q);
                    if frc(q) || cur + (1 - slack) * g(j) <= Y(tau + 1) + 1e-9
                        if isp(q), ovh(j) = ovh(j) + t_rs; ovh_gm = ovh_gm + t_rs * g(j); end
                        st(j) = 2; cur = cur + g(j);
                    end
                end
            end
        end
        on = find(st == 2);
        busy(tau + 1) = sum(g(on));
        busyc(t, :) = busyc(t, :) + accumarray(cls(on), g(on), [3 1])' / ns;
        oh = ovh(on) > 0;
        ovh(on(oh)) = ovh(on(oh)) - 1;
        pr = on(~oh); rem(pr) = rem(pr) - 1;
        dn = pr(rem(pr) <= 0);
        if ~isempty(dn)
            lagmax(dn) = max(lagmax(dn), tau + 1 + rem(dn) - e(dn)); st(dn) = 4;
        end
    end
    %% backlog and overdue work at the end of the step (GPU-h behind the nominal progress)
    te = t0 + ns;
    a = find(st >= 1 & st <= 3);
    lag = max((te - s(a)) - (dd(a) - rem(a)), 0);
    lagmax(a) = max(lagmax(a), lag);
    B(t, :) = accumarray(cls(a), g(a) .* lag / 60, [3 1])';
    OV(t) = sum(g(a) .* max(lag - Lc(cls(a))', 0)) / 60;
end
%% job-level log (fluid frame: job-level busy GPUs minus job-level nominal plus fluid nominal)
Yhat = mean(reshape(busy, ns, T), 1)';
dev = (Yhat - sum(Nc, 2)) - sum(L.y(1:T, :) - flex, 2);     % GPUs
dpit = d.pdyn * dev;
L2 = L;
L2.pit = L.pit + dpit;
L2.qec = max(L.qec + par.fac.theta * dpit, 0);
L2.pg = L.pg + (1 + par.fac.a_aux) * dpit + (L2.qec - L.qec) ./ L.cop;
L2.backlog = B; L2.overdue = OV; L2.over = max(L2.pg - d.Pcap, 0);
L2.y = busyc - Nc + flex;
%% statistics
dpg = L2.pg - L.pg;
evs = false(T, 1); S.ev_dev = NaN(numel(ev), 1);
for k = 1:numel(ev)
    if isfield(ev, 'called') && ~ev(k).called, continue; end
    evs(ev(k).s:ev(k).e) = true; S.ev_dev(k) = mean(dpg(ev(k).s:ev(k).e));
end
S.rmse_pg = sqrt(mean(dpg .^ 2));                 % MW, grid power vs fluid
S.max_dev = max(abs(dpg));
S.over_defer = sum(max(-dev(evs), 0)) * dt;       % GPU-h deferred beyond the plan in events
S.rec_short = sum(max(-dev(~evs), 0)) * dt;       % GPU-h of planned (recovery) load not executed elsewhere
S.extra_run = sum(max(dev, 0)) * dt;              % GPU-h run above the plan (forced jobs, rounding)
S.class_mae = mean(abs(busyc - Nc - (L.y(1:T, :) - flex)), 1);   % GPUs, per class
S.n_pause = sum(npz); S.n_paused_jobs = sum(npz > 0); S.n_jobs = n;
S.ovh_GPUh = ovh_gm / 60; S.lost_GPUh = lost_gm / 60;
S.ovh_MWh = (S.ovh_GPUh + S.lost_GPUh) * d.eps_ref;
S.B_end = sum(B(T, :)); S.B_end_fluid = sum(L.backlog(T, :));
S.lateness = sum(OV) * dt;                         % GPU-h * h
for c = 1:3
    k = cls == c;
    S.lag_max_ratio(c) = max([0; lagmax(k)]) / Lc(c);
    S.late_share(c) = sum(g(k) .* (lagmax(k) > Lc(c) + 1e-6)) / max(sum(g(k)), 1e-9);
end
S.step_max_MW = max(abs(diff(busy))) * d.pdyn;     % largest 1-min change of deferrable IT power
pz = npz > 0;
S.gang_max_MW = max([0; g(pz)]) * d.pdyn;          % largest gang that was paused
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
