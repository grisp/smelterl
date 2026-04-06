%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_vcs).
-moduledoc """
Repository provenance lookup for Smelterl planning.

The lookup prefers a precomputed `.alloy_repo_info` file and falls back to a
real git checkout when one is available.
""".


%=== EXPORTS ===================================================================

-export([info/1]).


%=== API FUNCTIONS =============================================================

-doc """
Return repository provenance for `Path`, or `undefined` when no valid source
of VCS metadata can be found.
""".
-spec info(smelterl:file_path() | string()) -> smelterl:vcs_info() | undefined.
info(Path) ->
    CandidateDirs = candidate_directories(Path),
    case find_alloy_repo_info(CandidateDirs) of
        {ok, Info} ->
            Info;
        not_found ->
            find_git_info(CandidateDirs)
    end.


%=== INTERNAL FUNCTIONS ========================================================

candidate_directories(Path) ->
    AbsolutePath = filename:absname(to_list(Path)),
    Dir =
        case filelib:is_dir(AbsolutePath) of
            true ->
                AbsolutePath;
            false ->
                filename:dirname(AbsolutePath)
        end,
    walk_up(Dir, []).

walk_up("/", Acc) ->
    lists:reverse(["/" | Acc]);
walk_up(Dir, Acc) ->
    Parent = filename:dirname(Dir),
    case Parent =:= Dir of
        true ->
            lists:reverse([Dir | Acc]);
        false ->
            walk_up(Parent, [Dir | Acc])
    end.

find_alloy_repo_info([]) ->
    not_found;
find_alloy_repo_info([Dir | Rest]) ->
    InfoPath = filename:join(Dir, ".alloy_repo_info"),
    case parse_alloy_repo_info(InfoPath) of
        {ok, Info} ->
            {ok, Info};
        _ ->
            find_alloy_repo_info(Rest)
    end.

parse_alloy_repo_info(InfoPath) ->
    case file:read_file(InfoPath) of
        {ok, Content} ->
            parse_alloy_repo_info_content(Content);
        {error, _} ->
            not_found
    end.

parse_alloy_repo_info_content(Content) ->
    Lines = binary:split(Content, <<"\n">>, [global]),
    Parsed = parse_alloy_repo_info_lines(Lines, #{}),
    build_info_from_pairs(Parsed).

parse_alloy_repo_info_lines([], Acc) ->
    Acc;
parse_alloy_repo_info_lines([Line | Rest], Acc0) ->
    Trimmed = trim_binary(Line),
    Acc1 =
        case Trimmed of
            <<>> ->
                Acc0;
            <<"#", _/binary>> ->
                Acc0;
            _ ->
                case binary:match(Trimmed, <<"=">>) of
                    {Pos, 1} ->
                        Key = binary:part(Trimmed, 0, Pos),
                        Value =
                            binary:part(
                                Trimmed,
                                Pos + 1,
                                byte_size(Trimmed) - Pos - 1
                            ),
                        maps:put(Key, Value, Acc0);
                    nomatch ->
                        Acc0
                end
        end,
    parse_alloy_repo_info_lines(Rest, Acc1).

build_info_from_pairs(Pairs) ->
    maybe
        {ok, Name} ?= required_pair(<<"NAME">>, Pairs),
        {ok, Url} ?= required_pair(<<"URL">>, Pairs),
        {ok, Commit} ?= required_pair(<<"COMMIT">>, Pairs),
        {ok, Describe} ?= required_pair(<<"DESCRIBE">>, Pairs),
        {ok, Dirty} ?= dirty_pair(Pairs),
        {ok,
            #{
                name => Name,
                url => Url,
                commit => Commit,
                describe => Describe,
                dirty => Dirty
            }}
    else
        _ ->
            not_found
    end.

required_pair(Key, Pairs) ->
    case maps:get(Key, Pairs, <<>>) of
        <<>> ->
            {error, {missing_pair, Key}};
        Value ->
            {ok, Value}
    end.

dirty_pair(Pairs) ->
    case maps:get(<<"DIRTY">>, Pairs, <<>>) of
        <<"true">> ->
            {ok, true};
        <<"false">> ->
            {ok, false};
        _ ->
            {error, invalid_dirty}
    end.

find_git_info([]) ->
    undefined;
find_git_info([Dir | Rest]) ->
    case is_git_root(Dir) of
        true ->
            git_info(Dir);
        false ->
            find_git_info(Rest)
    end.

is_git_root(Dir) ->
    GitPath = filename:join(Dir, ".git"),
    filelib:is_dir(GitPath) orelse filelib:is_regular(GitPath).

git_info(RepoRoot) ->
    maybe
        {ok, Url} ?= git_output(RepoRoot, ["config", "--get", "remote.origin.url"]),
        {ok, Commit} ?= git_output(RepoRoot, ["rev-parse", "HEAD"]),
        {ok, Describe} ?= git_output(RepoRoot, ["describe", "--always"]),
        {ok, Status} ?= git_output(RepoRoot, ["status", "--porcelain"]),
        #{
            name => unicode:characters_to_binary(filename:basename(RepoRoot)),
            url => Url,
            commit => Commit,
            describe => Describe,
            dirty => trim_binary(Status) =/= <<>>
        }
    else
        _ ->
            undefined
    end.

git_output(RepoRoot, Args) ->
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
                        {args, ["-C", RepoRoot | Args]}
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

trim_binary(Value) when is_binary(Value) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Value))).

to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
to_list(Path) ->
    Path.
