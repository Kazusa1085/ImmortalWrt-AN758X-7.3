%% Minimal H.248/Megaco media-gateway skeleton.
%%
%% The protocol stack is Erlang/OTP megaco.  The callbacks are deliberately
%% small: transport and FXS port integration are layered on top.
-module(h248_mg).
-behaviour(megaco_user).
-export([start/0, stop/0]).
-export([handle_connect/2, handle_disconnect/3,
         handle_syntax_error/3, handle_message_error/3,
         handle_trans_request/3, handle_trans_long_request/3,
         handle_trans_reply/4, handle_trans_ack/4,
         handle_unexpected_trans/3, handle_trans_request_abort/4]).

start() ->
    Mgc = os:getenv("H248_MGC", "127.0.0.1"),
    Port = list_to_integer(os:getenv("H248_MGC_PORT", "2944")),
    Mid = {deviceName, "en75xx-mg"},
    Config = [{user_mod, h248_mg},
              {encoding_mod, megaco_pretty_text_encoder},
              {encoding_config, []},
              {send_mod, megaco_udp}],
    io:format("h248_mg: MGC=~s:~p~n", [Mgc, Port]),
    application:ensure_all_started(megaco),
    case megaco:start_user(Mid, Config) of
        ok ->
            io:format("h248_mg: megaco user started~n"),
            ok;
        Error ->
            io:format("h248_mg: start_user failed: ~p~n", [Error]),
            Error
    end.

stop() ->
    catch megaco:stop_user({deviceName, "en75xx-mg"}),
    ok.

handle_connect(_Handle, _Info) -> {ok, []}.
handle_disconnect(_Handle, _Reason, _Info) -> ok.
handle_syntax_error(_Handle, _Error, _Info) -> ok.
handle_message_error(_Handle, _Error, _Info) -> ok.
handle_trans_request(_Handle, _Request, _Res) -> {error, 1}.
handle_trans_long_request(_Handle, _Request, _Res) -> {error, 1}.
handle_trans_reply(_Handle, _Reply, _Res, _Info) -> ok.
handle_trans_ack(_Handle, _Ack, _Res, _Info) -> ok.
handle_unexpected_trans(_Handle, _Transaction, _Info) -> ok.
handle_trans_request_abort(_Handle, _Transaction, _Reason, _Info) -> ok.
