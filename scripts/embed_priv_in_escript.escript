#!/usr/bin/env escript
%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0
%%! -noshell

main(Args) ->
    RootDir = app_root(),
    case escript_path(Args, RootDir) of
        {ok, EscriptPath} ->
            case embed_priv(EscriptPath, RootDir) of
                ok ->
                    ok;
                {error, Reason} ->
                    io:format(standard_error, "embed_priv_in_escript: ~ts~n", [format_error(Reason)]),
                    halt(1)
            end;
        {error, Reason} ->
            io:format(standard_error, "embed_priv_in_escript: ~ts~n", [format_error(Reason)]),
            halt(2)
    end.

app_root() ->
    filename:dirname(filename:dirname(filename:absname(escript:script_name()))).

escript_path([Path], RootDir) ->
    {ok, filename:absname(Path, RootDir)};
escript_path([], RootDir) ->
    {ok, filename:join([RootDir, "_build", "default", "bin", "smelterl"])};
escript_path(_Args, _RootDir) ->
    {error, usage}.

embed_priv(EscriptPath, RootDir) ->
    case file:read_file(EscriptPath) of
        {ok, SourceBinary} ->
            case split_escript(SourceBinary) of
                {ok, Header, Archive} ->
                    WorkDir = make_temp_dir("smelterl-escript"),
                    TempZip = filename:join(WorkDir, "archive.zip"),
                    case file:write_file(TempZip, Archive) of
                        ok ->
                            case unzip(TempZip, WorkDir) of
                                ok ->
                                    case replace_priv_tree(WorkDir, RootDir) of
                                        ok ->
                                            case repack_archive(WorkDir) of
                                                {ok, RepackedZip} ->
                                                    case file:write_file(
                                                        EscriptPath,
                                                        [Header, RepackedZip]
                                                    ) of
                                                        ok ->
                                                            file:change_mode(
                                                                EscriptPath,
                                                                8#755
                                                            );
                                                        {error, Reason} ->
                                                            {error,
                                                                {write_failed, Reason}}
                                                    end;
                                                {error, _} = Error ->
                                                    Error
                                            end;
                                        {error, _} = Error ->
                                            Error
                                    end;
                                {error, _} = Error ->
                                    Error
                            end;
                        {error, Reason} ->
                            {error, {write_failed, Reason}}
                    end;
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error, {read_failed, Reason}}
    end.

split_escript(Binary) ->
    case binary:match(Binary, <<80, 75, 3, 4>>) of
        {Start, _Length} ->
            Header = binary:part(Binary, 0, Start),
            Archive = binary:part(Binary, Start, byte_size(Binary) - Start),
            {ok, Header, Archive};
        nomatch ->
            {error, missing_zip_archive}
    end.

unzip(ZipPath, WorkDir) ->
    case zip:extract(ZipPath, [{cwd, WorkDir}]) of
        {ok, _Files} ->
            ok;
        {error, Reason} ->
            {error, {zip_extract_failed, Reason}}
    end.

replace_priv_tree(WorkDir, RootDir) ->
    Destination = filename:join([WorkDir, "smelterl", "priv"]),
    Source = filename:join(RootDir, "priv"),
    case file:del_dir_r(Destination) of
        ok ->
            copy_tree(Source, Destination);
        {error, enoent} ->
            copy_tree(Source, Destination);
        {error, Reason} ->
            {error, {remove_priv_failed, Reason}}
    end.

copy_tree(Source, Destination) ->
    ok = filelib:ensure_dir(filename:join(Destination, "dummy")),
    case file:list_dir(Source) of
        {ok, Entries} ->
            copy_entries(Entries, Source, Destination);
        {error, Reason} ->
            {error, {list_dir_failed, Source, Reason}}
    end.

copy_entries([], _Source, _Destination) ->
    ok;
copy_entries([Entry | Rest], Source, Destination) ->
    SourcePath = filename:join(Source, Entry),
    DestinationPath = filename:join(Destination, Entry),
    case filelib:is_dir(SourcePath) of
        true ->
            case copy_tree(SourcePath, DestinationPath) of
                ok ->
                    copy_entries(Rest, Source, Destination);
                {error, _} = Error ->
                    Error
            end;
        false ->
            case copy_file(SourcePath, DestinationPath) of
                ok ->
                    copy_entries(Rest, Source, Destination);
                {error, _} = Error ->
                    Error
            end
    end.

copy_file(Source, Destination) ->
    ok = filelib:ensure_dir(Destination),
    case file:copy(Source, Destination) of
        {ok, _Bytes} ->
            ok;
        {error, Reason} ->
            {error, {copy_failed, Source, Destination, Reason}}
    end.

repack_archive(WorkDir) ->
    ArchivePath = filename:join(WorkDir, "archive-repacked.zip"),
    case zip:create(
        ArchivePath,
        ["smelterl"],
        [{cwd, WorkDir}, {compress, all}, {uncompress, [".beam", ".app"]}]
    ) of
        {ok, _ArchivePath} ->
            file:read_file(ArchivePath);
        {error, Reason} ->
            {error, {zip_create_failed, Reason}}
    end.

make_temp_dir(Prefix) ->
    make_temp_dir(Prefix, 0).

make_temp_dir(Prefix, Attempt) ->
    Suffix =
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([monotonic, positive])) ++ "-" ++
        integer_to_list(Attempt),
    Base = filename:join(os:getenv("TMPDIR", "/tmp"), Prefix ++ "-" ++ Suffix),
    case file:make_dir(Base) of
        ok ->
            Base;
        {error, eexist} ->
            make_temp_dir(Prefix, Attempt + 1);
        {error, Reason} ->
            erlang:error({temp_dir_failed, Base, Reason})
    end.

format_error(usage) ->
    <<"Usage: escript scripts/embed_priv_in_escript.escript [ESCRIPT_PATH]">>;
format_error(missing_zip_archive) ->
    <<"escript does not contain an embedded zip archive">>;
format_error({zip_extract_failed, Reason}) ->
    iolist_to_binary(io_lib:format("failed to extract escript archive: ~tp", [Reason]));
format_error({remove_priv_failed, Reason}) ->
    iolist_to_binary(io_lib:format("failed to replace embedded priv directory: ~tp", [Reason]));
format_error({list_dir_failed, Source, Reason}) ->
    iolist_to_binary(io_lib:format("failed to list ~ts: ~tp", [Source, Reason]));
format_error({copy_failed, Source, Destination, Reason}) ->
    iolist_to_binary(
        io_lib:format("failed to copy ~ts to ~ts: ~tp", [Source, Destination, Reason])
    );
format_error({zip_create_failed, Reason}) ->
    iolist_to_binary(io_lib:format("failed to repack escript archive: ~tp", [Reason]));
format_error({error, Reason}) ->
    format_error(Reason);
format_error(Reason) ->
    iolist_to_binary(io_lib:format("~tp", [Reason])).
