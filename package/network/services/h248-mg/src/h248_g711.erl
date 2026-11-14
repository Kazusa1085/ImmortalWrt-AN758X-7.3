%% Minimal G.711 mu/A-law codecs.
-module(h248_g711).
-export([encode/2, decode/2]).

encode(pcmu, Samples) -> list_to_binary([lin2ulaw(S) || S <- Samples]);
encode(pcma, Samples) -> list_to_binary([lin2alaw(S) || S <- Samples]).

decode(pcmu, Bytes) -> [ulaw2lin(B) || <<B>> <= Bytes];
decode(pcma, Bytes) -> [alaw2lin(B) || <<B>> <= Bytes].

lin2ulaw(S0) ->
    S = case S0 of N when N > 32767 -> 32767; N when N < -32768 -> -32768; N -> N end,
    Sign = case S < 0 of true -> 16#80; false -> 0 end,
    A = case S < 0 of true -> -S; false -> S end + 132,
    Seg = seg(A),
    Mant = (A bsr (Seg + 3)) band 16#0f,
    (Sign bor ((Seg - 1) bsl 4) bor Mant) band 16#ff.

ulaw2lin(B) ->
    U = B bxor 16#ff,
    Sign = U band 16#80,
    Seg = (U bsr 4) band 7,
    Mant = U band 16#0f,
    V = ((Mant bsl 3) + 132) bsl Seg,
    case Sign of 0 -> 132 - V; _ -> V - 132 end.

lin2alaw(S0) ->
    S = case S0 of N when N > 32767 -> 32767; N when N < -32768 -> -32768; N -> N end,
    Sign = case S < 0 of true -> 16#80; false -> 0 end,
    A = case S < 0 of true -> -S; false -> S end,
    Seg = case A < 256 of true -> 0; false -> seg(A) end,
    Mant = case Seg of 0 -> (A bsr 4) band 16#0f; _ -> (A bsr (Seg + 3)) band 16#0f end,
    (Sign bor (Seg bsl 4) bor Mant) bxor 16#55.

alaw2lin(B) ->
    A = B bxor 16#55,
    Sign = A band 16#80,
    Seg = (A bsr 4) band 7,
    Mant = A band 16#0f,
    V = case Seg of 0 -> Mant * 16 + 8; _ -> ((Mant * 16 + 8) bsl (Seg - 1)) + 256 end,
    case Sign of 0 -> V; _ -> -V end.

seg(A) when A < 256 -> 0;
seg(A) when A < 512 -> 1;
seg(A) when A < 1024 -> 2;
seg(A) when A < 2048 -> 3;
seg(A) when A < 4096 -> 4;
seg(A) when A < 8192 -> 5;
seg(A) when A < 16384 -> 6;
seg(_) -> 7.
