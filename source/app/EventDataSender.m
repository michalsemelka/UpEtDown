classdef (ConstructOnLoad) EventDataSender < event.EventData
% sends data for events
   properties
      newData
   end
   
   methods
      function data = EventDataSender(newData)
         data.newData = newData;
      end
   end
end
