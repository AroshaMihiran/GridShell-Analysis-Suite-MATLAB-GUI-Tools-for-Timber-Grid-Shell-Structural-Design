function GridShellAnalysisTool_FormFindingOnly()
% GridShellAnalysisTool_FormFindingOnly - Form Finding Only GUI
% Features: 3D selection, per-material/load colors, member areas,
%           free/fixed node creation, PNG export, improved undo

    % Create main figure
    hFig = figure('Name', 'GridShell Form Finding Tool', ...
                  'Position', [50 50 1700 950], ...
                  'NumberTitle', 'off', ...
                  'MenuBar', 'none', ...
                  'Toolbar', 'figure', ...
                  'Units', 'pixels', ...
                  'Color', [0.94 0.94 0.96]);

    % Initialize data structure
    data = struct();
    data.grid_x_spacing = 1; data.grid_y_spacing = 1;
    data.grid_x_spans = 10; data.grid_y_spans = 10;
    data.nodes = []; data.node_types = [];
    data.edges = []; data.materials = [];
    data.member_materials = [];
    data.member_areas = [];  % Member cross-sectional areas in m²
    data.load_patterns = []; data.panels = []; data.panel_loads = [];
    data.working_dir = pwd;
    data.ff_tolerance = 1e-4; data.ff_max_iter = 50;
    data.history = {}; data.current_history_index = 0;
    data.selected_nodes = [];
    data.selection_active = false; data.current_selection_type = '';
    data.imported = false;
    guidata(hFig, data);

    % Color constants
    sectionColor = [0.22 0.42 0.69];
    sectionBg = [0.85 0.90 0.98]; importBg = [0.88 0.95 0.88];
    dangerBg = [1.0 0.88 0.88]; successBg = [0.82 0.95 0.82];
    warningBg = [1.0 0.97 0.82]; neutralBg = [0.93 0.93 0.95];
    areaBg = [0.95 0.88 0.88];

    %% Create UI Panels
    leftPanel = uipanel('Parent', hFig, 'Title', 'Controls', ...
        'Units', 'pixels', 'Position', [10 10 500 930], ...
        'FontSize', 11, 'FontWeight', 'bold', 'BackgroundColor', [0.96 0.96 0.98]);
    middlePanel = uipanel('Parent', hFig, 'Title', 'Data Tables', ...
        'Units', 'pixels', 'Position', [520 10 450 930], 'FontSize', 11, 'FontWeight', 'bold');
    rightPanel = uipanel('Parent', hFig, 'Title', 'Grid Visualization', ...
        'Units', 'pixels', 'Position', [980 10 700 930], 'FontSize', 11, 'FontWeight', 'bold');

    hAxes = axes('Parent', rightPanel, 'Units', 'normalized', ...
        'Position', [0.05 0.05 0.9 0.9], 'Box', 'on', ...
        'XGrid', 'on', 'YGrid', 'on', 'ZGrid', 'on');
    xlabel(hAxes,'X (m)'); ylabel(hAxes,'Y (m)'); zlabel(hAxes,'Z (m)');
    view(hAxes,3); axis(hAxes,'equal'); rotate3d(hAxes,'on');

    %% Left Panel Controls
    yPos = 885; yStep = 22;
    labelW = 150; editW = 80; btnW = 220; btnH = 28;
    panelBg = get(leftPanel, 'BackgroundColor');

    function makeSection(txt, bgc)
        uicontrol('Parent', leftPanel, 'Style', 'text', 'String', txt, ...
            'Units', 'pixels', 'Position', [10 yPos 480 22], ...
            'FontWeight', 'bold', 'FontSize', 10, ...
            'ForegroundColor', sectionColor, 'BackgroundColor', bgc, ...
            'HorizontalAlignment', 'left');
        yPos = yPos - yStep;
    end

    % ===== 0. IMPORT =====
    makeSection('  0. IMPORT FROM CSV', importBg);
    hImportDir = uicontrol('Parent', leftPanel, 'Style', 'edit', 'String', '', ...
        'Units', 'pixels', 'Position', [10 yPos 270 25], 'HorizontalAlignment', 'left');
    uicontrol('Parent', leftPanel, 'Style', 'pushbutton', 'String', 'Browse', ...
        'Units', 'pixels', 'Position', [290 yPos 80 25], 'Callback', @browseImportDir);
    uicontrol('Parent', leftPanel, 'Style', 'pushbutton', 'String', 'Import', ...
        'Units', 'pixels', 'Position', [380 yPos 80 25], 'FontWeight', 'bold', ...
        'BackgroundColor', successBg, 'Callback', @importFromCSV);
    yPos = yPos - yStep - 4;

    % ===== 1. GRID SYSTEM =====
    makeSection('  1. GRID SYSTEM DEFINITION', sectionBg);
    uicontrol('Parent',leftPanel,'Style','text','String','X Spacing (m):','Units','pixels','Position',[10 yPos labelW 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hXSpacing = uicontrol('Parent',leftPanel,'Style','edit','String','1','Units','pixels','Position',[160 yPos editW 25]);
    uicontrol('Parent',leftPanel,'Style','text','String','Y Spacing (m):','Units','pixels','Position',[260 yPos labelW 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hYSpacing = uicontrol('Parent',leftPanel,'Style','edit','String','1','Units','pixels','Position',[410 yPos editW 25]);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','text','String','X Spans:','Units','pixels','Position',[10 yPos labelW 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hXSpans = uicontrol('Parent',leftPanel,'Style','edit','String','10','Units','pixels','Position',[160 yPos editW 25]);
    uicontrol('Parent',leftPanel,'Style','text','String','Y Spans:','Units','pixels','Position',[260 yPos labelW 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hYSpans = uicontrol('Parent',leftPanel,'Style','edit','String','10','Units','pixels','Position',[410 yPos editW 25]);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Generate Grid Points','Units','pixels','Position',[10 yPos btnW btnH],'FontWeight','bold','BackgroundColor',neutralBg,'Callback',@generateGrid);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Clear All','Units','pixels','Position',[240 yPos btnW btnH],'FontWeight','bold','BackgroundColor',dangerBg,'Callback',@clearAll);
    yPos = yPos - yStep - 4;

    % ===== 2. NODE SELECTION =====
    makeSection('  2. NODE SELECTION & CONSTRAINTS', sectionBg);
    hPickNodeType = uicontrol('Parent',leftPanel,'Style','popupmenu','String',{'Pick as Free Nodes','Pick as Fixed Nodes'},'Units','pixels','Position',[10 yPos 220 25]);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Pick Nodes (Click on Grid)','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@pickNodes);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Add Custom Node','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@addCustomNode);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Change Node Type','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@setNodeType);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Delete Nodes','Units','pixels','Position',[10 yPos btnW btnH],'BackgroundColor',dangerBg,'FontWeight','bold','Callback',@deleteNodes);
    yPos = yPos - yStep - 4;

    % ===== 3. GRID CONNECTIVITY =====
    makeSection('  3. GRID CONNECTIVITY', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Draw Edges (Click 2 Nodes)','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@drawEdges);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Auto Connect Grid','Units','pixels','Position',[240 yPos btnW btnH],'FontWeight','bold','BackgroundColor',successBg,'Callback',@autoConnect);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Delete Edges','Units','pixels','Position',[10 yPos btnW btnH],'BackgroundColor',dangerBg,'FontWeight','bold','Callback',@deleteEdges);
    yPos = yPos - yStep - 4;

    % ===== 4. MATERIALS =====
    makeSection('  4. MATERIALS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Define Material','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@defineMaterials);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign to All Members','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@assignMaterialsToAll);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign to Selected Members','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@assignMaterialsToSelected);
    yPos = yPos - yStep - 4;

    % ===== 5. MEMBER AREAS =====
    makeSection('  5. MEMBER AREAS', areaBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Set Default Areas (0.005 m²)','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@setDefaultAreas);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign Area to All Members','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@assignAreaToAll);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign Area to Selected','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@assignAreaToSelected);
    yPos = yPos - yStep - 4;

    % ===== 6. LOAD PATTERNS =====
    makeSection('  6. LOAD PATTERNS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Define Load Pattern','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@defineLoads);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign to All Panels','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@assignLoadsToAll);
    yPos = yPos - yStep;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Assign to Selected Panels','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@assignLoadsToSelected);
    yPos = yPos - yStep - 4;

    % ===== 7. FORM FINDING PARAMETERS =====
    makeSection('  7. FORM FINDING PARAMETERS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','text','String','FF Tolerance:','Units','pixels','Position',[10 yPos 100 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hFFTolerance = uicontrol('Parent',leftPanel,'Style','edit','String','1e-4','Units','pixels','Position',[110 yPos editW 25]);
    uicontrol('Parent',leftPanel,'Style','text','String','FF Max Iter:','Units','pixels','Position',[260 yPos 100 20],'HorizontalAlignment','left','BackgroundColor',panelBg);
    hFFMaxIter = uicontrol('Parent',leftPanel,'Style','edit','String','50','Units','pixels','Position',[360 yPos editW 25]);
    yPos = yPos - yStep - 4;

    % ===== 8. OUTPUT DIRECTORY =====
    makeSection('  8. OUTPUT DIRECTORY', sectionBg);
    hWorkDir = uicontrol('Parent',leftPanel,'Style','edit','String',pwd,'Units','pixels','Position',[10 yPos 350 25],'HorizontalAlignment','left');
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Browse','Units','pixels','Position',[370 yPos 80 25],'Callback',@browseDir);
    yPos = yPos - yStep - 4;

    % ===== 9. TOOLS =====
    makeSection('  9. TOOLS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Undo Last Action','Units','pixels','Position',[10 yPos btnW btnH],'BackgroundColor',warningBg,'FontWeight','bold','Callback',@undoLastAction);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Cancel Operation','Units','pixels','Position',[240 yPos btnW btnH],'BackgroundColor',[1 0.92 0.85],'FontWeight','bold','Callback',@cancelOperation);
    yPos = yPos - yStep - 4;

    % ===== 10. VIEW =====
    makeSection('  10. VIEW CONTROLS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','3D View','Units','pixels','Position',[10 yPos 80 btnH],'Callback',{@changeView,3});
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','XY View','Units','pixels','Position',[100 yPos 80 btnH],'Callback',{@changeView,'xy'});
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','XZ View','Units','pixels','Position',[190 yPos 80 btnH],'Callback',{@changeView,'xz'});
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','YZ View','Units','pixels','Position',[280 yPos 80 btnH],'Callback',{@changeView,'yz'});
    yPos = yPos - yStep - 4;

    % ===== 11. PANELS =====
    makeSection('  11. PANEL TOOLS', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Generate Panels','Units','pixels','Position',[10 yPos btnW btnH],'Callback',@generatePanels);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','Visualize Panels','Units','pixels','Position',[240 yPos btnW btnH],'Callback',@visualizePanels);
    yPos = yPos - yStep - 4;

    % ===== 12. RUN =====
    makeSection('  12. GENERATE CSV / RUN FORM FINDING', sectionBg);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','VALIDATE INPUTS','Units','pixels','Position',[10 yPos btnW 32],'BackgroundColor',warningBg,'FontWeight','bold','FontSize',10,'Callback',@validateInputs);
    yPos = yPos - 36;
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','GENERATE CSV FILES','Units','pixels','Position',[10 yPos btnW 32],'BackgroundColor',[0.82 0.92 1],'FontWeight','bold','FontSize',10,'Callback',@generateCSVOnly);
    uicontrol('Parent',leftPanel,'Style','pushbutton','String','RUN FORM FINDING','Units','pixels','Position',[240 yPos btnW 32],'BackgroundColor',successBg,'FontWeight','bold','FontSize',10,'Callback',@runAnalysis);

    hStatus = uicontrol('Parent',leftPanel,'Style','text','String','Ready - Start by generating grid points','Units','pixels','Position',[10 10 480 25],'BackgroundColor',[0.95 0.95 0.95],'FontWeight','bold','HorizontalAlignment','center');

    %% Middle Panel - Data Tables
    tabGroup = uitabgroup('Parent', middlePanel, 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96]);

    nodesTab = uitab('Parent',tabGroup,'Title','Nodes');
    hNodesTable = uitable('Parent',nodesTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'ID','X','Y','Z','Type'},'ColumnEditable',[false true true true true],...
        'CellEditCallback',@editNodeData,'CellSelectionCallback',{@tableSelectionCallback,'nodes'});

    edgesTab = uitab('Parent',tabGroup,'Title','Edges');
    hEdgesTable = uitable('Parent',edgesTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'ID','Node1','Node2','Material','Area(m²)'},...
        'ColumnEditable',[false true true true true],...
        'CellEditCallback',@editEdgeData,'CellSelectionCallback',{@tableSelectionCallback,'edges'});

    materialsTab = uitab('Parent',tabGroup,'Title','Materials');
    hMaterialsTable = uitable('Parent',materialsTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'ID','Name','E','fcok','ftok','kmod','Color'},...
        'ColumnEditable',[false true true true true true false],...
        'CellEditCallback',@editMaterialData,'CellSelectionCallback',{@tableSelectionCallback,'materials'});

    loadsTab = uitab('Parent',tabGroup,'Title','Loads');
    hLoadsTable = uitable('Parent',loadsTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'ID','Name','q1','q2','Color'},'ColumnEditable',[false true true true false],...
        'CellEditCallback',@editLoadData,'CellSelectionCallback',{@tableSelectionCallback,'loads'});

    panelsTab = uitab('Parent',tabGroup,'Title','Panels');
    hPanelsTable = uitable('Parent',panelsTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'ID','Nodes','Load Pattern'},'ColumnEditable',[false true true],...
        'CellEditCallback',@editPanelData,'CellSelectionCallback',{@tableSelectionCallback,'panels'});

    assignmentsTab = uitab('Parent',tabGroup,'Title','Assignments');
    hAssignmentsTable = uitable('Parent',assignmentsTab,'Units','normalized','Position',[0.05 0.05 0.9 0.9],...
        'ColumnName',{'Type','ID','Material/Load/Area'},'ColumnEditable',[false false true]);

    uicontrol('Parent',middlePanel,'Style','pushbutton','String','Add Row','Units','pixels','Position',[10 40 80 25],'Callback',@addTableRow);
    uicontrol('Parent',middlePanel,'Style','pushbutton','String','Delete Row','Units','pixels','Position',[100 40 80 25],'Callback',@deleteTableRow);

    updateVisualization(); updateDataTables();

    %% ============ HELPERS: 3D Ray Picking ============
    function [idx, min_dist] = findNearestNode3D(nodes)
        cp = get(hAxes,'CurrentPoint'); ray_o = cp(1,:); ray_d = cp(2,:)-cp(1,:);
        rl = norm(ray_d); if rl<eps||isempty(nodes), idx=0; min_dist=inf; return; end
        ray_d = ray_d/rl; n = size(nodes,1); dists = zeros(n,1);
        for ni = 1:n, v = nodes(ni,:)-ray_o; t = dot(v,ray_d); dists(ni) = norm(nodes(ni,:)-(ray_o+t*ray_d)); end
        [min_dist,idx] = min(dists);
    end
    function [idx, min_dist] = findNearestEdge3D(nodes, edges)
        cp = get(hAxes,'CurrentPoint'); ray_o = cp(1,:); ray_d = cp(2,:)-cp(1,:);
        rl = norm(ray_d); if rl<eps||isempty(edges), idx=0; min_dist=inf; return; end
        ray_d = ray_d/rl; ne = size(edges,1); dists = inf(ne,1);
        for ei = 1:ne
            n1=edges(ei,1); n2=edges(ei,2);
            if n1<=size(nodes,1) && n2<=size(nodes,1)
                for frac = 0:0.1:1
                    pt = nodes(n1,:)*(1-frac)+nodes(n2,:)*frac;
                    v = pt-ray_o; t = dot(v,ray_d); d = norm(pt-(ray_o+t*ray_d));
                    if d < dists(ei), dists(ei) = d; end
                end
            end
        end
        [min_dist,idx] = min(dists);
    end
    function thr = getThreshold()
        d = guidata(hFig);
        if isfield(d,'grid_x_spacing'), thr = max(d.grid_x_spacing,d.grid_y_spacing)*0.5; else, thr = 0.5; end
    end
    function stop = checkCancel()
        tmp = guidata(hFig); stop = ~tmp.selection_active;
    end

    %% ============ HISTORY / UNDO ============
    function saveHistory()
        data = guidata(hFig);
        data.current_history_index = data.current_history_index + 1;
        snapshot = data; snapshot.history = {}; snapshot.current_history_index = 0;
        data.history{data.current_history_index} = snapshot;
        if length(data.history)>30, data.history = data.history(end-29:end); data.current_history_index = 30; end
        guidata(hFig, data);
    end
    function undoLastAction(~,~)
        data = guidata(hFig);
        if data.current_history_index > 0
            prev = data.history{data.current_history_index};
            data.current_history_index = data.current_history_index - 1;
            data.nodes=prev.nodes; data.node_types=prev.node_types; data.edges=prev.edges;
            data.materials=prev.materials; data.member_materials=prev.member_materials;
            data.member_areas=prev.member_areas; data.load_patterns=prev.load_patterns;
            data.panels=prev.panels; data.panel_loads=prev.panel_loads;
            if isfield(prev,'grid_points')
                data.grid_points=prev.grid_points; data.grid_x_spacing=prev.grid_x_spacing;
                data.grid_y_spacing=prev.grid_y_spacing; data.grid_x_spans=prev.grid_x_spans; data.grid_y_spans=prev.grid_y_spans;
                set(hXSpacing,'String',num2str(prev.grid_x_spacing)); set(hYSpacing,'String',num2str(prev.grid_y_spacing));
                set(hXSpans,'String',num2str(prev.grid_x_spans)); set(hYSpans,'String',num2str(prev.grid_y_spans));
            end
            guidata(hFig,data); updateVisualization(); updateDataTables(); updateStatus('Undo completed.');
        else, updateStatus('No actions to undo.'); end
    end
    function cancelOperation(~,~)
        data = guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); set(hFig,'Pointer','arrow'); updateStatus('Operation cancelled.');
    end

    %% ============ GRID ============
    function generateGrid(~,~)
        saveHistory(); data = guidata(hFig);
        xs=str2double(get(hXSpacing,'String')); ys=str2double(get(hYSpacing,'String'));
        xn=str2double(get(hXSpans,'String')); yn=str2double(get(hYSpans,'String'));
        if isnan(xs)||xs<=0||isnan(ys)||ys<=0||isnan(xn)||xn<1||isnan(yn)||yn<1, errordlg('Invalid grid parameters','Error'); return; end
        [X,Y]=meshgrid(0:xs:xn*xs, 0:ys:yn*ys);
        data.grid_points=[X(:),Y(:),zeros(numel(X),1)];
        data.grid_x_spacing=xs; data.grid_y_spacing=ys; data.grid_x_spans=xn; data.grid_y_spans=yn;
        guidata(hFig,data); updateVisualization(); updateDataTables();
        updateStatus(sprintf('Grid: %d points. Click "Pick Nodes" to select.', numel(X)));
    end
    function clearAll(~,~)
        if ~strcmp(questdlg('Clear all data?','Confirm','Yes','No','No'),'Yes'), return; end
        saveHistory(); data = guidata(hFig);
        data.nodes=[]; data.node_types=[]; data.edges=[]; data.materials=[];
        data.member_materials=[]; data.member_areas=[]; data.load_patterns=[];
        data.panels=[]; data.panel_loads=[];
        data.selection_active=false; data.current_selection_type='';
        if isfield(data,'grid_points'), data=rmfield(data,'grid_points'); end
        guidata(hFig,data); updateVisualization(); updateDataTables(); updateStatus('All data cleared.');
    end

    %% ============ NODES ============
    function pickNodes(~,~)
        saveHistory(); data = guidata(hFig);
        if ~isfield(data,'grid_points')||isempty(data.grid_points), warndlg('Generate grid first.','Error'); return; end
        ntype = get(hPickNodeType,'Value')-1; ts = {'Free','Fixed'};
        updateStatus(sprintf('Click grid points to add as %s nodes. ENTER when done.', ts{ntype+1}));
        data.selection_active=true; data.current_selection_type='nodes'; guidata(hFig,data);
        hold(hAxes,'on'); sel_nodes = [];
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                [idx,md]=findNearestNode3D(data.grid_points);
                if md<getThreshold()
                    nn=data.grid_points(idx,:);
                    if isempty(sel_nodes)||~any(all(abs(sel_nodes-nn)<0.01,2))
                        sel_nodes=[sel_nodes;nn];
                        if ntype==1, plot3(hAxes,nn(1),nn(2),nn(3),'rs','MarkerSize',12,'MarkerFaceColor','r');
                        else, plot3(hAxes,nn(1),nn(2),nn(3),'go','MarkerSize',10,'MarkerFaceColor','g'); end
                        drawnow;
                    end
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        if ~isempty(sel_nodes), data.nodes=[data.nodes;sel_nodes]; data.node_types=[data.node_types;ntype*ones(size(sel_nodes,1),1)]; end
        guidata(hFig,data); updateVisualization(); updateDataTables();
        if ~isempty(sel_nodes), updateStatus(sprintf('%d %s nodes added. Total: %d',size(sel_nodes,1),ts{ntype+1},size(data.nodes,1)));
        else, updateStatus('No nodes selected.'); end
    end
    function addCustomNode(~,~)
        saveHistory(); answer=inputdlg({'X:','Y:','Z:','Type (0=Free, 1=Fixed):'},'Add Node',[1 35],{'0','0','0','0'});
        if isempty(answer), return; end
        c=[str2double(answer{1}),str2double(answer{2}),str2double(answer{3})]; nt=round(max(0,min(1,str2double(answer{4}))));
        if any(isnan(c))||isnan(nt), errordlg('Invalid input','Error'); return; end
        data=guidata(hFig); data.nodes=[data.nodes;c]; data.node_types=[data.node_types;nt];
        guidata(hFig,data); updateVisualization(); updateDataTables();
    end
    function setNodeType(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.nodes), warndlg('No nodes.','Error'); return; end
        ch=questdlg('Set clicked nodes to:','Change Type','Free','Fixed','Free');
        if isempty(ch), return; end; nt=double(strcmp(ch,'Fixed'));
        updateStatus(sprintf('Click nodes to set as %s. ENTER when done.',ch));
        data.selection_active=true; data.current_selection_type='ntype'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestNode3D(data.nodes);
                if md<getThreshold(), data.node_types(idx)=nt; cnt=cnt+1; guidata(hFig,data);
                    if nt==1, plot3(hAxes,data.nodes(idx,1),data.nodes(idx,2),data.nodes(idx,3),'rs','MarkerSize',12,'MarkerFaceColor','r');
                    else, plot3(hAxes,data.nodes(idx,1),data.nodes(idx,2),data.nodes(idx,3),'go','MarkerSize',10,'MarkerFaceColor','g'); end; drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateVisualization(); updateDataTables(); updateStatus(sprintf('%d nodes set as %s.',cnt,ch));
    end
    function deleteNodes(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.nodes), warndlg('No nodes.','Error'); return; end
        updateStatus('Click nodes to delete. ENTER when done.');
        data.selection_active=true; data.current_selection_type='del_n'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestNode3D(data.nodes);
                if md<getThreshold()
                    data.nodes(idx,:)=[]; data.node_types(idx)=[];
                    er=any(data.edges==idx,2); data.edges(er,:)=[];
                    if ~isempty(data.member_materials), data.member_materials(er)=[]; end
                    if ~isempty(data.member_areas), data.member_areas(er)=[]; end
                    data.edges(data.edges>idx)=data.edges(data.edges>idx)-1;
                    if ~isempty(data.panels)
                        rm=[];
                        for pi=1:length(data.panels)
                            if any(data.panels{pi}==idx), rm=[rm,pi];
                            else, data.panels{pi}(data.panels{pi}>idx)=data.panels{pi}(data.panels{pi}>idx)-1; end
                        end
                        if ~isempty(rm), data.panels(rm)=[]; data.panel_loads(rm)=[]; end
                    end
                    cnt=cnt+1; guidata(hFig,data); updateVisualization(); drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateStatus(sprintf('%d nodes deleted.',cnt));
    end

    %% ============ EDGES ============
    function drawEdges(~,~)
        saveHistory(); data=guidata(hFig);
        if size(data.nodes,1)<2, warndlg('Need 2+ nodes.','Error'); return; end
        updateStatus('Click two nodes to create edge. ENTER when done.');
        data.selection_active=true; data.current_selection_type='edges'; guidata(hFig,data);
        hold(hAxes,'on'); ecnt=0; fn=[]; tp=[];
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestNode3D(data.nodes);
                if md<getThreshold()
                    if isempty(fn)
                        fn=idx; if ~isempty(tp)&&ishandle(tp), delete(tp); end
                        tp=plot3(hAxes,data.nodes(idx,1),data.nodes(idx,2),data.nodes(idx,3),'yo','MarkerSize',14,'MarkerFaceColor','y'); drawnow;
                    else
                        if fn~=idx
                            ex=false; if ~isempty(data.edges), ex=any((data.edges(:,1)==fn&data.edges(:,2)==idx)|(data.edges(:,1)==idx&data.edges(:,2)==fn)); end
                            if ~ex
                                data.edges=[data.edges;fn,idx];
                                if ~isempty(data.member_materials), data.member_materials=[data.member_materials;1]; end
                                if ~isempty(data.member_areas), data.member_areas=[data.member_areas;0.005]; end
                                ecnt=ecnt+1; guidata(hFig,data);
                                plot3(hAxes,[data.nodes(fn,1),data.nodes(idx,1)],[data.nodes(fn,2),data.nodes(idx,2)],[data.nodes(fn,3),data.nodes(idx,3)],'b-','LineWidth',2); drawnow;
                            end
                        end
                        fn=[]; if ~isempty(tp)&&ishandle(tp), delete(tp); tp=[]; end; updateVisualization();
                    end
                end
            catch, break; end
        end
        if ~isempty(tp)&&ishandle(tp), delete(tp); end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateStatus(sprintf('%d new edges. Total: %d',ecnt,size(data.edges,1)));
    end
    function autoConnect(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.nodes), warndlg('No nodes.','Error'); return; end
        ch=questdlg('Include diagonal connections?','Auto Connect','Orthogonal Only','Include Diagonals','Orthogonal Only');
        if isempty(ch), return; end
        if strcmp(ch,'Include Diagonals'), thr=1.5*max(data.grid_x_spacing,data.grid_y_spacing);
        else, thr=1.1*max(data.grid_x_spacing,data.grid_y_spacing); end
        ne=[];
        for i=1:size(data.nodes,1), for j=i+1:size(data.nodes,1)
            if norm(data.nodes(i,:)-data.nodes(j,:))<=thr
                ex=false; if ~isempty(data.edges), ex=any((data.edges(:,1)==i&data.edges(:,2)==j)|(data.edges(:,1)==j&data.edges(:,2)==i)); end
                if ~ex, ne=[ne;i,j]; end
            end
        end, end
        if ~isempty(ne)
            data.edges=[data.edges;ne];
            if ~isempty(data.member_materials), data.member_materials=[data.member_materials;ones(size(ne,1),1)]; end
            data.member_areas=[data.member_areas;0.005*ones(size(ne,1),1)];
            guidata(hFig,data); updateVisualization(); updateDataTables();
            updateStatus(sprintf('Auto-connected: %d new, %d total.',size(ne,1),size(data.edges,1)));
        else, updateStatus('No new connections.'); end
    end
    function deleteEdges(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.edges), warndlg('No edges.','Error'); return; end
        updateStatus('Click edges to delete. ENTER when done.');
        data.selection_active=true; data.current_selection_type='del_e'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestEdge3D(data.nodes,data.edges);
                if md<getThreshold()&&idx>0
                    data.edges(idx,:)=[];
                    if ~isempty(data.member_materials)&&idx<=length(data.member_materials), data.member_materials(idx)=[]; end
                    if ~isempty(data.member_areas)&&idx<=length(data.member_areas), data.member_areas(idx)=[]; end
                    cnt=cnt+1; guidata(hFig,data); updateVisualization(); drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateStatus(sprintf('%d edges deleted.',cnt));
    end

    %% ============ MATERIALS ============
    function defineMaterials(~,~)
        saveHistory(); data=guidata(hFig);
        answer=inputdlg({'Name:','E (kN/m²):','fcok (kN/m²):','ftok (kN/m²):','kmod:'},'Define Material',[1 50],{'Wood','11000000','24000','14000','0.9'});
        if isempty(answer), return; end
        m.name=answer{1}; m.E=str2double(answer{2}); m.fcok=str2double(answer{3}); m.ftok=str2double(answer{4}); m.kmod=str2double(answer{5});
        if any(isnan([m.E,m.fcok,m.ftok,m.kmod])), errordlg('Invalid values','Error'); return; end
        c=uisetcolor([rand rand rand],sprintf('Color for "%s"',m.name)); if length(c)==1, c=[0.2 0.6 1]; end; m.color=c;
        if isempty(data.materials), data.materials=m; else, data.materials(end+1)=m; end
        guidata(hFig,data); updateDataTables(); updateVisualization();
        updateStatus(sprintf('Material "%s" defined. Total: %d',m.name,length(data.materials)));
    end
    function assignMaterialsToAll(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.materials), warndlg('Define materials first.','Error'); return; end
        if isempty(data.edges), warndlg('No edges.','Error'); return; end
        [s,ok]=listdlg('ListString',{data.materials.name},'SelectionMode','single','PromptString','Material for ALL:');
        if ~ok, return; end
        data.member_materials=s*ones(size(data.edges,1),1);
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable(); updateVisualization();
    end
    function assignMaterialsToSelected(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.materials)||isempty(data.edges), warndlg('Need materials and edges.','Error'); return; end
        [s,ok]=listdlg('ListString',{data.materials.name},'SelectionMode','single','PromptString','Material for clicked:');
        if ~ok, return; end
        updateStatus('Click edges to assign material. ENTER when done.');
        data.selection_active=true; data.current_selection_type='mat_a'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestEdge3D(data.nodes,data.edges);
                if md<getThreshold()&&idx>0
                    if isempty(data.member_materials), data.member_materials=ones(size(data.edges,1),1); end
                    data.member_materials(idx)=s; cnt=cnt+1; guidata(hFig,data);
                    n1=data.edges(idx,1); n2=data.edges(idx,2);
                    plot3(hAxes,[data.nodes(n1,1),data.nodes(n2,1)],[data.nodes(n1,2),data.nodes(n2,2)],[data.nodes(n1,3),data.nodes(n2,3)],'-','LineWidth',3,'Color',data.materials(s).color); drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable(); updateVisualization();
    end

    %% ============ MEMBER AREAS ============
    function setDefaultAreas(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.edges), warndlg('No edges.','Error'); return; end
        data.member_areas=0.005*ones(size(data.edges,1),1);
        guidata(hFig,data); updateDataTables();
        updateStatus(sprintf('Default area 0.005 m² set for all %d members.',size(data.edges,1)));
    end
    function assignAreaToAll(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.edges), warndlg('No edges.','Error'); return; end
        answer=inputdlg({'Cross-sectional Area (m²):'},'Area for All',[1 35],{'0.005'});
        if isempty(answer), return; end
        av=str2double(answer{1}); if isnan(av)||av<=0, errordlg('Invalid area','Error'); return; end
        data.member_areas=av*ones(size(data.edges,1),1);
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable();
        updateStatus(sprintf('Area %.4f m² assigned to all %d members.',av,size(data.edges,1)));
    end
    function assignAreaToSelected(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.edges), warndlg('No edges.','Error'); return; end
        answer=inputdlg({'Cross-sectional Area (m²):'},'Area for Selected',[1 35],{'0.005'});
        if isempty(answer), return; end
        av=str2double(answer{1}); if isnan(av)||av<=0, errordlg('Invalid area','Error'); return; end
        updateStatus('Click edges to assign area. ENTER when done.');
        data.selection_active=true; data.current_selection_type='area_a'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); [idx,md]=findNearestEdge3D(data.nodes,data.edges);
                if md<getThreshold()&&idx>0
                    if isempty(data.member_areas), data.member_areas=0.005*ones(size(data.edges,1),1); end
                    data.member_areas(idx)=av; cnt=cnt+1; guidata(hFig,data);
                    n1=data.edges(idx,1); n2=data.edges(idx,2);
                    plot3(hAxes,[data.nodes(n1,1),data.nodes(n2,1)],[data.nodes(n1,2),data.nodes(n2,2)],[data.nodes(n1,3),data.nodes(n2,3)],'-','LineWidth',4,'Color','m'); drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable();
        updateStatus(sprintf('Area %.4f m² assigned to %d members.',av,cnt));
    end

    %% ============ LOADS ============
    function defineLoads(~,~)
        saveHistory(); data=guidata(hFig);
        answer=inputdlg({'Name:','Dead Load q1 (kN/m²):','Wind Load q2 (kN/m²):'},'Define Load',[1 50],{'Load 1','3','2'});
        if isempty(answer), return; end
        lp.name=answer{1}; lp.q1=str2double(answer{2}); lp.q2=str2double(answer{3});
        if isnan(lp.q1)||isnan(lp.q2), errordlg('Invalid values','Error'); return; end
        c=uisetcolor([rand rand rand],sprintf('Color for "%s"',lp.name)); if length(c)==1, c=[0.8 0.2 0.2]; end; lp.color=c;
        if isempty(data.load_patterns), data.load_patterns=lp; else, data.load_patterns(end+1)=lp; end
        guidata(hFig,data); updateDataTables();
    end
    function assignLoadsToAll(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.load_patterns), warndlg('Define loads first.','Error'); return; end
        if isempty(data.panels), generatePanels([],[],true); data=guidata(hFig); end
        if isempty(data.panels), return; end
        [s,ok]=listdlg('ListString',{data.load_patterns.name},'SelectionMode','single','PromptString','Load for ALL:');
        if ~ok, return; end; data.panel_loads(:)=s;
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable();
    end
    function assignLoadsToSelected(~,~)
        saveHistory(); data=guidata(hFig);
        if isempty(data.load_patterns), warndlg('Define loads first.','Error'); return; end
        if isempty(data.panels), generatePanels([],[],true); data=guidata(hFig); end
        if isempty(data.panels), return; end
        [s,ok]=listdlg('ListString',{data.load_patterns.name},'SelectionMode','single','PromptString','Load for clicked:');
        if ~ok, return; end
        updateStatus('Click panels to assign. ENTER when done.');
        data.selection_active=true; data.current_selection_type='load_a'; guidata(hFig,data);
        hold(hAxes,'on'); cnt=0;
        while true
            try [~,~,b]=ginput(1); if isempty(b)||b==13, break; end; if checkCancel(), break; end
                data=guidata(hFig); cp=get(hAxes,'CurrentPoint'); ro=cp(1,:); rd=cp(2,:)-cp(1,:);
                rl=norm(rd); if rl<eps, continue; end; rd=rd/rl;
                md=inf; pidx=0;
                for pi=1:length(data.panels), pn=data.panels{pi}; if length(pn)<3, continue; end
                    cen=mean(data.nodes(pn,:),1); v=cen-ro; t=dot(v,rd); d=norm(cen-(ro+t*rd));
                    if d<md, md=d; pidx=pi; end
                end
                if md<max(data.grid_x_spacing,data.grid_y_spacing)*0.8 && pidx>0
                    data.panel_loads(pidx)=s; cnt=cnt+1; guidata(hFig,data);
                    pn=data.panels{pidx};
                    patch(hAxes,data.nodes(pn,1),data.nodes(pn,2),data.nodes(pn,3),data.load_patterns(s).color,'FaceAlpha',0.4,'EdgeColor','k','LineWidth',2); drawnow;
                end
            catch, break; end
        end
        set(hFig,'Pointer','arrow'); data=guidata(hFig); data.selection_active=false; data.current_selection_type='';
        guidata(hFig,data); updateDataTables(); updateAssignmentsTable();
    end

    %% ============ PANELS ============
    function generatePanels(~,~,silent)
        if nargin<3, silent=false; end; if ~silent, saveHistory(); end
        data=guidata(hFig);
        if isempty(data.edges), if ~silent, warndlg('Create edges first.','Error'); end; return; end
        try
            opts=struct('tolAng',1e-9,'dropOuter',true,'shareRule','equal');
            [P,T,PA]=gridshell_panels(data.nodes,data.edges,opts);
            if isempty(P), if ~silent, warndlg('No panels generated.','Error'); end; return; end
            data.panels=P; data.panel_loads=ones(length(P),1); data.tributary_areas=T; data.panel_areas=PA;
        catch
            panels=detectPanelsFromGrid(data.nodes,data.edges);
            if isempty(panels), if ~silent, warndlg('No panels.','Error'); end; return; end
            sz=cellfun(@length,panels); [mx,mi]=max(sz); if mx>2*median(sz), panels(mi)=[]; end
            data.panels=panels; data.panel_loads=ones(length(panels),1);
        end
        guidata(hFig,data); updateDataTables();
        updateStatus(sprintf('%d panels generated.',length(data.panels)));
    end
    function visualizePanels(~,~)
        data=guidata(hFig); if isempty(data.panels), warndlg('No panels.','Error'); return; end
        pf=figure('Name','Panel Visualization','Position',[100 100 800 600]);
        pa=axes('Parent',pf,'Position',[0.05 0.05 0.9 0.9]); hold(pa,'on');
        for i=1:size(data.edges,1), n1=data.edges(i,1); n2=data.edges(i,2);
            if n1<=size(data.nodes,1)&&n2<=size(data.nodes,1), plot3(pa,[data.nodes(n1,1),data.nodes(n2,1)],[data.nodes(n1,2),data.nodes(n2,2)],[data.nodes(n1,3),data.nodes(n2,3)],'b-','LineWidth',1); end
        end
        for i=1:length(data.panels), pn=data.panels{i}; if length(pn)<3, continue; end
            if i<=length(data.panel_loads)&&~isempty(data.load_patterns)
                li=data.panel_loads(i); if li>0&&li<=length(data.load_patterns), c=data.load_patterns(li).color; else, c=[.5 .5 .5]; end
            else, c=[.5 .5 .5]; end
            patch(pa,data.nodes(pn,1),data.nodes(pn,2),data.nodes(pn,3),c,'FaceAlpha',0.5,'EdgeColor','k');
            cen=mean(data.nodes(pn,:),1); text(pa,cen(1),cen(2),cen(3),sprintf('%d',i),'HorizontalAlignment','center','FontWeight','bold');
        end
        xlabel(pa,'X'); ylabel(pa,'Y'); zlabel(pa,'Z'); title(pa,'Panels'); axis(pa,'equal'); view(pa,3); grid(pa,'on'); hold(pa,'off');
    end

    %% ============ VIEW / BROWSE ============
    function changeView(~,~,vt), switch vt, case 3, view(hAxes,3); case 'xy', view(hAxes,0,90); case 'xz', view(hAxes,0,0); case 'yz', view(hAxes,90,0); end; axis(hAxes,'equal'); end
    function browseDir(~,~), f=uigetdir(pwd,'Select Directory'); if f~=0, set(hWorkDir,'String',f); end; end
    function browseImportDir(~,~), f=uigetdir(pwd,'Select CSV Directory'); if f~=0, set(hImportDir,'String',f); end; end

    %% ============ VALIDATE ============
    function validateInputs(~,~)
        data=guidata(hFig); errs={}; warns={};
        if isempty(data.nodes), errs{end+1}='No nodes'; end
        if isempty(data.edges), errs{end+1}='No edges'; end
        if isempty(data.materials), errs{end+1}='No materials'; end
        if isempty(data.member_areas), errs{end+1}='No member areas'; end
        if ~isempty(data.node_types)
            if sum(data.node_types==1)<3, errs{end+1}=sprintf('Need >=3 fixed nodes (have %d)',sum(data.node_types==1)); end
            if sum(data.node_types==0)<1, errs{end+1}=sprintf('Need >=1 free node (have %d)',sum(data.node_types==0)); end
        end
        if ~isempty(data.edges)&&~isempty(data.member_areas)&&length(data.member_areas)~=size(data.edges,1)
            errs{end+1}='Area count does not match edge count'; end
        if ~isempty(data.member_areas)
            if any(data.member_areas<=0), errs{end+1}='Some areas are zero/negative';
            elseif min(data.member_areas)<0.001, warns{end+1}=sprintf('Small areas (min: %.6f)',min(data.member_areas)); end
        end
        if isempty(data.load_patterns), warns{end+1}='No loads (defaults used)'; end
        if isempty(data.panels), warns{end+1}='No panels (auto-generated)'; end
        if isempty(errs)
            if isempty(warns), msgbox('All inputs valid!','Success','help'); updateStatus('Validation OK.');
            else, msgbox(['Warnings:' char(10) strjoin(warns,char(10))],'Warnings','warn'); updateStatus('Validation OK with warnings.'); end
        else
            msg=['Errors:' char(10) strjoin(errs,char(10))];
            if ~isempty(warns), msg=[msg char(10) char(10) 'Warnings:' char(10) strjoin(warns,char(10))]; end
            errordlg(msg,'Validation Failed'); updateStatus('Validation FAILED.');
        end
    end

    %% ============ GENERATE CSV ============
    function generateCSVOnly(~,~)
        data=guidata(hFig);
        if isempty(data.nodes)||isempty(data.edges), errordlg('Define nodes and edges!','Error'); return; end
        if isempty(data.member_areas), errordlg('Define member areas!','Error'); return; end
        data.ff_tolerance=str2double(get(hFFTolerance,'String')); data.ff_max_iter=str2double(get(hFFMaxIter,'String'));
        data.working_dir=get(hWorkDir,'String');
        if isfield(data,'imported')&&data.imported, output_dir=data.working_dir;
        else
            output_dir=fullfile(data.working_dir,['gridshell_formfinding_' datestr(now,'yyyymmdd_HHMMSS')]);
            try mkdir(output_dir); catch, errordlg('Cannot create dir!','Error'); return; end
        end
        try
            generateCSVFiles(data,output_dir); saveVisualizationImages(data,output_dir);
            updateStatus('CSV + images generated!');
            msgbox(sprintf('Files in:\n%s',output_dir),'Success','help');
        catch ME, errordlg(['Error: ' ME.message],'Error'); updateStatus('Failed!');
        end
    end
    function saveVisualizationImages(data,output_dir)
        try
            f1=figure('Visible','off','Position',[0 0 1000 800]); a1=axes('Parent',f1); hold(a1,'on'); grid(a1,'on');
            if ~isempty(data.edges)&&~isempty(data.nodes)
                for i=1:size(data.edges,1), n1=data.edges(i,1); n2=data.edges(i,2);
                    if n1<=size(data.nodes,1)&&n2<=size(data.nodes,1)
                        ec=[0.3 0.5 0.8];
                        if ~isempty(data.member_materials)&&i<=length(data.member_materials)&&~isempty(data.materials)
                            mi=data.member_materials(i); if mi<=length(data.materials), ec=data.materials(mi).color; end; end
                        plot3(a1,[data.nodes(n1,1),data.nodes(n2,1)],[data.nodes(n1,2),data.nodes(n2,2)],[data.nodes(n1,3),data.nodes(n2,3)],'-','LineWidth',2,'Color',ec);
                    end
                end
            end
            if ~isempty(data.nodes)
                fi=data.node_types==0; xi=data.node_types==1;
                if any(fi), plot3(a1,data.nodes(fi,1),data.nodes(fi,2),data.nodes(fi,3),'go','MarkerSize',8,'MarkerFaceColor','g'); end
                if any(xi), plot3(a1,data.nodes(xi,1),data.nodes(xi,2),data.nodes(xi,3),'rs','MarkerSize',10,'MarkerFaceColor','r'); end
            end
            xlabel(a1,'X'); ylabel(a1,'Y'); zlabel(a1,'Z'); title(a1,'Structure 3D'); axis(a1,'equal'); view(a1,3); hold(a1,'off');
            print(f1,fullfile(output_dir,'grid_structure_3d.png'),'-dpng','-r150');
            view(a1,0,90); title(a1,'Plan View (XY)'); print(f1,fullfile(output_dir,'grid_structure_xy.png'),'-dpng','-r150');
            close(f1);
        catch, fprintf('Warning: Could not save images.\n'); end
    end

    %% ============ RUN FORM FINDING ============
    function runAnalysis(~,~)
        data=guidata(hFig);
        if isempty(data.nodes)||isempty(data.edges), errordlg('Define nodes and edges!','Error'); return; end
        if isempty(data.member_areas), errordlg('Define member areas!','Error'); return; end
        data.ff_tolerance=str2double(get(hFFTolerance,'String')); data.ff_max_iter=str2double(get(hFFMaxIter,'String'));
        data.working_dir=get(hWorkDir,'String');
        output_dir=fullfile(data.working_dir,['gridshell_formfinding_' datestr(now,'yyyymmdd_HHMMSS')]);
        try mkdir(output_dir); catch, errordlg('Cannot create dir!','Error'); return; end
        updateStatus('Generating CSV files...'); drawnow;
        try generateCSVFiles(data,output_dir); saveVisualizationImages(data,output_dir);
        catch ME, errordlg(['CSV error: ' ME.message],'Error'); return; end
        updateStatus('Running form finding...'); drawnow;
        try
            figs_before=findall(0,'Type','figure');
            RunGridShellFormFinding(output_dir);
            figs_after=findall(0,'Type','figure');
            new_figs=setdiff(figs_after,figs_before); new_figs=new_figs(new_figs~=hFig);
            if ~isempty(new_figs)
                img_dir=fullfile(output_dir,'result_images');
                if ~exist(img_dir,'dir'), mkdir(img_dir); end
                for fi=1:length(new_figs)
                    fn=get(new_figs(fi),'Name'); if isempty(fn), fn=sprintf('result_%d',fi); end
                    sn=regexprep(fn,'[^a-zA-Z0-9_\-]','_');
                    try print(new_figs(fi),fullfile(img_dir,[sn '.png']),'-dpng','-r150'); catch, end
                end
                updateStatus(sprintf('Form finding done! %d result images saved.',length(new_figs)));
            else, updateStatus('Form finding completed!'); end
            msgbox(sprintf('Form finding completed!\nResults in: %s',output_dir),'Success','help');
        catch ME
            updateStatus('Form finding failed!');
            errordlg(['Error: ' ME.message],'Error');
            fprintf('Error: %s\n',ME.message);
            for si=1:length(ME.stack), fprintf('  %s line %d\n',ME.stack(si).name,ME.stack(si).line); end
        end
    end

    %% ============ IMPORT ============
    function importFromCSV(~,~)
        idir=get(hImportDir,'String');
        if isempty(idir)||~exist(idir,'dir'), errordlg('Select valid directory!','Error'); return; end
        updateStatus('Importing...'); saveHistory(); data=guidata(hFig);
        try
            nf=fullfile(idir,'nodal_coordinates.csv'); if ~exist(nf,'file'), error('nodal_coordinates.csv not found!'); end
            nd=readtable(nf); data.nodes=[nd.X,nd.Y,nd.Z]; data.node_types=nd.Fixed_Free;
            ef=fullfile(idir,'edge_connectivity.csv'); if ~exist(ef,'file'), error('edge_connectivity.csv not found!'); end
            ed=readtable(ef); data.edges=[ed.Node1,ed.Node2];
            data.working_dir=idir; set(hWorkDir,'String',idir); data.imported=true;
            data.materials=[]; data.member_materials=[]; data.member_areas=[];
            data.load_patterns=[]; data.panels=[]; data.panel_loads=[];
            % Materials + areas
            mf=fullfile(idir,'member_materials.csv');
            if exist(mf,'file')
                try md=readtable(mf);
                    [uq,~,ic]=unique([md.E,md.fcok,md.ftok,md.kmod],'rows'); colors=lines(size(uq,1));
                    for mi=1:size(uq,1), m.name=sprintf('Material %d',mi); m.E=uq(mi,1); m.fcok=uq(mi,2); m.ftok=uq(mi,3); m.kmod=uq(mi,4); m.color=colors(mi,:);
                        if isempty(data.materials), data.materials=m; else, data.materials(end+1)=m; end; end
                    data.member_materials=ic;
                    if ismember('Area',md.Properties.VariableNames), data.member_areas=md.Area; end
                catch, end
            end
            % Loads
            lf=fullfile(idir,'load_patterns.csv');
            if exist(lf,'file')
                try ld=readtable(lf); colors=lines(height(ld));
                    for li=1:height(ld), lp.name=char(ld.Name(li)); lp.q1=ld.q1(li); lp.q2=ld.q2(li); lp.color=colors(li,:);
                        if isempty(data.load_patterns), data.load_patterns=lp; else, data.load_patterns(end+1)=lp; end; end
                catch, end
            end
            % Panels
            pf=fullfile(idir,'panel_connectivity.csv'); plf=fullfile(idir,'panel_loads.csv');
            if exist(pf,'file')
                try pd=readtable(pf); if height(pd)>0
                    data.panels=cell(height(pd),1);
                    for pi=1:height(pd), data.panels{pi}=str2num(char(pd.Nodes(pi))); end %#ok
                    data.panel_loads=ones(length(data.panels),1);
                    if exist(plf,'file'), pld=readtable(plf);
                        for pi=1:min(height(pld),length(data.panels)), data.panel_loads(pi)=pld.Load_Pattern(pi); end; end
                end; catch, data.panels=[]; data.panel_loads=[]; end
            end
            % FF params
            af=fullfile(idir,'analysis_parameters.csv');
            if exist(af,'file')
                try ap=readtable(af);
                    for pi=1:height(ap), pn=char(ap.Parameter(pi)); pv=ap.Value(pi);
                        switch pn, case 'FF_Tolerance', set(hFFTolerance,'String',num2str(pv)); case 'FF_Max_Iter', set(hFFMaxIter,'String',num2str(pv)); end
                    end; catch, end
            end
            guidata(hFig,data); updateVisualization(); updateDataTables();
            updateStatus(sprintf('Imported: %d nodes, %d edges, %d materials.',size(data.nodes,1),size(data.edges,1),length(data.materials)));
        catch ME, errordlg(['Import failed: ' ME.message],'Error'); updateStatus('Import failed!');
        end
    end

    %% ============ DATA TABLES ============
    function updateDataTables()
        data=guidata(hFig);
        if ~isempty(data.nodes)
            ts=cell(size(data.nodes,1),1); ts(data.node_types==0)={'Free'}; ts(data.node_types==1)={'Fixed'};
            set(hNodesTable,'Data',[num2cell(1:size(data.nodes,1))',num2cell(data.nodes),ts]);
        else, set(hNodesTable,'Data',{}); end
        if ~isempty(data.edges)
            em=cell(size(data.edges,1),1); ea=cell(size(data.edges,1),1);
            for i=1:size(data.edges,1)
                if ~isempty(data.member_materials)&&i<=length(data.member_materials)&&~isempty(data.materials)&&data.member_materials(i)<=length(data.materials)
                    em{i}=data.materials(data.member_materials(i)).name; else, em{i}='N/A'; end
                if ~isempty(data.member_areas)&&i<=length(data.member_areas), ea{i}=data.member_areas(i); else, ea{i}='N/A'; end
            end
            set(hEdgesTable,'Data',[num2cell(1:size(data.edges,1))',num2cell(data.edges),em,ea]);
        else, set(hEdgesTable,'Data',{}); end
        if ~isempty(data.materials)
            md=cell(length(data.materials),7);
            for i=1:length(data.materials), md{i,1}=i; md{i,2}=data.materials(i).name; md{i,3}=data.materials(i).E;
                md{i,4}=data.materials(i).fcok; md{i,5}=data.materials(i).ftok; md{i,6}=data.materials(i).kmod;
                md{i,7}=sprintf('[%.2f %.2f %.2f]',data.materials(i).color); end
            set(hMaterialsTable,'Data',md);
        else, set(hMaterialsTable,'Data',{}); end
        if ~isempty(data.load_patterns)
            ld=cell(length(data.load_patterns),5);
            for i=1:length(data.load_patterns), ld{i,1}=i; ld{i,2}=data.load_patterns(i).name;
                ld{i,3}=data.load_patterns(i).q1; ld{i,4}=data.load_patterns(i).q2;
                ld{i,5}=sprintf('[%.2f %.2f %.2f]',data.load_patterns(i).color); end
            set(hLoadsTable,'Data',ld);
        else, set(hLoadsTable,'Data',{}); end
        if ~isempty(data.panels)
            pd=cell(length(data.panels),3);
            for i=1:length(data.panels), pd{i,1}=i; pd{i,2}=mat2str(data.panels{i});
                if i<=length(data.panel_loads)&&~isempty(data.load_patterns)&&data.panel_loads(i)>0&&data.panel_loads(i)<=length(data.load_patterns)
                    pd{i,3}=data.load_patterns(data.panel_loads(i)).name; else, pd{i,3}='N/A'; end; end
            set(hPanelsTable,'Data',pd);
        else, set(hPanelsTable,'Data',{}); end
        updateAssignmentsTable();
    end
    function updateAssignmentsTable()
        data=guidata(hFig); ad={};
        if ~isempty(data.member_materials)
            for i=1:min(length(data.member_materials),size(data.edges,1))
                mi=data.member_materials(i); if ~isempty(data.materials)&&mi<=length(data.materials)
                    ad{end+1,1}='Material'; ad{end,2}=i; ad{end,3}=data.materials(mi).name; end; end; end
        if ~isempty(data.member_areas)
            for i=1:length(data.member_areas), ad{end+1,1}='Area'; ad{end,2}=i; ad{end,3}=sprintf('%.4f m²',data.member_areas(i)); end; end
        if ~isempty(data.panel_loads)
            for i=1:length(data.panel_loads), li=data.panel_loads(i);
                if ~isempty(data.load_patterns)&&li<=length(data.load_patterns)
                    ad{end+1,1}='Load'; ad{end,2}=i; ad{end,3}=data.load_patterns(li).name; end; end; end
        set(hAssignmentsTable,'Data',ad);
    end

    %% ============ TABLE EDIT CALLBACKS ============
    function editNodeData(~,ev), saveHistory(); data=guidata(hFig); r=ev.Indices(1); c=ev.Indices(2); v=ev.NewData;
        if c==2, data.nodes(r,1)=v; elseif c==3, data.nodes(r,2)=v; elseif c==4, data.nodes(r,3)=v;
        elseif c==5, data.node_types(r)=double(strcmpi(v,'fixed')); end
        guidata(hFig,data); updateVisualization(); end
    function editEdgeData(~,ev), saveHistory(); data=guidata(hFig); r=ev.Indices(1); c=ev.Indices(2); v=ev.NewData;
        if c==2||c==3
            if v<1||v>size(data.nodes,1), errordlg('Invalid node','Error'); updateDataTables(); return; end
            if c==2, data.edges(r,1)=v; else, data.edges(r,2)=v; end
        elseif c==4
            mi=find(strcmp({data.materials.name},v),1);
            if isempty(mi), errordlg('Material not found','Error'); updateDataTables(); return; end
            if isempty(data.member_materials), data.member_materials=ones(size(data.edges,1),1); end
            data.member_materials(r)=mi;
        elseif c==5
            if isempty(data.member_areas), data.member_areas=0.005*ones(size(data.edges,1),1); end
            data.member_areas(r)=v;
        end
        guidata(hFig,data); updateVisualization(); updateDataTables(); end
    function editMaterialData(~,ev), saveHistory(); data=guidata(hFig); r=ev.Indices(1); c=ev.Indices(2); v=ev.NewData;
        if c==2, data.materials(r).name=v; elseif c==3, data.materials(r).E=v; elseif c==4, data.materials(r).fcok=v;
        elseif c==5, data.materials(r).ftok=v; elseif c==6, data.materials(r).kmod=v; end
        guidata(hFig,data); updateDataTables(); end
    function editLoadData(~,ev), saveHistory(); data=guidata(hFig); r=ev.Indices(1); c=ev.Indices(2); v=ev.NewData;
        if c==2, data.load_patterns(r).name=v; elseif c==3, data.load_patterns(r).q1=v; elseif c==4, data.load_patterns(r).q2=v; end
        guidata(hFig,data); updateDataTables(); end
    function editPanelData(~,ev), saveHistory(); data=guidata(hFig); r=ev.Indices(1); c=ev.Indices(2); v=ev.NewData;
        if c==2, try ns=str2num(v); if isempty(ns)||any(ns<1)||any(ns>size(data.nodes,1)), error('x'); end; data.panels{r}=ns; catch, errordlg('Invalid','Error'); updateDataTables(); return; end %#ok
        elseif c==3, li=find(strcmp({data.load_patterns.name},v),1); if isempty(li), errordlg('Not found','Error'); updateDataTables(); return; end; data.panel_loads(r)=li; end
        guidata(hFig,data); updateVisualization(); updateDataTables(); end
    function tableSelectionCallback(src,ev,~), if ~isempty(ev.Indices), set(src,'UserData',ev.Indices(1,1)); end; end

    function addTableRow(~,~)
        saveHistory(); data=guidata(hFig); tt=get(get(tabGroup,'SelectedTab'),'Title');
        switch tt
            case 'Nodes', data.nodes=[data.nodes;0 0 0]; data.node_types=[data.node_types;0];
            case 'Edges', if size(data.nodes,1)<2, return; end; data.edges=[data.edges;1 2];
                if ~isempty(data.member_materials), data.member_materials=[data.member_materials;1]; end
                data.member_areas=[data.member_areas;0.005];
            case 'Materials', m.name='New'; m.E=1e6; m.fcok=1e4; m.ftok=5e3; m.kmod=0.8; m.color=[rand rand rand];
                if isempty(data.materials), data.materials=m; else, data.materials(end+1)=m; end
            case 'Loads', lp.name='New'; lp.q1=1; lp.q2=0.5; lp.color=[rand rand rand];
                if isempty(data.load_patterns), data.load_patterns=lp; else, data.load_patterns(end+1)=lp; end
            case 'Panels', if size(data.nodes,1)<3, return; end; data.panels{end+1}=[1 2 3]; data.panel_loads(end+1)=1;
        end
        guidata(hFig,data); updateVisualization(); updateDataTables();
    end
    function deleteTableRow(~,~)
        saveHistory(); data=guidata(hFig); tt=get(get(tabGroup,'SelectedTab'),'Title');
        switch tt
            case 'Nodes', sr=get(hNodesTable,'UserData'); if isempty(sr)||sr>size(data.nodes,1), return; end
                data.nodes(sr,:)=[]; data.node_types(sr)=[];
                er=any(data.edges==sr,2); data.edges(er,:)=[];
                if ~isempty(data.member_materials), data.member_materials(er)=[]; end
                if ~isempty(data.member_areas), data.member_areas(er)=[]; end
                data.edges(data.edges>sr)=data.edges(data.edges>sr)-1;
                if ~isempty(data.panels), rm=[];
                    for pi=1:length(data.panels), if any(data.panels{pi}==sr), rm=[rm,pi];
                        else, data.panels{pi}(data.panels{pi}>sr)=data.panels{pi}(data.panels{pi}>sr)-1; end; end
                    if ~isempty(rm), data.panels(rm)=[]; data.panel_loads(rm)=[]; end; end
            case 'Edges', sr=get(hEdgesTable,'UserData'); if isempty(sr)||sr>size(data.edges,1), return; end
                data.edges(sr,:)=[];
                if ~isempty(data.member_materials)&&sr<=length(data.member_materials), data.member_materials(sr)=[]; end
                if ~isempty(data.member_areas)&&sr<=length(data.member_areas), data.member_areas(sr)=[]; end
            case 'Materials', sr=get(hMaterialsTable,'UserData'); if isempty(sr)||sr>length(data.materials), return; end
                data.materials(sr)=[];
                if ~isempty(data.member_materials)
                    if isempty(data.materials), data.member_materials=[];
                    else, data.member_materials(data.member_materials>sr)=data.member_materials(data.member_materials>sr)-1;
                        data.member_materials(data.member_materials==sr)=min(sr,length(data.materials)); end; end
            case 'Loads', sr=get(hLoadsTable,'UserData'); if isempty(sr)||sr>length(data.load_patterns), return; end
                data.load_patterns(sr)=[];
                if ~isempty(data.panel_loads)
                    if isempty(data.load_patterns), data.panel_loads=[];
                    else, data.panel_loads(data.panel_loads>sr)=data.panel_loads(data.panel_loads>sr)-1;
                        data.panel_loads(data.panel_loads==sr)=min(sr,length(data.load_patterns)); end; end
            case 'Panels', sr=get(hPanelsTable,'UserData'); if isempty(sr)||sr>length(data.panels), return; end
                data.panels(sr)=[]; if ~isempty(data.panel_loads), data.panel_loads(sr)=[]; end
        end
        guidata(hFig,data); updateVisualization(); updateDataTables();
    end

    %% ============ VISUALIZATION ============
    function updateVisualization(~,~)
        data=guidata(hFig); [ca,ce]=view(hAxes); wh=ishold(hAxes);
        cla(hAxes); hold(hAxes,'on'); grid(hAxes,'on');
        if isfield(data,'grid_points')&&~isempty(data.grid_points)
            plot3(hAxes,data.grid_points(:,1),data.grid_points(:,2),data.grid_points(:,3),'.','MarkerSize',15,'Color',[0.2 0.2 0.2]); end
        if ~isempty(data.edges)&&~isempty(data.nodes)
            dc=[0.3 0.5 0.8];
            for i=1:size(data.edges,1), n1=data.edges(i,1); n2=data.edges(i,2);
                if n1<=size(data.nodes,1)&&n2<=size(data.nodes,1)
                    ec=dc; lw=1.5;
                    if ~isempty(data.member_materials)&&i<=length(data.member_materials)&&~isempty(data.materials)
                        mi=data.member_materials(i); if mi<=length(data.materials), ec=data.materials(mi).color; lw=2; end; end
                    plot3(hAxes,[data.nodes(n1,1),data.nodes(n2,1)],[data.nodes(n1,2),data.nodes(n2,2)],[data.nodes(n1,3),data.nodes(n2,3)],'-','LineWidth',lw,'Color',ec);
                end; end; end
        if ~isempty(data.nodes)
            fi=data.node_types==0; xi=data.node_types==1;
            if any(fi), plot3(hAxes,data.nodes(fi,1),data.nodes(fi,2),data.nodes(fi,3),'o','MarkerSize',8,'MarkerFaceColor',[0.3 0.85 0.3],'MarkerEdgeColor',[0.1 0.5 0.1]); end
            if any(xi), plot3(hAxes,data.nodes(xi,1),data.nodes(xi,2),data.nodes(xi,3),'s','MarkerSize',10,'MarkerFaceColor',[0.95 0.2 0.2],'MarkerEdgeColor',[0.6 0.1 0.1]); end
            if size(data.nodes,1)<=60
                for i=1:size(data.nodes,1), text(hAxes,data.nodes(i,1),data.nodes(i,2),data.nodes(i,3),sprintf(' %d',i),'FontSize',7,'Color',[0.3 0.3 0.3]); end; end; end
        lh=[]; ln={};
        if isfield(data,'grid_points')&&~isempty(data.grid_points), lh(end+1)=plot3(hAxes,NaN,NaN,NaN,'.','Color',[.75 .75 .75],'MarkerSize',10); ln{end+1}='Grid Points'; end
        if ~isempty(data.nodes)
            if any(data.node_types==0), lh(end+1)=plot3(hAxes,NaN,NaN,NaN,'o','MarkerSize',8,'MarkerFaceColor',[0.3 0.85 0.3],'MarkerEdgeColor',[0.1 0.5 0.1]); ln{end+1}='Free Nodes'; end
            if any(data.node_types==1), lh(end+1)=plot3(hAxes,NaN,NaN,NaN,'s','MarkerSize',10,'MarkerFaceColor',[0.95 0.2 0.2],'MarkerEdgeColor',[0.6 0.1 0.1]); ln{end+1}='Fixed Nodes'; end; end
        if ~isempty(data.materials), for mi=1:length(data.materials), lh(end+1)=plot3(hAxes,NaN,NaN,NaN,'-','LineWidth',2,'Color',data.materials(mi).color); ln{end+1}=data.materials(mi).name; end
        elseif ~isempty(data.edges), lh(end+1)=plot3(hAxes,NaN,NaN,NaN,'-','LineWidth',1.5,'Color',[0.3 0.5 0.8]); ln{end+1}='Edges'; end
        if ~isempty(lh), legend(hAxes,lh,ln,'Location','best','FontSize',7); end
        xlabel(hAxes,'X (m)'); ylabel(hAxes,'Y (m)'); zlabel(hAxes,'Z (m)');
        axis(hAxes,'equal'); view(hAxes,ca,ce); if ~wh, hold(hAxes,'off'); end; drawnow;
    end
    function updateStatus(msg), set(hStatus,'String',msg); drawnow; end

end % ============ END MAIN FUNCTION ============

%% ============ LOCAL FUNCTIONS ============
function generateCSVFiles(data, output_dir)
    ne=size(data.edges,1); nn=size(data.nodes,1);
    writetable(table((1:nn)',data.nodes(:,1),data.nodes(:,2),data.nodes(:,3),data.node_types,...
        'VariableNames',{'Node_ID','X','Y','Z','Fixed_Free'}), fullfile(output_dir,'nodal_coordinates.csv'));
    fd=[]; fr=[];
    for i=1:length(data.node_types)
        if data.node_types(i)==1, fd=[fd,3*i-2,3*i-1,3*i]; else, fr=[fr,3*i-2,3*i-1,3*i]; end; end
    writetable(table(fd','VariableNames',{'DOF'}), fullfile(output_dir,'fixed_dofs.csv'));
    writetable(table(fr','VariableNames',{'DOF'}), fullfile(output_dir,'free_dofs.csv'));
    writetable(table((1:ne)',data.edges(:,1),data.edges(:,2),'VariableNames',{'Edge_ID','Node1','Node2'}), fullfile(output_dir,'edge_connectivity.csv'));
    fe=[]; fre=[];
    for i=1:ne
        if data.node_types(data.edges(i,1))==1&&data.node_types(data.edges(i,2))==1, fe=[fe;data.edges(i,:)];
        else, fre=[fre;data.edges(i,:)]; end; end
    if isempty(fe), fe=zeros(0,2); end; if isempty(fre), fre=zeros(0,2); end
    writetable(table(fe(:,1),fe(:,2),'VariableNames',{'Node1','Node2'}), fullfile(output_dir,'fixed_edges.csv'));
    writetable(table(fre(:,1),fre(:,2),'VariableNames',{'Node1','Node2'}), fullfile(output_dir,'free_edges.csv'));
    % Member materials + areas
    Ev=zeros(ne,1); fc=zeros(ne,1); ft=zeros(ne,1); km=zeros(ne,1); av=0.005*ones(ne,1);
    if ~isempty(data.materials)&&~isempty(data.member_materials)
        for i=1:ne, if i<=length(data.member_materials), mi=data.member_materials(i);
            if mi<=length(data.materials), Ev(i)=data.materials(mi).E; fc(i)=data.materials(mi).fcok; ft(i)=data.materials(mi).ftok; km(i)=data.materials(mi).kmod; end; end; end
    else, Ev(:)=11e6; fc(:)=24000; ft(:)=14000; km(:)=0.9; end
    if ~isempty(data.member_areas)
        for i=1:min(ne,length(data.member_areas)), av(i)=data.member_areas(i); end; end
    writetable(table((1:ne)',Ev,fc,ft,km,av,'VariableNames',{'Member_ID','E','fcok','ftok','kmod','Area'}), fullfile(output_dir,'member_materials.csv'));
    % Loads
    if ~isempty(data.load_patterns)
        writetable(table((1:length(data.load_patterns))',{data.load_patterns.name}',[data.load_patterns.q1]',[data.load_patterns.q2]',...
            'VariableNames',{'Load_ID','Name','q1','q2'}), fullfile(output_dir,'load_patterns.csv'));
    else, writetable(table(1,{'Default'},3,2,'VariableNames',{'Load_ID','Name','q1','q2'}), fullfile(output_dir,'load_patterns.csv')); end
    % Panels
    if ~isempty(data.panels)
        pt=table(); plt=table();
        for i=1:length(data.panels), pt.Panel_ID(i)=i; pt.Nodes{i}=mat2str(data.panels{i});
            plt.Panel_ID(i)=i; if i<=length(data.panel_loads), plt.Load_Pattern(i)=data.panel_loads(i); else, plt.Load_Pattern(i)=1; end; end
        writetable(pt,fullfile(output_dir,'panel_connectivity.csv')); writetable(plt,fullfile(output_dir,'panel_loads.csv'));
    else
        writetable(table([],{},'VariableNames',{'Panel_ID','Nodes'}), fullfile(output_dir,'panel_connectivity.csv'));
        writetable(table([],[],'VariableNames',{'Panel_ID','Load_Pattern'}), fullfile(output_dir,'panel_loads.csv'));
    end
    % FF Parameters only
    pt=table(); pt.Parameter={'FF_Tolerance';'FF_Max_Iter'}; pt.Value=[data.ff_tolerance;data.ff_max_iter];
    writetable(pt, fullfile(output_dir,'analysis_parameters.csv'));
end

function updateProgress(~,ax,text_h,progress,message)
    cla(ax); patch(ax,[0 progress progress 0],[0 0 1 1],[0 0.5 1]);
    set(ax,'XLim',[0 1],'YLim',[0 1],'XTick',[],'YTick',[]); title(ax,'Progress');
    set(text_h,'String',message); drawnow;
end

function createPlaceholderFunctions()
    if ~exist('FF','dir'), mkdir('FF'); end
    if ~exist('FF/GetL.m','file'), fid=fopen('FF/GetL.m','w'); fprintf(fid,'function L=GetL(NODE,BARS)\n  Nb=size(BARS,1); L=zeros(Nb,1);\n  for i=1:Nb, L(i)=norm(NODE(BARS(i,2),:)-NODE(BARS(i,1),:)); end\nend\n'); fclose(fid); end
    if ~exist('FF/GetPotential.m','file'), fid=fopen('FF/GetPotential.m','w'); fprintf(fid,'function PE=GetPotential(NODE,BARS,Uf,F,K,FREE,L0)\n  U=zeros(3*size(NODE,1),1); U(FREE)=Uf;\n  PE=0.5*U''*diag(K)*U-U''*F;\nend\n'); fclose(fid); end
    if ~exist('FF/GetNeps.m','file'), fid=fopen('FF/GetNeps.m','w'); fprintf(fid,'function NS=GetNeps(NODE,BARS,L0,Nb)\n  NS=[];\nend\n'); fclose(fid); end
end
