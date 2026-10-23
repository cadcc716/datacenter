function st = state_init(par, nev)
%STATE_INIT  Initial plant state at 00:00 of the DR day (no backlog, nominal SOC).
d = sys_derived(par);
st.t = 1;
st.E = par.bess.E0;
st.S = par.tes.S0;
st.pgt_prev = 0;
st.rem = zeros(par.Tsim + d.nlagmax + 2, 3);   % remaining GPU-h by deadline step
st.ev_r  = zeros(nev, 1);   % sum of realised reductions (MW*steps)
st.ev_n  = zeros(nev, 1);   % elapsed event steps
st.ev_mx = zeros(nev, 1);   % max grid power inside event (MW)
st.rb    = zeros(nev, 1);   % max rebound in post-event window (MW)
st.late  = 0;               % accumulated lateness (GPU-h * h)
st.y_prev = NaN;            % deferrable GPUs executed in the previous step (for the ramp limit)
st.TH = 0;                  % heat stored in the data hall above the set-point (MWh_th, thermal-inertia option)
st.acc = zeros(1, 4);       % accrued facility, IT, PV and consumption energy (MWh) for the policy constraints
end
