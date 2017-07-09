classdef Human < handle
%HUMAN - class for visitor in model, instance of Human is created in SIMULATION
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
    properties (Access = {?Simulation, ?Controller, ?View, ?Lift})
        startFloor;
        desiredFloor;
        
        actualFloor;
        nextFloor;      % based on this att human will leave the lift on specified floor
        
        history;        % keep track of lifts used
        explored;       % deprecated
        state;          % floor, waiting, newWaiting, lift, finished, floorHold
        
        inLift;         % ID of lift in which human is
        
        % Time-based
        timeStart; 
        timeStop;
        timeQueue;      % vector of waiting times for lifts, if any      
        timeTravel;     % vector of travel time in lifts
        waitTime;       % vector of timeStamp values when human started waiting, if any
        
        % Paths
        path;
        actualPath;
    end
    
    methods (Access = {?Simulation, ?Controller, ?View, ?Lift})
        
        function [this] = Human(startFloor, desiredFloor, path)
            this.ID = Human.setID();
            this.startFloor = startFloor;
            this.desiredFloor = desiredFloor;
            this.nextFloor = 0;
            this.actualFloor = startFloor;
            this.state = States.floor;
            this.history = [];
            this.explored = [];
            this.inLift = 0;
            this.timeStart = 0;
            this.timeStop = 0;
            this.timeQueue = [];
            this.timeTravel = [];
            this.waitTime = [];
            this.path = path;
            this.actualPath = [];
            this.selectActualPath;
        end
        
        %------------------------------------------------------------------
        %   Getters & Setters
        %------------------------------------------------------------------
        function ID = getID(this)
            ID = this.ID;
        end
        
        function floor = getStartFloor(this)
            floor = this.startFloor;
        end
        
        function floor = getDesiredFloor(this)
            floor = this.desiredFloor;
        end
        
        function floor = getNextFloor(this)
            floor = this.nextFloor;
        end
        
        function setNextFloor(this,floor)
            this.nextFloor = floor;
        end
        
        function floor = getActualFloor(this)
            floor = this.actualFloor;
        end
        
        function setHistory(this,lift)
            this.history(end+1) = lift;
        end
        
        function explored = getExplored(this)
            explored = this.explored;
        end
        
        function setExplored(this,lift)
            this.explored(end+1) = lift;
        end
        
        function history = getHistory(this)
            history = this.history;
        end
        
        function lift = getLastUsedLift(this)
            if (isempty(this.history))
                lift = 0;
            else
                lift = this.history(end);
            end
        end
        
        function state = getState(this)
            state = this.state;
        end
        
        function setState(this, state)
            this.state = state;
        end
        
        function time = getTimeStart(this)
            time = this.timeStart;
        end
        
        function setTimeStart(this, time)
            this.timeStart = time;
        end
        
        function time = getTimeStop(this)
            time = this.timeStop;
        end
        
        function setTimeStop(this, time)
            this.timeStop = time;
        end
        
        function path = getActualPath(this)
            path = this.actualPath;
        end
        
        function setPath(this, path)
            this.path = path;
        end
        
        function setTimeQueue(this, time, newCall)
            % when newCall is true, add new entry in vector (timeStamp
            % value), when newCall is false (human enter lift), make the difference between
            % the previous and the current time. Also track time when user
            % started waiting.
            if (newCall == true)
                this.timeQueue(end+1) = time;
                this.waitTime(end+1) = time;
            else
                if ((States.newWaiting.eq(this.getState) || States.waiting.eq(this.getState)) && ~isempty(this.timeQueue))
                    this.timeQueue(end) = abs(time - this.timeQueue(end));
                end
            end
        end
        
        function setTimeTravel(this, time, newCall)
            % when newCall is true (humen enter lift), add new entry in vector (timeStamp
            % value), when newCall is false (human leave lift), make the difference between
            % the previous and the current time. 
            if (newCall == true)
                this.timeTravel(end+1) = time;
            else
                if (~isempty(this.timeTravel))
                    this.timeTravel(end) = abs(time - this.timeTravel(end));
                end
            end
        end
        
        %------------------------------------------------------------------
        %   Functions
        %------------------------------------------------------------------
        function enterLift(this, lift, time)
            this.inLift = lift;
            this.setHistory(lift);
            this.setTimeQueue(time, false);
            this.setTimeTravel(time, true);
            this.setState(States.lift);
        end
        
        function leaveLift(this, final, time)
            this.setTimeTravel(time, false);
            if (final == true)
                this.inLift = 0;
                this.setState(States.finished);
            else
                this.inLift = 0;
                this.setState(States.floor);
            end
        end
        
        function selectActualPath(this)
            % Select next path from structure and delete it in itinerary
            if (size(this.path,2) ~= 0)
                this.actualPath = this.path(1);
                this.path(1) = [];
            end
        end
        
        %------------------------------------------------------------------
        %   Statistics related
        function time = statsTotalTime(this)
            % return total time of travel
            time = sum(this.timeQueue) + sum(this.timeTravel);
        end
        
        function time = statsWaiting(this)
            % return sum of waiting times
            if (~isempty(this.timeQueue))
                time = sum(this.timeQueue);
            else
                time = 0;
            end
        end
        
        function time = statsTravel(this)
            % return total time spent in lift
            time = sum(this.timeTravel);
        end
        
    end
    
    methods (Static, Access = private)
        % Function that count instances of Human.m class and return its ID
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

