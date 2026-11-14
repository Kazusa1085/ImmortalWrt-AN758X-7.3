%% Minimal software DTMF detector for 8 kHz PCM blocks.
-module(h248_dtmf).
-export([detect/1, power/2]).

-define(RATE, 8000).

detect(Samples) when length(Samples) >= 80 ->
    Low = [{F, power(Samples, F)} || F <- [697, 770, 852, 941]],
    High = [{F, power(Samples, F)} || F <- [1209, 1336, 1477, 1633]],
    {LF, LP} = lists:last(lists:keysort(2, Low)),
    {HF, HP} = lists:last(lists:keysort(2, High)),
    Total = lists:sum([P || {_, P} <- Low ++ High]),
    case (LP > 0.08 * Total) andalso (HP > 0.08 * Total) andalso
         (LP > 2 * second_high(Low)) andalso (HP > 2 * second_high(High)) of
        true -> digit(LF, HF);
        false -> none
    end;
detect(_) -> none.

power(Samples, Freq) ->
    Coeff = 2.0 * math:cos(2.0 * math:pi() * Freq / ?RATE),
    {Q1, Q2} = lists:foldl(
        fun(S, {A, B}) -> {Coeff * A - B + S, A} end,
        {0.0, 0.0}, Samples),
    Q1 * Q1 + Q2 * Q2 - Coeff * Q1 * Q2.

second_high(List) ->
    case lists:reverse(lists:keysort(2, List)) of
        [_, {_, P} | _] -> P;
        _ -> 0
    end.

digit(697, 1209) -> $1;
digit(697, 1336) -> $2;
digit(697, 1477) -> $3;
digit(770, 1209) -> $4;
digit(770, 1336) -> $5;
digit(770, 1477) -> $6;
digit(852, 1209) -> $7;
digit(852, 1336) -> $8;
digit(852, 1477) -> $9;
digit(941, 1336) -> $0;
digit(941, 1209) -> $*;
digit(941, 1477) -> $#;
digit(_, _) -> none.
