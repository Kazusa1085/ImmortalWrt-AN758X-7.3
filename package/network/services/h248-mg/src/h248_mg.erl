%% Minimal H.248/Megaco MG.
%%
%% Protocol stack: Erlang/OTP megaco.  The C port owns /dev/en75xx-fxs0.
-module(h248_mg).
-behaviour(megaco_user).
-export([start/0, stop/0, port_loop/1, fxs_cmd/1, dtmf_event/1, hook_event/1]).
-export([handle_connect/2, handle_disconnect/3,
         handle_syntax_error/3, handle_message_error/3,
         handle_trans_request/3, handle_trans_long_request/3,
         handle_trans_reply/4, handle_trans_ack/4,
         handle_unexpected_trans/3, handle_trans_request_abort/4]).

-include_lib("megaco/include/megaco.hrl").
-include_lib("megaco/include/megaco_message_v1.hrl").

start() ->
    application:ensure_all_started(megaco),
    ets:new(h248_terms, [named_table, public, set]),
    Mgc = os:getenv("H248_MGC", "127.0.0.1"),
    RtpPort = list_to_integer(os:getenv("H248_RTP_PORT", "5004")),
    ets:insert(h248_terms, {rtp_port, RtpPort}),
    MgcPort = list_to_integer(os:getenv("H248_MGC_PORT", "2944")),
    LocalPort = list_to_integer(os:getenv("H248_LOCAL_PORT", "2944")),
    Mid = {deviceName, "en75xx-mg"},
    Config = [{user_mod, h248_mg},
              {encoding_mod, megaco_pretty_text_encoder},
              {encoding_config, []},
              {send_mod, megaco_udp}],
    case megaco:start_user(Mid, Config) of
        ok ->
            io:format("h248_mg: user started, MGC ~s:~p local ~p~n",
                      [Mgc, MgcPort, LocalPort]),
            start_transport(Mid, Mgc, MgcPort, LocalPort),
            start_fxs_port(),
            ok;
        Error ->
            io:format("h248_mg: start_user failed: ~p~n", [Error]),
            Error
    end.

start_transport(Mid, Mgc, MgcPort, LocalPort) ->
    RecHandle = megaco:user_info(Mid, receive_handle),
    case megaco_udp:start_transport() of
        {ok, SupPid} ->
            case megaco_udp:open(SupPid, [{port, LocalPort},
                                          {receive_handle, RecHandle}]) of
                {ok, Handle, ControlPid} ->
                    SendHandle = megaco_udp:create_send_handle(Handle, Mgc, MgcPort),
                    case megaco:connect(RecHandle, preliminary_mid,
                                        SendHandle, ControlPid) of
                        {ok, ConnHandle} ->
                            io:format("h248_mg: connected~n"),
                            ets:insert(h248_terms, {conn, ConnHandle}),
                            service_change(ConnHandle);
                        Other ->
                            io:format("h248_mg: connect failed: ~p~n", [Other])
                    end;
                Other ->
                    io:format("h248_mg: udp open failed: ~p~n", [Other])
            end;
        Other ->
            io:format("h248_mg: udp transport failed: ~p~n", [Other])
    end.

service_change(ConnHandle) ->
    SCP = #'ServiceChangeParm'{serviceChangeMethod = restart,
                               serviceChangeReason = [?megaco_cold_boot]},
    SCR = #'ServiceChangeRequest'{terminationID = [?megaco_root_termination_id],
                                  serviceChangeParms = SCP},
    CR = #'CommandRequest'{command = {serviceChangeReq, SCR}},
    AR = #'ActionRequest'{contextId = ?megaco_null_context_id,
                          commandRequests = [CR]},
    case megaco:call(ConnHandle, [AR], []) of
        {ok, _Reply} -> io:format("h248_mg: service change ok~n");
        Other -> io:format("h248_mg: service change reply: ~p~n", [Other])
    end.

stop() ->
    catch megaco:stop_user({deviceName, "en75xx-mg"}),
    ok.

start_fxs_port() ->
    Device = os:getenv("H248_DEVICE", "/dev/en75xx-fxs0"),
    Port = open_port({spawn, "/usr/bin/en75xx_fxs_port"}, [binary, {packet, line}]),
    port_command(Port, "OPEN " ++ Device ++ "\n"),
    Pid = spawn(?MODULE, port_loop, [Port]),
    register(h248_fxs, Pid),
    ok.

port_loop(Port) ->
    receive
        {Port, {data, Line}} ->
            case Line of
                <<"PCM ", _/binary>> -> h248_media:handle_pcm(Line);
                <<"EVENT hook=", H/binary>> ->
                    hook_event(binary_to_integer(strip_nl(H)));
                _ -> io:format("h248_mg: fxs ~s", [Line])
            end,
            port_loop(Port);
        {cmd, Cmd} ->
            port_command(Port, Cmd ++ "\n"),
            port_loop(Port);
        {Port, closed} -> ok;
        _ -> port_loop(Port)
    end.

dtmf_event(Digit) ->
    io:format("h248_mg: DTMF ~c~n", [Digit]),
    Params = [#'EventParameter'{eventParameterName = "digit",
                                  value = [Digit]}],
    send_event({packageName, "D"}, Params).

hook_event(Hook) ->
    io:format("h248_mg: hook ~p~n", [Hook]),
    EventName = {packageName, "al"},
    Params = [#'EventParameter'{eventParameterName = "hook",
                                  value = integer_to_list(Hook)}],
    send_event(EventName, Params).

strip_nl(B) ->
    binary:replace(binary:replace(B, <<"\r">>, <<>>), <<"\n">>, <<>>).

send_event(EventName, Params) ->
    case {ets:lookup(h248_terms, conn), ets:match_object(h248_terms, {{term, '_'}, media, '_', '_', '_', '_'})} of
        {[{conn, ConnHandle}], [{TermKey, media, _Pid, _Ip, _Port, ContextId} | _]} ->
            {term, TID} = TermKey,
            Event = #'ObservedEvent'{
                eventName = EventName,
                eventParList = Params},
            Notify = #'NotifyRequest'{
                terminationID = [TID],
                observedEventsDescriptor = #'ObservedEventsDescriptor'{
                    requestId = 1,
                    observedEventLst = [Event]}},
            CR = #'CommandRequest'{command = {notifyReq, Notify}},
            AR = #'ActionRequest'{contextId = ContextId, commandRequests = [CR]},
            catch megaco:cast(ConnHandle, [AR], []),
            ok;
        _ ->
            io:format("h248_mg: no termination for event~n"),
            ok
    end.

fxs_cmd(Cmd) ->
    case whereis(h248_fxs) of
        undefined -> ok;
        Pid -> Pid ! {cmd, Cmd}, ok
    end.

handle_connect(_Handle, _Info) -> {ok, []}.
handle_disconnect(_Handle, _Reason, _Info) -> ok.
handle_syntax_error(_Handle, _Error, _Info) -> ok.
handle_message_error(_Handle, _Error, _Info) -> ok.

handle_trans_request(ConnHandle, _Proto, [AR]) ->
    ContextId = AR#'ActionRequest'.contextId,
    case AR#'ActionRequest'.commandRequests of
        [CR] ->
            case CR#'CommandRequest'.command of
                {serviceChangeReq, Req} ->
                    Rep = service_change_reply(ConnHandle, Req),
                    {discard_ack,
                     [#'ActionReply'{contextId = ContextId,
                                     commandReply = [{serviceChangeReply, Rep}]}]};
                {addReq, Amm} ->
                    fxs_cmd("RING ON"),
                    add_rtp_termination(ContextId, Amm),
                    amm_reply(ContextId, addReply, Amm);
                {modifyReq, Amm} ->
                    fxs_cmd("LINEFEED 2"),
                    amm_reply(ContextId, modifyReply, Amm);
                {subtractReq, Amm} ->
                    fxs_cmd("RING OFF"),
                    fxs_cmd("LINEFEED 1"),
                    del_rtp_termination(Amm),
                    amm_reply(ContextId, subtractReply, Amm);
                _ ->
                    not_implemented(ContextId)
            end;
        _ -> not_implemented(ContextId)
    end;
handle_trans_request(_ConnHandle, _Proto, _Requests) ->
    ED = #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
                             errorText = "Only one action request is supported"},
    {discard_ack, ED}.

service_change_reply(ConnHandle, SCR) ->
    TermId = SCR#'ServiceChangeRequest'.terminationID,
    case TermId of
        [?megaco_root_termination_id] ->
            MyMid = ConnHandle#megaco_conn_handle.local_mid,
            SCP = SCR#'ServiceChangeRequest'.serviceChangeParms,
            Res = {serviceChangeResParms,
                   #'ServiceChangeResParm'{serviceChangeMgcId = MyMid,
                                           serviceChangeAddress =
                                               SCP#'ServiceChangeParm'.serviceChangeAddress,
                                           serviceChangeProfile =
                                               SCP#'ServiceChangeParm'.serviceChangeProfile}},
            #'ServiceChangeReply'{terminationID = TermId,
                                  serviceChangeResult = Res};
        _ ->
            #'ServiceChangeReply'{terminationID = TermId,
                                  serviceChangeResult =
                                      {errorDescriptor,
                                       #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
                                                          errorText = "Only root supported"}}}
    end.

add_rtp_termination(ContextId, Amm) ->
    TID = Amm#'AmmRequest'.terminationID,
    case ets:lookup(h248_terms, {term, TID}) of
        [] ->
            case find_remote(Amm) of
                {ok, Ip, Port} ->
                    case h248_media:start(Ip, Port) of
                        {ok, Pid} ->
                            ets:insert(h248_terms, {{term, TID}, media, Pid, Ip, Port, ContextId});
                        Other ->
                            io:format("h248_mg: media open failed: ~p~n", [Other])
                    end;
                not_found ->
                    io:format("h248_mg: no remote SDP for ~p~n", [TID])
            end;
        _ -> ok
    end.

del_rtp_termination(Amm) ->
    TID = Amm#'AmmRequest'.terminationID,
    case ets:lookup(h248_terms, {term, TID}) of
        [{_, media, _Pid, _Ip, _Port}] ->
            catch h248_media:stop(),
            ets:delete(h248_terms, {term, TID});
        [] -> ok
    end.

find_remote(Term) ->
    Bins = collect_bins(Term, []),
    find_sdp_remote(Bins).

collect_bins(B, Acc) when is_binary(B) -> [B | Acc];
collect_bins(T, Acc) when is_tuple(T) -> collect_bins(tuple_to_list(T), Acc);
collect_bins([H | T], Acc) -> collect_bins(T, collect_bins(H, Acc));
collect_bins(_, Acc) -> Acc.

find_c([]) -> not_found;
find_c([B | Rest]) ->
    case binary:match(B, <<"c=IN IP4 ">>) of
        {Pos, Len} ->
            Tail = binary:part(B, Pos + Len, byte_size(B) - Pos - Len),
            [Ip | _] = binary:split(Tail, [<<"\r">>, <<"\n">>, <<" ">>], [global]),
            {ok, binary_to_list(Ip)};
        nomatch -> find_c(Rest)
    end.

find_m([]) -> not_found;
find_m([B | Rest]) ->
    case binary:match(B, <<"m=audio ">>) of
        {Pos, Len} ->
            Tail = binary:part(B, Pos + Len, byte_size(B) - Pos - Len),
            [PortBin | _] = binary:split(Tail, <<" ">>, [global]),
            {ok, binary_to_integer(PortBin)};
        nomatch -> find_m(Rest)
    end.

find_sdp_remote(Bins) ->
    case {find_c(Bins), find_m(Bins)} of
        {{ok, Ip}, {ok, Port}} -> {ok, Ip, Port};
        _ -> not_found
    end.

amm_reply(ContextId, Tag, Amm) ->
    TID = Amm#'AmmRequest'.terminationID,
    Reply = #'AmmsReply'{terminationID = TID},
    {discard_ack,
     [#'ActionReply'{contextId = ContextId,
                     commandReply = [{Tag, Reply}]}]}.

not_implemented(ContextId) ->
    ED = #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
                             errorText = "Termination mapping not implemented"},
    {discard_ack, [#'ActionReply'{contextId = ContextId,
                                 errorDescriptor = ED}]}.

handle_trans_long_request(_Handle, _Proto, _Req) ->
    {discard_ack, #'ErrorDescriptor'{errorCode = ?megaco_not_implemented,
                                     errorText = "Long requests not implemented"}}.
handle_trans_reply(_Handle, _Reply, _Res, _Info) -> ok.
handle_trans_ack(_Handle, _Ack, _Res, _Info) -> ok.
handle_unexpected_trans(_Handle, _Transaction, _Info) -> ok.
handle_trans_request_abort(_Handle, _Transaction, _Reason, _Info) -> ok.
