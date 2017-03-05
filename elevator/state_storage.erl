
- module (state_storage). %Was thinking file is not a state machine, but a state storage?
- compile(export_all). % Turns out, loops have to be exported to be registered like we do... this may not be very neat
- define(STATE_STORAGE_PID, ss). %Maybe we can send to this process on other computers when it is registered like this, at least, the simple add functions used to just send are not needed!

init()->
	Memberlist = get_member_list(),
	io:fwrite("~w ~n ", [Memberlist]),
	States = init_state_storage(dict:new(), Memberlist),
	Last_known_floors = init_floor_storage(dict:new(), Memberlist), %Reconsider function name and structure
	Directions = init_direction_storage(dict:new(), Memberlist),
	register(?STATE_STORAGE_PID, spawn(?MODULE, storage_loop, [States,Last_known_floors,Directions])).

get_member_list() ->
	[node()] ++ nodes().	
	

init_state_storage(States,MemberList)-> %Consider merging these three functions!
	case MemberList of 
		[Member | Rest] ->	
			New_states = dict:append(Member, init , States),  %Assuming we will not initialize state machine unless in state init
			init_state_storage(New_states,Rest);
		[] ->
			States
	end.

init_floor_storage(Last_known_floors, MemberList) ->
	case MemberList of 
		[Member | Rest] ->	
			New_last_known_floors = dict:append(Member, -1 , Last_known_floors),  %Assuming the actual last known floor will be set in main, using -1 as dummy variable
			init_floor_storage(New_last_known_floors,Rest);
		[] ->
			Last_known_floors
	end.

init_direction_storage(Directions, MemberList) ->
	case MemberList of 
		[Member | Rest] ->	
			New_directions= dict:append(Member, 0 , Directions),  %Assuming the actual last known floor will be set in main, using 0 as dummy variable(is also rather probable)
			init_direction_storage(New_directions,Rest);
		[] ->
			Directions
	end.

storage_loop(States,Last_known_floors,Directions) ->
	io:fwrite("Hallo fra loop ~n ", []),
	receive
		{get_state, {Pid, Key}} ->
			{_ok,[State | _Meh]} = dict:find(Key, States),
			io:fwrite("~w ~n ", [State]), %Debug
			Pid ! {ok,State},
			storage_loop(States,Last_known_floors,Directions);

		{get_last_known_floor, {Pid, Key}} ->
			{_ok,[Last_known_floor| _Meh]} = dict:find(Key, Last_known_floors),
			io:fwrite("~w ~n ", [Last_known_floor]), %Debug
			Pid ! {ok,Last_known_floor},
			storage_loop(States,Last_known_floors,Directions);

		{get_direction,{Pid,Key}} ->
			{_ok,[Direction| _Meh]} = dict:find(Key, Directions),
			io:fwrite("~w ~n ", [Direction]), %Debug
			Pid ! {ok,Direction},
			storage_loop(States,Last_known_floors,Directions);

		{set_state, {Key,State}} -> 
			Updated_states = dict:append(Key, State, dict:erase(Key, States)),
			storage_loop(Updated_states,Last_known_floors,Directions);

		{set_last_known_floor, {Key,Last_known_floor}} -> 
			Updated_last_known_floors = dict:append(Key, Last_known_floor, dict:erase(Key, Last_known_floors)),
			storage_loop(States,Updated_last_known_floors,Directions);

		{set_direction, {Key,Direction}} -> 
			Updated_directions = dict:append(Key, Direction, dict:erase(Key, Directions)),
			storage_loop(States,Last_known_floors,Updated_directions)

	end.
