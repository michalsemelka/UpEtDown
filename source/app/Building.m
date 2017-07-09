classdef Building < handle
%BUILIDING - class for builiding in model, instance of builiding is created 
%in SIMULATION class
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% Up&Down
% Author - Michal Semelka, <m.semelka@gmail.com>, 2017
% https://github.com/michalsemelka/UpEtDown
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    properties (Access = private)
        numOfFloors;
        liftsOnFloors;      % list of lifts IDs for each floor in building   
    end
    
    properties (Access = ?Simulation)
        l;
    end
    
    methods (Access = {?Simulation, ?Controller, ?View})
        
        function [this] = Building(numOfFloors, l)
            this.numOfFloors = numOfFloors;
            this.l = l;
            this.liftsOnFloors = this.mapFloorsAndLifts();
        end
        
        function numFloors = getNumOfFloors(this)
            numFloors = this.numOfFloors;
        end
        
        function liftsOnFloors = getLiftsOnFloors(this)
            liftsOnFloors = this.liftsOnFloors;
        end
        
        function l = getLifts(this)
            l = this.l;
        end
        
        function lifts = getNumOfLifts(this)
            lifts = size(this.l,2);
        end
        
    end
    
    methods (Access = private)
        
        function mapped = mapFloorsAndLifts(this)
            % return list of lifts ID for each floor in building 
            
            mapped = cell(this.getNumOfFloors,2);
            for k=1:this.getNumOfFloors
                for i=1:1:size(this.l,2)
                    mapped{k,1} = k;
                    if (k >= this.l(i).getBaseFloor && k <= this.l(i).getFinalFloor && ~this.l(i).isFloorDenied(k))
                        mapped{k,2} = [mapped{k,2} i];
                    end
                end
            end
        end
        
    end
end

