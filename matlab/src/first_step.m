function u = first_step(x, ix)
%FIRST_STEP  Extract the first-step decisions (scenario 1) from a solved model.
u.y = [x(ix.Y{1}(1,1)), x(ix.Y{2}(1,1)), x(ix.Y{3}(1,1))];
u.z = [0 0 0]; if isfield(ix, 'Zc') && ~isempty(ix.Zc), u.z = [x(ix.Zc{1}(1,1)), x(ix.Zc{2}(1,1)), x(ix.Zc{3}(1,1))]; end
u.pch = x(ix.PCH(1,1)); u.pdis = x(ix.PDS(1,1));
u.pgt = x(ix.PGT(1,1)); u.hac = x(ix.HAC(1,1));
u.qtc = x(ix.QTC(1,1)); u.qtd = x(ix.QTD(1,1));
u.qth = 0; if isfield(ix, 'QHC') && ~isempty(ix.QHC), u.qth = x(ix.QHC(1,1)) - x(ix.QHD(1,1)); end
end
