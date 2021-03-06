- module(elevator).
- export([start/0]).

- record(order,{floor,type}).
- record(button,{floor,type,state = 0}).

- define(ELEVATOR_MONITOR_PID, empid).
- define(REMOTE_LISTENER_PID, rlpid).
- define(STATE_STORAGE_PID, ss).
- define(DRIVER_MANAGER_PID, dmpid).
- define(NODE_WATCHER_PID, nwpid).
- define(TIMER, tmpid).

start() ->
	register(?ELEVATOR_MONITOR_PID, spawn(fun() -> elevator_monitor_init() end)),
	register(?REMOTE_LISTENER_PID, spawn(fun() -> remote_listener_init() end)),
	register(?DRIVER_MANAGER_PID, spawn(fun() -> driver_manager_init() end)),

	connection:init(self()),
	receive 
		connection_init_complete ->
			connection_init_ok
	end,
	driver:start(self(), ?ELEVATOR_MONITOR_PID),
	receive
		{driver_init_complete, Floor} ->
			driver_init_ok
	end,
	queue_storage:init(self()),
	receive
		queue_init_complete ->
			queue_init_ok
	end,
	state_storage:init(self(), Floor),
	receive
		state_init_complete ->
			state_init_ok
	end,

	spawn(fun() -> button_light_manager(driver:create_buttons([],0)) end),
	register(?NODE_WATCHER_PID ,spawn(fun() -> node_watcher({0,0,0}) end)), 

	?ELEVATOR_MONITOR_PID ! init_complete,
	?REMOTE_LISTENER_PID ! init_complete,
	?DRIVER_MANAGER_PID ! init_complete,

	lists:foreach(fun(Node) -> {?NODE_WATCHER_PID, Node} ! init_complete end, nodes()),
	set_my_local_and_remote_info("state", idle),
	io:fwrite("Sening my info: State = idle, to nodes: ~w ~n", [nodes()]),
	spawn(fun()-> order_distributer:order_poller(?ELEVATOR_MONITOR_PID) end).

elevator_monitor_init() ->
	receive
		init_complete ->
			elevator_monitor()
	end.
elevator_monitor() ->
	receive
		{new_floor_reached,Floor} ->
			respond_to_new_floor(Floor),
			elevator_monitor();

		{button_pressed, Floor, ButtonType} ->
			Order = #order{floor = Floor, type = ButtonType},
			Winner = order_distributer:distribute_order(Order),
			send_to_connected_nodes(add_order, {Winner, Order}),
			elevator_monitor();

		{new_destination, Direction} ->
			go_to_destination(Direction),
			elevator_monitor();

		{stuck} ->
			driver:set_motor_direction(stop),
			init:stop()
			
	end.

driver_manager_init() ->
	receive
		init_complete ->
			driver_manager()
	end.
driver_manager() ->
	receive
		{stop_at_floor,Floor} ->
			%?TIMER ! stop,
			stop_timer_if_present(),
			driver:set_motor_direction(stop),
			set_my_local_and_remote_info("direction", stop),

			driver:set_door_open_lamp(on),
			set_my_local_and_remote_info("state", door_open),
			timer:sleep(3000),
			driver:set_door_open_lamp(off),

			lists:foreach(fun(Node) -> queue_storage:remove_from_queue(Node == node(), Node, Floor) end, [node()]++nodes() ), 
			send_to_connected_nodes(remove_from_queue, {node(), Floor}),
			set_my_local_and_remote_info("state", idle),
			
			driver_manager();

		{at_end_floor} ->
			%?TIMER ! stop,
			stop_timer_if_present(),
			driver:set_motor_direction(stop),
			set_my_local_and_remote_info("direction", stop),
			set_my_local_and_remote_info("state", idle),

			driver_manager();

		{go_to_destination, Direction} ->
			driver:set_motor_direction(Direction),
			set_my_local_and_remote_info("direction", Direction),
			set_my_local_and_remote_info("state", moving),
			%register(?TIMER , spawn(fun() -> delay_timer() end)),
			start_timer_if_not_present(),

			driver_manager()
	end.

remote_listener_init() ->
	receive 
		init_complete ->
			remote_listener()
	end.
remote_listener() ->
	receive
		{add_order, {Elevator, Order}} ->
			queue_storage:add_to_queue(Elevator, Order),
			remote_listener();

		{update_state, {Elevator, stuck}} ->
			state_storage:set_information(set_state, {Elevator, stuck}),
			order_distributer:merge_from_elevator(Elevator),
			remote_listener();

		{update_state, {Elevator, State}} ->
			state_storage:set_information(set_state, {Elevator, State}),
			remote_listener();

		{update_last_known_floor, {Elevator, Floor}} ->
			state_storage:set_information(set_last_known_floor, {Elevator, Floor}),
			remote_listener();

		{update_direction, {Elevator, Direction}} ->
			state_storage:set_information(set_direction, {Elevator, Direction}),
			remote_listener();

		{remove_from_queue, {Elevator, Floor}} ->
			lists:foreach(fun(Node) -> queue_storage:remove_from_queue(Node == Elevator, Node, Floor) end, [node()]++nodes() ),
			remote_listener();

		{merge_to_inner_queue, Remote_queue} ->	
			Original_queue = queue_storage:get_queue_set(node(),inner),
			New_queue = ordsets:union(Original_queue,Remote_queue),
			queue_storage:replace_queue(node(),New_queue),
			remote_listener()
	end.

node_watcher({0,0,0}) ->
	global_group:monitor_nodes(true),
	node_watcher({0,0,1});
node_watcher(Timestamp) ->
	receive 
		{nodedown, Node} ->
			io:fwrite("Node down ~w ~n", [Node]),
			order_distributer:merge_from_elevator(Node),
			node_watcher(Timestamp);
		{nodeup, Node} ->
			io:fwrite("Node up ~w ~n", [Node]),
			queue_storage:update_queue(Node),
			state_storage:update_storage(Node),
			Node_queue = queue_storage:get_queue_set(Node,inner),
			spawn(fun() -> send_to_elevator_if_present(Node,Node_queue) end)
			
	after 3000 ->
		State = state_storage:get_information(get_state, node()),
		Floor = state_storage:get_information(get_last_known_floor,node()),
		Direction = state_storage:get_information(get_direction,node()),
		set_my_local_and_remote_info("state", State),
		set_my_local_and_remote_info("last_known_floor", Floor),
		set_my_local_and_remote_info("direction", Direction)
	end,
	node_watcher({0,0,1}).

delay_timer() ->
	receive
		stop ->
			ok

	after 8000 ->
		?ELEVATOR_MONITOR_PID ! {stuck},
		delay_timer()
	end.

button_light_manager(Buttons) ->
	lists:foreach(fun(Button) -> update_button_light(Button) end,Buttons),
	timer:sleep(50),
	button_light_manager(Buttons).

update_button_light(Button)->
	Toset = toset(Button),
	set_button (Toset, Button). 

toset({button,Floor,inner, _State}) ->
	Order = #order{floor= Floor, type = inner},
	queue_storage:is_order(Order, node(), []);
toset({button, Floor, Type, _State}) ->
	Order = #order{floor= Floor, type = Type},
	queue_storage:is_order(Order).

go_to_destination(stop) ->
	%register(?TIMER , spawn(fun() -> delay_timer() end)),
	start_timer_if_not_present(),
	Floor = state_storage:get_information(get_last_known_floor, node()),
	respond_to_new_floor(true, Floor);
go_to_destination(Direction) ->
	case Direction == state_storage:get_information(get_direction,node()) of 
		true ->
			ok;
		false ->
			?DRIVER_MANAGER_PID  ! {go_to_destination, Direction}
	end.

respond_to_new_floor(Floor) ->
	driver:set_floor_indicator(Floor),
	set_my_local_and_remote_info("last_known_floor", Floor),
	respond_to_new_floor(Floor == queue_storage:get_my_next(), Floor).

respond_to_new_floor(true, Floor) ->% argument (Stop_for_order, Floor)
	?DRIVER_MANAGER_PID ! {stop_at_floor,Floor};
respond_to_new_floor(false, 0) -> 
	respond_to_new_floor(false, 3);
respond_to_new_floor(false, 3) -> 
	?DRIVER_MANAGER_PID  ! {at_end_floor};
respond_to_new_floor(false, _) ->
	ok.

send_to_connected_nodes(Command, Message) ->
	lists:foreach(fun(Node) -> {?REMOTE_LISTENER_PID, Node} ! {Command, Message} end, nodes()).

set_my_local_and_remote_info(Info_type, Message) ->
	state_storage:set_information(list_to_atom("set_" ++ Info_type), {node(), Message}),
	send_to_connected_nodes(list_to_atom("update_" ++ Info_type), {node(), Message}).

set_button(true, Button) -> driver:set_button_lamp(Button#button.type,Button#button.floor,on);
set_button(false, Button) -> driver:set_button_lamp(Button#button.type,Button#button.floor,off).

start_timer_if_not_present() ->
	Is_present = lists:member(?TIMER, registered()),
	start_timer_if_not_present(Is_present).
start_timer_if_not_present(true) -> 
	?TIMER ! stop,
	timer:sleep(60),
	register(?TIMER , spawn(fun() -> delay_timer() end));
start_timer_if_not_present(false) ->
	register(?TIMER , spawn(fun() -> delay_timer() end)).


stop_timer_if_present() ->
	Is_present = lists:member(?TIMER, registered()),
	stop_timer_if_present(Is_present).
stop_timer_if_present(true) -> 
	?TIMER ! stop;
stop_timer_if_present(false) ->
	ok.

send_to_elevator_if_present(ID, Msg) ->
	State = state_storage:get_information(get_state,ID),
	send_to_elevator_if_present(ID, State, Msg).


send_to_elevator_if_present(ID,unknown,Msg) ->
	timer:sleep(100),
	send_to_elevator_if_present(ID,Msg);

send_to_elevator_if_present(ID,_State,Msg) ->
	io:fwrite("Sending merge message ~n", []),
	{?REMOTE_LISTENER_PID, ID} ! {merge_to_inner_queue, Msg}.
