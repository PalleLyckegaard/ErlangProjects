-module(irc).

-export([start/0, stop/0, lists/0, connect/2, disconnect/0, join/1, leave/1]).

start() -> 
    register(irc, spawn(fun irc_server/0)).

stop() ->
    unregister(irc).

connect(Hostname, Nickname) ->
    {ok, connected} = rpc({connect, Hostname, Nickname}).

disconnect() ->
    {ok, disconnected} = rpc(disconnect).

lists() ->
    ok = rpc(lists).

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
%	    io:format("Connected to [~p] using Socket [~s]~n", [Hostname, Socket]),
	    Pid = spawn(fun() -> irc_server_loop(Socket, 1) end),
	    true = register(irc_server, Pid),
%	    WhereisPid = whereis(irc_server),
%	    io:format("[irc_server] is PID [~p]~n", [WhereisPid]),
	    ok = gen_tcp:controlling_process(Socket, Pid),
%	    io:format("Spawned PID [~p]~n", [Pid]),
	    send_data(["NICK", " ", Nickname, "\r\n"]),
 	    send_data(["USER pling plang plong :ding dong\r\n"]),
	    From ! {irc, {ok, connected}},
	    irc_server();
	{From, disconnect} ->
 	    send_data(["QUIT :ding dong\r\n"]),
	    From ! {irc, {ok, disconnected}},
	    true = unregister(irc_server),
	    irc_server();
	{From, lists} ->
 	    send_data(["LIST\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	{From, {join, Channel}} ->
 	    send_data(["JOIN", " ", Channel, "\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	{From, {leave, Channel}} ->
 	    send_data(["PART", " ", Channel, "\r\n"]),
	    From ! {irc, ok},
	    irc_server();
	Any ->
	    io:format("Received unhandle [~p]~n", [Any]),
	    irc_server()
    end.

irc_server_loop(Socket, Turn) ->
%    io:format("Entering loop with PID [~p] Socket [~p]~n", [self(), Socket]),
    Turn1 = Turn + 1,
%    io:format("Turn: ~p\n", [Turn1]),
    receive
	{tcp, Socket, Bin} ->
%	    io:format("Got data~n"),
	    L = binary_to_list(Bin),
%	    io:format("L ~p~n", [L]),
	    EndPos = string:rstr(L, "\r\n"),
%	    io:format("EndPos ~p~n", [EndPos]),
	    OkStr = string:substr(L, 1, EndPos+1),
%	    LostStr = string:substr(L, EndPos+2),
	    T = string:tokens(OkStr, "\r\n"),
%	    io:format("Number of tokens is ~p\n", [length(T)]),
	    handle_server_message(T, Socket),
	    irc_server_loop(Socket, Turn1);
	{tcp_closed, Socket} ->
	    io:format("Connection closed~n"),
	    irc_server_loop(Socket, Turn1);
	{irc_client_request, Payload} ->
	    ok = gen_tcp:send(Socket, list_to_binary(Payload)),
	    irc_server_loop(Socket, Turn1)
    end.

send_data(Payload) ->
    irc_server ! {irc_client_request, Payload}.

handle_server_message([H|T], Socket)->
%    io:format("~p ~s~n", [calendar:local_time(),H]),
    Message = string:tokens(H, " "),
%    io:format("~p~n", [Message]),
    First = lists:nth(1, Message),
    case string:str(First, ":") of
	0 ->
	    case string:str(First, "PING") of
		1 ->
%		    io:format("Got a PING~n"),
		    send_data(["PONG\r\n"]);
		_ ->
		    io:format("Unhandled command ~s~n", [First])
	    end;
	_ ->
	    Second = lists:nth(2, Message),
	    case Second of 
		"PRIVMSG" ->
		    io:format("~p ~s~n", [calendar:local_time(),H]);
		_ ->
		    ok
	    end,
	    ok
    end,
    handle_server_message(T, Socket);
handle_server_message([], Socket) ->
    ok.


