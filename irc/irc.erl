-module(irc).

-export([start/0, stop/0, list/0, connect/2, disconnect/0, join/1, leave/1]).

start() -> 
    register(irc, spawn(fun irc_server/0)),
    register(channel_controller_pid, spawn(fun() -> channel_controller(dict:new()) end)).

stop() ->
    unregister(irc),
    unregister(channel_controller_pid).

connect(Hostname, Nickname) ->
    {ok, connected} = rpc({connect, Hostname, Nickname}).

disconnect() ->
    {ok, disconnected} = rpc(disconnect).

list() ->
    ok = rpc(list).

join(Channel) ->
    ok = rpc({join, Channel}).

leave(Channel) ->
    ok = rpc({leave, Channel}).

rpc(Request) ->
    irc ! {self(), Request},
    receive 
	{irc, Response} ->
	    Response
    end.

irc_server() ->
    receive
	{From, {connect, Hostname, Nickname}} ->
	    {ok, Socket} = gen_tcp:connect(Hostname, 6667,[binary, {packet, 0}]),
	    Pid = spawn(fun() -> irc_server_loop(Socket, []) end),
 	    true = register(irc_server, Pid),
	    ok = gen_tcp:controlling_process(Socket, Pid),
	    send_data(["NICK", " ", Nickname, "\r\n"]),
 	    send_data(["USER pling plang plong :ding dong\r\n"]),
	    From ! {irc, {ok, connected}},
	    irc_server();
	{From, disconnect} ->
 	    send_data(["QUIT :ding dong\r\n"]),
	    From ! {irc, {ok, disconnected}},
	    true = unregister(irc_server),
	    irc_server();
	{From, list} ->
 	    send_data(["LIST\r\n"]),
	    From ! {irc, ok},
	    irc_server();
%	{From, {join, Channel}} ->
%	    io:format("Got a join request for ~p~n", [Channel]),
%	    send_join_channel(Channel),
%	    io:format("Sending a JOIN~n"),
%	    send_data(["JOIN", " ", Channel, "\r\n"]),
%	    From ! {irc, ok},
%	    irc_server();
	{From, {leave, Channel}} ->
 	    send_data(["PART", " ", Channel, "\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	Any ->
	    io:format("Received unhandle [~p]~n", [Any]),
	    irc_server()
    end.

irc_server_loop(Socket, Leftover) ->
    % io:format("Leftover: ~p~n", [Leftover]),
    receive
	{tcp, Socket, Bin} ->
	    L = Leftover ++ binary_to_list(Bin),
	    % io:format("L: ~s", [L]),
	    LastCrLfPos = string:rstr(L, "\r\n"),
	    LinesWithCrLf = 
		case LastCrLfPos of 
		    0 ->
			[];
		    _ ->
			string:substr(L, 1, LastCrLfPos+1)
		end,
	    Leftoversize = string:len(L)-string:len(LinesWithCrLf),
	    NewLeftover = 
		if
		    Leftoversize == 0 -> [];
		    Leftoversize > 0  -> string:substr(L, LastCrLfPos+2, Leftoversize)
		end,
	    % io:format("NewLeftover: ~p~n", [NewLeftover]),
	    T = string:tokens(LinesWithCrLf, "\r\n"),
	    handle_server_message(T, Socket),
	    irc_server_loop(Socket, NewLeftover);
	{tcp_closed, Socket} ->
	    io:format("Connection closed~n"),
	    irc_server_loop(Socket, Leftover);
	{error, closed}  ->
	    io:format("Connection closed by peer~n"),
	    irc_server_loop(Socket, Leftover);
	{irc_client_request, Payload} ->
	    ok = gen_tcp:send(Socket, list_to_binary(Payload)),
	    irc_server_loop(Socket, Leftover);
%	{irc_client_request_join_channel, Channel} ->
%	    ChannelPid = spawn(fun() -> channel_handler(Channel) end),
%	    %io:format("Spawned new process ~p for handling channel ~s~n", [ChannelPid, Channel]),
%	    NewDict = dict:store(Channel, ChannelPid, Dict),
%	    irc_server_loop(Socket, Leftover, NewDict);
	Any ->
	    io:format("Received unhandled [~p]~n", [Any]),
	    irc_server_loop(Socket, Leftover)
    end.

send_data(Payload) ->
    irc_server ! {irc_client_request, Payload}.

%send_join_channel(Channel) ->
%    irc_server ! {irc_client_request_join_channel, Channel}.

handle_server_message([H|T], Socket)->
    % io:format("H: ~s~n", [H]),
    Message = string:tokens(H, " "),
    %io:format("Message: ~s~n", [Message]),
    First = lists:nth(1, Message),
    case string:str(First, ":") of
	0 ->
	    case string:str(First, "PING") of
		1 ->
		    send_data(["PONG\r\n"]);
		_ ->
		    io:format("Unhandled command ~s~n", [H])
	    end;
	_ ->
	    Second = lists:nth(2, Message),
	    case Second of 
		"PRIVMSG" ->
		    Third = lists:nth(3, Message),
		    channel_controller_request({message, Third, Message});
		% RPL_LIST (322)
		"322" ->
		    Channel = lists:nth(4, Message),
		    channel_controller_request({join, Channel});
		_ ->
		    ok
	    end,
	    ok
    end,
    handle_server_message(T, Socket);

handle_server_message([], _Socket) ->
    ok.



channel_controller_request(Request) ->    
    channel_controller_pid ! Request.

channel_controller(Dict) ->
    % io:format("channel_controller: ~p~n", [Dict]),
    receive
	{join, Channel} ->
	    % io:format("channel_controller: Join request [~s]~n", [Channel]),
	    ChannelPid = spawn(fun() -> channel_handler(Channel) end),
	    NewDict = dict:store(Channel, ChannelPid, Dict),
	    send_data(["JOIN", " ", Channel, "\r\n"]),
	    channel_controller(NewDict);
	{leave, Channel} ->
	    % io:format("channel_controller: Leave request [~s]~n", [Channel]),
	    NewDict=Dict,
	    channel_controller(NewDict);
	{message, Channel, Contents} ->
	    % io:format("channel_controller: Message request [~s][~s]~n", [Channel, Contents]),
	    {ok, ChannelPID } = dict:find(Channel, Dict),
	    ChannelPID ! {channel_message, Contents},
	    channel_controller(Dict);
	Any ->
	    io:format("channel_controller: Unhandled message ~p~n", [Any]),
	    channel_controller(Dict)
    end.

channel_handler(Channel) ->
    % io:format("~p Channel handler for ~s~n", [self(), Channel]),
    receive
	{channel_message, Message} ->
	    io:format("~p ~s ~s~n", [calendar:local_time(),Channel, Message]),
	    channel_handler(Channel);
	Any ->
	    io:format("Received unhandle [~p]~n", [Any]),
	    channel_handler(Channel)
    end.


