classdef States
    % Enumerations used in classes Lift, Human, Simulation.
    enumeration
        % Lift states
        idle;
        moving;
        dns;
        stop;
        % direction
        up;
        down;
        free;
        
        % Human and lift states
        lift;
        floor;
        floorHold;
        waiting;
        finished;
        newWaiting;
        
        % Behavior states
        random;     % Random
        dijkstra_e; % Scheduler
    end
    
end

