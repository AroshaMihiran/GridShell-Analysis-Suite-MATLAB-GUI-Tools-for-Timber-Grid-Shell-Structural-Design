function [NS_Zdof] = GetNepsZdof(NODE, BARS, L0, Nb)
    % Calculate current lengths
    L = GetL(NODE, BARS);
    
    % Calculate strain
    epsilon = (L - L0) ./ L0;
    
    % Initialize array for z-DOFs
    NS_Zdof = [];
    
    % Loop through all bars
    for i = 1:Nb
        if epsilon(i) < 0  % If compressed
            % Get the two nodes of this bar
            node1 = BARS(i, 1);
            node2 = BARS(i, 2);
            
            % Calculate z-DOF for each node (3*node for sequential DOF numbering)
            zdof1 = 3 * node1;
            zdof2 = 3 * node2;
            
            % Add to array
            NS_Zdof = [NS_Zdof, zdof1, zdof2];
        end
    end
    
    % Remove duplicates (if same node appears in multiple compressed bars)
    NS_Zdof = unique(NS_Zdof);
    
    % Return empty array instead of NaN if no compression found
    if isempty(NS_Zdof)
        NS_Zdof = [];
    end
end