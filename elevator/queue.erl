
-module (queue).
-export( [init/0, add_to_queue/3, addToInnerQueue/2, mergeFromQueue/2, 
	getInnerQueue/2, getNextOrder/1, deleteFromQueue/2, isOrder/2]).

% Order i a tuple of the form {inner/outer, floor, direction}

- define(IN_KEY = 13).
- define(OUT_KEY = 42).
- define(QUEUE_PID = queue).
- define(INNER = 0).
- define(OUTER = 1).


% makes a file type to bag, witch corresponds to map. Må vel være dynamisk og tilpasse til antall noder?

init() ->
	MyQueue_inner = ordsets:new(),
	MyQueue_outer = ordsets:new(),
	MyDict_ini = dict:append(IN_KEY, MyQueue_inner, dict:new()),
	MyDict = dict:append(OUT_KEY, MyQueue_outer, MyDict_ini),
	
	
	
	QueueID1_inner = ordsets:new(),
	QueueID1_outer = ordsets:new(),
	DictID1_ini = dict:append(IN_KEY, QueueID1_inner, dict:new()),
	DictID1 = dict:append(OUT_KEY, QueueID1_outer, QueueID1_ini),
	
	
	QueueID2_inner = ordsets:new(),
	QueueID2_outer = ordsets:new(),
	DictID2_ini = dict:append(IN_KEY, QueueID2_inner, dict:new()),
	DictID2 = dict:append(OUT_KEY, QueueID2_outer, QueueID2_ini),
	

	register(?QUEUE_PID, spawn(?MODULE, queue_storage_loop, [MyDict, DictID1, DictID2]).


init_from_stop ->
	% Modulen skal spørre andre tilkoplede heiser om deres ytre og indre kø.
	% Bruker "insert" egenskapen i queue_storage som skal overskrive eventuelle data som er på "dict -> key"
	

queue_storage_loop(MyQueue, Queue1, Queue2) ->
	receive
		{get_set, {Pid, {Id, Key, _Floor, _Direction}}} ->
			Pid ! dict:find(Key, Id),
			queue_storage(MyQueue, Queue1, Queue2);

		{insert, {Pid, {Id, Key, _Floor, _Direction}}}
			%Add to dictionary? How?
			Pid ! dict:find(Key,Id) %Hvordan fungerer denne?
			queue_storage(MyQueue, Queue1, Queue2);

		{add, }

		{remove, {Id, Key, Floor, Direction}} -> % UFERDIG
			SubjectSet = dict:find(Key, Id),
			New_set = ordsets:subtract(SubjectSet, {Floor, Direction}),
			New_dict = dict:append(dict:erase(Key, Id)
			queue_storage(MyQueue, ,

	end 



add_to_queue(ElevatorID, Key,OrderFloor,OrderDir) -> % Er en dum funksjon, som bare setter inn basert på input, order_distributer bestemmer hvor
	?QUEUE_PID ! {insert,{self(),ElevatorID,Key,OrderFloor,OrderDir}}
	receive
		{ok,Queue} ->
			ok;
		{_,_} ->
			io:fwrite("Order was not added ~n ", []),
			error;
	end

mergeFromQueue(ElevatorID) -> % er dum, merger fra elevatorID inn i andre køer, sletter køen til elevatorID?

getInnerQueue(ElevatorID) ->
	?QUEUE_PID ! {get_set, {self(), {ElevatorID, IN_KEY, 0, 0}}} % MY_PID er tenkt å brukes så queue_storage kan sende et svar
	receive
		{ok,Queue} ->
			Queue;
		{_,_} ->
			io:fwrite("No queue for ~w ~n ", [ElevatorID]),
			error;
	end

getNextOrder(ElevatorID) -> %Må denne være glup? I så fall, flytt til order_distributer

deleteFromQueue(ElevatorID, CurrentFloor) ->
	% Kjør en loop som itererer over retningene (-1, 0, 1)
	?QUEUE_PID ! {remove, {ID, IN_KEY, CurrentFloor, Direction}}
	?QUEUE_PID ! {remove, {ID, OUT_KEY, CurrentFloor, Direction}}

isOrder(Floor, ButtonType) ->
