function [on, Eref, Sref, Href] = terminal_ref(ctx, tend)
%TERMINAL_REF  Terminal SOC references: day-ahead/nominal trajectory at the horizon end.
on = true;
if isfield(ctx, 'Eterm') && ~isempty(ctx.Eterm), Ev = ctx.Eterm; Sv = ctx.Sterm; else, Ev = ctx.Eref; Sv = ctx.Sref; end
Eref = Ev(min(tend, numel(Ev)));
Sref = Sv(min(tend, numel(Sv)));
Href = 0; if isfield(ctx, 'Href') && ~isempty(ctx.Href), Href = ctx.Href(min(tend, numel(ctx.Href))); end
end
