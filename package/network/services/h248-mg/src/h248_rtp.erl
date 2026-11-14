%% Minimal RTP transport for the H.248 MG.
-module(h248_rtp).
-export([start/1, stop/1, send/4, decode_payload/2]).

start(Port) ->
    gen_udp:open(Port, [binary, {active, false}, {reuseaddr, true}]).

stop(Socket) ->
    gen_udp:close(Socket).

send(Socket, Ip, Port, Payload) ->
    gen_udp:send(Socket, Ip, Port, Payload).

%% Return the static payload type and codec name for the common G.711 cases.
decode_payload(0, _Payload) -> {ok, pcmu};
decode_payload(8, _Payload) -> {ok, pcma};
decode_payload(_Type, _Payload) -> {error, unsupported_payload}.
