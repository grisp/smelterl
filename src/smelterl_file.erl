%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_file).
-moduledoc """
Generic Smelterl file and path helpers.

This module provides consistent Erlang-term serialization for generated files
and a small set of reusable path helpers for later plan/generate stages.
""".


%=== EXPORTS ===================================================================

-export([format_term/1]).
-export([relativize/2]).
-export([resolve_path/2]).
-export([write_term/2]).


%=== API FUNCTIONS =============================================================

-doc """
Serialize one Erlang term using Alloy's UTF-8 term-file conventions.
""".
-spec format_term(term()) -> iodata().
format_term(Term) ->
    [
        <<"%% coding: utf-8\n">>,
        io_lib:format("~0tp.~n", [Term])
    ].

-doc """
Write one Erlang term to a filesystem path or already-open IO device.
""".
-spec write_term(smelterl:file_path() | file:io_device(), term()) ->
    ok | {error, term()}.
write_term(PathOrDevice, Term) when is_binary(PathOrDevice); is_list(PathOrDevice) ->
    Path = to_list(PathOrDevice),
    Content = unicode:characters_to_binary(format_term(Term)),
    case file:open(Path, [write, binary]) of
        {ok, Device} ->
            Result =
                case file:write(Device, Content) of
                    ok ->
                        ok;
                    {error, Reason} ->
                        {error, {write_failed, Reason}}
                end,
            _ = file:close(Device),
            Result;
        {error, Posix} ->
            {error, {open_failed, to_binary(Path), Posix}}
    end;
write_term(Device, Term) ->
    case catch io:put_chars(Device, format_term(Term)) of
        ok ->
            ok;
        {'EXIT', Reason} ->
            {error, {write_failed, Reason}};
        Error ->
            {error, {write_failed, Error}}
    end.

-doc """
Resolve `Path` against `Base`, normalizing the resulting absolute path.
""".
-spec resolve_path(smelterl:file_path() | string(), smelterl:file_path() | string()) ->
    smelterl:file_path().
resolve_path(Path, Base) ->
    PathString = to_list(Path),
    Resolved =
        case filename:pathtype(PathString) of
            absolute ->
                filename:absname(PathString);
            _Relative ->
                filename:absname(PathString, to_list(Base))
        end,
    to_binary(Resolved).

-doc """
Return `Path` relative to `Base`.
""".
-spec relativize(smelterl:file_path(), smelterl:file_path()) -> smelterl:file_path().
relativize(Path, Base) ->
    PathParts = split_abs_path(Path),
    BaseParts = split_abs_path(Base),
    {Shared, PathRest, BaseRest} = drop_common_prefix(PathParts, BaseParts),
    _ = Shared,
    RelativeParts =
        lists:duplicate(length(BaseRest), <<"..">>) ++ PathRest,
    case RelativeParts of
        [] ->
            <<".">>;
        _ ->
            unicode:characters_to_binary(filename:join([to_list(Part) || Part <- RelativeParts]))
    end.


%=== INTERNAL FUNCTIONS ========================================================

to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
to_list(Path) ->
    Path.

to_binary(Path) when is_binary(Path) ->
    Path;
to_binary(Path) ->
    unicode:characters_to_binary(Path).

split_abs_path(Path) ->
    Parts = filename:split(filename:absname(to_list(Path))),
    [to_binary(Part) || Part <- Parts, Part =/= "/"].

drop_common_prefix([Part | PathRest], [Part | BaseRest]) ->
    {Shared, RemainingPath, RemainingBase} = drop_common_prefix(PathRest, BaseRest),
    {[Part | Shared], RemainingPath, RemainingBase};
drop_common_prefix(PathParts, BaseParts) ->
    {[], PathParts, BaseParts}.
