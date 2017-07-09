classdef Lift < handle
%LIFT - class for lifts in model, instance of lift is created in BUILDING
%class
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (Access = private)
        ID = 0;
    end
    properties (Access = {?Simulation, ?Controller, ?View, ?Building, ?StateSpace})
        % parameters of lift
        baseFloor;
        finalFloor;
        actualFloor;
        deniedFloors;
        capacity;
        speed;
        
        % queues for both directions
        queueUp;
        queueDown;

        nextStop;                   % next floor where lift will stop, lift will 
                                    % keep moving until actualFloor == nextStop
        
        history;
        
        % states of lift
        state;                      % moving, stop, idle
        direction;                  % up, down, free
        % direction is used to ensure, that human will not enter lift that
        % is going in opposite direction of his travel.
        
        % atributtes for humans in lift
        humansInLift;               % ID of humans in lift
        numOfHumansInLift;          % Number of humans in lift
        
        IdleLiftToBase;             % when true, lift will go to base when idle 
    end
    
    events
        liftOnFloor;
    end
    
    methods (Access = {?Simulation, ?Controller, ?View, ?Building, ?StateSpace})
        
        function [this] = Lift(baseFloor, finalFloor, deniedFloors, capacity, speed, IdleLiftToBase)
            if (nargin() > 0)
                % parameters
                this.ID = Lift.setID;
                this.baseFloor = baseFloor;
                this.finalFloor = finalFloor;
                this.actualFloor = baseFloor;
                this.deniedFloors = deniedFloors;
                this.capacity = capacity;
                
                if (speed > 0.7)
                    this.speed = 0.7;
                else
                    this.speed = ceil(speed*10)/10;
                end
                
                % Queues for registered calls
                this.queueUp = [];
                this.queueDown = [];
                
                this.nextStop = 0;
                this.history = baseFloor;
                
                this.state = States.idle;
                this.direction = States.free;
                
                this.humansInLift = [];
                this.numOfHumansInLift = 0;
                
                this.IdleLiftToBase = IdleLiftToBase;
            else
                
            end
        end
        
        %------------------------------------------------------------------
        %   Getters & Setters
        %------------------------------------------------------------------
        function ID = getID(this)
            ID = this.ID;
        end
        
        function baseFloor = getBaseFloor(this)
            baseFloor = this.baseFloor;
        end
        
        function finalFloor = getFinalFloor(this)
            finalFloor = this.finalFloor;
        end
        
        function actualFloor = getActualFloor(this)
            actualFloor = this.actualFloor;
        end
        
        function deniedFloors = getDeniedFloors(this)
            deniedFloors = this.deniedFloors;
        end
        
        function bool = isFloorDenied(this, floor)
            % return true if floor is denieded
            bool = ~isempty(find(ismember(this.getDeniedFloors,floor),1));
        end
        
        function bool = isLiftFull(this)
            % return true if lift is full
            if (this.capacity == this.numOfHumansInLift)
                bool = true;
            else
                bool = false;
            end
        end
        
        function speed = getCapacity(this)
            speed = this.capacity;
        end
        
        function speed = getLiftSpeed(this)
            speed = this.speed;
        end
        
        function state = getState(this)
            state = this.state;
        end
        
        function setState(this, state)
            this.state = state;
        end
        
        function direction = getDirection(this)
            direction = this.direction;
        end
        
        function setDirection(this, direction)
            this.direction = direction;
        end
        
        function [history] = getHistory(this)
            [history] = this.history;
        end
        
        function nextstop = getNextStop(this)
            nextstop = this.nextStop;
        end
        
        function setNextStop(this, floor)
            this.nextStop = floor;
        end
        
        function num = getHumansInLift(this)
            num = this.humansInLift;
        end
        
        function num = getNumOfHumansInLift(this)
            num = this.numOfHumansInLift;
        end
        
        %------------------------------------------------------------------
        %   Functions
        %------------------------------------------------------------------
        
        %------------------------------------------------------------------
        %   Move related
        function [h] = move(this, humans)
            floorLift = this.getActualFloor();
            nextstop = this.getNextStop();
            if (States.idle.eq(this.getState) && (nextstop == 0 || floorLift == nextstop))
                % do nothing
            else
                if (nextstop > floorLift)
                    % if moving up
                    floorLift = floorLift + this.getLiftSpeed;
                    if (abs(nextstop - floorLift) < 1 && floorLift > nextstop)
                        % The distance to the next stop is smaller than the defined step
                        floorLift = nextstop;
                    end
                else
                    % if moving down
                    floorLift = floorLift - this.getLiftSpeed;
                    if (abs(nextstop - floorLift) < 1 && floorLift < nextstop)
                        % The distance to the next stop is smaller than the defined step
                        floorLift = nextstop;
                    end
                end
                
                % refresh actual floor for lift and for humans in lift
                this.actualFloor = floorLift;
                for i=1:this.getNumOfHumansInLift
                    humans(this.humansInLift(i)).actualFloor = floorLift;
                end
                if (floorLift == nextstop)
                    % lift stoped on floor, change state to stop nad add
                    % floor to history
                    this.setState(States.stop);
                    this.addToHistory(floorLift);
                    % event for humans leaving lift
                    this.notify('liftOnFloor');
                    % remove current floor from queue and get next stop and
                    % direction
                    this.selectFromQueue(true);
                else
                    % otherwise keep moving
                    this.setState(States.moving);
                end
            end
            h = humans;
        end
        
        function addToQueue(this,floor, up, inLift)
            % Function that registers all calls for lift
            % floor = floor of call or floor to go
            % up = direction of call, true -> up; false -> down
            % inLift = true when call was made inside of lift
            
            if (floor >= this.baseFloor && floor <= this.finalFloor && ~this.isFloorDenied(floor) && floor ~= this.getNextStop  && floor ~= this.getActualFloor)
                
                % add call to specific queue based on the direction
                if (up && isempty(find(ismember(this.queueUp,floor),1)))
                    this.queueUp = [this.queueUp floor];
                elseif (~up && isempty(find(ismember(this.queueDown,floor),1)))
                    this.queueDown = [this.queueDown floor];
                end
                
                % when lift is idle (and free) first visitor in lift set
                % direction
                if (States.free.eq(this.getDirection) && inLift)
                    if (up)
                        this.setDirection(States.up);
                    else
                        this.setDirection(States.down);
                    end
                    
                    this.selectFromQueue(false);                    
                end
                
            end
        end
        
        function selectFromQueue(this, floor)
            % handle calls, removing them and set next stop of lift 
            % floor = true when lift stopped at nextStop floor
            
            if (floor)
                % lift stopped, clear nextStop from queues
                
                QU = this.queueUp;
                QU = QU(QU ~= this.getNextStop);
                this.queueUp = QU;
                
                QD = this.queueDown;
                QD = QD(QD ~= this.getNextStop);
                this.queueDown = QD;
            end
            
            if (size(this.queueUp,2) == 0 && size(this.queueDown,2) == 0 && (this.getNextStop == this.getActualFloor || this.getNextStop == 0))
                % there are no calls -> state idle
                this.setDirection(States.free);
                this.setState(States.idle);
                this.setNextStop(0);
            else
                % handle calls in queues
                liftFloor = this.getActualFloor;
                
                if (States.down.ne(this.getDirection))
                    % when lift is not moving down
                    
                    QU = this.queueUp;
                    
                    % ignoring calls that are not in direction in sequence
                    QU = QU(QU >= liftFloor);
                    
                    % there are no more calls in direction in sequence
                    if (size(QU,2) == 0)
                        if (size(this.queueDown,2) > 0)
                            % but there are calls in opposite direction,
                            % lets handle them, but check where are
                            % they
                            QD = this.queueDown;
                            if (liftFloor > QD(1))
                                nextDown(this, liftFloor);
                            else
                                nextUp(this, liftFloor);
                            end
                        elseif (size(this.queueUp,2) ~= 0 && size(this.queueDown,2) == 0)
                            % nothing in opposite direction, but there
                            % are some calls that matches direction, but not
                            % sequence, so handle them
                            nextDown(this, liftFloor);
                        end
                    else
                        % continue in direction or update nextstop
                        nextUp(this, liftFloor);
                    end
                    
                elseif (States.up.ne(this.getDirection))
                    % when lift is not moving up
                    
                    liftFloor = this.getActualFloor;
                    QD = this.queueDown;
                    
                    % ignoring calls that are not in direction in sequence
                    QD = QD(QD <= liftFloor);
                    
                    % there are no more calls in direction in sequence
                    if (size(QD,2) == 0)
                        if (size(this.queueUp,2) > 0)
                            % but there are calls in opposite direction,
                            % lets handle them, but check where are
                            % they
                            QU = this.queueUp;
                            if (liftFloor < QU(1))
                                nextUp(this, liftFloor);
                            else
                                nextDown(this, liftFloor);
                            end
                        elseif (size(this.queueDown,2) ~= 0 && size(this.queueUp,2) == 0)
                            % nothing in opposite direction, but there
                            % are some calls that matches direction, but not
                            % sequence, so handle them
                            nextUp(this, liftFloor);
                        end
                    else
                        % continue in direction or update nextstop
                        nextDown(this, liftFloor);
                    end
                    
                end
                
            end
                
            function nextUp(this, liftFloor)
                % set nextstop that is in up direction
                
                actualQueue = this.queueUp;
                %ignoring calls that are not in direction in sequence
                actualQueue = actualQueue(actualQueue >= liftFloor);
                
                if ((size(this.queueDown,2) ~= 0 && size(actualQueue,2) == 0) || size(this.queueDown,2) ~= 0 && size(this.queueUp,2) == 0)
                    % ok there are no more calls in direction and queue for
                    % this direction is empty, but opposite queue is not,
                    % so pick furthest call from opposite queue and handle
                    % it
                    queueDownFirst = this.queueDown;
                    [~, ind] = max(queueDownFirst);
                    
                    actualQueue = [actualQueue queueDownFirst(ind)];
                    this.queueUp = actualQueue;
                    
                    queueDownFirst(ind) = [];
                    this.queueDown = queueDownFirst;
                    actualQueue = sort(actualQueue, 'descend');
                else
                    % there are no need to switch calls from queues, so
                    % sort queue to select closest one
                    actualQueue = sort(actualQueue);
                end

                % select nextFloor, set direction to UP
                nextFloor = actualQueue(1);
                this.setDirection(States.up);
                this.setNextStop(nextFloor);
                
            end
                
            function nextDown(this, liftFloor)
                % set nextstop that is in down direction
                
                actualQueue = this.queueDown;
                % ignoring calls that are not in direction in sequence
                actualQueue = actualQueue(actualQueue <= liftFloor);
                
                if ((size(this.queueUp,2) ~= 0 && size(actualQueue,2) == 0) || size(this.queueUp,2) ~= 0 && size(this.queueDown,2) == 0)
                    % ok there are no more calls in direction and queue for
                    % this direction is empty, but opposite queue is not,
                    % so pick furthest call from opposite queue and handle
                    % it
                    queueUpFirst = this.queueUp;
                    [~, ind] = min(queueUpFirst);
                    actualQueue = [actualQueue queueUpFirst(ind)];
                    this.queueDown = actualQueue;
                    
                    queueUpFirst(ind) = [];
                    this.queueUp = queueUpFirst;
                    actualQueue = sort(actualQueue);
                else
                    % there are no need to switch calls from queues, so
                    % sort queue to select closest one
                    actualQueue = sort(actualQueue,'descend');
                end               
                
                % select nextFloor, set direction to DOWN
                nextFloor = actualQueue(1);
                this.setDirection(States.down);
                this.setNextStop(nextFloor);
                
            end
        end
        
        function selectNextFloor(this)
            % after each simulation step, handle all calls for lift
            
            this.selectFromQueue(false);
            if (this.IdleLiftToBase == 1)
                this.goToBaseWhenIdle();
            end
        end
        
        function goToBaseWhenIdle(this)
            % when IdleLiftToBase == 1, lift will go down to base floor
            % everytime when is idle
            
            if (States.idle.eq(this.getState) && this.getActualFloor ~= this.getBaseFloor)
                this.addToQueue(this.getBaseFloor, false, true);
            end
        end
        
        
        %------------------------------------------------------------------
        %   Humans related
        function addHumanToLift(this, human)
            this.humansInLift = [this.humansInLift human];
            this.numOfHumansInLift = this.numOfHumansInLift + 1;
        end
        
        function removeHumanFromLift(this, human)
            this.humansInLift = this.humansInLift(this.humansInLift ~= human);
            this.numOfHumansInLift = this.numOfHumansInLift - 1;
        end
        
        %------------------------------------------------------------------
        %   Statistics related
        function addToHistory(this, floor)
            this.history = [this.history floor];
        end
    end
    
    methods (Static, Access = private)
        % Function that count instances of Lift.m class and return its ID
        function ID = setID()
            persistent objID
            if isempty(objID)
                objID = 1;
            else
                objID = objID + 1;
            end
            ID = objID;
        end
        
    end
    
end



