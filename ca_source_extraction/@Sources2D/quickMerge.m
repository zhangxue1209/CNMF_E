function  [merged_ROIs, newIDs] = quickMerge(obj, X)
%% merge neurons based on simple spatial and temporal correlation 
% input: 
%   X:     character, {'C', 'S', 'A'}, it compupte 
%   correlation based on either calcium traces ('C') or spike counts ('S') or spatial shapes .
% output: 
%   merged_ROIs: cell arrarys, each element contains indices of merged
%   components 
%   newIDs: vector, each element is the new index of the merged neurons 

%% Author: Pengcheng Zhou, Carnegie Mellon University. 
%  The basic idea is proposed by Eftychios A. Pnevmatikakis: high temporal
%  correlation + spatial overlap
%  reference: Pnevmatikakis et.al.(2016). Simultaneous Denoising, Deconvolution, and Demixing of Calcium Imaging Data. Neuron

%% variables & parameters
A = obj.A;          % spatial components 
C = obj.C;          % temporal components 
options = obj.options;      % options for merging 
merge_thr = options.merge_thr;      % merging threshold 
[K, ~] = size(C);   % number of neurons 

%% find neuron pairs to merge
% compute spatial correlation
temp = bsxfun(@times, A, 1./sum(A.^2,1)); 
A_overlap = temp'*temp; 

% compute temporal correlation
if ~exist('X', 'var')|| isempty(X)
    X = 'C'; 
end

if strcmpi(X, 'S')
    S = obj.S; 
    if isempty(S) || (size(S, 1)~=size(obj.C, 1))
        S = diff(obj.C, 1, 2); 
        S(bsxfun(@lt, S, 2*get_noise_fft(S))) = 0; 
    end
    C_corr = corr(S') - eye(K); 
elseif strcmpi(X, 'A')
    C_corr = A_overlap;   % use correlation of the spatial components 
else
    strcmpi(X, 'C')
    C_corr = corr(C')-eye(K);
end

%% using merging criterion to detect paired neurons
flag_merge = and((C_corr>=merge_thr), A_overlap>0);

[l,c] = graph_connected_comp(sparse(flag_merge));     % extract connected components

MC = bsxfun(@eq, reshape(l, [],1), 1:c);
MC(:, sum(MC,1)==1) = [];
if isempty(MC)
    fprintf('All pairs of neurons are below the merging criterion!\n\n');
    merged_ROIs = []; 
    return;
else
    fprintf('%d neurons will be merged into %d new neurons\n\n', sum(MC(:)), size(MC,2));
end

%% start merging
[nr, n2merge] = size(MC);
ind_del = false(nr, 1 );    % indicator of deleting corresponding neurons
merged_ROIs = cell(n2merge,1); 
newIDs = zeros(nr, 1); 
for m=1:n2merge
    IDs = find(MC(:, m));   % IDs of neurons within this cluster
    merged_ROIs{m} = IDs; 
    
    % determine searching area
    active_pixel = (sum(A(:,IDs), 2)>0);  
    
    % update spatial/temporal components of the merged neuron
    data = A(active_pixel, IDs)*C(IDs, :); 
    ci = C(IDs(1), :); 
    for miter=1:10
        ai = data*ci'/(ci*ci'); 
        ci = ai'*data/(ai'*ai); 
    end 
    % normalize ai to make its maximum to be 1
    max_ai = max(ai, [], 1);           
    A(active_pixel, IDs(1)) = ai/max_ai;
    C(IDs(1), :) = ci*max_ai; 
    newIDs(IDs(1)) = IDs(1); 
    % remove merged elements
    ind_del(IDs(2:end)) = true;
end
newIDs(newIDs==0) = []; 

% remove merged neurons and update obj
A(:, ind_del) = [];
C(ind_del, :) = [];
obj.A = A; 
obj.C = C; 
