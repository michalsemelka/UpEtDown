classdef StateSpace < handle
%STATESPACE - add state-space to the model, used to
%generate visitors paths.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (SetAccess = private)
        l;              % Lifts object
        liftsSpeed;
        floors;         % Num of floors in building
        list;           % List of Lifts, floors and IDs
        G;              % Matrix representing SS of model
        nodes;          % Rated nodes
        predecessors;
        paths;          
    end
    
    methods (Access = {?Simulation})
        
        function [this] = StateSpace(l,numOfFloors)
            
            this.l = l;
            this.liftsSpeed = this.rateLiftsSpeed();
            this.floors = numOfFloors;
            
            this.list = struct('ID',{},'Lift', {}, 'Floor', {});
            [this.G, this.list] = this.createGMatrix;
            
            [this.nodes, this.predecessors] = this.dijkstra;
            
            this.paths = struct('Path', 0);
            this.paths = this.findAllPaths;
            
        end
        
        function path = getPath(this,floor)
            % return path for defined floor
            path = this.paths(floor).Path;
        end
        
        function viewAsBioGraph(this)
            % represent G matrix as graph, Bioformatics toolbox required
            bg = biograph(this.G);
            view(bg);
        end
        
        function [path, cost] = findPath(this,floor)
            % Search nodes and predecessors and return the path for the selected floor
            
            route = floor;
            actStep = floor;
            finished = false;
            predecessorsRes = this.predecessors;
            nodesRes = this.nodes;
            
            [ind, ~] = find(nodesRes(:,1) == actStep);
            cost = nodesRes(ind,2);
            
            while(~finished)
                [ind, ~] = find(predecessorsRes(:,1) == actStep);
                if (predecessorsRes(ind,2) == 0)
                    path = fliplr(route);
                    finished = true;
                    break;
                end
                route(end+1) = predecessorsRes(ind,2);
                actStep = predecessorsRes(ind,2);
            end
        end
        
        function [paths] = findAllPaths(this)
            numOfFloors = this.floors;
            paths = this.paths;
            for i=1:numOfFloors
                pathRes = this.findPath(i);
                pathStruct = this.makeItinerary(pathRes);
                paths(i) = struct('Path',pathStruct);
            end
        end
        
        function pathRes = makeItinerary(this,path)
            % Return structure of itinerary based on path
            
            numOfFloors = this.floors;
            
            allFloors = 1:numOfFloors;
            floorsRes = find(ismember(path,allFloors)==1);
            
            pathRes = struct('Floor',[],'Lift',[],'FinalFloor', []);
            listRes = this.list;
            
            for i=1:size(floorsRes,2)
                firstFloor = path(floorsRes(i));
                
                if (i == size(floorsRes,2))
                    lastFloor = path(floorsRes(i));
                    FinalFloor = 0;
                    Lift = 0;
                else
                    Lift = listRes(path(floorsRes(i)+1)-numOfFloors).Lift;
                    FinalFloor = path(floorsRes(i+1));
                end
                
                pathRes(i) = struct('Floor',firstFloor,'Lift',Lift,'FinalFloor', FinalFloor);
            end
        end
        
        function cost = rateLiftsSpeed(this)
            % return cost of each lift in building (fastest 2, second 3,
            % ...)
            
            lifts = this.l;
            speeds = [];
            for i=1:size(lifts,2)
                speeds(i) = lifts(i).speed;
            end
            [uniqueSpeeds, ~] = unique(speeds);
            uniqueSpeeds = sort(uniqueSpeeds,'descend');
            
            for k=1:size(uniqueSpeeds,2)
                ind = find(speeds == uniqueSpeeds(k));
                speeds(ind) = k+1;
            end
            cost = speeds;
        end
        
        function speed = getLiftSpeed(this, lift)
            speed = this.liftsSpeed(lift);
        end
        
        function [Gres, listRes] = createGMatrix(this,listFloors)
            % create G (Gres) matrix that represents state-stace of model and
            % return list (listRes) with number of states for each lift and floor
            % listFloors = additional info about current situation in
            % model, used for scheduler
            
            numOfFloors = this.floors;
            numOfLifts = size(this.l,2);
            ID = numOfFloors;
            listRes = this.list;
            
            if (isempty(listRes))
                for i=1:numOfLifts
                    max = this.l(i).getFinalFloor;
                    min = this.l(i).getBaseFloor;
                    liftID = this.l(i).getID;
                    
                    for k=min:max
                        ID = ID + 1;
                        listRes(end+1) = struct('ID',ID,'Lift', liftID, 'Floor',k);
                    end
                end
            end
            
            numOfStates = size(listRes,2);
            
            Gres = zeros(numOfStates+numOfFloors,numOfStates+numOfFloors);
            
            % we want exclude connections between states and floors, that
            % are denied
            listResWithoutDenied = listRes;
            for k=1:size(this.l,2)
                deniedFloors = this.l(k).getDeniedFloors;
                if (deniedFloors ~= 0)
                    ind = find([listResWithoutDenied.Lift] == k);
                    floors = [listResWithoutDenied(ind).Floor];
                    delInd = find(ismember(floors,deniedFloors) == 1);
                    delInd = ind(1)+delInd-1;
                    listResWithoutDenied(delInd)=[];
                end
            end
            
            for i=1:numOfFloors
                ind = find([listResWithoutDenied.Floor] == i);
                if (~isempty(ind))
                    ind = [listResWithoutDenied(ind).ID];
                    Gres(i, ind) = 1;
                    Gres(ind, i) = 1;
                end
            end
            
            Gs = zeros(numOfStates,numOfStates);
            
            for i=1:numOfStates
                floor = listRes(i).Floor;
                
                floorPlus = floor + 1;
                floorMinus = floor -1;
                
                if (floorPlus <= numOfStates || floorMinus > 0)
                    ind = find([listRes.Lift] == listRes(i).Lift);
                    indP = find([listRes(ind).Floor] == floorPlus);
                    indM = find([listRes(ind).Floor] == floorMinus);
                    
                    if (~isempty(indP))
                        
                        %plus = this.getLiftSpeed(listRes(i).Lift);
                        %plus = ceil(rand*20);
                        
                        plus = 2;
                        
                        if ( nargin() == 2 && ~(size(listFloors,1) == 1 && listFloors == 1) )
                            % for Scheduler
                            plus = listFloors(listRes(i).Lift);
                        end
                        
                        Gs(i, ind(indP)) = plus;
                    end
                    
                    if (~isempty(indM))
                        
                        %plus = this.getLiftSpeed(listRes(i).Lift);
                        %plus = ceil(rand*20);
                        
                        plus = 2;
                        
                        if ( nargin() == 2 && ~(size(listFloors,1) == 1 && listFloors ==1) )
                            % for Scheduler
                            plus = listFloors(listRes(i).Lift);
                        end
                        Gs(i, ind(indM)) = plus;
                    end
                end                
            end
            Gres(numOfFloors+1:end,numOfFloors+1:end)=Gs;
        end
        
        function [nodes, predecessors] = dijkstra(this, START)
            % Implementation of Dijkstra algorithm
            % START = default node
            
            if (nargin() == 1)
                START = 1;
            end
            
            numOfFloors = this.floors;
            numOfStates = size(this.list,2);
            Gm = this.G;
            
            Q = [(1:1:numOfFloors+numOfStates)' zeros(1,numOfFloors+numOfStates)'];
            Q(:,2)=Inf;
            
            START_IND = START;
            Q(START_IND,2) = 0;
            
            closed = [];
            predecessors = double.empty;
            for k=1:numOfFloors+numOfStates
                predecessors(k,1) = k;
                predecessors(k,2) = 0;
            end
            node = [];
            while (~isempty(Q))
                
                % select node with minimum d
                [not, ind] = min(Q(:,2));
                node = Q(ind,1);
                closed(end+1,1) = node;
                closed(end,2) = Q(ind,2);
                Q(ind,:) = [];
                
                descendants = findDescendants(Gm,node);
                for i=1:size(descendants,2)
                    if (isempty(find(closed(:,1) == descendants(i))))
                        ind = find(Q(:,1) == descendants(i));
                        indNode = find(closed(:,1) == node);
                        if (closed(indNode,2) + Gm(node,descendants(i)) < Q(ind,2))
                            Q(ind,2) = closed(indNode,2) + Gm(node,descendants(i));
                            predecessors(descendants(i),2) = node;
                        end
                    end
                end
                
            end
            
            nodes = closed;
            
            function ind=findDescendants(Gm,node)
                ind = find(Gm(node,:) > 0);
            end
        end
        
        function path = findOnePath(this, list, startfloor, desiredFloor)
            % return itinerary for Scheduler behavior
            
            [this.G, ~] = this.createGMatrix(list);
            
            [this.nodes, this.predecessors] = this.dijkstra(startfloor);
            
            pathSeq = this.findPath(desiredFloor);
            
            path = this.makeItinerary(pathSeq);
            
        end
        
        function path = findRandomPath(this, startFloor, desiredFloor, lifts, AvaLifts)
            % return itinerary for Random behavior
            
            listRes = this.list;
            
            % Priority to available lifts
            if (size(AvaLifts,2) > 0)
                lifts = AvaLifts;
            end
            
            ind = ceil(rand * size(lifts,2));
            lift = lifts(ind);
            ind = find([listRes.Lift] ~= lift);
            listRes(ind) = [];
            ind = find([listRes.Floor] == startFloor);
            node = listRes(ind).ID;
            
            [this.G, ~] = this.createGMatrix();
            this.G(node,startFloor) = 0;
            this.G(startFloor,node) = 0;
            
            [this.nodes, this.predecessors] = this.dijkstra(node);
            
            pathSeq = this.findPath(desiredFloor);
            
            pathSeq = [startFloor pathSeq];
            
            if (size(pathSeq,2) == 2)
                % hack if path is too short, create new
                this.G(node,startFloor) = 1;
                this.G(startFloor,node) = 1;
                
                [this.nodes, this.predecessors] = this.dijkstra(node);
                
                pathSeq = this.findPath(desiredFloor);
                
                pathSeq = [startFloor pathSeq];
                if (pathSeq(1) == pathSeq(3))
                    pathSeq(1:2) = [];
                end
            end
            
            path = this.makeItinerary(pathSeq);   
        end
    end
end

