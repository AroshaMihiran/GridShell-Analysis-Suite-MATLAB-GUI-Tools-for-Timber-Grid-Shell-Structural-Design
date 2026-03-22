function [PE,PEi,PEe]=GetPotential(NODE,BARS,Uf,F,K,FREE,L0)

U = zeros(3*size(NODE,1),1);
U(FREE) = Uf;
D = reshape(U,3,numel(U)/3)';
DNODE = NODE + D;
Ln = GetL(DNODE,BARS);

if isscalar(K),
    PEi = 1/2*sum((Ln-L0).^2)*K;
else
    PEi = 1/2*dot((Ln-L0).^2,K);
end
PEe = dot(U,F);

PE = PEi - PEe;