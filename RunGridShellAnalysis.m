function RunGridShellAnalysis(csv_dir)
% RunGridShellAnalysis - Enhanced with comprehensive plotting and PE tracking
% Input: csv_dir - directory containing CSV files from GUI

    clc;
    fprintf('=== GridShell Analysis Starting ===\n');
    fprintf('CSV Directory: %s\n', csv_dir);
    
    %% GLOBAL VARIABLES FOR ENHANCED TRACKING
    global PE_iteration_data;
    
    %% Add paths for required functions
    addpath('./FFMS');
    
    % Font Settings for plots - Times New Roman
    FontSizes.Title = 26;
    FontSizes.AxisLabel = 22;
    FontSizes.TickLabel = 20;
    FontSizes.Legend = 20;
    FontSizes.ColorbarLabel = 22;
    FontSizes.FontName = 'Times New Roman';
    
    % Set default font for all figures
    set(0, 'DefaultAxesFontName', 'Times New Roman');
    set(0, 'DefaultTextFontName', 'Times New Roman');
    
    %% DATA IMPORT FROM CSV FILES
    fprintf('Loading data from CSV files...\n');
    
    % Import nodal coordinates
    nodal_file = fullfile(csv_dir, 'nodal_coordinates.csv');
    if ~exist(nodal_file, 'file')
        error('nodal_coordinates.csv not found!');
    end
    nodal_data = readtable(nodal_file);
    NODE_ori = [nodal_data.X, nodal_data.Y, nodal_data.Z];
    Nn = size(NODE_ori, 1);
    
    % Identify fixed and free nodes
    FIX_NODE = nodal_data.Node_ID(nodal_data.Fixed_Free == 1)';
    FREE_NODE = nodal_data.Node_ID(nodal_data.Fixed_Free == 0)';
    
    fprintf('  Nodes: %d (Fixed: %d, Free: %d)\n', Nn, length(FIX_NODE), length(FREE_NODE));
    
    % Import DOF information
    fixed_dofs = readtable(fullfile(csv_dir, 'fixed_dofs.csv'));
    free_dofs = readtable(fullfile(csv_dir, 'free_dofs.csv'));
    FIX = fixed_dofs.DOF';
    FREE = free_dofs.DOF';
    Nf = length(FREE);
    
    % Import edge connectivity
    edge_conn = readtable(fullfile(csv_dir, 'edge_connectivity.csv'));
    BARS = [edge_conn.Node1, edge_conn.Node2];
    Nb = size(BARS, 1);
    fprintf('  Edges: %d\n', Nb);
    
    %% IMPORT FIXED AND FREE EDGES - ROBUST HANDLING OF EMPTY ARRAYS
    fixed_edges_file = fullfile(csv_dir, 'fixed_edges.csv');
    free_edges_file = fullfile(csv_dir, 'free_edges.csv');
    
    % Initialize EDGE as empty array with correct dimensions
    EDGE = zeros(0, 2);  % Empty array with 2 columns
    
    if exist(fixed_edges_file, 'file')
        try
            fixed_edges = readtable(fixed_edges_file);
            if height(fixed_edges) > 0 && width(fixed_edges) >= 2
                % Check if the table has valid data
                node1_col = fixed_edges{:,1};
                node2_col = fixed_edges{:,2};
                
                % Remove rows with invalid data (zeros, NaN, or empty)
                valid_rows = ~isnan(node1_col) & ~isnan(node2_col) & ...
                           node1_col > 0 & node2_col > 0 & ...
                           node1_col ~= node2_col;  % Avoid self-loops
                
                if any(valid_rows)
                    EDGE = [node1_col(valid_rows), node2_col(valid_rows)];
                    fprintf('  Fixed edges: %d\n', size(EDGE, 1));
                else
                    fprintf('  Fixed edges: 0 (no valid fixed edge data)\n');
                end
            else
                fprintf('  Fixed edges: 0 (empty file)\n');
            end
        catch ME
            fprintf('  Warning: Error reading fixed edges file: %s\n', ME.message);
            fprintf('  Fixed edges: 0 (using empty array)\n');
        end
    else
        fprintf('  Fixed edges: 0 (file not found)\n');
    end
    
    % Initialize INNER as empty array with correct dimensions
    INNER = zeros(0, 2);  % Empty array with 2 columns
    
    if exist(free_edges_file, 'file')
        try
            free_edges = readtable(free_edges_file);
            if height(free_edges) > 0 && width(free_edges) >= 2
                % Check if the table has valid data
                node1_col = free_edges{:,1};
                node2_col = free_edges{:,2};
                
                % Remove rows with invalid data
                valid_rows = ~isnan(node1_col) & ~isnan(node2_col) & ...
                           node1_col > 0 & node2_col > 0 & ...
                           node1_col ~= node2_col;  % Avoid self-loops
                
                if any(valid_rows)
                    INNER = [node1_col(valid_rows), node2_col(valid_rows)];
                    fprintf('  Free edges: %d\n', size(INNER, 1));
                else
                    fprintf('  Free edges: 0 (no valid free edge data)\n');
                end
            else
                fprintf('  Free edges: 0 (empty file)\n');
            end
        catch ME
            fprintf('  Warning: Error reading free edges file: %s\n', ME.message);
            fprintf('  Free edges: 0 (using empty array)\n');
        end
    else
        fprintf('  Free edges: 0 (file not found)\n');
    end
    
    % If no free edges specified, use all bars as inner edges
    if isempty(INNER)
        INNER = BARS;
        fprintf('  Using all edges as free edges: %d\n', size(INNER, 1));
    end
    
%% LOAD PANEL DATA FROM CSV - DIRECT EXTRACTION
    panel_conn_file = fullfile(csv_dir, 'panel_connectivity.csv');
    panel_loads_file = fullfile(csv_dir, 'panel_loads.csv');
    
    if exist(panel_conn_file, 'file') && exist(panel_loads_file, 'file')
        fprintf('Loading panel data from CSV...\n');
        
        % Read panel connectivity directly from CSV
        fid = fopen(panel_conn_file, 'r');
        if fid == -1
            error('Could not open panel connectivity file');
        end
        
        % Skip header row
        header_line = fgetl(fid);
        fprintf('Panel connectivity header: %s\n', header_line);
        
        % Initialize variables
        panel_ids = [];
        node_strings = {};
        row_count = 0;
        
        % Read data rows
        while ~feof(fid)
            line = fgetl(fid);
            if ischar(line) && ~isempty(strtrim(line))
                row_count = row_count + 1;
                
                % Split line by comma
                parts = strsplit(line, ',');
                
                if length(parts) >= 2
                    % Extract panel ID from first column
                    panel_ids(row_count) = str2double(strtrim(parts{1})); %#ok<AGROW>
                    
                    % Extract node string from second column
                    node_strings{row_count} = strtrim(parts{2}); %#ok<AGROW>
                else
                    fprintf('Warning: Invalid line format at row %d: %s\n', row_count, line);
                end
            end
        end
        fclose(fid);
        
        fprintf('Read %d panel connectivity rows\n', row_count);
        
        % Process node strings to extract node lists
        ELEM = cell(row_count, 1);
        
        for i = 1:row_count
            try
                % Step 1: Extract string from second column
                node_str = node_strings{i};
                
                % Step 2: Split string by spaces (deliminate by space)
                string_parts = strsplit(strtrim(node_str), ' ');
                
                % Step 3: Remove '[' from first string and ']' from last string
                if ~isempty(string_parts)
                    % Remove '[' from first string
                    first_part = string_parts{1};
                    if startsWith(first_part, '[')
                        string_parts{1} = first_part(2:end);
                    end
                    
                    % Remove ']' from last string
                    last_part = string_parts{end};
                    if endsWith(last_part, ']')
                        string_parts{end} = last_part(1:end-1);
                    end
                    
                    % Step 4: Convert updated strings to integers
                    nodes = [];
                    for j = 1:length(string_parts)
                        if ~isempty(string_parts{j}) && ~isnan(str2double(string_parts{j}))
                            nodes(end+1) = str2double(string_parts{j}); %#ok<AGROW>
                        end
                    end
                    
                    % Step 5: Create the corresponding list
                    ELEM{i} = nodes;
                else
                    ELEM{i} = [];
                    fprintf('Warning: Empty node string for panel %d\n', panel_ids(i));
                end
                
            catch ME
                fprintf('Error processing panel %d: %s\n', panel_ids(i), ME.message);
                fprintf('  Node string was: %s\n', node_strings{i});
                ELEM{i} = [];
            end
        end
        
        Ne = length(ELEM);
        
        % Read panel loads directly from CSV
        fid = fopen(panel_loads_file, 'r');
        if fid == -1
            error('Could not open panel loads file');
        end
        
        % Skip header row
        header_line = fgetl(fid);
        fprintf('Panel loads header: %s\n', header_line);
        
        % Read panel loads
        panel_loads = [];
        load_row_count = 0;
        
        while ~feof(fid)
            line = fgetl(fid);
            if ischar(line) && ~isempty(strtrim(line))
                load_row_count = load_row_count + 1;
                
                % Split line by comma
                parts = strsplit(line, ',');
                
                if length(parts) >= 2
                    % Extract load pattern from second column
                    panel_loads(load_row_count) = str2double(strtrim(parts{2})); %#ok<AGROW>
                else
                    fprintf('Warning: Invalid load line format at row %d: %s\n', load_row_count, line);
                    panel_loads(load_row_count) = 1; % Default %#ok<AGROW>
                end
            end
        end
        fclose(fid);
        
        % Ensure panel loads match the number of panels
        if isempty(panel_loads)
            panel_loads = ones(Ne, 1);
            fprintf('Warning: No panel loads found, using default load pattern 1 for all panels\n');
        elseif length(panel_loads) < Ne
            panel_loads(end+1:Ne) = 1; % Default to first load pattern
            fprintf('Warning: Panel loads array extended to match number of panels\n');
        elseif length(panel_loads) > Ne
            panel_loads = panel_loads(1:Ne);
            fprintf('Warning: Panel loads array truncated to match number of panels\n');
        end
        
        fprintf('  Panels loaded: %d\n', Ne);
        
        % Display panel information for debugging
        for i = 1:min(5, Ne) % Show first 5 panels for debugging
            fprintf('  Panel %d: Nodes %s, Load Pattern %d\n', panel_ids(i), mat2str(ELEM{i}), panel_loads(i));
        end
        if Ne > 5
            fprintf('  ... and %d more panels\n', Ne-5);
        end
    end
    
    %% LOAD PATTERNS FROM CSV
    load_pattern_file = fullfile(csv_dir, 'load_patterns.csv');
    if exist(load_pattern_file, 'file')
        fprintf('Loading load patterns from CSV...\n');
        load_pattern_data = readtable(load_pattern_file);
        
        % Create q1_panels and q2_panels based on panel_loads
        q1_panels = zeros(Ne, 1);
        q2_panels = zeros(Ne, 1);
        
        for i = 1:Ne
            if i <= length(panel_loads)
                load_idx = panel_loads(i);
                if load_idx > 0 && load_idx <= height(load_pattern_data)
                    q1_panels(i) = load_pattern_data.q1(load_idx);
                    q2_panels(i) = load_pattern_data.q2(load_idx);
                else
                    q1_panels(i) = 3;  % Default
                    q2_panels(i) = 2;  % Default
                end
            else
                q1_panels(i) = 3;  % Default
                q2_panels(i) = 2;  % Default
            end
        end
    else
        % Default loads if not provided
        fprintf('Using default panel loads...\n');
        q1_panels = 3 * ones(max(Ne, 1), 1);
        q2_panels = 2 * ones(max(Ne, 1), 1);
    end
    %% LOAD MEMBER MATERIALS FROM CSV
    material_file = fullfile(csv_dir, 'member_materials.csv');
    if exist(material_file, 'file')
        fprintf('Loading member materials from CSV...\n');
        material_data = readtable(material_file);
        
        E_members = material_data.E;
        fcok_members = material_data.fcok;
        ftok_members = material_data.ftok;
        kmod_members = material_data.kmod;
    else
        % Default materials if not provided
        fprintf('Using default materials...\n');
        E_members = 14000000 * ones(Nb, 1);
        fcok_members = 29000 * ones(Nb, 1);
        ftok_members = 30000 * ones(Nb, 1);
        kmod_members = 0.7 * ones(Nb, 1);
    end
    
    E005_members = 0.84 * E_members;
    fprintf('Material properties:\n');
    fprintf('  E range: %.0f - %.0f kN/m²\n', min(E_members), max(E_members));
    fprintf('  fcok range: %.0f - %.0f kN/m²\n', min(fcok_members), max(fcok_members));
    
    %% LOAD ANALYSIS PARAMETERS FROM CSV
    param_file = fullfile(csv_dir, 'analysis_parameters.csv');
    if exist(param_file, 'file')
        fprintf('Loading analysis parameters from CSV...\n');
        param_data = readtable(param_file);
        
        % Read FF parameters
        ff_tol_idx = strcmp(param_data.Parameter, 'FF_Tolerance');
        ff_max_iter_idx = strcmp(param_data.Parameter, 'FF_Max_Iter');
        ms_tol_idx = strcmp(param_data.Parameter, 'MS_Tolerance');
        ms_max_iter_idx = strcmp(param_data.Parameter, 'MS_Max_Iter');
        max_rel_change_idx = strcmp(param_data.Parameter, 'Max_Rel_Change');
        coupled_max_iter_idx = strcmp(param_data.Parameter, 'Coupled_Max_Iter');
        
        % Use proper MATLAB conditional syntax
        if any(ff_tol_idx)
            ff_tol = param_data.Value(ff_tol_idx);
        else
            ff_tol = 1e-3;
        end
        
        if any(ff_max_iter_idx)
            ff_max_iter = param_data.Value(ff_max_iter_idx);
        else
            ff_max_iter = 100;
        end
        
        if any(ms_tol_idx)
            ms_tol = param_data.Value(ms_tol_idx);
        else
            ms_tol = 0.005;
        end
        
        if any(ms_max_iter_idx)
            ms_max_iter = param_data.Value(ms_max_iter_idx);
        else
            ms_max_iter = 200;
        end
        
        if any(max_rel_change_idx)
            max_rel_change_tolerance = param_data.Value(max_rel_change_idx);
        else
            max_rel_change_tolerance = 0.01;
        end
        
        if any(coupled_max_iter_idx)
            coupled_max_iter = param_data.Value(coupled_max_iter_idx);
        else
            coupled_max_iter = 20;
        end
        
        fprintf('  FF Tolerance: %.2e\n', ff_tol);
        fprintf('  FF Max Iterations: %d\n', ff_max_iter);
        fprintf('  MS Tolerance: %.3f\n', ms_tol);
        fprintf('  MS Max Iterations: %d\n', ms_max_iter);
        fprintf('  Max Relative Change: %.3f\n', max_rel_change_tolerance);
        fprintf('  Coupled Max Iterations: %d\n', coupled_max_iter);
    else
        % Default values if file not found
        fprintf('Analysis parameters file not found, using defaults...\n');
        ff_tol = 1e-3;
        ff_max_iter = 100;
        ms_tol = 0.005;
        ms_max_iter = 200;
        max_rel_change_tolerance = 0.01;
        coupled_max_iter = 20;
    end
    
    % Helper function to get parameter values
    function value = getParameterValue(param_data, param_name, default_value)
        idx = strcmpi(param_data.Parameter, param_name);
        if any(idx)
            value = param_data.Value(idx);
        else
            value = default_value;
            fprintf('Parameter "%s" not found, using default value: %.6f\n', param_name, default_value);
        end
    end

    %% COUPLED FORM FINDING AND MEMBER SIZING
    fprintf('\nStarting Coupled Form Finding and Member Sizing...\n');
    
    % Initialize areas
    A = 0.005 * ones(Nb, 1);
    
    % Get fixed edge indices - HANDLE EMPTY EDGE CASE
    fixed_edge_indices = [];
    if ~isempty(EDGE) && size(EDGE, 1) > 0
        for i = 1:size(EDGE, 1)
            node1 = EDGE(i, 1);
            node2 = EDGE(i, 2);
            for j = 1:size(BARS, 1)
                if (BARS(j, 1) == node1 && BARS(j, 2) == node2) || ...
                   (BARS(j, 1) == node2 && BARS(j, 2) == node1)
                    fixed_edge_indices = [fixed_edge_indices; j];
                    break;
                end
            end
        end
        fprintf('  Fixed edge indices found: %d\n', length(fixed_edge_indices));
    else
        fprintf('  No fixed edges defined. Using fixed nodes for constraints.\n');
    end
    
    % Get free edge indices for analysis
    free_edge_indices = setdiff(1:Nb, fixed_edge_indices);
    
    % Convergence parameters
    max_coupled_iter = coupled_max_iter;
    EA_tolerance = 100;
    coupled_iter = 0;
    EA_converged = false;
    EA_history_full = [];
    EA_convergence_metric = [];
    FF_convergence_history = [];
    MS_convergence_history = [];
    PE_per_coupled_iteration = [];

    % Storage for PE tracking
    PE_history_FF = {};
    PE_history_MS = {};
    PE_detailed_first_FF = [];
    PE_detailed_first_MS = [];
    
    %% PLOT INITIAL LAYOUT (BEFORE ANALYSIS)
    fprintf('Generating initial layout plot...\n');
    
    figure('Name','Initial Layout - 3D View (Before Analysis)','Position',[50 50 1000 700]);
    hold on; axis equal; grid on; box on;
    
    % Plot initial members
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE_ori(n1,1), NODE_ori(n2,1)];
        Y = [NODE_ori(n1,2), NODE_ori(n2,2)];
        Z = [NODE_ori(n1,3), NODE_ori(n2,3)];
        plot3(X, Y, Z, 'k-', 'LineWidth', 1.5);  % Black lines for initial
    end
    
    % Plot fixed nodes
    if ~isempty(FIX_NODE)
        scatter3(NODE_ori(FIX_NODE,1), NODE_ori(FIX_NODE,2), NODE_ori(FIX_NODE,3), ...
                 100, 'red', 'filled', 'MarkerEdgeColor', 'black', 'LineWidth', 1.5);
    end
    
    % Plot free nodes
    if ~isempty(FREE_NODE)
        scatter3(NODE_ori(FREE_NODE,1), NODE_ori(FREE_NODE,2), NODE_ori(FREE_NODE,3), ...
                 50, 'blue', 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Initial Grid Shell Layout (Before Form Finding)', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    legend({'Members', 'Fixed Nodes', 'Free Nodes'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName, 'Location', 'best');
    
    fprintf('Initial layout plotted.\n');

    while ~EA_converged && coupled_iter < max_coupled_iter
        coupled_iter = coupled_iter + 1;
        fprintf('\n--- Coupled Iteration %d ---\n', coupled_iter);
        
        %% FORM FINDING
        fprintf('Form Finding...\n');
        
        % Calculate EA values
        EA_current = E005_members .* A;
        
        % Generate springs - ROBUST HANDLING OF EMPTY EDGE
        [K] = GetSprings(NODE_ori, BARS, E005_members, A);
        
        % Reset geometry
        NODE = NODE_ori;
        
        % Form finding options with enhanced tracking
        options_FF = optimset('Display','off','MaxFunEvals',50000000,'LargeScale','off');
        options_FF_enhanced = optimset('Display','off',...
                                     'MaxFunEvals',50000000,...
                                     'LargeScale','off',...
                                     'GradObj','off',...
                                     'DerivativeCheck','off',...
                                     'OutputFcn',@captureOptimizationPEandGradient);
        
        % Initialize
        U = zeros(3*Nn,1);
        
        x(:) = 0;
        x(3:3:Nf) = 0;
        x0 = x;
        U(FREE) = x;
        DNODE = NODE_ori + reshape(U,3,Nn)';
        
        % Initialize PE tracking for this FF session
        PE_FF_current = [];
        
        % Calculate loads - HANDLE EMPTY EDGE CASE
        opts = struct();
        if Ne > 0
            % Combine edges safely - handle empty EDGE
            ALL_BARS = combineEdges(INNER, EDGE);
            
            [PANELS, TRIB_AREA, PANEL_AREAS, aux1, F_nodal1] = ...
                gridshell_panels_loads(DNODE, BARS, q1_panels, opts);
            Plane_NODE = [DNODE(:,1:2) zeros(Nn,1)];
            [PANELS, TRIB_AREA, PANEL_AREAS, aux2, F_nodal2] = ...
                gridshell_panels_loads(Plane_NODE, BARS, q2_panels, opts);
            F0 = reshape([zeros(Nn,2) -aux1-aux2]',3*Nn,1);
        else
            F0 = zeros(3*Nn,1);
            F0(3:3:end) = -1; % Default downward load
        end
        
        % Get initial lengths
        L0 = GetL(NODE_ori, BARS);
        
        % Form finding iteration with enhanced tracking for first iteration
        tol = ff_tol;
        iter_limit = ff_max_iter;
        ff_iter = 0;
        res1 = 1;
        
        % Clear PE tracking data before first optimization
        if coupled_iter == 1
            PE_iteration_data = struct('iteration_count', 0, 'values', [], 'iterations', [], ...
                                      'gradient_norms', [], 'max_gradient_components', []);
            
            fprintf('  Running first FF fminunc with PE and gradient tracking...\n');
            [x,PE,~,output] = fminunc(@(Uf)GetPotential(NODE_ori,BARS,Uf,F0,K,FREE,L0),x,options_FF_enhanced);
            
            % Store the detailed tracking for first FF optimization
            PE_detailed_first_FF = PE_iteration_data;
            fprintf('  Captured %d PE and %d gradient data points\n', ...
                    length(PE_iteration_data.values), sum(~isnan(PE_iteration_data.gradient_norms)));
        else
            [x,PE,~,output] = fminunc(@(Uf)GetPotential(NODE_ori,BARS,Uf,F0,K,FREE,L0),x,options_FF);
        end
        
        PE_FF_current = [PE_FF_current; PE];
        U(FREE) = x;
        NODE = NODE_ori + reshape(U,3,Nn)';
        res1 = norm(x-x0)/sqrt(Nf);
        
        while res1 > tol && ff_iter < iter_limit
            if coupled_iter == 1
                FF_convergence_history = [FF_convergence_history; res1];
            end
            if Ne > 0
                ALL_BARS = combineEdges(INNER, EDGE);
                [PANELS, TRIB_AREA, PANEL_AREAS, aux1, F_nodal1] = ...
                    gridshell_panels_loads(NODE, BARS, q1_panels, opts);
                Plane_NODE = [NODE(:,1:2) zeros(Nn,1)];
                [PANELS, TRIB_AREA, PANEL_AREAS, aux2, F_nodal2] = ...
                    gridshell_panels_loads(Plane_NODE, BARS, q2_panels, opts);
                F = reshape([zeros(Nn,2) -aux1-aux2]',3*Nn,1);
            else
                F = F0;
            end
            % Check for snap-through
            NS_Zdof = GetNepsZdof(NODE, BARS, L0, Nb);
            
            if ~isempty(NS_Zdof)
                Umin = min(U(FREE));
                
                % Create displacement adjustment
                aux1 = zeros(Nn, 3);
                
                % Directly use NS_Zdof to index into the z-column
                % Convert DOF indices to node indices
                NS_nodes = NS_Zdof / 3;  % Since zdof = 3*node
                aux1(NS_nodes, 3) = 2 * Umin;
                
                % Apply only to free nodes
                aux1 = aux1(FREE_NODE, :);
                aux1 = reshape(aux1', 1, numel(aux1));
                
                % Update initial guess
                x = x + aux1;
            end
            [x,PE,~,output] = fminunc(@(Uf)GetPotential(NODE_ori,BARS,Uf,F,K,FREE,L0),x,options_FF);
            PE_FF_current = [PE_FF_current; PE];
            U(FREE) = x;
            NODE = NODE_ori + reshape(U,3,Nn)';
            ff_iter = ff_iter + 1;
            res1 = norm(x-x0)/sqrt(Nf);
            x0 = x;
            fprintf('  FF Iter %d: Residual = %.4f\n', ff_iter, res1);
        end
        
        % Store FF PE history for this coupled iteration
        PE_history_FF{coupled_iter} = PE_FF_current;

        if coupled_iter == 1 && ~isempty(FF_convergence_history)
            figure('Name','FF Convergence Criteria - First Iteration','Position',[150 150 800 600]);
            semilogy(1:length(FF_convergence_history), FF_convergence_history, 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
            hold on;
            yline(ff_tol, 'b--', sprintf('Tolerance = %.0e', ff_tol), 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            xlabel('FF Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('||X^{(k)} - X^{(k-1)}|| / N_{dof} (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Form Finding Convergence - First Coupled Iteration', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            legend({'Convergence Metric', 'Tolerance'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
        end

        % Update lengths
        L = GetL(NODE,BARS);
        L0 = L;
        NODE_MS_ori = NODE;
        
        %% MEMBER SIZING
        fprintf('Member Sizing...\n');
        
        % Initialize PE tracking for this MS session
        PE_MS_current = [];
        
        % Member sizing options with enhanced tracking
        options_MS = optimset('MaxFunEvals',500000000,'MaxIter',5000000,'Display','off','LargeScale','off');
        options_MS_enhanced = optimset('MaxFunEvals',500000000,...
                                      'MaxIter',5000000,...
                                      'Display','off',...
                                      'LargeScale','off',...
                                      'GradObj','off',...
                                      'DerivativeCheck','off',...
                                      'OutputFcn',@captureOptimizationPEandGradient);
        
        FREE_MS = 1:3*Nn;
        FREE_MS(FIX) = [];
        U_ms = zeros(3*Nn,1);
        x_ms = zeros(numel(FREE_MS),1);
        ms_iter = 0;
        res = 1;
        iter_limit_ms = ms_max_iter;
        tol_ms = ms_tol;
        c = 0.3;
        
        while (res > tol_ms) && (ms_iter < iter_limit_ms)
            % Update stiffness
            K_MS = GetStiffness_SA(E005_members, A, L0);
            
            % Calculate loads
            if Ne > 0
                ALL_BARS = combineEdges(INNER, EDGE);
                [PANELS, TRIB_AREA, PANEL_AREAS, aux1, F_nodal1] = ...
                    gridshell_panels_loads(NODE, BARS, q1_panels, opts);
                Plane_NODE = [NODE(:,1:2) zeros(Nn,1)];
                [PANELS, TRIB_AREA, PANEL_AREAS, aux2, F_nodal2] = ...
                    gridshell_panels_loads(Plane_NODE, BARS, q2_panels, opts);
                F = reshape([zeros(Nn,2) -aux1-aux2]',3*Nn,1);
            else
                F = zeros(3*Nn,1);
                F(3:3:end) = -1;
            end
            
            % For first MS iteration, use enhanced tracking
            if coupled_iter == 1 && ms_iter == 0
                % Clear tracking data for MS
                PE_iteration_data = struct('iteration_count', 0, 'values', [], 'iterations', [], ...
                                          'gradient_norms', [], 'max_gradient_components', []);
                
                fprintf('  Running first MS fminunc with PE and gradient tracking...\n');
                [x_ms,PE_ms,exitflag,output] = fminunc(@(Uf)GetPotential(NODE_MS_ori,BARS,Uf,F,K_MS,FREE_MS,L0),x_ms,options_MS_enhanced);
                
                % Store first MS tracking data
                PE_detailed_first_MS = PE_iteration_data;
                fprintf('  First MS captured %d PE and %d gradient data points\n', ...
                        length(PE_iteration_data.values), sum(~isnan(PE_iteration_data.gradient_norms)));
            else
                [x_ms,PE_ms,exitflag,output] = fminunc(@(Uf)GetPotential(NODE_MS_ori,BARS,Uf,F,K_MS,FREE_MS,L0),x_ms,options_MS);
            end
            
            PE_MS_current = [PE_MS_current; PE_ms];
            
            if exitflag <= 0
                [x_ms,PE_ms,exitflag,output] = fminunc(@(Uf)GetPotential(NODE_MS_ori,BARS,Uf,F,K_MS,FREE_MS,L0),x_ms,options_MS);
                PE_MS_current = [PE_MS_current; PE_ms];
                if exitflag <= 0
                    warning('MS Optimization did not converge');
                    break;
                end
            end
            
            U_ms = zeros(3*Nn,1);
            U_ms(FREE_MS) = x_ms;
            NODE = NODE_MS_ori + reshape(U_ms,3,Nn)';
            
            % Update areas based on stress
            [S, ~, ~] = GetSigma(NODE, BARS, E005_members, L0);
            iz = sqrt(A) ./ (2*sqrt(3));
            lmz = L0 ./ iz;
            lmrelz = (lmz / pi) .* sqrt(fcok_members ./ E005_members);
            k = 0.5 * (1 + 0.2 * (lmrelz - 0.3) + lmrelz.^2);
            kcz = 1 ./ (k + sqrt(k.^2 - lmrelz.^2));
            S_adm_C = kcz .* kmod_members .* fcok_members / 1.3;
            S_abs = abs(S);
            S_abs(S_abs == 0) = S_adm_C(S_abs == 0);
            Coe = S_abs ./ S_adm_C;
            A = A .* (Coe .^ c);

            if coupled_iter == 1
                MS_convergence_history = [MS_convergence_history; res];
            end
            ms_iter = ms_iter + 1;
            res = max(abs(Coe-1));
            fprintf('  MS Iter %d: Residual = %.4f\n', ms_iter, res);
        end
        
        % Store MS PE history for this coupled iteration
        PE_history_MS{coupled_iter} = PE_MS_current;
        
        if coupled_iter == 1 && ~isempty(MS_convergence_history)
            figure('Name','MS Convergence Criteria - First Iteration','Position',[250 150 800 600]);
            semilogy(1:length(MS_convergence_history), MS_convergence_history, 'b-s', 'LineWidth', 2, 'MarkerSize', 6);
            hold on;
            yline(ms_tol, 'b--', sprintf('Tolerance = %.3f', ms_tol), 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            xlabel('MS Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('max(|Stress Ratio - 1|) (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Member Sizing Convergence - First Coupled Iteration', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            legend({'Convergence Metric', 'Tolerance'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
        end

        if ~isempty(PE_MS_current)
            PE_per_coupled_iteration = [PE_per_coupled_iteration; PE_MS_current(end)];
        elseif ~isempty(PE_FF_current)
            PE_per_coupled_iteration = [PE_per_coupled_iteration; PE_FF_current(end)];
        end

        % Fix areas for fixed edges - HANDLE EMPTY CASE
        if ~isempty(fixed_edge_indices)
            A(fixed_edge_indices) = min(A);
        end
        
        %% CHECK CONVERGENCE
        all_EA_current = E005_members .* A;
        EA_history_full = [EA_history_full, all_EA_current];
        
        if coupled_iter > 1
            EA_prev = EA_history_full(:, end-1);
            EA_now = EA_history_full(:, end);
            
            relative_changes = abs(EA_now - EA_prev) ./ (EA_prev + 1e-6);
            max_relative_change = max(relative_changes);
            
            fprintf('EA Max Relative Change: %.6f\n', max_relative_change);
            EA_convergence_metric = [EA_convergence_metric; max_relative_change];
            
            if max_relative_change <= max_rel_change_tolerance % 1% tolerance
                EA_converged = true;
                fprintf('*** EA VALUES CONVERGED! ***\n');
            end
        else
            EA_convergence_metric = [EA_convergence_metric; NaN];
        end
    end
    
    if ~isempty(PE_per_coupled_iteration) && length(PE_per_coupled_iteration) > 1
        figure('Name','PE Evolution Across Coupled Iterations','Position',[350 150 800 600]);
        plot(1:length(PE_per_coupled_iteration), abs(PE_per_coupled_iteration), 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
        xlabel('Coupled Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('|Potential Energy|', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('Potential Energy Evolution Across Coupled Iterations', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        text(0.7, 0.9, sprintf('Initial PE: %.3e\nFinal PE: %.3e\nIterations: %d', ...
            abs(PE_per_coupled_iteration(1)), abs(PE_per_coupled_iteration(end)), coupled_iter), ...
            'Units', 'normalized', 'FontSize', 11, 'FontWeight', 'bold', 'BackgroundColor', 'white', 'FontName', FontSizes.FontName);
    end


    %% FINAL CALCULATIONS
    fprintf('\nFinal calculations...\n');
    
    L = GetL(NODE,BARS);
    [S_final, ~, ~] = GetSigma(NODE, BARS, E005_members, L0);
    F_member = S_final .* A;
    
    % Calculate stress ratios
    iz = sqrt(A) ./ (2*sqrt(3));
    lmz = L0 ./ iz;
    lmrelz = (lmz / pi) .* sqrt(fcok_members ./ E005_members);
    k = 0.5 * (1 + 0.2 * (lmrelz - 0.3) + lmrelz.^2);
    kcz = 1 ./ (k + sqrt(k.^2 - lmrelz.^2));
    S_adm_C = kcz .* kmod_members .* fcok_members / 1.3;
    
    stress_ratio = abs(S_final) ./ S_adm_C;
    stress_values = abs(S_final);
    A_cm2 = A * 10000;
    
    %% ENHANCED PLOTTING SECTION
    fprintf('Generating comprehensive plots...\n');
    
    % Generate all plots from Mat_Load_Un
    generateAllPlots(NODE, BARS, FIX_NODE, FREE_NODE, A_cm2, stress_ratio, stress_values, S_final, F_member, ...
                    fixed_edge_indices, free_edge_indices, FontSizes, PE_detailed_first_FF, PE_detailed_first_MS, ...
                    PE_history_FF, PE_history_MS, EA_history_full, EA_convergence_metric, EA_tolerance, ...
                    coupled_iter, Nn, Nb, L0, A);
    
    %% SAVE RESULTS
    fprintf('Saving results...\n');
    
    % Save final coordinates
    final_nodes = table((1:Nn)', NODE(:,1), NODE(:,2), NODE(:,3), ...
                       'VariableNames', {'Node_ID', 'X', 'Y', 'Z'});
    writetable(final_nodes, fullfile(csv_dir, 'final_node_coordinates.csv'));
    
    % Save member results
    member_results = table((1:Nb)', BARS(:,1), BARS(:,2), A_cm2, F_member, ...
                          stress_values, stress_ratio, ...
                          'VariableNames', {'Member_ID', 'Node1', 'Node2', ...
                                           'Area_cm2', 'Force_kN', 'Stress_kNm2', 'Stress_Ratio'});
    writetable(member_results, fullfile(csv_dir, 'member_results.csv'));
    
    % Save summary
    summary_file = fullfile(csv_dir, 'analysis_summary.txt');
    fid = fopen(summary_file, 'w');
    fprintf(fid, 'GRIDSHELL ANALYSIS SUMMARY\n');
    fprintf(fid, '==========================\n\n');
    fprintf(fid, 'Analysis Date: %s\n', datestr(now));
    fprintf(fid, 'CSV Directory: %s\n\n', csv_dir);
    fprintf(fid, 'Structure:\n');
    fprintf(fid, '  Nodes: %d (Fixed: %d, Free: %d)\n', Nn, length(FIX_NODE), length(FREE_NODE));
    fprintf(fid, '  Members: %d\n', Nb);
    fprintf(fid, '  Panels: %d\n', Ne);
    fprintf(fid, '\nConvergence:\n');
    fprintf(fid, '  Coupled Iterations: %d\n', coupled_iter);
    fprintf(fid, '  EA Converged: %s\n', iff(EA_converged, 'Yes', 'No'));
    fprintf(fid, '\nResults:\n');
    fprintf(fid, '  Max Area: %.2f cm²\n', max(A_cm2));
    fprintf(fid, '  Min Area: %.2f cm²\n', min(A_cm2));
    fprintf(fid, '  Mean Area: %.2f cm²\n', mean(A_cm2));
    fprintf(fid, '  Max Stress Ratio: %.3f\n', max(stress_ratio));
    fprintf(fid, '  Min Stress Ratio: %.3f\n', min(stress_ratio));
    fprintf(fid, '  Total Volume: %.3f m³\n', sum(A .* L0));
    fclose(fid);
    
    fprintf('\n=== ANALYSIS COMPLETE ===\n');
    fprintf('Results saved to: %s\n', csv_dir);
    fprintf('Max Area: %.2f cm²\n', max(A_cm2));
    fprintf('Max Stress Ratio: %.3f\n', max(stress_ratio));
    fprintf('Generated comprehensive plots including PE tracking and analysis\n');
    fprintf('========================\n');
    
    rmpath('./FFMS');
end

%% COMPREHENSIVE PLOTTING FUNCTION
function generateAllPlots(NODE, BARS, FIX_NODE, FREE_NODE, A_cm2, stress_ratio, stress_values, S_final, F_member, ...
                         fixed_edge_indices, free_edge_indices, FontSizes, PE_detailed_first_FF, PE_detailed_first_MS, ...
                         PE_history_FF, PE_history_MS, EA_history_full, EA_convergence_metric, EA_tolerance, ...
                         coupled_iter, Nn, Nb, L0, A)

    % Determine Z flip
    z_flipped = min(NODE(:,3)) < 0;
    free_nodes = setdiff(1:Nn, FIX_NODE);
    
    %% 1. ENHANCED PE AND GRADIENT TRACKING FOR FIRST FF
    if ~isempty(PE_detailed_first_FF) && ~isempty(PE_detailed_first_FF.values)
        figure('Name','First Form Finding: PE and Gradient Convergence','Position',[50 50 1400 800]);
        
        % PE Linear Scale
        subplot(2,3,1);
        plot(PE_detailed_first_FF.iterations, PE_detailed_first_FF.values, 'b-o', 'LineWidth', 2, 'MarkerSize', 4);
        xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('Potential Energy', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('PE Convergence - FF', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        % PE Log Scale
        subplot(2,3,2);
        semilogy(PE_detailed_first_FF.iterations, abs(PE_detailed_first_FF.values), 'b-s', 'LineWidth', 2, 'MarkerSize', 4);
        xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('|PE| (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('PE Convergence (Log) - FF', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        % Gradient Norm Convergence
        subplot(2,3,3);
        valid_grad_idx = ~isnan(PE_detailed_first_FF.gradient_norms);
        if sum(valid_grad_idx) > 0
            valid_iters = PE_detailed_first_FF.iterations(valid_grad_idx);
            valid_grads = PE_detailed_first_FF.gradient_norms(valid_grad_idx);
            semilogy(valid_iters, valid_grads, 'b-^', 'LineWidth', 2, 'MarkerSize', 5);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('||∇PE|| (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Gradient Norm → 0 - FF', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
        else
            text(0.5, 0.5, 'Gradient data not available', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', FontSizes.FontName);
            title('Gradient Norm - FF (No Data)', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        end
        
        % Max Gradient Component
        subplot(2,3,4);
        valid_max_grad_idx = ~isnan(PE_detailed_first_FF.max_gradient_components);
        if sum(valid_max_grad_idx) > 0
            valid_iters_max = PE_detailed_first_FF.iterations(valid_max_grad_idx);
            valid_max_grads = PE_detailed_first_FF.max_gradient_components(valid_max_grad_idx);
            semilogy(valid_iters_max, valid_max_grads, 'b-d', 'LineWidth', 2, 'MarkerSize', 6);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('max(|∂PE/∂u|) (log)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Max Gradient → 0 - FF', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            
            if length(valid_max_grads) > 1
                final_grad = valid_max_grads(end);
                yline(final_grad, 'b--', sprintf('Final: %.2e', final_grad), 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            end
        else
            text(0.5, 0.5, 'Max gradient data not available', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', FontSizes.FontName);
            title('Max Gradient - FF (No Data)', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        end
        
        % PE Reduction Rate
        subplot(2,3,5);
        if length(PE_detailed_first_FF.values) > 1
            PE_diff = diff(PE_detailed_first_FF.values);
            plot(PE_detailed_first_FF.iterations(2:end), -PE_diff, 'b-v', 'LineWidth', 2, 'MarkerSize', 4);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('PE Reduction per Step', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Energy Reduction Rate - FF', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
        end
        
        % Statistics
        subplot(2,3,6);
        axis off;
        stats_text = {};
        stats_text{end+1} = sprintf('FF Total Iterations: %d', length(PE_detailed_first_FF.values));
        stats_text{end+1} = sprintf('Initial PE: %.6e', PE_detailed_first_FF.values(1));
        stats_text{end+1} = sprintf('Final PE: %.6e', PE_detailed_first_FF.values(end));
        
        if sum(valid_grad_idx) > 0
            stats_text{end+1} = sprintf('Final ||∇PE||: %.6e', valid_grads(end));
        end
        
        if sum(valid_max_grad_idx) > 0
            stats_text{end+1} = sprintf('Final max(|∂PE/∂u|): %.6e', valid_max_grads(end));
            
            % Equilibrium quality assessment
            if valid_max_grads(end) < 1e-6
                equilibrium_status = 'EXCELLENT';
            elseif valid_max_grads(end) < 1e-4
                equilibrium_status = 'GOOD';
            elseif valid_max_grads(end) < 1e-2
                equilibrium_status = 'ACCEPTABLE';
            else
                equilibrium_status = 'POOR';
            end
            stats_text{end+1} = sprintf('Equilibrium Quality: %s', equilibrium_status);
        end
        
        for i = 1:length(stats_text)
            text(0.1, 0.9 - (i-1)*0.12, stats_text{i}, 'FontSize', 12, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        end
        title('FF Statistics', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        
        sgtitle('First Form Finding: Complete Equilibrium Analysis', 'FontSize', 18, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    end
    
    %% 2. ENHANCED PE AND GRADIENT TRACKING FOR FIRST MS
    if ~isempty(PE_detailed_first_MS) && ~isempty(PE_detailed_first_MS.values)
        figure('Name','First Member Sizing: PE and Gradient Convergence','Position',[100 100 1400 800]);
        
        % PE Linear Scale
        subplot(2,3,1);
        plot(PE_detailed_first_MS.iterations, PE_detailed_first_MS.values, 'b-o', 'LineWidth', 2, 'MarkerSize', 4);
        xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('Potential Energy', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('PE Convergence - MS', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        % PE Log Scale
        subplot(2,3,2);
        semilogy(PE_detailed_first_MS.iterations, abs(PE_detailed_first_MS.values), 'b-s', 'LineWidth', 2, 'MarkerSize', 4);
        xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('|PE| (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('PE Convergence (Log) - MS', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        % Gradient Norm Convergence
        subplot(2,3,3);
        valid_grad_idx_ms = ~isnan(PE_detailed_first_MS.gradient_norms);
        if sum(valid_grad_idx_ms) > 0
            valid_iters_ms = PE_detailed_first_MS.iterations(valid_grad_idx_ms);
            valid_grads_ms = PE_detailed_first_MS.gradient_norms(valid_grad_idx_ms);
            semilogy(valid_iters_ms, valid_grads_ms, 'b-^', 'LineWidth', 2, 'MarkerSize', 5);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('||∇PE|| (log scale)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Gradient Norm → 0 - MS', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
        else
            text(0.5, 0.5, 'Gradient data not available', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', FontSizes.FontName);
            title('Gradient Norm - MS (No Data)', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        end
        
        % Max Gradient Component
        subplot(2,3,4);
        valid_max_grad_idx_ms = ~isnan(PE_detailed_first_MS.max_gradient_components);
        if sum(valid_max_grad_idx_ms) > 0
            valid_iters_max_ms = PE_detailed_first_MS.iterations(valid_max_grad_idx_ms);
            valid_max_grads_ms = PE_detailed_first_MS.max_gradient_components(valid_max_grad_idx_ms);
            semilogy(valid_iters_max_ms, valid_max_grads_ms, 'b-d', 'LineWidth', 2, 'MarkerSize', 6);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('max(|∂PE/∂u|) (log)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Max Gradient → 0 - MS', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            
            if length(valid_max_grads_ms) > 1
                final_grad_ms = valid_max_grads_ms(end);
                yline(final_grad_ms, 'b--', sprintf('Final: %.2e', final_grad_ms), 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            end
        else
            text(0.5, 0.5, 'Max gradient data not available', 'Units', 'normalized', 'HorizontalAlignment', 'center', 'FontName', FontSizes.FontName);
            title('Max Gradient - MS (No Data)', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        end
        
        % PE Reduction Rate
        subplot(2,3,5);
        if length(PE_detailed_first_MS.values) > 1
            PE_diff_ms = diff(PE_detailed_first_MS.values);
            plot(PE_detailed_first_MS.iterations(2:end), -PE_diff_ms, 'b-v', 'LineWidth', 2, 'MarkerSize', 4);
            xlabel('fminunc Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('PE Reduction per Step', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Energy Reduction Rate - MS', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
        end
        
        % Statistics
        subplot(2,3,6);
        axis off;
        stats_text_ms = {};
        stats_text_ms{end+1} = sprintf('MS Total Iterations: %d', length(PE_detailed_first_MS.values));
        stats_text_ms{end+1} = sprintf('Initial PE: %.6e', PE_detailed_first_MS.values(1));
        stats_text_ms{end+1} = sprintf('Final PE: %.6e', PE_detailed_first_MS.values(end));
        
        if sum(valid_grad_idx_ms) > 0
            stats_text_ms{end+1} = sprintf('Final ||∇PE||: %.6e', valid_grads_ms(end));
        end
        
        if sum(valid_max_grad_idx_ms) > 0
            stats_text_ms{end+1} = sprintf('Final max(|∂PE/∂u|): %.6e', valid_max_grads_ms(end));
            
            % Equilibrium quality assessment
            if valid_max_grads_ms(end) < 1e-6
                equilibrium_status_ms = 'EXCELLENT';
            elseif valid_max_grads_ms(end) < 1e-4
                equilibrium_status_ms = 'GOOD';
            elseif valid_max_grads_ms(end) < 1e-2
                equilibrium_status_ms = 'ACCEPTABLE';
            else
                equilibrium_status_ms = 'POOR';
            end
            stats_text_ms{end+1} = sprintf('Equilibrium Quality: %s', equilibrium_status_ms);
        end
        
        for i = 1:length(stats_text_ms)
            text(0.1, 0.9 - (i-1)*0.12, stats_text_ms{i}, 'FontSize', 12, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        end
        title('MS Statistics', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        
        sgtitle('First Member Sizing: Complete Equilibrium Analysis', 'FontSize', 18, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    end
    
    %% 3. EA CONVERGENCE PLOTS
    if ~isempty(EA_history_full)
        figure('Name','EA Convergence History','Position',[50 50 800 500]);
        subplot(2,1,1);
        max_EA_history = max(EA_history_full, [], 1);
        plot(1:length(max_EA_history), max_EA_history, 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
        xlabel('Coupled Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('Max EA Value', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('EA Convergence History (Max Values)', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        if length(max_EA_history) > 1
            yline(max_EA_history(end), 'b--', 'Final Value', 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
        end
        
        % EA Convergence Metric
        subplot(2,1,2);
        valid_indices = ~isnan(EA_convergence_metric);
        if any(valid_indices)
            plot(find(valid_indices), EA_convergence_metric(valid_indices), 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
            yline(0.01, 'b--', 'Tolerance = 0.01', 'LineWidth', 2, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            xlabel('Coupled Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('Max Relative Change', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('EA Convergence Metric vs Iteration', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            ylim([0, max(EA_convergence_metric(valid_indices)) * 1.1]);
        end
    end
    
    %% 4. PE HISTORY PLOTS
    if coupled_iter >= 1 && ~isempty(PE_history_FF) && ~isempty(PE_history_FF{1})
        % First Form Finding PE
        figure('Name','Potential Energy - First Form Finding','Position',[100 100 800 600]);
        plot(1:length(PE_history_FF{1}), abs(PE_history_FF{1}), 'b-o', 'LineWidth', 2, 'MarkerSize', 5);
        xlabel('Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('Potential Energy', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('Potential Energy Evolution - First Form Finding', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        final_pe = abs(PE_history_FF{1}(end));
        text(0.7, 0.9, sprintf('Final PE: %.3e', final_pe), 'Units', 'normalized', ...
             'FontSize', 12, 'FontWeight', 'bold', 'Color', 'blue', 'FontName', FontSizes.FontName);
        
        % First Member Sizing PE
        if ~isempty(PE_history_MS) && ~isempty(PE_history_MS{1})
            figure('Name','Potential Energy - First Member Sizing','Position',[200 100 800 600]);
            plot(1:length(PE_history_MS{1}), abs(PE_history_MS{1}), 'b-o', 'LineWidth', 2, 'MarkerSize', 5);
            xlabel('Iteration', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('Potential Energy', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Potential Energy Evolution - First Member Sizing', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            grid on;
            
            final_pe = abs(PE_history_MS{1}(end));
            text(0.7, 0.9, sprintf('Final PE: %.3e', final_pe), 'Units', 'normalized', ...
                 'FontSize', 12, 'FontWeight', 'bold', 'Color', 'blue', 'FontName', FontSizes.FontName);
            
            % Combined comparison
            figure('Name','Potential Energy Comparison - First FF vs MS','Position',[300 100 1000 600]);
            
            ff_iterations = 1:length(PE_history_FF{1});
            ms_iterations = 1:length(PE_history_MS{1});
            
            ff_norm = ff_iterations / max(ff_iterations);
            ms_norm = ms_iterations / max(ms_iterations);
            
            plot(ff_norm, abs(PE_history_FF{1}), 'b-o', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Form Finding');
            hold on;
            plot(ms_norm, abs(PE_history_MS{1}), 'b-s', 'LineWidth', 2, 'MarkerSize', 5, 'DisplayName', 'Member Sizing');
            
            xlabel('Normalized Iteration (%)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            ylabel('Potential Energy', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
            title('Potential Energy Comparison - First FF vs MS', 'FontSize', FontSizes.Title, 'FontName', FontSizes.FontName);
            set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
            legend('show', 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
            grid on;
        end
    end
    
    %% 5. FINAL LAYOUT PLOTS (4 views)
    % 3D View
    figure('Name','Final Layout - 3D View','Position',[100 100 1000 700]);
    hold on; axis equal; grid on; box on;
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        plot3(X, Y, Z, 'b-', 'LineWidth', 1.5);
    end
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'red', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, 'green', 'filled');
    end
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Final Grid Shell Layout - 3D View', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    legend({'Members', 'Fixed Nodes', 'Free Nodes'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
    
    % XZ View
    figure('Name','Final Layout - XZ View','Position',[200 100 1000 700]);
    hold on; grid on; box on;
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        plot(X, Z, 'b-', 'LineWidth', 1.5);
    end
    if ~isempty(FIX_NODE)
        scatter(NODE(FIX_NODE,1), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'red', 'filled');
    end
    if ~isempty(free_nodes)
        scatter(NODE(free_nodes,1), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, 'green', 'filled');
    end
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Final Grid Shell Layout - XZ View (Side)', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    axis equal;
    
    % Plan View (XY)
    figure('Name','Final Layout - Plan View','Position',[300 100 1000 700]);
    hold on; grid on; box on;
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        plot(X, Y, 'b-', 'LineWidth', 1.5);
    end
    if ~isempty(FIX_NODE)
        scatter(NODE(FIX_NODE,1), NODE(FIX_NODE,2), 80, 'red', 'filled');
    end
    if ~isempty(free_nodes)
        scatter(NODE(free_nodes,1), NODE(free_nodes,2), 40, 'green', 'filled');
    end
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Final Grid Shell Layout - Plan View (XY)', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    axis equal;
    
    % YZ View
    figure('Name','Final Layout - YZ View','Position',[400 100 1000 700]);
    hold on; grid on; box on;
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        plot(Y, Z, 'b-', 'LineWidth', 1.5);
    end
    if ~isempty(FIX_NODE)
        scatter(NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'red', 'filled');
    end
    if ~isempty(free_nodes)
        scatter(NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, 'green', 'filled');
    end
    xlabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Final Grid Shell Layout - YZ View (Side)', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    axis equal;
    
    %% 6. AREA PLOT
    figure('Name','Member Areas','Position',[100 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    % Color mapping for areas
    max_area = max(A_cm2);
    min_area = min(A_cm2);
    area_norm = (A_cm2 - min_area) / (max_area - min_area);
    cmap = parula(256);
    idx = round(area_norm * 255) + 1;
    
    % Variable line width based on area
    min_width = 1;
    max_width = 6;
    line_widths = min_width + area_norm * (max_width - min_width);
    
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        plot3(X, Y, Z, 'Color', cmap(idx(i),:), 'LineWidth', line_widths(i));
    end
    
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'red', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, 'black', 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Grid Shell - Member Cross-Sectional Areas', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    colormap(cmap);
    caxis([min_area max_area]);
    cb = colorbar;
    cb.Label.String = 'Cross-Sectional Area (cm²)';
    cb.Label.FontSize = FontSizes.ColorbarLabel;
    cb.Label.FontWeight = 'bold';
    cb.Label.FontName = FontSizes.FontName;
    
    %% 7. STRESS RATIO PLOT
    stress_ratio_free = stress_ratio(free_edge_indices);
    
    figure('Name','Stress Ratios - Members Classified','Position',[200 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    % Color scheme for stress levels
    safe_color = [0.2, 0.8, 0.2];
    warning_color = [1.0, 0.8, 0.0];
    critical_color = [0.9, 0.1, 0.1];
    fixed_color = [0.7, 0.7, 0.7];
    
    if ~isempty(stress_ratio_free)
        max_ratio_free = max(stress_ratio_free);
    else
        max_ratio_free = 1;
    end
    min_line_width = 1;
    max_line_width = 5;
    
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        
        if ismember(i, fixed_edge_indices)
            color = fixed_color;
            line_width = 1;
        else
            free_idx = find(free_edge_indices == i);
            if ~isempty(free_idx) && free_idx <= length(stress_ratio_free)
                line_width = min_line_width + (max_line_width - min_line_width) * (stress_ratio_free(free_idx) / max_ratio_free);
                
                if stress_ratio_free(free_idx) > 0.9
                    color = critical_color;
                elseif stress_ratio_free(free_idx) > 0.7
                    color = warning_color;
                else
                    color = safe_color;
                end
            else
                color = safe_color;
                line_width = 1;
            end
        end
        
        plot3(X, Y, Z, 'Color', color, 'LineWidth', line_width);
    end
    
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'black', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, [0.5 0.5 0.5], 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Stress Ratios (σ/σ_{adm}) - Free Members Analyzed', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    h_safe = plot3(NaN, NaN, NaN, 'Color', safe_color, 'LineWidth', 4);
    h_warning = plot3(NaN, NaN, NaN, 'Color', warning_color, 'LineWidth', 4);
    h_critical = plot3(NaN, NaN, NaN, 'Color', critical_color, 'LineWidth', 4);
    legend([h_safe, h_warning, h_critical], {'Safe (<0.7)', 'Warning (0.7-0.9)', 'Critical (>0.9)'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
    
    %% 8. AXIAL FORCE PLOT
    figure('Name','Axial Forces','Position',[300 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    tension_color = [0.8, 0.2, 0.2];
    compression_color = [0.2, 0.2, 0.8];
    
    max_force = max(abs(F_member));
    
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        
        line_width = 1 + 4 * (abs(F_member(i)) / max_force);
        
        if (z_flipped && F_member(i) < 0) || (~z_flipped && F_member(i) > 0)
            color = tension_color;
        else
            color = compression_color;
        end
        
        plot3(X, Y, Z, 'Color', color, 'LineWidth', line_width);
    end
    
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'black', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, [0.5 0.5 0.5], 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Grid Shell - Axial Forces', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    h_tension = plot3(NaN, NaN, NaN, 'Color', tension_color, 'LineWidth', 3);
    h_compression = plot3(NaN, NaN, NaN, 'Color', compression_color, 'LineWidth', 3);
    legend([h_tension, h_compression], {'Tension', 'Compression'}, 'FontSize', FontSizes.Legend, 'FontName', FontSizes.FontName);
    
    %% 9. STRESS PLOT
    figure('Name','Stress Values','Position',[400 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    max_stress = max(stress_values);
    stress_norm = stress_values / max_stress;
    stress_cmap = parula(256);
    stress_idx = round(stress_norm * 255) + 1;
    
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        
        line_width = 1 + 4 * stress_norm(i);
        plot3(X, Y, Z, 'Color', stress_cmap(stress_idx(i),:), 'LineWidth', line_width);
    end
    
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'black', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, [0.5 0.5 0.5], 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Grid Shell - Stress Values |σ|', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    colormap(stress_cmap);
    caxis([0 max_stress]);
    cb = colorbar;
    cb.Label.String = 'Stress |σ| (kN/m²)';
    cb.Label.FontSize = FontSizes.ColorbarLabel;
    cb.Label.FontWeight = 'bold';
    cb.Label.FontName = FontSizes.FontName;
    
    %% 10. MEMBER CLASSIFICATION PLOT
    A_stats = A_cm2(A_cm2 > 10);
    if ~isempty(A_stats)
        large_threshold = 0.8 * max(A_stats);
        med_threshold = 0.4 * max(A_stats);
        
        figure('Name','Member Classification by Area','Position',[100 300 1400 500]);
        
        % Pie chart
        subplot(1,3,1);
        n_large = sum(A_cm2 > large_threshold);
        n_med = sum(A_cm2 > med_threshold & A_cm2 <= large_threshold);
        n_small = sum(A_cm2 > 10 & A_cm2 <= med_threshold);
        n_fixed = sum(A_cm2 <= 10);
        
        pie_data = [n_small, n_med, n_large, n_fixed];
        pie_labels = {sprintf('Small\n(%d)', n_small), sprintf('Medium\n(%d)', n_med), ...
                      sprintf('Large\n(%d)', n_large), sprintf('Fixed\n(%d)', n_fixed)};
        pie([n_small, n_med, n_large, n_fixed], pie_labels);
        title('Member Classification by Area', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        set(gca, 'FontName', FontSizes.FontName);
        
        % Histogram
        subplot(1,3,2);
        histogram(A_stats, 20, 'FaceColor', [0.6 0.6 0.9], 'EdgeColor', 'black');
        xlabel('Cross-Sectional Area (cm²)', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        ylabel('Frequency', 'FontSize', FontSizes.AxisLabel, 'FontName', FontSizes.FontName);
        title('Area Distribution', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
        grid on;
        
        % Statistics table
        subplot(1,3,3);
        axis off;
        stats_text = {
            sprintf('Total Members: %d', length(BARS));
            sprintf('Large Areas (>%.0f cm²): %d', large_threshold, n_large);
            sprintf('Medium Areas: %d', n_med);
            sprintf('Small Areas: %d', n_small);
            sprintf('Fixed Areas (≤10 cm²): %d', n_fixed);
            sprintf('Max Area: %.1f cm²', max(A_stats));
            sprintf('Mean Area: %.1f cm²', mean(A_stats));
            sprintf('Total Volume: %.3f m³', sum(A .* L0));
        };
        
        for i = 1:length(stats_text)
            text(0.1, 0.9 - (i-1)*0.1, stats_text{i}, 'FontSize', 12, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
        end
        title('Area Statistics', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    end

    %% 11. AXIAL FORCE PLOT (with colormap)
    figure('Name','Axial Forces - Colormap','Position',[500 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    % Create colormap for axial forces
    colormap(jet(256));
    min_force = min(F_member);
    max_force = max(F_member);
    
    % Normalize force values for colormap indexing
    if max_force == min_force
        force_norm = zeros(size(F_member));
    else
        force_norm = (F_member - min_force) / (max_force - min_force);
    end
    color_indices = round(force_norm * 255) + 1;
    
    % Plot members with color representing axial force
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        
        % Line width proportional to force magnitude
        line_width = 1 + 4 * (abs(F_member(i)) / max(abs(F_member)));
        
        % Get color from colormap
        color = jet(256);
        plot3(X, Y, Z, 'Color', color(color_indices(i), :), 'LineWidth', line_width);
    end
    
    % Plot nodes
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'black', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, [0.5 0.5 0.5], 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Grid Shell - Axial Forces', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    % Add colorbar with proper labeling
    caxis([min_force max_force]);
    cb = colorbar;
    cb.Label.String = 'Axial Force (kN)';
    cb.Label.FontSize = FontSizes.ColorbarLabel;
    cb.Label.FontWeight = 'bold';
    cb.Label.FontName = FontSizes.FontName;
    
    % Add text annotation with force statistics
    text(0.02, 0.98, sprintf('Max Force: %.1f kN\nMin Force: %.1f kN', max_force, min_force), ...
         'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'white', ...
         'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'FontName', FontSizes.FontName);

    %% 12. STRESS RATIO VALUES PLOT
    figure('Name','Stress Ratio Values','Position',[600 200 1000 700]);
    hold on; axis equal; grid on; box on;
    
    % Create colormap for stress ratio values
    colormap(jet(256));
    min_ratio = min(stress_ratio);
    max_ratio = max(stress_ratio);
    
    % Normalize stress ratio values for colormap indexing
    if max_ratio == min_ratio
        ratio_norm = zeros(size(stress_ratio));
    else
        ratio_norm = (stress_ratio - min_ratio) / (max_ratio - min_ratio);
    end
    color_indices = round(ratio_norm * 255) + 1;
    
    % Plot members with color representing stress ratio
    for i = 1:length(BARS)
        n1 = BARS(i,1); n2 = BARS(i,2);
        X = [NODE(n1,1), NODE(n2,1)];
        Y = [NODE(n1,2), NODE(n2,2)];
        Z = z_flipped * -[NODE(n1,3), NODE(n2,3)] + ~z_flipped * [NODE(n1,3), NODE(n2,3)];
        
        % Line width proportional to stress ratio
        line_width = 1 + 4 * stress_ratio(i) / max_ratio;
        
        % Get color from colormap
        color = jet(256);
        plot3(X, Y, Z, 'Color', color(color_indices(i), :), 'LineWidth', line_width);
    end
    
    % Plot nodes
    if ~isempty(FIX_NODE)
        scatter3(NODE(FIX_NODE,1), NODE(FIX_NODE,2), z_flipped*(-NODE(FIX_NODE,3))+~z_flipped*NODE(FIX_NODE,3), 80, 'black', 'filled');
    end
    if ~isempty(free_nodes)
        scatter3(NODE(free_nodes,1), NODE(free_nodes,2), z_flipped*(-NODE(free_nodes,3))+~z_flipped*NODE(free_nodes,3), 40, [0.5 0.5 0.5], 'filled');
    end
    
    xlabel('X (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    ylabel('Y (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    zlabel('Z (m)', 'FontSize', FontSizes.AxisLabel, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    title('Grid Shell - Stress Ratio Values (σ/σ_{adm})', 'FontSize', FontSizes.Title, 'FontWeight', 'bold', 'FontName', FontSizes.FontName);
    set(gca, 'FontSize', FontSizes.TickLabel, 'FontName', FontSizes.FontName);
    view(30,40);
    
    % Add colorbar with proper labeling
    caxis([min_ratio max_ratio]);
    cb = colorbar;
    cb.Label.String = 'Stress Ratio (σ/σ_{adm})';
    cb.Label.FontSize = FontSizes.ColorbarLabel;
    cb.Label.FontWeight = 'bold';
    cb.Label.FontName = FontSizes.FontName;
    
    % Add text annotation with stress ratio statistics
    text(0.02, 0.98, sprintf('Max Ratio: %.3f\nMin Ratio: %.3f\nCritical (>0.9): %d members', ...
          max_ratio, min_ratio, sum(stress_ratio > 0.9)), ...
          'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'white', ...
          'VerticalAlignment', 'top', 'HorizontalAlignment', 'left', 'FontName', FontSizes.FontName);
end

%% ENHANCED PE AND GRADIENT TRACKING FUNCTION
function stop = captureOptimizationPEandGradient(x, optimValues, state)
    global PE_iteration_data;
    
    switch state
        case 'init'
            PE_iteration_data.iteration_count = 0;
            PE_iteration_data.values = [];
            PE_iteration_data.iterations = [];
            PE_iteration_data.gradient_norms = [];
            PE_iteration_data.max_gradient_components = [];
        case 'iter'
            PE_iteration_data.iteration_count = PE_iteration_data.iteration_count + 1;
            
            % Store PE value
            PE_iteration_data.values(end+1) = optimValues.fval;
            PE_iteration_data.iterations(end+1) = PE_iteration_data.iteration_count;
            
            % Store gradient information if available
            if isfield(optimValues, 'gradient') && ~isempty(optimValues.gradient)
                gradient = optimValues.gradient;
                PE_iteration_data.gradient_norms(end+1) = norm(gradient);
                PE_iteration_data.max_gradient_components(end+1) = max(abs(gradient));
            else
                PE_iteration_data.gradient_norms(end+1) = NaN;
                PE_iteration_data.max_gradient_components(end+1) = NaN;
            end
        case 'done'
            % Optimization finished
    end
    stop = false;
end

%% Helper Functions

function result = iff(condition, true_value, false_value)
    if condition
        result = true_value;
    else
        result = false_value;
    end
end

function [S,Sigma_G_P,Sigma_G_M] = GetSigma(NODE,BARS,E,L0,group)
    L = GetL(NODE,BARS);
    L0_safe = max(L0, 1e-6);
    epsilon = (L-L0_safe)./L0_safe;
    
    if isscalar(E)
        S = E * epsilon;
    else
        S = E .* epsilon;
    end
    
    if nargin == 5
        NG = length(group);
        Sigma_G_P = zeros(NG,1);
        Sigma_G_M = zeros(NG,1);
        for i=1:NG
            if ~isempty(group{i}) && all(group{i} <= length(S))
                Sigma_G_P(i) = max(S(group{i}));
                Sigma_G_M(i) = min(S(group{i}));
            end
        end
    else
        Sigma_G_P = 0;
        Sigma_G_M = 0;
    end
end

function K = GetStiffness_SA(E,A,L)
    if isscalar(E)
        E_vec = E * ones(size(A));
    else
        E_vec = E;
    end
    
    L_safe = max(L, 1e-6);
    A_safe = max(A, 1e-6);
    E_safe = max(E_vec, 1e3);
    
    AE = E_safe .* A_safe;
    K = AE ./ L_safe;
end

function [K] = GetSprings(NODE,BARS,E_members,A_members)
    L = GetL(NODE,BARS);
    K = GetStiffness_SA(E_members, A_members, L);
end

function ALL_BARS = combineEdges(INNER, EDGE)
    % Safely combine INNER and EDGE arrays, handling empty cases
    
    % Ensure both arrays have correct dimensions (n x 2)
    if isempty(INNER)
        INNER = zeros(0, 2);
    end
    if isempty(EDGE)
        EDGE = zeros(0, 2);
    end
    
    % Check if arrays have correct number of columns
    if size(INNER, 2) ~= 2
        if size(INNER, 1) == 2 && size(INNER, 2) > 2
            INNER = INNER'; % Transpose if needed
        else
            error('INNER array must have 2 columns (Node1, Node2)');
        end
    end
    
    if size(EDGE, 2) ~= 2 && ~isempty(EDGE)
        if size(EDGE, 1) == 2 && size(EDGE, 2) > 2
            EDGE = EDGE'; % Transpose if needed
        else
            error('EDGE array must have 2 columns (Node1, Node2)');
        end
    end
    
    % Combine arrays
    if isempty(EDGE)
        ALL_BARS = INNER;
    elseif isempty(INNER)
        ALL_BARS = EDGE;
    else
        ALL_BARS = [INNER; EDGE];
    end
    
    % Ensure result has correct dimensions
    if isempty(ALL_BARS)
        ALL_BARS = zeros(0, 2);
    end
end