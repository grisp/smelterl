#!/usr/bin/env escript
%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0
%%! -noshell

main(Args) ->
    RootDir = app_root(),
    OutputPath = output_path(Args, RootDir),
    case build_info(RootDir) of
        {ok, BuildInfo} ->
            ok = filelib:ensure_dir(OutputPath),
            ok = file:write_file(OutputPath, format_term(BuildInfo)),
            ok;
        {error, Reason} ->
            io:format(standard_error, "generate_build_info: ~ts~n", [format_error(Reason)]),
            halt(1)
    end.

app_root() ->
    filename:dirname(filename:dirname(filename:absname(escript:script_name()))).

output_path([], RootDir) ->
    filename:join([RootDir, "priv", "build_info.term"]);
output_path([Path], RootDir) ->
    filename:absname(Path, RootDir);
output_path(_Args, _RootDir) ->
    io:put_chars(standard_error, "Usage: escript scripts/generate_build_info.escript [OUTPUT_PATH]\n"),
    halt(2).

build_info(RootDir) ->
    case git_output(RootDir, ["config", "--get", "remote.origin.url"]) of
        {ok, Url} ->
            case git_output(RootDir, ["rev-parse", "HEAD"]) of
                {ok, Commit} ->
                    case git_output(RootDir, ["describe", "--always"]) of
                        {ok, Describe} ->
                            case git_output(RootDir, ["status", "--porcelain"]) of
                                {ok, Status} ->
                                    {ok,
                                        #{
                                            name => <<"smelterl">>,
                                            relpath => <<>>,
                                            repo =>
                                                #{
                                                    name => <<"smelterl">>,
                                                    url => Url,
                                                    commit => Commit,
                                                    describe => Describe,
                                                    dirty => Status =/= <<>>
                                                }
                                        }};
                                {error, _} = Error ->
                                    Error
                            end;
                        {error, _} = Error ->
                            Error
                    end;
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end.

git_output(RootDir, Args) ->
    case os:find_executable("git") of
        false ->
            {error, git_not_found};
        Git ->
            Port =
                open_port(
                    {spawn_executable, Git},
                    [
                        binary,
                        exit_status,
                        stderr_to_stdout,
                        use_stdio,
                        hide,
                        {args, ["-C", RootDir | Args]}
                    ]
                ),
            collect_git_output(Port, [])
    end.

collect_git_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_git_output(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            {ok, trim_binary(iolist_to_binary(lists:reverse(Acc)))};
        {Port, {exit_status, Status}} ->
            {error, {git_failed, Status, trim_binary(iolist_to_binary(lists:reverse(Acc)))}} 
    end.

format_term(Term) ->
    [
        <<"%% coding: utf-8\n">>,
        io_lib:format("~tp.~n", [Term])
    ].

trim_binary(Value) when is_binary(Value) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Value))).

format_error(git_not_found) ->
    <<"git executable not found">>;
format_error({git_failed, Status, Output}) ->
    iolist_to_binary(
        io_lib:format("git exited with status ~B: ~ts", [Status, Output])
    ).
