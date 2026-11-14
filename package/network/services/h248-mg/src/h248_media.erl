%% Minimal RTP/PCM media loop skeleton.
-module(h248_media).
-export([start/2, handle_pcm/1, stop/0]).
-define(FRAME_MS, 20).

start(RemoteIp, RemotePort) ->
    case h248_rtp:start(0) of
        {ok, Socket} ->
            Pid = spawn(fun() -> loop(Socket, RemoteIp, RemotePort, 0, 0) end),
            register(h248_media, Pid),
            inet:setopts(Socket, [{active, true}]),
            timer:send_interval(?FRAME_MS, Pid, read_pcm),
            {ok, Pid};
        Error -> Error
    end.

stop() ->
    case whereis(h248_media) of
        undefined -> ok;
        Pid -> Pid ! stop
    end.

handle_pcm(Line) ->
    case whereis(h248_media) of
        undefined -> ok;
        Pid -> Pid ! {pcm, Line}
    end.

loop(Socket, Ip, Port, Seq, Ts) ->
    receive
        stop ->
            h248_rtp:stop(Socket);
        read_pcm ->
            h248_mg:fxs_cmd("PCM READ"),
            timer:send_after(?FRAME_MS, self(), read_pcm),
            loop(Socket, Ip, Port, Seq, Ts);
        {pcm, <<"NONE", _/binary>>} ->
            loop(Socket, Ip, Port, Seq, Ts);
        {pcm, Hex} ->
            Pcm = hex_to_samples(Hex),
            Payload = h248_g711:encode(pcmu, Pcm),
            Hdr = <<2:2, 0:1, 0:1, 0:4, 0:8, Seq:16, Ts:32, 1:32>>,
            h248_rtp:send(Socket, Ip, Port, <<Hdr/binary, Payload/binary>>),
            loop(Socket, Ip, Port, (Seq + 1) band 16#ffff, (Ts + 160) band 16#ffffffff);
        {udp, Socket, _Ip, _Port, <<_Hdr:12/binary, Payload/binary>>} ->
            Pcm = h248_g711:decode(pcmu, Payload),
            Hex = lists:flatten([io_lib:format("~2.16.0b~2.16.0b", [S band 16#ff, (S bsr 8) band 16#ff]) || S <- Pcm]),
            h248_mg:fxs_cmd("PCM WRITE " ++ Hex),
            loop(Socket, Ip, Port, Seq, Ts);
        _ ->
            loop(Socket, Ip, Port, Seq, Ts)
    end.

hex_to_samples(Hex) ->
    case catch binary_to_list(Hex) of
        L when is_list(L) -> hex_pairs(L, []);
        _ -> []
    end.

hex_pairs([A, B | Rest], Acc) ->
    Val = (hex(A) bsl 4) bor hex(B),
    S = case Val band 16#8000 of 0 -> Val; _ -> Val - 16#10000 end,
    hex_pairs(Rest, [S | Acc]);
hex_pairs(_, Acc) -> lists:reverse(Acc).

hex(C) when C >= $0, C =< $9 -> C - $0;
hex(C) when C >= $a, C =< $f -> C - $a + 10;
hex(C) when C >= $A, C =< $F -> C - $A + 10;
hex(_) -> 0.
