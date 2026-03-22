function [PANELS, TRIB_AREA, PANEL_AREAS] = gridshell_panels(NODE, BARS, opts)
% GRIDHSELL_PANELS  Recover polygonal panels (faces) from node + member connectivity
% and compute node tributary areas.
%
% Inputs
%   NODE : (N x 3) double, node coordinates [x y z]
%   BARS : (M x 2) integer, undirected member connectivity (1-based indices)
%   opts : (struct, optional)
%       .tolAng    : angular tolerance for sorting (default 1e-9)
%       .dropOuter : logical, drop the outer/unbounded face (default true)
%       .shareRule : 'equal' (default) or 'voronoi' [equal shares are robust]
%
% Outputs
%   PANELS       : (cell array) each cell is a 1xK list of node indices (CCW order)
%   TRIB_AREA    : (N x 1) tributary area at each node (sum of equal shares by default)
%   PANEL_AREAS  : (P x 1) area of each panel in 3D
%
% Assumptions
%   * BARS form a manifold graph on a (piecewise) smooth shell without T-junctions.
%   * Panels are simple polygons (mostly triangles/quads) with no self-intersections.
%   * There may be an outer boundary; by default it is detected and dropped.
%
% Example
%   % [PANELS, TRIB_AREA, PANEL_AREAS] = gridshell_panels(NODE, BARS);
%
% References: half-edge/DCEL face-walking with local planar embedding via PCA.

if nargin < 3, opts = struct(); end
if ~isfield(opts,'tolAng'),    opts.tolAng    = 1e-9; end
if ~isfield(opts,'dropOuter'), opts.dropOuter = true; end
if ~isfield(opts,'shareRule'), opts.shareRule = 'equal'; end

NODE = double(NODE);
BARS = double(BARS);

% 1) Build half-edge structure and local angular ordering around each vertex
HE = build_halfedges(NODE, BARS, opts);

% 2) Face-walk using "turn left" rule (previous edge around head)
faces = face_walk(HE);

% 3) Convert to node cycles, compute areas, optionally drop outer face
P = numel(faces);
PANELS = {};
PANEL_AREAS = [];
for f = 1:P
    hedges = faces{f};
    if isempty(hedges), continue; end
    vloop = HE.to(hedges(:));
    % Remove immediate duplicates and ensure simple cycle
    vloop = unique_consecutive(vloop);
    if numel(vloop) < 3, continue; end
    [Af,~,~] = polygon_area3D(NODE(vloop,:));
    if Af < 1e-12, continue; end
    PANELS{end+1,1} = vloop(:)'; %#ok<AGROW>
    PANEL_AREAS(end+1,1) = Af; %#ok<AGROW>
end

% 4) Drop the outer/unbounded face (largest area) if requested
if opts.dropOuter && ~isempty(PANEL_AREAS)
    [~,imax] = max(PANEL_AREAS);
    PANELS(imax) = [];
    PANEL_AREAS(imax) = [];
end

% 5) Tributary area at nodes
N = size(NODE,1);
TRIB_AREA = zeros(N,1);

switch lower(opts.shareRule)
    case 'equal'
        for p = 1:numel(PANELS)
            vids = PANELS{p};
            k = numel(vids);
            A = PANEL_AREAS(p);
            TRIB_AREA(vids) = TRIB_AREA(vids) + (A/k);
        end
    case 'voronoi'
        % Simple mixed Voronoi/Barycentric (no obtuse handling).
        % For robustness on arbitrary shells, equal share is recommended.
        for p = 1:numel(PANELS)
            vids = PANELS{p};
            V = NODE(vids,:);
            A = PANEL_AREAS(p);
            w = polygon_vertex_voronoi_weights(V);
            TRIB_AREA(vids) = TRIB_AREA(vids) + A * w(:);
        end
    otherwise
        error('Unknown shareRule: %s', opts.shareRule);
end

end

%% ===================== Helpers ===================== %%
function HE = build_halfedges(NODE, BARS, opts)
% Create half-edges for each undirected bar (i,j) -> two directed half-edges
M = size(BARS,1);
N = size(NODE,1);

i = BARS(:,1); j = BARS(:,2);
all_i = [i; j];
all_j = [j; i];
H = numel(all_i);                 % number of half-edges

HE.from = all_i(:);
HE.to   = all_j(:);

% Twin mapping: h and h+M are twins
HE.twin = [(1:M)'+M; (1:M)'];

% For each vertex, compute local tangent frame via PCA of neighbors
neighbors = accumarray(HE.from, HE.to, [N,1], @(x){x});
if numel(neighbors) < N
    tmp = cell(N,1); tmp(1:numel(neighbors)) = neighbors; neighbors = tmp; %#ok<NASGU>
end

% Precompute local frames and outgoing half-edges lists
HE.out = cell(N,1);
HE.ang = zeros(H,1); % angle of each half-edge around its origin in local plane

for v = 1:N
    HE.out{v} = find(HE.from == v).';
    nb = unique(HE.to(HE.out{v}));
    if numel(nb) < 2
        % Degenerate: pick arbitrary frame
        nrm = [0 0 1]';
        t1 = [1 0 0]'; t2 = [0 1 0]';
    else
        % Local PCA for normal
        P = NODE([v; nb],:);
        C = cov(P);
        [evec,evals] = eig(C);
        [~,imin] = min(diag(evals));
        nrm = evec(:,imin);
        % Orthonormal tangent basis
        a = [1 0 0]'; if abs(dot(a,nrm))>0.9, a=[0 1 0]'; end
        t1 = cross(nrm,a); t1 = t1/norm(t1);
        t2 = cross(nrm,t1);
    end
    p0 = NODE(v,:).';
    for h = HE.out{v}
        p1 = NODE(HE.to(h),:).';
        d = p1 - p0;
        x = dot(d,t1); y = dot(d,t2);
        HE.ang(h) = atan2(y,x);
    end
    % Sort outgoing half-edges CCW by angle
    [~,ord] = sort(HE.ang(HE.out{v}));
    HE.out{v} = HE.out{v}(ord);
end

% Next mapping: for a half-edge h: u=from(h), v=to(h).
% Go to twin at (v->u), then take the PREVIOUS half-edge around v to "turn left".
HE.next = zeros(H,1);
for h = 1:H
    v = HE.to(h);
    ht = HE.twin(h);
    out_v = HE.out{v};
    % Find index of twin among outgoing from v
    k = find(out_v == ht, 1);
    if isempty(k)
        error('Twin not found in outgoing list (non-manifold?).');
    end
    kprev = k - 1; if kprev < 1, kprev = numel(out_v); end
    HE.next(h) = out_v(kprev);
end

end

function faces = face_walk(HE)
H = numel(HE.from);
seen = false(H,1);
faces = {};
for h = 1:H
    if seen(h), continue; end
    % Walk cycle starting at h
    cyc = [];
    hh = h;
    while ~seen(hh)
        seen(hh) = true;
        cyc(end+1) = hh; %#ok<AGROW>
        hh = HE.next(hh);
        if isempty(hh) || hh==0, break; end
    end
    % Validate cycle closure
    if ~isempty(cyc) && HE.from(cyc(1))==HE.to(cyc(end))
        faces{end+1} = cyc; %#ok<AGROW>
    else
        % open walk (boundary); still store if forms a loop later
        faces{end+1} = cyc; %#ok<AGROW>
    end
end
end

function v = unique_consecutive(v)
% remove consecutive duplicates and wrap-around duplicate
if isempty(v), return; end
mask = [true, diff(v(:)')~=0];
v = v(mask);
if numel(v)>=2 && v(1)==v(end)
    v = v(1:end-1);
end
end

function [A, n, c] = polygon_area3D(V)
% Newell's method for 3D polygon area and normal
% V: (K x 3)
K = size(V,1);
Nx = 0; Ny = 0; Nz = 0;
Cx = 0; Cy = 0; Cz = 0;
for i = 1:K
    i2 = i+1; if i2>K, i2=1; end
    Xi = V(i,1); Yi = V(i,2); Zi = V(i,3);
    Xj = V(i2,1); Yj = V(i2,2); Zj = V(i2,3);
    Nx = Nx + (Yi - Yj)*(Zi + Zj);
    Ny = Ny + (Zi - Zj)*(Xi + Xj);
    Nz = Nz + (Xi - Xj)*(Yi + Yj);
    Cx = Cx + (Xi + Xj)*(Xi*Yj - Xj*Yi);
    Cy = Cy + (Yi + Yj)*(Xi*Yj - Xj*Yi);
    Cz = Cz + (Zi + Zj)*(Xi*Yj - Xj*Yi);
end
n = [Nx Ny Nz];
A = 0.5 * norm(n);
if A > 0
    n = n / (2*A); % unit normal
else
    n = [0 0 1];
end
c = [Cx Cy Cz] / (6*max(A,eps));
end

function w = polygon_vertex_voronoi_weights(V)
% Very light-weight area split: equal to internal angle fractions / sum
% (Not exact Voronoi; used as a smooth proxy.)
K = size(V,1);
ang = zeros(K,1);
for i = 1:K
    im = i-1; if im<1, im=K; end
    ip = i+1; if ip>K, ip=1; end
    a = V(im,:) - V(i,:);
    b = V(ip,:) - V(i,:);
    ang(i) = real(acos( max(-1,min(1, dot(a,b)/(norm(a)*norm(b)+eps))) ));
end
w = ang / sum(ang);
end
