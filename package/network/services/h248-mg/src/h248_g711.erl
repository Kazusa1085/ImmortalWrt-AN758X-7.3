%% Minimal G.711 mu/A-law codecs.
-module(h248_g711).
-export([encode/2, decode/2]).

-define(BIAS, 132).
-define(CLIP, 32635).

encode(pcmu, Samples) -> list_to_binary([lin2ulaw(S) || S <- Samples]);
encode(pcma, Samples) -> list_to_binary([lin2alaw(S) || S <- Samples]).

decode(pcmu, Bytes) -> [ulaw2lin(B) || <<B>> <= Bytes];
decode(pcma, Bytes) -> [alaw2lin(B) || <<B>> <= Bytes].

lin2ulaw(S0) ->
    S = clip(S0),
    Sign = case S < 0 of true -> 16#80; false -> 0 end,
    A0 = case S < 0 of true -> -S; false -> S end,
    A = A0 + ?BIAS,
    Seg = ulaw_seg(A),
    Mant = (A bsr (Seg + 3)) band 16#0f,
    (bnot(Sign bor (Seg bsl 4) bor Mant)) band 16#ff.

ulaw2lin(B) ->
    U = B bxor 16#ff,
    Sign = U band 16#80,
    Seg = (U bsr 4) band 7,
    Mant = U band 16#0f,
    V = (((Mant bsl 3) + ?BIAS) bsl Seg) - ?BIAS,
    case Sign of 0 -> V; _ -> -V end.

lin2alaw(S0) ->
    S = clip(S0),
    Sign = case S < 0 of true -> 16#80; false -> 0 end,
    A = case S < 0 of true -> -S; false -> S end,
    {Seg, Mant} = case A < 256 of
        true -> {0, (A bsr 4) band 16#0f};
        false -> Sg = alaw_seg(A), {Sg, (A bsr (Sg + 3)) band 16#0f}
    end,
    ((Sign bor (Seg bsl 4) bor Mant) bxor 16#55) band 16#ff.

alaw2lin(B) ->
    A = B bxor 16#55,
    Sign = A band 16#80,
    Seg = (A bsr 4) band 7,
    Mant = A band 16#0f,
    V = case Seg of
        0 -> (Mant bsl 4) + 8;
        _ -> ((Mant bsl 4) + 16#108) bsl (Seg - 1)
    end,
    case Sign of 0 -> V; _ -> -V end.

clip(S) when S > ?CLIP -> ?CLIP;
clip(S) when S < -?CLIP -> -?CLIP;
clip(S) -> S.

ulaw_seg(A) when A >= 16#4000 -> 7;
ulaw_seg(A) when A >= 16#2000 -> 6;
ulaw_seg(A) when A >= 16#1000 -> 5;
ulaw_seg(A) when A >= 16#0800 -> 4;
ulaw_seg(A) when A >= 16#0400 -> 3;
ulaw_seg(A) when A >= 16#0200 -> 2;
ulaw_seg(A) when A >= 16#0100 -> 1;
ulaw_seg(_) -> 0.

alaw_seg(A) when A >= 16#4000 -> 7;
alaw_seg(A) when A >= 16#2000 -> 6;
alaw_seg(A) when A >= 16#1000 -> 5;
alaw_seg(A) when A >= 16#0800 -> 4;
alaw_seg(A) when A >= 16#0400 -> 3;
alaw_seg(A) when A >= 16#0200 -> 2;
alaw_seg(_) -> 1.
