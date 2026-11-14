%% Minimal SDP parser/encoder for G.711 audio.
-module(h248_sdp).
-export([parse/1, encode/2]).

parse(Bin) when is_binary(Bin) ->
    parse_lines(binary:split(Bin, <<"\r\n">>, [global]), undefined, undefined, undefined).

parse_lines([], Address, Port, Payload) ->
    {ok, #{address => Address, port => Port, payload => Payload}};
parse_lines([Line | Rest], Address, Port, Payload) ->
    case Line of
        <<"c=IN IP4 ", A/binary>> ->
            parse_lines(Rest, A, Port, Payload);
        <<"m=audio ", P/binary>> ->
            Parts = binary:split(P, <<" ">>, [global]),
            NewPort = case Parts of
                [PortBin | _] -> binary_to_integer(PortBin);
                _ -> Port
            end,
            NewPayload = case binary:match(P, <<"RTP/AVP ">>) of
                {Pos, Len} ->
                    Tail = binary:part(P, Pos + Len, byte_size(P) - Pos - Len),
                    [Type | _] = binary:split(Tail, <<" ">>, [global]),
                    binary_to_integer(Type);
                nomatch -> Payload
            end,
            parse_lines(Rest, Address, NewPort, NewPayload);
        _ ->
            %% Look for the first RTP/AVP payload type in the m-line.
            case binary:match(Line, <<"RTP/AVP ">>) of
                {Pos, Len} ->
                    Tail = binary:part(Line, Pos + Len, byte_size(Line) - Pos - Len),
                    [P | _] = binary:split(Tail, <<" ">>, [global]),
                    parse_lines(Rest, Address, Port, binary_to_integer(P));
                nomatch ->
                    parse_lines(Rest, Address, Port, Payload)
            end
    end.

encode(Address, Port) ->
    iolist_to_binary([
        "v=0\r\n",
        "o=- 0 0 IN IP4 ", Address, "\r\n",
        "s=h248-mg\r\n",
        "c=IN IP4 ", Address, "\r\n",
        "t=0 0\r\n",
        "m=audio ", integer_to_list(Port), " RTP/AVP 0 8\r\n",
        "a=rtpmap:0 PCMU/8000\r\n",
        "a=rtpmap:8 PCMA/8000\r\n"
    ]).
