%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_log).
-moduledoc """
Shared stderr reporting helpers for Smelterl modules.

This module centralizes command-visible diagnostics so warnings and errors use
one reporting path instead of ad-hoc `io:format/3` calls spread across the
planner modules.
""".

%=== EXPORTS ===================================================================

-export([debug/2]).
-export([error/2]).
-export([info/2]).
-export([parse_level/1]).
-export([warning/2]).
-export([with_log_level/2]).


%=== TYPES =====================================================================

-type log_level() :: error | warning | info | debug.


%=== API FUNCTIONS =============================================================

-doc """
Format and write one error message to stderr.

The format string is passed directly to `io:format/3`; callers control newline
handling in the same way as a normal `io:format/3` call.
""".
-spec error(string(), [term()]) -> ok.
error(Fmt, Args) ->
    io:format(standard_error, Fmt, Args).

-doc """
Format and write one warning message to stderr.

Warnings are visible at the default log level because they communicate
non-fatal conditions that may still matter to the caller.
""".
-spec warning(string(), [term()]) -> ok.
warning(Fmt, Args) ->
    maybe_write(warning, Fmt, Args).

-doc """
Format and write one informational message to stderr when enabled.

Info messages are suppressed unless the configured log level is `info` or
`debug`.
""".
-spec info(string(), [term()]) -> ok.
info(Fmt, Args) ->
    maybe_write(info, Fmt, Args).

-doc """
Format and write one debug message to stderr when enabled.

Debug messages are suppressed unless the configured log level is `debug`.
""".
-spec debug(string(), [term()]) -> ok.
debug(Fmt, Args) ->
    maybe_write(debug, Fmt, Args).

-doc """
Parse one supported log-level token.
""".
-spec parse_level(term()) -> {ok, log_level()} | error.
parse_level(error) ->
    {ok, error};
parse_level(warning) ->
    {ok, warning};
parse_level(info) ->
    {ok, info};
parse_level(debug) ->
    {ok, debug};
parse_level(Value) when is_binary(Value) ->
    parse_level(binary_to_atom(string:lowercase(Value), utf8));
parse_level(Value) when is_list(Value) ->
    parse_level(unicode:characters_to_binary(Value));
parse_level(_Other) ->
    error.

-doc """
Run `Fun` with the requested log level and restore the previous level after.
""".
-spec with_log_level(log_level(), fun(() -> Result)) -> Result.
with_log_level(Level, Fun) when is_function(Fun, 0) ->
    Previous = application:get_env(smelterl, log_level),
    application:set_env(smelterl, log_level, Level),
    try
        Fun()
    after
        restore_level(Previous)
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec maybe_write(log_level(), string(), [term()]) -> ok.
maybe_write(Level, Fmt, Args) ->
    case should_write(Level) of
        true ->
            io:format(standard_error, Fmt, Args);
        false ->
            ok
    end.

-spec should_write(log_level()) -> boolean().
should_write(Level) ->
    level_value(Level) =< level_value(configured_level()).

-spec configured_level() -> log_level().
configured_level() ->
    case application:get_env(smelterl, log_level) of
        {ok, Level} ->
            case parse_level(Level) of
                {ok, ParsedLevel} -> ParsedLevel;
                error -> warning
            end;
        _ ->
            warning
    end.

-spec restore_level({ok, log_level()} | undefined) -> ok.
restore_level({ok, Level}) ->
    application:set_env(smelterl, log_level, Level);
restore_level(undefined) ->
    application:unset_env(smelterl, log_level).

-spec level_value(log_level()) -> 0..3.
level_value(error) ->
    0;
level_value(warning) ->
    1;
level_value(info) ->
    2;
level_value(debug) ->
    3.
