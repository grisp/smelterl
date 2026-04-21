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
-export([read_app_priv_file/2]).
-export([read_app_priv_term/2]).
-export([resolve_path/2]).
-export([write_iodata/2]).
-export([write_term/2]).


%=== API FUNCTIONS =============================================================

-doc """
Serialize one Erlang term using Alloy's UTF-8 term-file conventions.
""".
-spec format_term(term()) -> iodata().
format_term(Term) ->
    [
        <<"%% coding: utf-8\n">>,
        io_lib:format("~tp.~n", [Term])
    ].

-doc """
Write one Erlang term to a filesystem path or already-open IO device.
""".
-spec write_term(smelterl:file_path() | file:io_device(), term()) ->
    ok | {error, term()}.
write_term(PathOrDevice, Term) when is_binary(PathOrDevice); is_list(PathOrDevice) ->
    write_iodata(PathOrDevice, format_term(Term));
write_term(Device, Term) ->
    write_iodata(Device, format_term(Term)).

-doc """
Write UTF-8 iodata to a filesystem path or already-open IO device.
""".
-spec write_iodata(smelterl:file_path() | file:io_device(), iodata()) ->
    ok | {error, term()}.
write_iodata(PathOrDevice, Content) when is_binary(PathOrDevice); is_list(PathOrDevice) ->
    Path = to_list(PathOrDevice),
    Binary = unicode:characters_to_binary(Content),
    case file:open(Path, [write, binary]) of
        {ok, Device} ->
            Result =
                case file:write(Device, Binary) of
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
write_iodata(Device, Content) ->
    case catch io:put_chars(Device, Content) of
        ok ->
            ok;
        {'EXIT', Reason} ->
            {error, {write_failed, Reason}};
        Error ->
            {error, {write_failed, Error}}
    end.

-doc """
Read one file from an application's `priv` directory.
""".
-spec read_app_priv_file(atom(), smelterl:file_path() | string()) ->
    {ok, binary()} | {error, term()}.
read_app_priv_file(App, RelativePath) ->
    case app_priv_path(App, RelativePath) of
        {ok, Path} ->
            case erl_prim_loader:get_file(to_list(Path)) of
                {ok, Content, _FullName} ->
                    {ok, Content};
                error ->
                    {error, {read_failed, Path, unknown}}
            end;
        {error, _} = Error ->
            Error
    end.

-doc """
Read and parse one Erlang term file from an application's `priv` directory.
""".
-spec read_app_priv_term(atom(), smelterl:file_path() | string()) ->
    {ok, term()} | {error, term()}.
read_app_priv_term(App, RelativePath) ->
    case read_app_priv_file(App, RelativePath) of
        {ok, Content} ->
            parse_term_binary(Content);
        {error, _} = Error ->
            Error
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

app_priv_path(App, RelativePath) ->
    case application:get_env(App, priv_dir) of
        {ok, PrivDir} ->
            {ok, filename:join(PrivDir, to_list(RelativePath))};
        undefined ->
            case code:priv_dir(App) of
                {error, bad_name} ->
                    {error, missing_priv_dir};
                PrivDir ->
                    {ok, filename:join(PrivDir, to_list(RelativePath))}
            end
    end.

parse_term_binary(Content) ->
    Source = unicode:characters_to_list(Content),
    case erl_scan:string(Source) of
        {ok, Tokens, _EndLine} ->
            case erl_parse:parse_term(Tokens) of
                {ok, Term} ->
                    {ok, Term};
                {error, Reason} ->
                    {error, {invalid_term, Reason}}
            end;
        {error, Reason, _EndLine} ->
            {error, {invalid_term, Reason}}
    end.

split_abs_path(Path) ->
    Parts = filename:split(filename:absname(to_list(Path))),
    [to_binary(Part) || Part <- Parts, Part =/= "/"].

drop_common_prefix([Part | PathRest], [Part | BaseRest]) ->
    {Shared, RemainingPath, RemainingBase} = drop_common_prefix(PathRest, BaseRest),
    {[Part | Shared], RemainingPath, RemainingBase};
drop_common_prefix(PathParts, BaseParts) ->
    {[], PathParts, BaseParts}.
