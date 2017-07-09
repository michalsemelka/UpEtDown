classdef Simulation < handle
%SIMULATION - creates all objects for model.
% |___ b     -> Instance of Building.m
%   |___ l   -> Instance of Lift.m
% |___ h     -> Instance of Human.m
% |___ ss    -> Instance of StateSpace.m
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (Access = {?View, ?Controller, ?GUI})
        b;                      % Instance of Building.m
        h;                      % Instance of Human.m
        
        humansList;             % used defined list of visitors            
        humansListForGraph;
        
        % these lists are used to determine which Human must be
        % simulated in current/next step, waitingList is for Humans waiting for
        % lift and floorList for newly created Humans or
        % Humans who have just left the lift
        % 1st column Floor ID, 2nd column cell array of Humans IDs
        waitingList;
        floorList;
        
        systemBehavior;
        
        ss;                     % Instance of StateSpace.m
        
        timeStamp;              % Counting of iterations
        
        e_liftOnFloor;          % Handle for event when lift arrives on floor
        
        showDebugInfo;          % Option to show debug info in console
    end
    
    properties (SetObservable)
        humansLeft;             % Number of Humans to simulate
    end
    
    events
        humanFinished;          % Event when Human are in final floor
        finished;               % Event when simulation is finished
    end
    
    methods
        function [this] = Simulation(numOfFloors,numOfShaft,lifts,humanListPath,simOptions)
            
            % When creating object only for GUI, not for simulation
            if (nargin == 3)
                this.humansList = -42;
                simOptions = struct('systemBehaviorOption',1,'showDebugInfo', false, 'IdleLiftsToBase', 0);
            else
                list = dlmread(humanListPath);
                [this.humansList, ~, ~] = Simulation.deleteWrongHumans(list, numOfFloors);
                this.humansListForGraph = this.humansList;
            end
            
            % Create instances of Lifts from Lift cell
            liftCons = Lift.empty(0);
            for i=1:1:numOfShaft
                liftCons(i) = Lift(cell2mat(lifts(i,1)),cell2mat(lifts(i,2)),cell2mat(lifts(i,3)),cell2mat(lifts(i,4)),cell2mat(lifts(i,5)), simOptions.IdleLiftsToBase);
            end 
            
            % Create instance of Building
            this.b = Building(numOfFloors, liftCons);
            
            this.waitingList = cell(0);
            this.floorList = cell(0);
            this.h = Human.empty(0);
            
            % Select behavior of system
            switch simOptions.systemBehaviorOption
                case 1
                    this.systemBehavior = States.random;
                case 2
                    this.systemBehavior = States.dijkstra_e;
                otherwise
                    this.systemBehavior = States.random;
            end
            
            this.humansLeft = size(this.humansList,1);
            
            % Create instance of StateSpace
            this.ss = StateSpace(this.b.l,numOfFloors);
            
            % Timestamp value
            % start from minimal value from humanList
            start = min(this.humansList(:,1)); 
            this.timeStamp = start - 1;
            
            % Event for situation, when lift hit the floor
            this.e_liftOnFloor = addlistener(this.b.l,'liftOnFloor',@this.liftOnFloor);
            
            this.showDebugInfo = simOptions.showDebugInfo;
        end
    end
    
    methods (Access = {?View, ?Controller})
        
        %------------------------------------------------------------------
        %   Getters & Setters
        %------------------------------------------------------------------
        function setTimeStamp(this)
            this.timeStamp = this.timeStamp + 1;
        end
        
        function time = getTimeStamp(this)
            time = this.timeStamp;
        end
        
        function time = getShowDebugInfo(this)
            time = this.showDebugInfo;
        end
        
        function state = getSystemBehavior(this)
            state =  this.systemBehavior;
        end
        
        function setHumansLeft(this)
            this.humansLeft = this.humansLeft - 1;
            if (this.humansLeft == 0)
                % no Humas left -> simulation finished
                this.notify('finished');
            end
        end
        
        function num = getHumansLeft(this)
            num = this.humansLeft;
        end
        
        %------------------------------------------------------------------
        %   Functions
        %------------------------------------------------------------------

        %------------------------------------------------------------------
        %   Events
        function liftOnFloor(this, src, evtdata)
            % When the lift arrives on the floor, allows the Humans 
            % to get off the elevator.
            
            liftID = src.getID();
            liftActualFloor = src.getActualFloor();
            
            if (this.getShowDebugInfo)
                fprintf('Event %1s - lift no. %d on floor %d - Iteration %d\n', evtdata.EventName, liftID, liftActualFloor, this.getTimeStamp);
            end
            
            % get Humans in lift
            num = src.getNumOfHumansInLift();
            humans = src.getHumansInLift();
            
            if (num > 0)
                for i=1:num
                    
                    % check if Human should leave lift
                    humanNextFloor = this.h(humans(i)).getNextFloor();

                    if (liftActualFloor == humanNextFloor && liftActualFloor == this.h(humans(i)).getDesiredFloor)
                        % and check if Human is in final floor
                        this.humanLeaveLift(humans(i), src.getID, true);
                        
                    elseif ((liftActualFloor == humanNextFloor))
                        this.humanLeaveLift(humans(i), src.getID, false);
                    end
                end
            end
  
        end
        
        %------------------------------------------------------------------
        %   Lift based   
        function callLiftsOnFloor(this, floor, direction)
            % Simulation of situation, when Human calls
            % all lift on floor.
            % floor = in which floor call was made
            % direction = true when up, false when down
            
            lifts = this.findLiftsOnFloor(floor);
            num = size(lifts,2);
            for i=1:1:num
                this.callOneLift(lifts(i), floor, direction);
            end
            
        end
        
        function callOneLift(this, ID, floor, direction)
            % Simulation of situation, when Human calls
            % the lift on floor.
            % floor = in which floor call was made
            % direction = true when up, false when down
            if (floor ~= this.b.l(ID).getActualFloor || States.moving.eq(this.b.l(ID).getState))
                this.b.l(ID).addToQueue(floor, direction, false);
            end
            
        end
        
        function lifts = findLiftsOnFloor(this, floor)
            % return IDs of lifts for specific floor
            
            lifts = this.b.getLiftsOnFloors{floor,2};
            
        end
        
        function moveLifts(this)
            % move all lifts
            
            num = this.b.getNumOfLifts();
            for i=1:1:num
                liftWasFull = this.b.l(i).isLiftFull;
                [~] = this.b.l(i).move(this.h);
                if (liftWasFull || States.idle.eq(this.b.l(i).getState))
                    % when lift was full or became idle, lets check if
                    % there are some humans still waiting for lift and
                    % renew their calls
                    this.canCallLift(this.b.l(i).getID);
                end
            end
            
        end
        
        function selectLiftsNextFloor(this)
            % after each simulation step, check new calls for lifts
            
            num = this.b.getNumOfLifts();
            for i=1:1:num
                this.b.l(i).selectNextFloor();
            end
            
        end
        
        function list = getAllLiftsActualFloor(this, startFloor, desiredFloor, humanFloor)
            % for Scheduler behavior, evaluate all lifts and return cost
            % for G matrix in StateSpace.m (ss)
            % startFloor = where Human have started his travel
            % desiredFloor = Human final floor
            % humanFloor = actual position of Human
            % list = list for new cost for all lifts in building
            
            if (startFloor < desiredFloor)
                directionHuman = States.up;
            else
                directionHuman = States.down;
            end
            
            num = this.b.getNumOfLifts();
            list = zeros(num,1);
            
            for i = 1:num
                if (humanFloor == this.b.l(i).getActualFloor && ~this.b.l(i).isLiftFull && (States.idle.eq(this.b.l(i).getState) || States.stop.eq(this.b.l(i).getState)) && (directionHuman.eq(this.b.l(i).getDirection) || States.free.eq(this.b.l(i).getDirection)) )
                    list(i) = 2;
                elseif ( (humanFloor > this.b.l(i).getActualFloor || humanFloor < this.b.l(i).getActualFloor) && ~this.b.l(i).isLiftFull && (States.idle.eq(this.b.l(i).getState) || States.stop.eq(this.b.l(i).getState)) && (directionHuman.eq(this.b.l(i).getDirection) || States.free.eq(this.b.l(i).getDirection)) )
                    y = -this.b.l(i).getLiftSpeed + 0.7;
                    d = abs(this.b.l(i).getActualFloor - humanFloor) * 0.1;
                    list(i) = 3 + y + d;                   
                else
                    y = -this.b.l(i).getLiftSpeed + 0.7;
                    d = abs(this.b.l(i).getActualFloor - humanFloor) * 0.1;
                    list(i) = 10 + y + d;
                end
            end
            
        end
        
        %------------------------------------------------------------------
        %   Human based
        function humans = findHumansOnFloorWaiting(this, floor, listType)
            % return Humans IDs for humans waiting for lift on specific floor
            % listType == true => WaitingList, == false => FloorList
            
            if (listType)
                list = this.waitingList;
            else
                list = this.floorList;
            end
            
            if (size(list,1) > 0)
                listFloors = [list{:,1}];
                [row, col]=find(listFloors == floor);
                if ( ~(isempty(row) && isempty(col)) )
                    humans = list{col,2};
                else
                    humans = [];
                end
            else
                humans = [];
            end
            
        end
        
        function lifts = findAvailableLifts(this, floor, allLifts)
            % return IDs of lifts, that are available for enter
            % floor = on which floor
            % allLifts = list of all lifts on specified floor
            % lifts = list of IDs
            
            num = size(allLifts,2);
            availableLiftsIndex = [];
            
            for i=1:num
                if (floor == this.b.l(allLifts(i)).getActualFloor && ~this.b.l(allLifts(i)).isLiftFull &&  ~this.b.l(allLifts(i)).isFloorDenied(floor) && (States.moving.ne(this.b.l(allLifts(i)).getState) && States.dns.ne(this.b.l(allLifts(i)).getState)))
                    availableLiftsIndex = [availableLiftsIndex i];
                end
            end
            
            lifts = allLifts(availableLiftsIndex);
            
        end    
        
        function simulateOneHuman(this, ID)
            % Simulation of selection and call of lift by Human
            % ID = ID of Human
            
            if (this.h(ID).getTimeStart == 0)
                this.h(ID).setTimeStart(this.getTimeStamp);
                
                switch (this.getSystemBehavior)
                    % get initial path for Human
                    case States.random
                        % find all lifts on floor
                        liftsOnFloor = this.findLiftsOnFloor(this.h(ID).getActualFloor);
                        % check if there are some available
                        availableLifts = this.findAvailableLifts(this.h(ID).getActualFloor, liftsOnFloor);
                        % based on this information, create path for random
                        % lift from list
                        path = this.ss.findRandomPath(this.h(ID).getActualFloor, this.h(ID).getDesiredFloor, liftsOnFloor, availableLifts);
                        this.h(ID).setPath(path);
                        this.h(ID).selectActualPath;
                    case States.dijkstra_e
                        path = this.ss.findOnePath(this.getAllLiftsActualFloor(this.h(ID).getStartFloor, this.h(ID).getDesiredFloor, this.h(ID).getActualFloor), this.h(ID).getActualFloor, this.h(ID).getDesiredFloor);
                        this.h(ID).setPath(path);
                        this.h(ID).selectActualPath;
                end
            end
            
            if (this.h(ID).getDesiredFloor == this.h(ID).getStartFloor)
                % In case when the passenger has the same starting and final floor
                this.h(ID).leaveLift(true,0);
                this.removeFromWaitingList(ID, false);
                this.setHumansLeft();
                evtdata = EventDataSender(this.h(ID).getDesiredFloor);
                notify(this,'humanFinished',evtdata);
            else
                this.removeFromWaitingList(ID, false);  % Remove visitor from floorList
                switch (this.getSystemBehavior)
                    % This is not obey DRY concept (Don't repeat yourself),
                    % because both cases are the same.
                    % Divided to demonstrate the implementation of other
                    % possible behaviors.
                    case States.random
                        % Random behavior
                        
                        % Load floors - from actualPlan and current floor
                        planFloor = this.h(ID).actualPath.Floor;
                        actualFloor = this.h(ID).getActualFloor;
                        
                        if (planFloor == actualFloor)
                            % get ID of current Lift in actualPath
                            liftID = this.h(ID).actualPath.Lift;
                            
                            % Destination direction check
                            finalFloor = this.h(ID).actualPath.FinalFloor;
                            direction = false;
                            directionState = States.down;
                            if (finalFloor > this.h(ID).getActualFloor)
                                direction = true;
                                directionState = States.up;
                            end
                            
                            % If the lift is available (state is not moving and direction of travel is same), Human enters
                            if (this.h(ID).getActualFloor == this.b.l(liftID).getActualFloor && ~this.b.l(liftID).isLiftFull && (States.moving.ne(this.b.l(liftID).getState) && States.dns.ne(this.b.l(liftID).getState)) && (directionState.eq(this.b.l(liftID).getDirection) || States.free.eq(this.b.l(liftID).getDirection)) )
                                this.humanEnterLift(this.h(ID).getID, liftID);
                            else
                                % Otherwise, if Human is not waiting yet,
                                % he starts
                                if (States.waiting.ne(this.h(ID).getState))
                                    % and call the lift
                                    this.callOneLift(liftID, actualFloor, direction);
                                    if (States.newWaiting.ne(this.h(ID).getState))
                                        % Add to waitingList and start
                                        % counting waiting time
                                        this.addToWaitingList(ID,this.h(ID).getActualFloor, true);
                                        this.h(ID).setTimeQueue(this.getTimeStamp, true);
                                    end
                                    this.h(ID).setState(States.waiting);
                                end
                            end
                        end
                        
                    case States.dijkstra_e
                        % Scheduler behavior
                        
                        % Load floors - from actualPlan and current floor
                        planFloor = this.h(ID).actualPath.Floor;
                        actualFloor = this.h(ID).getActualFloor;
                        
                        if (planFloor == actualFloor)
                            % get ID of current Lift in actualPath
                            liftID = this.h(ID).actualPath.Lift;
                            
                            % Destination direction check
                            finalFloor = this.h(ID).actualPath.FinalFloor;
                            direction = false;
                            directionState = States.down;
                            if (finalFloor > this.h(ID).getActualFloor)
                                direction = true;
                                directionState = States.up;
                            end
                            
                            % If the lift is available (state is not moving and direction of travel is same), Human enters
                            if (this.h(ID).getActualFloor == this.b.l(liftID).getActualFloor && ~this.b.l(liftID).isLiftFull && (States.moving.ne(this.b.l(liftID).getState) && States.dns.ne(this.b.l(liftID).getState)) && (directionState.eq(this.b.l(liftID).getDirection) || States.free.eq(this.b.l(liftID).getDirection)) )
                                this.humanEnterLift(this.h(ID).getID, liftID);
                            else
                                % Otherwise, if Human is not waiting yet,
                                % he starts
                                if (States.waiting.ne(this.h(ID).getState))
                                    % and call the lift
                                    this.callOneLift(liftID, actualFloor, direction);
                                    if (States.newWaiting.ne(this.h(ID).getState))
                                        % Add to waitingList and start
                                        % counting waiting time
                                        this.addToWaitingList(ID,this.h(ID).getActualFloor, true);
                                        this.h(ID).setTimeQueue(this.getTimeStamp, true);
                                    end
                                    this.h(ID).setState(States.waiting);
                                end
                            end
                        end
                end
            end
      
        end
        
        function  humanEnterLift(this, ID, lift)
            % Simulate Human entering lift
            % ID = Human ID
            % lift = ID of Lift
            
            % remote Human from waitingList
            this.removeFromWaitingList(ID, true);
            
            % set that visitor is in lift for Human and Lift object
            this.h(ID).enterLift(lift, this.getTimeStamp);
            this.b.l(lift).addHumanToLift(ID);
            
            switch (this.getSystemBehavior)
                % get the next floor and set it
                case States.random
                    floor = this.h(ID).actualPath.FinalFloor;
                    this.h(ID).setNextFloor(floor);
                case States.dijkstra_e
                    floor = this.h(ID).actualPath.FinalFloor;
                    this.h(ID).setNextFloor(floor);
            end
            
            % get direction
            direction = false;
            if (floor > this.h(ID).getActualFloor)
                direction = true;
            end
            
            % register new call
            this.b.l(lift).addToQueue(floor, direction, true);
            
            if (this.getShowDebugInfo)
                fprintf('Human no.%d has entered lift n.%d. Travelling to floor: %d \n', ID, lift, floor);
            end
            
        end
        
        function  humanLeaveLift(this, ID, lift, final)
            % Simulate Human leaving lift
            % ID = Human ID
            % lift = ID of Lift
            % final = true if next floor is final floor, false if not
            
            switch (this.getSystemBehavior)
                case States.random
                    % get next part of path
                    this.h(ID).selectActualPath();
                case States.dijkstra_e
                    if (~final)
                        % get the new part of path based on current
                        % situation
                        path = this.ss.findOnePath(this.getAllLiftsActualFloor(this.h(ID).getStartFloor, this.h(ID).getDesiredFloor,this.h(ID).getActualFloor), this.h(ID).getActualFloor, this.h(ID).getDesiredFloor);
                        this.h(ID).setPath(path);
                    end
                    % and select only actual step
                    this.h(ID).selectActualPath();
            end
            
            if (final == true)
                % Final floor for visitor, remove him from lift
                this.h(ID).leaveLift(true,this.getTimeStamp);
                this.b.l(lift).removeHumanFromLift(ID);
                % and stop counting time
                this.h(ID).setTimeStop(this.getTimeStamp);
                % refresh count of  humans left
                this.setHumansLeft();
                evtdata = EventDataSender(this.h(ID).getActualFloor);
                notify(this,'humanFinished',evtdata);
                
                if (this.getShowDebugInfo == true)
                    fprintf('Human no.%d has finished his travel to floor n.%d with lift no.%d, YAY! Num of iterations: %d\n', ID, this.h(ID).getDesiredFloor, lift, this.h(ID).getTimeStop-this.h(ID).getTimeStart);
                end
            else
                % Human is not yet in final floor, remove him from lift
                % only
                this.h(ID).leaveLift(false,this.getTimeStamp);
                this.b.l(lift).removeHumanFromLift(ID);
                
                if (this.getShowDebugInfo == true)
                    fprintf('Human no.%d has left on floor n.%d lift n.%d, not in finish yet! \n', ID, this.h(ID).getActualFloor, lift);
                end
                
                % and add him to floorList
                % state that prevents the simulation in current step
                this.h(ID).setState(States.floorHold);
                this.addToWaitingList(ID,this.h(ID).getActualFloor, false);
            end
            
        end
        
        function canCallLift(this, liftID)
            % For situation when it is appropriate to renew the human call for
            % liftID = ID of called lift
            list = this.waitingList;
            
            num = size(list,1);
            for i=1:num
                humans = list{i,2};
                for k = 1:size(humans,2)
                    if (this.h(humans(k)).actualPath.Lift == liftID)
                        this.h(humans(k)).setState(States.newWaiting);
                    end
                end
            end

        end
        
        function checkFloorPeople(this)
            % Simulate Humans, that are on floor, but did not left lift
            % recently.
            list = this.floorList;
            
            num = size(list,1);
            for i=1:num
                humans = list{i,2};
                
                for k = 1:size(humans,2)
                    if (States.floor.eq(this.h(humans(k)).getState))
                        this.simulateOneHuman(humans(k));
                    else
                        % change status, so human is going to be simulated
                        % in next step
                        this.h(humans(k)).setState(States.floor);
                    end
                end
            end 
        end
        
        function checkHumansWaiting(this)
            % Simulate Humans waiting
            
            this.checkFloorPeople();
            list = this.waitingList;
            
            num = size(list,1);
            for i=1:num
                humans = list{i,2}; 
                for k = 1:size(humans,2)
                    this.simulateOneHuman(humans(k));
                end
            end 
            
        end
        
        function checkForNewHumanBatch(this)
            % check timestamp value in humansList and eventually call 
            % method to create new instances of Human.m
            
            list = this.humansList(:,1);
            if (~isempty(list))
                ind = find(list(:,1) == this.getTimeStamp);
                % find Humans for current timeStamp
                if (~isempty(ind))
                    % method to create new Humans
                    this.runNextHumanBatch(ind);
                end
            end
            
        end
        
        function runNextHumanBatch(this,ind)
            % creation of new Humans
            % ind = vector of indexes of humans for current timeStamp
            
            list = this.humansList;
            
            if (~isempty(ind) && ~isempty(list))
                desiredFloors = list(ind,2); 
                startFloors = list(ind,3);
                
                for i=1:size(desiredFloors,1)                 
                    
                    path = struct('Path', 0);
                    
                    % new instance of Human
                    this.h(end+1) = Human(startFloors(i),desiredFloors(i),path);
                    % and add it to floorList
                    this.addToWaitingList(size(this.h,2),startFloors(i), false);
                    
                end
                % clear list from newly created Humans
                this.humansList(ind,:) = []; 
            end
            
        end
        
        function addToWaitingList(this, ID, floor, listType)
            % add Human to waiting list
            % ID = Human ID
            % floor = floor where Human is waiting
            % listType == true => WaitingList, == false => FloorList
            
            if (listType)
                list = this.waitingList;
            else
                list = this.floorList;
            end

            if (isempty(list))
                list{end+1,1} = floor;
                list{end,2} = ID;
            else
                index = find([list{:,1}] == floor);
                if (isempty(index))
                    list{end+1,1} = floor;
                    list{end,2} = ID;
                else
                    list{index,2} = [list{index,2} ID];
                end
            end
            
            if (listType)
                this.waitingList = list;
            else
                this.floorList = list;
            end
        end
        
        function removeFromWaitingList(this, ID, listType)
            % remove Human from waiting/floor list
            % ID = Human ID
            % listType == true => WaitingList, == false => FloorList
            
            if (listType)
                list = this.waitingList;
            else
                list = this.floorList;
            end
            
            if (~isempty(list))
                humansInList = list(:,2);
                for i=1:size(humansInList,1)
                    tmp = humansInList{i,:};
                    [row, col]=find(tmp == ID);
                    if ( ~(isempty(row) && isempty(col)) )
                        list{i,2} = list{i,2}( list{i,2} ~= [ID]);
                        if (isempty(list{i,2}))
                            list(i,:)=[];
                        end
                        break;
                    end
                end
                
                if (listType)
                    this.waitingList = list;
                else
                    this.floorList = list;
                end
                
            end
            
        end
        
        function error = checkAllFloorsCovered(this)
            % return true when there are some floors with no lifts
            
            floors = this.b.getNumOfFloors;
            liftsOnFloors = this.b.getLiftsOnFloors();
            
            error = false;
            for i=1:floors
                if (isempty(liftsOnFloors{i,2}))
                    error = true;
                end
            end
            
        end
        
        %------------------------------------------------------------------
        %   End of simulation based
        function getFinalStats(this)
            % Get stats about simulation and create report template
            
            num = size(this.h,2);
            sum = [];
            sumWait = [];
            sumNotWait = 0;
            sumTravel = [];
            for i=1:num
                
                % get all the travel time for each visitor
                if (this.h(i).statsTotalTime > 0)
                    sum(end+1) = this.h(i).statsTotalTime;
                end
                
                % get all the waiting time for each visitor
                sumWait = [sumWait this.h(i).statsWaiting];
                
                % get all the in-lift time for each visitor
                if (~isempty(this.h(i).statsTravel))
                    sumTravel = [sumTravel this.h(i).statsTravel];
                end
                
                % and get how many humans didnt wait for lift
                if (this.h(i).statsWaiting == 0)
                    sumNotWait = sumNotWait + 1;
                end
            end

            
            % Get stats for lifts
            totalFloors = 0;
            eachLiftFloors = [];
            for i=1:this.b.getNumOfLifts()
                
                %sum(abs(diff(this.b.l(i).getHistory)))
                history =  this.b.l(i).getHistory;
                temp = 0;
                for k=1:size(history,2) - 1
                    temp = temp + abs(history(k) - history(k+1));
                end
                eachLiftFloors(i) = temp;
                
                totalFloors = totalFloors + eachLiftFloors(i);
            end
            
            % get the most and least busy lift
            [liftMaxFloors, maxInd] = max(eachLiftFloors);
            [liftMinFloors, minInd] = min(eachLiftFloors);
            liftMeanFloors = mean(eachLiftFloors);
            
            % String for output based on behavior
            behavior = this.getSystemBehavior;
            switch behavior
                case States.random
                    fileSuffix = 'Random';
                case States.dijkstra_e
                    fileSuffix = 'Scheduler';
            end
            
            % Prepare html structure for lift settings in output
            liftsNum = this.b.getNumOfLifts();
            
            liftStr = [];
            for i=1:liftsNum
                liftStr = strcat(liftStr,'<tr>');
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getID)));
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getBaseFloor)));
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getFinalFloor)));
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getDeniedFloors)));
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getCapacity)));
                liftStr = strcat(liftStr,sprintf('<td>%s</td>',num2str(this.b.l(i).getLiftSpeed)));
                liftStr = strcat(liftStr,'</tr>');
            end
            
            % prepare variables for replacing strings
            
            % make graphs and get their paths
            [HIST_URL, WAIT_URL] = this.makeGraphs();
            LIFT_CONF = liftStr;
            DATE = Simulation.getTime();
            BEHAVIOR = fileSuffix;
            NUM_VISITORS = num2str(num);
            
            % waiting time
            AWT = num2str(mean(sumWait));
            AWT_MAX = num2str(max(sumWait));
            AWT_MIN = num2str(min(sumWait(sumWait ~= 0)));
            AWT_COUNT = num2str(num-sumNotWait);
            AWT_STDEV = num2str(std(sumWait));
            
            % travel time
            ATT = num2str(mean(sum));
            ATT_MAX = num2str(max(sum));
            ATT_MIN = num2str(min(sum));
            ATT_STDEV = num2str(std(sum));
            
            % in-lift time
            ALT = num2str(mean(sumTravel));
            ALT_MAX = num2str(max(sumTravel));
            ALT_MIN = num2str(min(sumTravel));
            ALT_STDEV = num2str(std(sumTravel));
            
            % lift data
            LIFT_TOTAL = num2str(this.b.getNumOfLifts());
            LIFT_FLOORS = num2str(totalFloors);
            LIFT_MAX_ID = num2str(maxInd);
            LIFT_MAX_COUNT = num2str(liftMaxFloors);
            LIFT_MIN_ID = num2str(minInd);
            LIFT_MIN_COUNT = num2str(liftMinFloors);
            LIFT_MEAN = num2str(liftMeanFloors);
            
            if (~isdeployed)
                template = fileread('assets/output_template.html');
            else
                template = fileread('output_template.html');
            end
            % replace strings
            output = strrep(template, '%%DATE%%', DATE);
            output = strrep(output, '%%BEHAVIOR%%', BEHAVIOR);
            output = strrep(output, '%%NUM_VISITORS%%', NUM_VISITORS);
            
            output = strrep(output, '%%LIFT_CONF%%', LIFT_CONF);
            
            output = strrep(output, '%%AWT%%', AWT);
            output = strrep(output, '%%AWT_MAX%%', AWT_MAX);
            output = strrep(output, '%%AWT_MIN%%', AWT_MIN);
            output = strrep(output, '%%AWT_COUNT%%', AWT_COUNT);
            output = strrep(output, '%%AWT_STDEV%%', AWT_STDEV);
            
            output = strrep(output, '%%ATT%%', ATT);
            output = strrep(output, '%%ATT_MAX%%', ATT_MAX);
            output = strrep(output, '%%ATT_MIN%%', ATT_MIN);
            output = strrep(output, '%%ATT_STDEV%%', ATT_STDEV);
            
            output = strrep(output, '%%ALT%%', ALT);
            output = strrep(output, '%%ALT_MAX%%', ALT_MAX);
            output = strrep(output, '%%ALT_MIN%%', ALT_MIN);
            output = strrep(output, '%%ALT_STDEV%%', ALT_STDEV);
            
            output = strrep(output, '%%LIFT_TOTAL%%', LIFT_TOTAL);
            output = strrep(output, '%%LIFT_FLOORS%%', LIFT_FLOORS);
            output = strrep(output, '%%LIFT_MAX_ID%%', LIFT_MAX_ID);
            output = strrep(output, '%%LIFT_MAX_COUNT%%', LIFT_MAX_COUNT);
            output = strrep(output, '%%LIFT_MIN_ID%%', LIFT_MIN_ID);
            output = strrep(output, '%%LIFT_MIN_COUNT%%', LIFT_MIN_COUNT);
            output = strrep(output, '%%LIFT_MEAN%%', LIFT_MEAN);
            
            output = strrep(output, '%%HIST_URL%%', HIST_URL);
            output = strrep(output, '%%WAIT_URL%%', WAIT_URL);

            disp(output);
        end
        
        function [figHistFullExt, figWaitFullExt] = makeGraphs(this)
            % make two graphs for output and return their paths
            
            % String for output based on behavior
            behavior = this.getSystemBehavior;
            switch behavior
                case States.random
                    fileSuffix = 'Random';
                case States.dijkstra_e
                    fileSuffix = 'Scheduler';
            end
            
            % Histogram
            figHis = figure;
            set(figHis, 'Visible', 'Off');
            histData = this.humansListForGraph;
            
            % check if histogram fcn exist
            testFunction = exist('histogram', 'file');
            
            if (testFunction)
                figHisG = histogram(histData(:,1));
            else
                hist(histData(:,1));
            end
            
            xlabel('{\itt}_{sim}');
            ylabel('{\ita}_R');
            grid on;
                      
            waitTime = [];
            waitIte = [];
            for i=1:size(this.h,2)
                waitTime = [waitTime this.h(i).timeQueue];
                waitIte = [waitIte this.h(i).waitTime];
            end
            
            if (testFunction)
                [~,edges] = histcounts(unique(waitIte));
            else
                [~,edges] = hist(unique(waitIte));
            end
            
            waitEvery = [];
            meanTotal = [];
            
            plotX = [];
            plotY = [];
            
            for k=1:size(edges,2)-1
                ind = find(waitIte >= edges(k) & waitIte <  edges(k+1));
                if (~isempty(ind))
                    meanOne = mean(waitTime(ind));
                    meanTotal = [meanTotal meanOne];
                    
                    plotX = [plotX edges(k) edges(k+1)];
                    plotY = [plotY meanOne meanOne];
                    
                    waitOne = (linspace(edges(k),edges(k+1),meanOne));
                    waitEvery = [waitEvery waitOne];
                end
            end

            % Waiting time
            figWait = figure;
            set(figWait, 'Visible', 'Off');
            figWaitG = stem(waitIte,waitTime, 'LineWidth',1, 'Marker', 'x', 'MarkerSize', 4, 'Color', 'k');
            hold on
            
            figStairs = stairs(plotX,plotY, 'LineWidth', 3, 'LineStyle', '-', 'Color', 'red');
            if (~isempty(figStairs))
                legend('Waiting time','Average Waiting Time')
            end
            xlabel('{\itt}_{sim}');
            ylabel('{\itT}_M, {\itT}_as');
            grid on;
            
            % String preparations
            prefix='_';
             
            figHistName=strcat('histogram',prefix,fileSuffix,prefix);
            figHistDate=Simulation.getTime();
            figHistFile=strcat(figHistName,figHistDate);
            figpath='output/';
            figHistFull=strcat(figpath,figHistFile);
            
            figWaitName=strcat('waittimes',prefix,fileSuffix,prefix);            
            figWaitDate=View.getTime();
            figWaitFile=strcat(figWaitName,figWaitDate);
            figpath='output/';
            figWaitFull=strcat(figpath,figWaitFile);
            
            if (isdeployed && ismac)
                % special care for deployed app on macOS
                [fileMacHist,pathMacHist] = uiputfile(strcat(figHistFile,'.png'),'Save histogram figure');
                print(figHis,'-dpng','-r200', strcat(pathMacHist,fileMacHist))
                
                [fileMacWait,pathMacWait] = uiputfile(strcat(figWaitFile,'.png'),'Save waiting time figure');
                print(figWait,'-dpng','-r200', strcat(pathMacWait,fileMacWait))
                
                figHistFullExt = strcat(pathMacHist,fileMacHist);
                figWaitFullExt = strcat(pathMacWait,fileMacWait);
            else
                print(figHis,'-dpng','-r200', figHistFull)
                close(figHis);
                print(figWait,'-dpng','-r200', figWaitFull)
                close(figWait);
                
                figHistFullExt = strcat(figHistFile,'.png');
                figWaitFullExt = strcat(figWaitFile,'.png');
            end
            
        end
        
        %------------------------------------------------------------------
        %   Deprecated functions
        function lifts = findUnexploredLifts(this, ID, allLifts)
            
            explored = this.h(ID).getExplored();
            
            if (isempty(explored))
                lifts = allLifts;
            else
                [~, y] = find(ismember(allLifts,explored)==1);
                allLifts(y) = [];
                lifts = allLifts;
            end
            
        end
        
        function lifts = findDirectLifts(this, ID)
            
            actualFloor = this.h(ID).getActualFloor();
            desiredFloor = this.h(ID).getDesiredFloor();
            liftsOnFloor = this.findLiftsOnFloor(actualFloor);
            
            ind = [];
            for i=1:size(liftsOnFloor,2)
                if (~this.b.l(liftsOnFloor(i)).isFloorDenied(desiredFloor) && desiredFloor <= this.b.l(liftsOnFloor(i)).getFinalFloor && desiredFloor >= this.b.l(liftsOnFloor(i)).getBaseFloor)
                    ind = [ind i];
                end
            end
            
            lifts = liftsOnFloor(ind);
            
        end
        
        function lifts = clearFinalLifts(this, ID, allLifts, up)
            
            if (size(allLifts,2) > 0)
                lifts_a_index = [];
                if (up)
                    for i=1:size(allLifts,2)
                        if (this.h(ID).getActualFloor == this.b.l(allLifts(i)).getFinalFloor)
                            lifts_a_index = [lifts_a_index i];
                        end
                    end
                else
                    for i=1:size(allLifts,2)
                        if (this.h(ID).getActualFloor == this.b.l(allLifts(i)).getBaseFloor)
                            lifts_a_index = [lifts_a_index i];
                        end
                    end
                end
                
                allLifts(lifts_a_index) = [];
                lifts = allLifts;
            end
            
        end
        
        function floor = findNearestFloor(this, ID, lift)
            
            floors = [];
            
            for i=this.b.l(lift).getBaseFloor:this.b.l(lift).getFinalFloor
                if (~this.b.l(lift).isFloorDenied(i))
                    floors = [floors i];
                end
            end
            
            floors = floors(floors ~= this.b.l(lift).getActualFloor);
            
            [~, ind] = min(abs(floors - this.h(ID).getDesiredFloor));
            floor = floors(ind);
            
        end
        
    end
    
    methods (Static)
        
        function timechar = getTime()
            % Test if datetime function is available and return
            % time string
            
            testFunction = exist('datetime', 'file');
            
            if (testFunction == 0)
                timechar = datestr(now, 'HH-MM-yyyy-dd-mm-ss');
            else
                timechar=char(datetime('now','Format','HH-mm-ss''-''yyyy-dd-MM'));
            end
            
        end
        
        function [cleanedList, error, sizes] = deleteWrongHumans(list, numOfFloors)
            % Clear list from invalid items
            % list = original list
            % numberOfFloor = self explanatory
            % cleanedList = list cleaned from invalid items
            % error = true when there are some invalid items
            % sizes = size of original and cleaned list
            
            sizes = [size(list,1) 0];
            del_index = [];
            error = false;
            
            for i=1:size(list,1)
                if (list(i,2) == list(i,3) || ceil(list(i,1)) < 1 || floor(list(i,2)) < 1 || ceil(list(i,3)) < 1 || list(i,2) > numOfFloors || list(i,3) > numOfFloors)
                    del_index = [del_index i];
                    error = true;
                end
            end
            
            list(del_index,:) = [];
            list = ceil(list);
            cleanedList = list;
            sizes(2) = size(cleanedList,1);
            
        end  
    end
      
end
