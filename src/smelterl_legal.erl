%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_legal).
-moduledoc """
Parse and export Buildroot `legal-info/` data for Smelterl generate stages.

`parse_legal/1` parses one Buildroot `legal-info/` tree into reusable package
data. `collect_legal/3` merges one or more such trees for manifest
finalization and can optionally write the merged export directory at the same
time. `export_legal/3` is the export-only wrapper over that shared path.
""".

-include_lib("kernel/include/file.hrl").


%=== EXPORTS ===================================================================

-export([parse_legal/1]).
-export([collect_legal/3]).
-export([export_legal/3]).
-export([export_alloy/5]).


%=== API FUNCTIONS =============================================================

-doc """
Parse one Buildroot `legal-info/` directory.
""".
-spec parse_legal(smelterl:file_path()) ->
    {ok, smelterl:br_legal_info()} | {error, term()}.
parse_legal(Path) ->
    LegalPath = absolute_binary_path(Path),
    maybe
        ok ?= ensure_legal_dir(LegalPath),
        {ok, Packages} ?= parse_manifest(LegalPath, <<"manifest.csv">>, target),
        {ok, HostPackages0} ?= parse_manifest(
            LegalPath,
            <<"host-manifest.csv">>,
            host
        ),
        {BuildrootVersion, HostPackages} = extract_buildroot_version(HostPackages0),
        {ok,
            #{
                path => LegalPath,
                br_version => BuildrootVersion,
                packages => Packages,
                host_packages => HostPackages
            }}
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Merge one or more Buildroot `legal-info/` trees for manifest generation.

When `ExportDir` is provided, the merged export is written first and the
returned package/license paths are anchored to that exported tree. When it is
`undefined`, the returned package/license paths are anchored to the original
input legal-info trees.
""".
-spec collect_legal(
    [smelterl:file_path()],
    smelterl:file_path() | undefined,
    boolean()
) ->
    {ok, smelterl:br_legal_info()} | {error, term()}.
collect_legal(BuildrootPaths, ExportDir, IncludeSources) ->
    AbsoluteExportDir =
        case ExportDir of
            undefined ->
                undefined;
            Path ->
                absolute_binary_path(Path)
        end,
    maybe
        ok ?= maybe_ensure_export_dir_absent(AbsoluteExportDir),
        {ok, Inputs} ?= load_legal_inputs(BuildrootPaths, 1, []),
        {ok, BuildrootVersion} ?= merge_buildroot_versions(Inputs),
        {ok, Packages} ?= merge_manifest_package_entries(Inputs, packages),
        {ok, HostPackages} ?= merge_manifest_package_entries(
            Inputs,
            host_packages
        ),
        ok ?= maybe_export_merged_legal(
            Inputs,
            AbsoluteExportDir,
            IncludeSources,
            BuildrootVersion,
            Packages,
            HostPackages
        ),
        {ok,
            #{
                path => manifest_legal_path(Inputs, AbsoluteExportDir),
                br_version => BuildrootVersion,
                packages => manifest_package_entries(Packages, AbsoluteExportDir),
                host_packages =>
                    manifest_package_entries(HostPackages, AbsoluteExportDir)
            }}
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Merge one or more Buildroot `legal-info/` trees into one exported directory.
""".
-spec export_legal(
    [smelterl:file_path()],
    smelterl:file_path(),
    boolean()
) -> ok | {error, term()}.
export_legal(BuildrootPaths, ExportDir, IncludeSources) ->
    case collect_legal(BuildrootPaths, ExportDir, IncludeSources) of
        {ok, _LegalInfo} ->
            ok;
        {error, _} = Error ->
            Error
    end.

-doc """
Export alloy-specific legal metadata and rewrite manifest seed license paths to
the exported tree.
""".
-spec export_alloy(
    smelterl:manifest_seed(),
    smelterl:build_target(),
    #{binary() => binary()},
    smelterl:file_path(),
    boolean()
) ->
    {ok, smelterl:manifest_seed()} | {error, term()}.
export_alloy(ManifestSeed0, Target, ExtraConfig, ExportDir, IncludeSources) ->
    AbsoluteExportDir = absolute_binary_path(ExportDir),
    maybe
        {ok, Nuggets, NuggetRows} ?= export_alloy_nuggets(
            maps:get(nuggets, ManifestSeed0, []),
            Target,
            AbsoluteExportDir,
            IncludeSources
        ),
        {ok, Components, ComponentRows} ?= export_alloy_components(
            maps:get(external_components, ManifestSeed0, []),
            Target,
            ExtraConfig,
            AbsoluteExportDir,
            IncludeSources
        ),
        ok ?= write_alloy_manifest(
            join_os_path(AbsoluteExportDir, <<"alloy-manifest.csv">>),
            NuggetRows ++ ComponentRows
        ),
        ok ?= append_alloy_readme(AbsoluteExportDir, IncludeSources),
        ok ?= write_sha256(AbsoluteExportDir),
        {ok,
            ManifestSeed0#{
                nuggets := Nuggets,
                external_components := Components
            }}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-type legal_input() :: #{
    label := binary(),
    path := smelterl:file_path(),
    readme := binary(),
    br_version := binary(),
    packages := [smelterl:br_package_entry()],
    host_packages := [smelterl:br_package_entry()],
    target_kind := main | auxiliary | input
}.

-type manifest_kind() :: target | host.
-type merged_package_entry() :: #{
    entry := smelterl:br_package_entry(),
    source_path := smelterl:file_path()
}.

-spec ensure_legal_dir(smelterl:file_path()) -> ok | {error, term()}.
ensure_legal_dir(LegalPath) ->
    case file:read_file_info(binary_to_list(LegalPath)) of
        {ok, #file_info{type = directory, access = Access}}
                when Access =:= read; Access =:= read_write ->
            ok;
        {ok, #file_info{type = directory}} ->
            ok;
        {ok, _Info} ->
            {error, {invalid_path, LegalPath, not_directory}};
        {error, Posix} ->
            {error, {invalid_path, LegalPath, Posix}}
    end.

-spec ensure_export_dir_absent(smelterl:file_path()) -> ok | {error, term()}.
ensure_export_dir_absent(Path) ->
    case file:read_file_info(binary_to_list(Path)) of
        {ok, _Info} ->
            {error, {export_exists, Path}};
        {error, enoent} ->
            ok;
        {error, Posix} ->
            {error, {export_exists_check_failed, Path, Posix}}
    end.

-spec maybe_ensure_export_dir_absent(smelterl:file_path() | undefined) ->
    ok | {error, term()}.
maybe_ensure_export_dir_absent(undefined) ->
    ok;
maybe_ensure_export_dir_absent(Path) ->
    ensure_export_dir_absent(Path).

-spec ensure_directory(smelterl:file_path()) -> ok | {error, term()}.
ensure_directory(Path) ->
    case filelib:ensure_dir(filename:join(binary_to_list(Path), "dummy")) of
        ok ->
            ok;
        {error, Posix} ->
            {error, {dir_error, Path, Posix}}
    end.

-spec load_legal_inputs([smelterl:file_path()], pos_integer(), [legal_input()]) ->
    {ok, [legal_input()]} | {error, term()}.
load_legal_inputs([], _Index, Acc) ->
    {ok, lists:reverse(Acc)};
load_legal_inputs([Path | Rest], Index, Acc) ->
    maybe
        {ok, LegalInfo} ?= parse_legal(Path),
        {ok, Readme} ?= read_legal_readme(maps:get(path, LegalInfo)),
        Input = build_legal_input(Index, LegalInfo, Readme),
        load_legal_inputs(Rest, Index + 1, [Input | Acc])
    else
        {error, _} = Error ->
            Error
    end.

-spec read_legal_readme(smelterl:file_path()) -> {ok, binary()} | {error, term()}.
read_legal_readme(LegalPath) ->
    ReadmePath = filename:join(binary_to_list(LegalPath), "README"),
    case file:read_file(ReadmePath) of
        {ok, Content} ->
            {ok, Content};
        {error, Posix} ->
            {error, {missing_readme, LegalPath, Posix}}
    end.

-spec build_legal_input(pos_integer(), smelterl:br_legal_info(), binary()) ->
    legal_input().
build_legal_input(Index, LegalInfo, Readme) ->
    LegalPath = maps:get(path, LegalInfo),
    {TargetKind, Label} = infer_input_label(LegalPath, Index),
    #{
        label => Label,
        path => LegalPath,
        readme => Readme,
        br_version => maps:get(br_version, LegalInfo),
        packages => maps:get(packages, LegalInfo),
        host_packages => maps:get(host_packages, LegalInfo),
        target_kind => TargetKind
    }.

-spec infer_input_label(smelterl:file_path(), pos_integer()) ->
    {main | auxiliary | input, binary()}.
infer_input_label(LegalPath, Index) ->
    case infer_target_id(LegalPath) of
        {main, _TargetId} ->
            {main, <<"main">>};
        {auxiliary, TargetId} ->
            {auxiliary, <<"auxiliary: ", TargetId/binary>>};
        undefined ->
            {
                input,
                unicode:characters_to_binary(
                    io_lib:format("input ~B", [Index])
                )
            }
    end.

-spec infer_target_id(smelterl:file_path()) ->
    {main, binary()} | {auxiliary, binary()} | undefined.
infer_target_id(LegalPath) ->
    Parts = [
        unicode:characters_to_binary(Part)
     || Part <- filename:split(binary_to_list(LegalPath))
    ],
    infer_target_id_parts(Parts).

infer_target_id_parts([<<"targets">>, TargetId, <<"workspace">>, <<"legal-info">> | _Rest]) ->
    case TargetId of
        <<"main">> ->
            {main, TargetId};
        _ ->
            {auxiliary, TargetId}
    end;
infer_target_id_parts([_Part | Rest]) ->
    infer_target_id_parts(Rest);
infer_target_id_parts([]) ->
    undefined.

-spec merge_manifest_package_entries([legal_input()], packages | host_packages) ->
    {ok, [merged_package_entry()]} | {error, term()}.
merge_manifest_package_entries(Inputs, Field) ->
    merge_manifest_package_entries(Inputs, Field, #{}, []).

merge_manifest_package_entries([], _Field, _Seen, Acc) ->
    {ok,
        lists:sort(
            fun compare_manifest_package_entries/2,
            Acc
        )};
merge_manifest_package_entries([Input | Rest], Field, Seen, Acc) ->
    Entries = maps:get(Field, Input),
    SourcePath = maps:get(path, Input),
    case merge_manifest_package_entry_list(
        Entries,
        SourcePath,
        Field,
        Seen,
        Acc
    ) of
        {ok, Seen1, Acc1} ->
            merge_manifest_package_entries(Rest, Field, Seen1, Acc1);
        {error, _} = Error ->
            Error
    end.

-spec merge_manifest_package_entry_list(
    [smelterl:br_package_entry()],
    smelterl:file_path(),
    packages | host_packages,
    #{{binary(), binary()} => merged_package_entry()},
    [merged_package_entry()]
) ->
    {ok, #{{binary(), binary()} => merged_package_entry()}, [merged_package_entry()]} |
    {error, term()}.
merge_manifest_package_entry_list([], _SourcePath, _Field, Seen, Acc) ->
    {ok, Seen, Acc};
merge_manifest_package_entry_list([Entry | Rest], SourcePath, Field, Seen, Acc) ->
    Key = {maps:get(name, Entry), maps:get(version, Entry)},
    MergedEntry = #{entry => Entry, source_path => SourcePath},
    case maps:get(Key, Seen, undefined) of
        undefined ->
            merge_manifest_package_entry_list(
                Rest,
                SourcePath,
                Field,
                maps:put(Key, MergedEntry, Seen),
                [MergedEntry | Acc]
            );
        #{entry := Entry} ->
            merge_manifest_package_entry_list(
                Rest,
                SourcePath,
                Field,
                Seen,
                Acc
            );
        #{entry := Existing} ->
            {error,
                {conflicting_package_entry,
                    Field,
                    maps:get(name, Entry),
                    maps:get(version, Entry),
                    Existing,
                    Entry}}
    end.

-spec compare_manifest_package_entries(
    merged_package_entry(),
    merged_package_entry()
) -> boolean().
compare_manifest_package_entries(
    #{entry := Left},
    #{entry := Right}
) ->
    compare_package_entries(Left, Right).

-spec maybe_export_merged_legal(
    [legal_input()],
    smelterl:file_path() | undefined,
    boolean(),
    binary(),
    [merged_package_entry()],
    [merged_package_entry()]
) -> ok | {error, term()}.
maybe_export_merged_legal(_Inputs, undefined, _IncludeSources, _BuildrootVersion, _Packages, _HostPackages) ->
    ok;
maybe_export_merged_legal(
    Inputs,
    ExportDir,
    IncludeSources,
    BuildrootVersion,
    Packages,
    HostPackages
) ->
    maybe
        ok ?= ensure_directory(ExportDir),
        ok ?= maybe_copy_buildroot_config(Inputs, ExportDir),
        ok ?= copy_tree_set(Inputs, ExportDir, <<"licenses">>),
        ok ?= copy_tree_set(Inputs, ExportDir, <<"host-licenses">>),
        ok ?= maybe_copy_sources(
            IncludeSources,
            Inputs,
            ExportDir
        ),
        ok ?= maybe_write_manifest(
            Inputs,
            filename:join(
                binary_to_list(ExportDir),
                "manifest.csv"
            ),
            target,
            BuildrootVersion,
            merged_entries(Packages)
        ),
        ok ?= maybe_write_manifest(
            Inputs,
            filename:join(
                binary_to_list(ExportDir),
                "host-manifest.csv"
            ),
            host,
            BuildrootVersion,
            merged_entries(HostPackages)
        ),
        ok ?= write_readme(
            filename:join(binary_to_list(ExportDir), "README"),
            Inputs,
            IncludeSources
        ),
        ok ?= write_sha256(ExportDir)
    else
        {error, _} = Error ->
            Error
    end.

-spec merged_entries([merged_package_entry()]) -> [smelterl:br_package_entry()].
merged_entries(Entries) ->
    [
        maps:get(entry, Entry)
     || Entry <- Entries
    ].

-spec manifest_legal_path([legal_input()], smelterl:file_path() | undefined) ->
    smelterl:file_path().
manifest_legal_path(_Inputs, ExportDir) when is_binary(ExportDir) ->
    ExportDir;
manifest_legal_path([#{path := Path} | _Rest], undefined) ->
    Path;
manifest_legal_path([], undefined) ->
    <<>>.

-spec manifest_package_entries(
    [merged_package_entry()],
    smelterl:file_path() | undefined
) -> [smelterl:br_package_entry()].
manifest_package_entries(Entries, ExportDir) ->
    [
        maps:put(
            license_files,
            manifest_license_files(
                maps:get(entry, Entry),
                maps:get(source_path, Entry),
                ExportDir
            ),
            maps:get(entry, Entry)
        )
     || Entry <- Entries
    ].

-spec manifest_license_files(
    smelterl:br_package_entry(),
    smelterl:file_path(),
    smelterl:file_path() | undefined
) -> [smelterl:file_path()].
manifest_license_files(Entry, _SourcePath, ExportDir) when is_binary(ExportDir) ->
    [
        join_os_path(ExportDir, RelativePath)
     || RelativePath <- maps:get(license_files, Entry, [])
    ];
manifest_license_files(Entry, SourcePath, undefined) ->
    [
        join_os_path(SourcePath, RelativePath)
     || RelativePath <- maps:get(license_files, Entry, [])
    ].

-spec merge_buildroot_versions([legal_input()]) -> {ok, binary()} | {error, term()}.
merge_buildroot_versions(Inputs) ->
    Versions = lists:usort([
        Version
     || #{br_version := Version} <- Inputs,
        Version =/= <<>>
    ]),
    case Versions of
        [] ->
            {ok, <<>>};
        [Version] ->
            {ok, Version};
        _ ->
            {error, {conflicting_buildroot_versions, Versions}}
    end.

-spec compare_package_entries(
    smelterl:br_package_entry(),
    smelterl:br_package_entry()
) -> boolean().
compare_package_entries(Left, Right) ->
    package_sort_key(Left) =< package_sort_key(Right).

-spec package_sort_key(smelterl:br_package_entry()) -> tuple().
package_sort_key(Entry) ->
    {
        maps:get(name, Entry),
        maps:get(version, Entry),
        maps:get(license, Entry),
        maps:get(license_files, Entry)
    }.

-spec maybe_copy_buildroot_config([legal_input()], smelterl:file_path()) ->
    ok | {error, term()}.
maybe_copy_buildroot_config([], _ExportDir) ->
    ok;
maybe_copy_buildroot_config(Inputs, ExportDir) ->
    SelectedInput = select_buildroot_config_input(Inputs),
    Source = filename:join(
        binary_to_list(maps:get(path, SelectedInput)),
        "buildroot.config"
    ),
    Destination = filename:join(binary_to_list(ExportDir), "buildroot.config"),
    case file:read_file_info(Source) of
        {ok, _Info} ->
            copy_file_with_validation(Source, Destination);
        {error, enoent} ->
            ok;
        {error, Posix} ->
            {error, {copy_failed, path_to_binary(Source), path_to_binary(Destination), Posix}}
    end.

-spec select_buildroot_config_input([legal_input()]) -> legal_input().
select_buildroot_config_input(Inputs) ->
    case [Input || Input <- Inputs, maps:get(target_kind, Input) =:= main] of
        [MainInput | _Rest] ->
            MainInput;
        [] ->
            lists:last(Inputs)
    end.

-spec copy_tree_set([legal_input()], smelterl:file_path(), binary()) ->
    ok | {error, term()}.
copy_tree_set([], _ExportDir, _Subdir) ->
    ok;
copy_tree_set([Input | Rest], ExportDir, Subdir) ->
    SourceRoot = join_os_path(maps:get(path, Input), Subdir),
    DestinationRoot = join_os_path(ExportDir, Subdir),
    case maybe_copy_tree(SourceRoot, DestinationRoot) of
        ok ->
            copy_tree_set(Rest, ExportDir, Subdir);
        {error, _} = Error ->
            Error
    end.

-spec maybe_copy_sources(boolean(), [legal_input()], smelterl:file_path()) ->
    ok | {error, term()}.
maybe_copy_sources(false, _Inputs, _ExportDir) ->
    ok;
maybe_copy_sources(true, Inputs, ExportDir) ->
    maybe
        ok ?= copy_tree_set(Inputs, ExportDir, <<"sources">>),
        ok ?= copy_tree_set(Inputs, ExportDir, <<"host-sources">>),
        ok
    else
        {error, _} = Error ->
            Error
    end.

-spec maybe_copy_tree(smelterl:file_path(), smelterl:file_path()) ->
    ok | {error, term()}.
maybe_copy_tree(SourceRoot, DestinationRoot) ->
    case file:read_file_info(binary_to_list(SourceRoot)) of
        {ok, #file_info{type = directory}} ->
            copy_tree(SourceRoot, DestinationRoot);
        {error, enoent} ->
            ok;
        {error, Posix} ->
            {error, {copy_failed, SourceRoot, DestinationRoot, Posix}};
        {ok, _Info} ->
            {error, {copy_failed, SourceRoot, DestinationRoot, not_directory}}
    end.

-spec copy_tree(smelterl:file_path(), smelterl:file_path()) -> ok | {error, term()}.
copy_tree(SourceRoot, DestinationRoot) ->
    case ensure_directory(DestinationRoot) of
        ok ->
            Files = lists:sort(
                filelib:fold_files(
                    binary_to_list(SourceRoot),
                    ".*",
                    true,
                    fun(Path, Acc) -> [path_to_binary(Path) | Acc] end,
                    []
                )
            ),
            copy_tree_files(Files, SourceRoot, DestinationRoot);
        {error, _} = Error ->
            Error
    end.

-spec copy_tree_files(
    [smelterl:file_path()],
    smelterl:file_path(),
    smelterl:file_path()
) -> ok | {error, term()}.
copy_tree_files([], _SourceRoot, _DestinationRoot) ->
    ok;
copy_tree_files([SourceFile | Rest], SourceRoot, DestinationRoot) ->
    RelativePath = smelterl_file:relativize(SourceFile, SourceRoot),
    DestinationFile = join_os_path(DestinationRoot, RelativePath),
    case copy_file_with_validation(SourceFile, DestinationFile) of
        ok ->
            copy_tree_files(Rest, SourceRoot, DestinationRoot);
        {error, _} = Error ->
            Error
    end.

-spec copy_file_with_validation(
    smelterl:file_path() | string(),
    smelterl:file_path() | string()
) -> ok | {error, term()}.
copy_file_with_validation(Source0, Destination0) ->
    Source = path_to_binary(Source0),
    Destination = path_to_binary(Destination0),
    maybe
        ok ?= ensure_parent_dir(Destination),
        case file:read_file(binary_to_list(Source)) of
            {ok, Content} ->
                write_or_validate_copy(Source, Destination, Content);
            {error, Posix} ->
                {error, {copy_failed, Source, Destination, Posix}}
        end
    else
        {error, _} = Error ->
            Error
    end.

-spec ensure_parent_dir(smelterl:file_path()) -> ok | {error, term()}.
ensure_parent_dir(Path) ->
    case filelib:ensure_dir(binary_to_list(Path)) of
        ok ->
            ok;
        {error, Posix} ->
            {error, {dir_error, Path, Posix}}
    end.

-spec write_or_validate_copy(
    smelterl:file_path(),
    smelterl:file_path(),
    binary()
) -> ok | {error, term()}.
write_or_validate_copy(Source, Destination, Content) ->
    case file:read_file(binary_to_list(Destination)) of
        {ok, Content} ->
            ok;
        {ok, ExistingContent} ->
            {error,
                {copy_conflict,
                    Source,
                    Destination,
                    {content_mismatch, ExistingContent, Content}}};
        {error, enoent} ->
            case file:write_file(binary_to_list(Destination), Content) of
                ok ->
                    ok;
                {error, Posix} ->
                    {error, {copy_failed, Source, Destination, Posix}}
            end;
        {error, Posix} ->
            {error, {copy_failed, Source, Destination, Posix}}
    end.

-spec maybe_write_manifest(
    [legal_input()],
    string(),
    manifest_kind(),
    binary(),
    [smelterl:br_package_entry()]
) -> ok | {error, term()}.
maybe_write_manifest([], _Path, _ManifestKind, _BuildrootVersion, _Packages) ->
    ok;
maybe_write_manifest(_Inputs, Path, ManifestKind, BuildrootVersion, Packages) ->
    Rows =
        case ManifestKind of
            target ->
                Packages;
            host when BuildrootVersion =:= <<>> ->
                Packages;
            host ->
                [buildroot_package_entry(BuildrootVersion) | Packages]
        end,
    smelterl_file:write_iodata(
        Path,
        render_manifest(ManifestKind, Rows)
    ).

-spec buildroot_package_entry(binary()) -> smelterl:br_package_entry().
buildroot_package_entry(BuildrootVersion) ->
    #{
        name => <<"buildroot">>,
        version => BuildrootVersion,
        license => <<"GPL-2.0+">>,
        license_files => [<<"host-licenses/buildroot/COPYING">>]
    }.

-spec render_manifest(manifest_kind(), [smelterl:br_package_entry()]) -> iodata().
render_manifest(ManifestKind, Packages) ->
    Header =
        render_csv_row([
            <<"PACKAGE">>,
            <<"VERSION">>,
            <<"LICENSE">>,
            <<"LICENSE FILES">>
        ]),
    Rows = [
        render_csv_row(entry_to_csv_fields(ManifestKind, Entry))
     || Entry <- Packages
    ],
    [Header | Rows].

-spec entry_to_csv_fields(manifest_kind(), smelterl:br_package_entry()) ->
    [binary()].
entry_to_csv_fields(ManifestKind, Entry) ->
    Name = maps:get(name, Entry),
    Version = maps:get(version, Entry),
    [
        Name,
        Version,
        maps:get(license, Entry),
        join_csv_license_files(
            manifest_license_files(
                ManifestKind,
                Name,
                Version,
                maps:get(license_files, Entry)
            )
        )
    ].

-spec manifest_license_files(
    manifest_kind(),
    binary(),
    binary(),
    [smelterl:file_path()]
) -> [binary()].
manifest_license_files(ManifestKind, Name, Version, LicenseFiles) ->
    Root = manifest_license_root(ManifestKind, Name, Version),
    [strip_path_prefix(Path, Root) || Path <- LicenseFiles].

-spec manifest_license_root(manifest_kind(), binary(), binary()) -> binary().
manifest_license_root(target, Name, Version) ->
    fallback_license_root(<<"licenses">>, Name, Version);
manifest_license_root(host, Name, Version) ->
    fallback_license_root(<<"host-licenses">>, Name, Version).

-spec strip_path_prefix(binary(), binary()) -> binary().
strip_path_prefix(Path, Prefix) ->
    PrefixWithSlash = <<Prefix/binary, "/">>,
    case Path =:= Prefix of
        true ->
            <<>>;
        false ->
            case binary:match(Path, PrefixWithSlash) of
                {0, _Length} ->
                    binary:part(
                        Path,
                        byte_size(PrefixWithSlash),
                        byte_size(Path) - byte_size(PrefixWithSlash)
                    );
                nomatch ->
                    Path
            end
    end.

-spec join_csv_license_files([binary()]) -> binary().
join_csv_license_files([]) ->
    <<>>;
join_csv_license_files(Files) ->
    unicode:characters_to_binary(string:join([binary_to_list(File) || File <- Files], " ")).

-spec render_csv_row([binary()]) -> iodata().
render_csv_row(Fields) ->
    Escaped = [quote_csv_field(Field) || Field <- Fields],
    [lists:join(<<",">>, Escaped), <<"\n">>].

-spec quote_csv_field(binary()) -> binary().
quote_csv_field(Field) ->
    Escaped = binary:replace(Field, <<"\"">>, <<"\"\"">>, [global]),
    <<"\"", Escaped/binary, "\"">>.

-spec write_readme(smelterl:file_path(), [legal_input()], boolean()) ->
    ok | {error, term()}.
write_readme(Path, Inputs, IncludeSources) ->
    Sections = [
        #{
            title => maps:get(label, Input),
            content => ensure_trailing_newline(maps:get(readme, Input))
        }
     || Input <- Inputs
    ],
    Data = #{
        has_buildroot_sections => Sections =/= [],
        no_buildroot_sections => Sections =:= [],
        buildroot_sections => Sections,
        include_sources => IncludeSources
    },
    smelterl_template:render_to_file(legal_readme, Data, Path).

-spec export_alloy_nuggets(
    [map()],
    smelterl:build_target(),
    smelterl:file_path(),
    boolean()
) -> {ok, [map()], [map()]} | {error, term()}.
export_alloy_nuggets(Nuggets, Target, ExportDir, IncludeSources) ->
    export_alloy_nuggets(Nuggets, Target, ExportDir, IncludeSources, [], []).

export_alloy_nuggets([], _Target, _ExportDir, _IncludeSources, NuggetAcc, RowAcc) ->
    {ok, lists:reverse(NuggetAcc), lists:reverse(RowAcc)};
export_alloy_nuggets(
    [#{id := NuggetId, fields := Fields0} = NuggetEntry | Rest],
    Target,
    ExportDir,
    IncludeSources,
    NuggetAcc,
    RowAcc
) ->
    maybe
        {ok, NuggetDir} ?= target_nugget_dir(NuggetId, Target),
        NuggetKey = artifact_key(NuggetId, maps:get(version, Fields0, undefined)),
        {ok, LicenseFiles} ?= export_license_files(
            maps:get(license_files, Fields0, []),
            ExportDir,
            join_relative_path(<<"alloy-licenses">>, NuggetKey)
        ),
        {ok, SourcePath} ?= maybe_export_nugget_source(
            IncludeSources,
            NuggetDir,
            ExportDir,
            join_relative_path(<<"alloy-sources">>, NuggetKey)
        ),
        Fields = maps:put(license_files, LicenseFiles, Fields0),
        Row = alloy_manifest_row(
            atom_binary(NuggetId),
            maps:get(version, Fields0, undefined),
            maps:get(license, Fields0, undefined),
            relativize_export_paths(LicenseFiles, ExportDir),
            SourcePath
        ),
        export_alloy_nuggets(
            Rest,
            Target,
            ExportDir,
            IncludeSources,
            [NuggetEntry#{fields := Fields} | NuggetAcc],
            [Row | RowAcc]
        )
    else
        {error, _} = Error ->
            Error
    end.

-spec export_alloy_components(
    [map()],
    smelterl:build_target(),
    #{binary() => binary()},
    smelterl:file_path(),
    boolean()
) -> {ok, [map()], [map()]} | {error, term()}.
export_alloy_components(Components, Target, ExtraConfig, ExportDir, IncludeSources) ->
    export_alloy_components(
        Components,
        Target,
        ExtraConfig,
        ExportDir,
        IncludeSources,
        [],
        []
    ).

export_alloy_components(
    [],
    _Target,
    _ExtraConfig,
    _ExportDir,
    _IncludeSources,
    ComponentAcc,
    RowAcc
) ->
    {ok, lists:reverse(ComponentAcc), lists:reverse(RowAcc)};
export_alloy_components(
    [Component0 | Rest],
    Target,
    ExtraConfig,
    ExportDir,
    IncludeSources,
    ComponentAcc,
    RowAcc
) ->
    maybe
        NuggetId = maps:get(nugget, Component0),
        {ok, NuggetDir} ?= target_nugget_dir(NuggetId, Target),
        {ok, NuggetVersion} ?= target_nugget_version(NuggetId, Target),
        ComponentKey = artifact_key(maps:get(id, Component0), maps:get(version, Component0, undefined)),
        LicenseSources = [
            resolve_declared_path(Path, NuggetDir)
         || Path <- maps:get(license_files, Component0, [])
        ],
        {ok, LicenseFiles} ?= export_license_files(
            LicenseSources,
            ExportDir,
            join_relative_path(
                join_relative_path(
                    <<"alloy-licenses">>,
                    artifact_key(NuggetId, NuggetVersion)
                ),
                ComponentKey
            )
        ),
        {ok, SourcePath} ?= maybe_export_component_source(
            IncludeSources,
            Component0,
            NuggetDir,
            source_resolution_context(Target, ExtraConfig),
            ExportDir,
            join_relative_path(
                join_relative_path(
                    <<"alloy-sources">>,
                    artifact_key(NuggetId, NuggetVersion)
                ),
                ComponentKey
            )
        ),
        Component = maps:put(license_files, LicenseFiles, Component0),
        Row = alloy_manifest_row(
            atom_binary(maps:get(id, Component0)),
            maps:get(version, Component0, undefined),
            maps:get(license, Component0, undefined),
            relativize_export_paths(LicenseFiles, ExportDir),
            SourcePath
        ),
        export_alloy_components(
            Rest,
            Target,
            ExtraConfig,
            ExportDir,
            IncludeSources,
            [Component | ComponentAcc],
            [Row | RowAcc]
        )
    else
        {error, _} = Error ->
            Error
    end.

-spec maybe_export_nugget_source(
    boolean(),
    smelterl:file_path(),
    smelterl:file_path(),
    smelterl:file_path()
) -> {ok, binary() | undefined} | {error, term()}.
maybe_export_nugget_source(false, _NuggetDir, _ExportDir, _RelativeDest) ->
    {ok, undefined};
maybe_export_nugget_source(true, NuggetDir, ExportDir, RelativeDest) ->
    case copy_source_item(NuggetDir, ExportDir, RelativeDest) of
        {ok, RelativePath} ->
            {ok, RelativePath};
        {error, _} = Error ->
            Error
    end.

-spec maybe_export_component_source(
    boolean(),
    map(),
    smelterl:file_path(),
    smelterl:config(),
    smelterl:file_path(),
    smelterl:file_path()
) -> {ok, binary() | undefined} | {error, term()}.
maybe_export_component_source(
    false,
    _Component,
    _NuggetDir,
    _Context,
    _ExportDir,
    _RelativeDest
) ->
    {ok, undefined};
maybe_export_component_source(
    true,
    Component,
    NuggetDir,
    Context,
    ExportDir,
    RelativeDest
) ->
    case resolve_component_source(Component, NuggetDir, Context) of
        {ok, undefined} ->
            {ok, undefined};
        {ok, SourcePath} ->
            copy_source_item(SourcePath, ExportDir, RelativeDest);
        {error, _} = Error ->
            Error
    end.

-spec export_license_files(
    [smelterl:file_path()],
    smelterl:file_path(),
    smelterl:file_path()
) -> {ok, [smelterl:file_path()]} | {error, term()}.
export_license_files(LicenseFiles, ExportDir, RelativeBase) ->
    export_license_files(LicenseFiles, ExportDir, RelativeBase, []).

export_license_files([], _ExportDir, _RelativeBase, Acc) ->
    {ok, lists:reverse(Acc)};
export_license_files([Source | Rest], ExportDir, RelativeBase, Acc) ->
    RelativePath = join_relative_path(RelativeBase, path_basename(Source)),
    AbsolutePath = join_os_path(ExportDir, RelativePath),
    case copy_file_with_validation(Source, AbsolutePath) of
        ok ->
            export_license_files(Rest, ExportDir, RelativeBase, [AbsolutePath | Acc]);
        {error, _} = Error ->
            Error
    end.

-spec write_alloy_manifest(smelterl:file_path(), [map()]) -> ok | {error, term()}.
write_alloy_manifest(Path, Rows) ->
    Header = render_csv_row([
        <<"PACKAGE">>,
        <<"VERSION">>,
        <<"LICENSE">>,
        <<"LICENSE FILES">>,
        <<"SOURCE ARCHIVE">>,
        <<"SOURCE SITE">>
    ]),
    Content = [
        Header,
        [
            render_csv_row([
                maps:get(package, Row, <<>>),
                maps:get(version, Row, <<>>),
                maps:get(license, Row, <<>>),
                join_csv_license_files(maps:get(license_files, Row, [])),
                maps:get(source_archive, Row, <<>>),
                <<>>
            ])
         || Row <- Rows
        ]
    ],
    smelterl_file:write_iodata(Path, Content).

-spec alloy_manifest_row(
    binary(),
    binary() | undefined,
    binary() | undefined,
    [binary()],
    binary() | undefined
) -> map().
alloy_manifest_row(Package, Version, License, LicenseFiles, SourcePath) ->
    #{
        package => Package,
        version => optional_binary_value(Version),
        license => optional_binary_value(License),
        license_files => LicenseFiles,
        source_archive => optional_binary_value(SourcePath)
    }.

-spec append_alloy_readme(smelterl:file_path(), boolean()) -> ok | {error, term()}.
append_alloy_readme(ExportDir, IncludeSources) ->
    ReadmePath = join_os_path(ExportDir, <<"README">>),
    case file:read_file(binary_to_list(ReadmePath)) of
        {ok, Content} ->
            Suffix = alloy_readme_suffix(IncludeSources),
            case file:write_file(binary_to_list(ReadmePath), <<Content/binary, Suffix/binary>>) of
                ok ->
                    ok;
                {error, Posix} ->
                    {error, {copy_failed, ReadmePath, ReadmePath, Posix}}
            end;
        {error, Posix} ->
            {error, {copy_failed, ReadmePath, ReadmePath, Posix}}
    end.

-spec alloy_readme_suffix(boolean()) -> binary().
alloy_readme_suffix(true) ->
    <<"\nAlloy-specific additions in this export:\n"
      "- `alloy-manifest.csv` with nugget and external component metadata\n"
      "- `alloy-licenses/` with nugget and external component license texts\n"
      "- `alloy-sources/` with exported nugget and external component sources\n">>;
alloy_readme_suffix(false) ->
    <<"\nAlloy-specific additions in this export:\n"
      "- `alloy-manifest.csv` with nugget and external component metadata\n"
      "- `alloy-licenses/` with nugget and external component license texts\n">>.

-spec source_resolution_context(
    smelterl:build_target(),
    #{binary() => binary()}
) -> smelterl:config().
source_resolution_context(Target, ExtraConfig) ->
    maps:merge(
        maps:from_list(
            [
                {Key, {extra, undefined, Value}}
             || {Key, Value} <- maps:to_list(ExtraConfig)
            ]
        ),
        maps:get(config, Target, #{})
    ).

-spec resolve_component_source(map(), smelterl:file_path(), smelterl:config()) ->
    {ok, smelterl:file_path() | undefined} | {error, term()}.
resolve_component_source(Component, NuggetDir, Context) ->
    case {maps:get(source_dir, Component, undefined), maps:get(source_archive, Component, undefined)} of
        {undefined, undefined} ->
            {ok, undefined};
        {SourceDir, undefined} ->
            resolve_source_spec(SourceDir, NuggetDir, Context);
        {undefined, SourceArchive} ->
            resolve_source_spec(SourceArchive, NuggetDir, Context);
        _ ->
            {error, {invalid_component_source, maps:get(id, Component)}}
    end.

-spec resolve_source_spec(term(), smelterl:file_path(), smelterl:config()) ->
    {ok, smelterl:file_path()} | {error, term()}.
resolve_source_spec({path, PathSpec}, NuggetDir, _Context) ->
    {ok, resolve_declared_path(PathSpec, NuggetDir)};
resolve_source_spec({computed, Template}, NuggetDir, Context) ->
    maybe
        {ok, RawPath} ?= smelterl_template:substitute(Template, Context),
        {ok, Expanded} ?= expand_env_refs(RawPath),
        {ok, resolve_declared_path(Expanded, NuggetDir)}
    else
        {error, _} = Error ->
            Error
    end;
resolve_source_spec({exec, ScriptPath}, NuggetDir, Context) ->
    maybe
        {ok, RawPath} ?= run_source_script(ScriptPath, NuggetDir, Context),
        {ok, Expanded} ?= expand_env_refs(RawPath),
        {ok, resolve_declared_path(Expanded, NuggetDir)}
    else
        {error, _} = Error ->
            Error
    end;
resolve_source_spec(Path, NuggetDir, _Context) when is_binary(Path); is_list(Path) ->
    {ok, resolve_declared_path(Path, NuggetDir)};
resolve_source_spec(Spec, _NuggetDir, _Context) ->
    {error, {invalid_source_spec, Spec}}.

-spec run_source_script(binary(), smelterl:file_path(), smelterl:config()) ->
    {ok, binary()} | {error, term()}.
run_source_script(ScriptPath, NuggetDir, Context) ->
    Script = resolve_declared_path(ScriptPath, NuggetDir),
    case filelib:is_regular(binary_to_list(Script)) of
        false ->
            {error, {script_not_found, Script}};
        true ->
            Port =
                open_port(
                    {spawn_executable, binary_to_list(Script)},
                    [
                        binary,
                        exit_status,
                        stderr_to_stdout,
                        use_stdio,
                        hide,
                        {cd, binary_to_list(NuggetDir)},
                        {env, context_env_pairs(Context)}
                    ]
                ),
            collect_script_output(Port, [])
    end.

-spec collect_script_output(port(), [binary()]) -> {ok, binary()} | {error, term()}.
collect_script_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_script_output(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            {ok, unicode:characters_to_binary(string:trim(iolist_to_binary(lists:reverse(Acc))))};
        {Port, {exit_status, Status}} ->
            {error, {exit_non_zero, Status, iolist_to_binary(lists:reverse(Acc))}}
    end.

-spec context_env_pairs(smelterl:config()) -> [{string(), string()}].
context_env_pairs(Context) ->
    [
        {binary_to_list(Key), binary_to_list(context_value(Value))}
     || {Key, Value} <- maps:to_list(Context)
    ].

-spec context_value(term()) -> binary().
context_value({_Kind, _Origin, Value}) when is_binary(Value) ->
    Value;
context_value(Value) when is_binary(Value) ->
    Value;
context_value(Value) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Value])).

-spec expand_env_refs(binary()) -> {ok, binary()} | {error, term()}.
expand_env_refs(Value) ->
    expand_env_refs(Value, []).

expand_env_refs(<<>>, Acc) ->
    {ok, iolist_to_binary(lists:reverse(Acc))};
expand_env_refs(<<"${", Rest/binary>>, Acc) ->
    case binary:match(Rest, <<"}">>) of
        nomatch ->
            {error, {invalid_env_syntax, <<"${", Rest/binary>>}};
        {EndPos, _} ->
            VarName = binary:part(Rest, 0, EndPos),
            Remaining = binary:part(Rest, EndPos + 1, byte_size(Rest) - EndPos - 1),
            case os:getenv(binary_to_list(VarName)) of
                false ->
                    {error, {unresolved_variable, VarName}};
                EnvValue ->
                    expand_env_refs(Remaining, [EnvValue | Acc])
            end
    end;
expand_env_refs(<<"$", Char, Rest/binary>>, Acc)
  when
    (Char >= $A andalso Char =< $Z) orelse
    (Char >= $a andalso Char =< $z) orelse
    Char =:= $_
->
    {VarChars, Remaining} = take_env_name(Rest, [Char]),
    VarName = iolist_to_binary(lists:reverse(VarChars)),
    case os:getenv(binary_to_list(VarName)) of
        false ->
            {error, {unresolved_variable, VarName}};
        EnvValue ->
            expand_env_refs(Remaining, [EnvValue | Acc])
    end;
expand_env_refs(<<Char/utf8, Rest/binary>>, Acc) ->
    expand_env_refs(Rest, [<<Char/utf8>> | Acc]).

take_env_name(<<Char, Rest/binary>>, Acc)
  when
    (Char >= $A andalso Char =< $Z) orelse
    (Char >= $a andalso Char =< $z) orelse
    (Char >= $0 andalso Char =< $9) orelse
    Char =:= $_
->
    take_env_name(Rest, [Char | Acc]);
take_env_name(Rest, Acc) ->
    {Acc, Rest}.

-spec resolve_declared_path(smelterl:file_path() | string(), smelterl:file_path()) ->
    smelterl:file_path().
resolve_declared_path(Path, BaseDir) ->
    PathBinary = path_to_binary(Path),
    case filename:pathtype(binary_to_list(PathBinary)) of
        absolute ->
            absolute_binary_path(PathBinary);
        _ ->
            absolute_binary_path(join_os_path(BaseDir, PathBinary))
    end.

-spec copy_source_item(
    smelterl:file_path(),
    smelterl:file_path(),
    smelterl:file_path()
) -> {ok, binary()} | {error, term()}.
copy_source_item(SourcePath, ExportDir, RelativeDest) ->
    case file:read_file_info(binary_to_list(SourcePath)) of
        {ok, #file_info{type = directory}} ->
            case copy_tree(SourcePath, join_os_path(ExportDir, RelativeDest)) of
                ok ->
                    {ok, RelativeDest};
                {error, _} = Error ->
                    Error
            end;
        {ok, #file_info{type = regular}} ->
            RelativeFile =
                join_relative_path(RelativeDest, path_basename(SourcePath)),
            AbsoluteFile = join_os_path(ExportDir, RelativeFile),
            case copy_file_with_validation(SourcePath, AbsoluteFile) of
                ok ->
                    {ok, RelativeFile};
                {error, _} = Error ->
                    Error
            end;
        {ok, _Info} ->
            {error, {invalid_source_path, SourcePath}};
        {error, Posix} ->
            {error, {copy_failed, SourcePath, join_os_path(ExportDir, RelativeDest), Posix}}
    end.

-spec target_nugget_dir(smelterl:nugget_id(), smelterl:build_target()) ->
    {ok, smelterl:file_path()} | {error, term()}.
target_nugget_dir(NuggetId, Target) ->
    case lookup_target_nugget(NuggetId, Target) of
        {ok, Nugget} ->
            {ok,
                resolve_declared_path(
                    maps:get(nugget_relpath, Nugget, <<>>),
                    maps:get(repo_path, Nugget)
                )};
        {error, _} = Error ->
            Error
    end.

-spec target_nugget_version(smelterl:nugget_id(), smelterl:build_target()) ->
    {ok, binary() | undefined} | {error, term()}.
target_nugget_version(NuggetId, Target) ->
    case lookup_target_nugget(NuggetId, Target) of
        {ok, Nugget} ->
            {ok, maps:get(version, Nugget, undefined)};
        {error, _} = Error ->
            Error
    end.

-spec lookup_target_nugget(smelterl:nugget_id(), smelterl:build_target()) ->
    {ok, map()} | {error, term()}.
lookup_target_nugget(NuggetId, Target) ->
    case maps:get(NuggetId, maps:get(motherlode, Target, #{}), undefined) of
        undefined ->
            case maps:get(NuggetId, maps:get(nuggets, maps:get(motherlode, Target, #{}), #{}), undefined) of
                undefined ->
                    {error, {unknown_nugget, NuggetId}};
                Nugget ->
                    {ok, Nugget}
            end;
        Nugget ->
            {ok, Nugget}
    end.

-spec relativize_export_paths([smelterl:file_path()], smelterl:file_path()) -> [binary()].
relativize_export_paths(Paths, ExportDir) ->
    [
        smelterl_file:relativize(Path, ExportDir)
     || Path <- Paths
    ].

-spec path_basename(smelterl:file_path()) -> binary().
path_basename(Path) ->
    unicode:characters_to_binary(filename:basename(binary_to_list(Path))).

-spec artifact_key(atom(), binary() | undefined) -> binary().
artifact_key(Name, undefined) ->
    atom_binary(Name);
artifact_key(Name, <<>>) ->
    atom_binary(Name);
artifact_key(Name, Version) when is_atom(Name) ->
    <<(atom_binary(Name))/binary, "-", Version/binary>>;
artifact_key(Name, Version) when is_binary(Name) ->
    <<Name/binary, "-", Version/binary>>.

-spec atom_binary(atom()) -> binary().
atom_binary(Value) ->
    atom_to_binary(Value, utf8).

-spec optional_binary_value(binary() | undefined) -> binary().
optional_binary_value(undefined) ->
    <<>>;
optional_binary_value(Value) ->
    path_to_binary(Value).

-spec ensure_trailing_newline(binary()) -> binary().
ensure_trailing_newline(<<>>) ->
    <<"\n">>;
ensure_trailing_newline(Value) ->
    case binary:last(Value) of
        $\n ->
            Value;
        _ ->
            <<Value/binary, "\n">>
    end.

-spec write_sha256(smelterl:file_path()) -> ok | {error, term()}.
write_sha256(ExportDir) ->
    Files = export_files(ExportDir),
    Lines = [
        sha256_line(ExportDir, RelativePath)
     || RelativePath <- Files
    ],
    smelterl_file:write_iodata(
        filename:join(binary_to_list(ExportDir), "legal-info.sha256"),
        Lines
    ).

-spec export_files(smelterl:file_path()) -> [smelterl:file_path()].
export_files(ExportDir) ->
    lists:sort([
        smelterl_file:relativize(Path, ExportDir)
     || Path <- filelib:fold_files(
            binary_to_list(ExportDir),
            ".*",
            true,
            fun(FilePath, Acc) -> [path_to_binary(FilePath) | Acc] end,
            []
        ),
        smelterl_file:relativize(Path, ExportDir) =/= <<"legal-info.sha256">>
    ]).

-spec sha256_line(smelterl:file_path(), smelterl:file_path()) -> iodata().
sha256_line(ExportDir, RelativePath) ->
    AbsolutePath = join_os_path(ExportDir, RelativePath),
    {ok, Content} = file:read_file(binary_to_list(AbsolutePath)),
    HexDigest = binary_to_hex(crypto:hash(sha256, Content)),
    [HexDigest, <<"  ">>, RelativePath, <<"\n">>].

-spec binary_to_hex(binary()) -> binary().
binary_to_hex(Binary) ->
    unicode:characters_to_binary(
        lists:flatten([
            io_lib:format("~2.16.0b", [Byte])
         || <<Byte>> <= Binary
        ])
    ).

-spec parse_manifest(smelterl:file_path(), binary(), target | host) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_manifest(LegalPath, FileName, ManifestKind) ->
    ManifestPath = filename:join(binary_to_list(LegalPath), binary_to_list(FileName)),
    case file:read_file(ManifestPath) of
        {ok, Content} ->
            parse_manifest_content(
                LegalPath,
                unicode:characters_to_binary(filename:absname(ManifestPath)),
                ManifestKind,
                Content
            );
        {error, Posix} ->
            {error,
                {missing_manifest, LegalPath, {open_failed, FileName, Posix}}}
    end.

-spec parse_manifest_content(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    binary()
) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_manifest_content(LegalPath, ManifestPath, ManifestKind, Content) ->
    Lines = nonempty_lines(Content),
    maybe
        {ok, HeaderLine, DataLines} ?= split_header_and_rows(ManifestPath, Lines),
        {ok, HeaderIndex} ?= parse_header(ManifestPath, HeaderLine),
        parse_rows(
            LegalPath,
            ManifestPath,
            ManifestKind,
            HeaderIndex,
            DataLines,
            2,
            []
        )
    else
        {error, _} = Error ->
            Error
    end.

-spec split_header_and_rows(smelterl:file_path(), [binary()]) ->
    {ok, binary(), [binary()]} | {error, term()}.
split_header_and_rows(_ManifestPath, [Header | Rows]) ->
    {ok, Header, Rows};
split_header_and_rows(ManifestPath, []) ->
    {error, {missing_manifest, parent_legal_path(ManifestPath), {malformed_csv, ManifestPath, empty_file}}}.

-spec parse_header(smelterl:file_path(), binary()) ->
    {ok, #{binary() => pos_integer()}} | {error, term()}.
parse_header(ManifestPath, HeaderLine) ->
    RequiredColumns = [<<"package">>, <<"version">>, <<"license">>, <<"license files">>],
    case parse_csv_line(HeaderLine) of
        {ok, HeaderFields} ->
            HeaderIndex = #{
                normalize_header(Field) => Index
             || {Field, Index} <- lists:zip(
                    HeaderFields,
                    lists:seq(1, length(HeaderFields))
                )
            },
            maybe
                ok ?= ensure_required_columns(
                    parent_legal_path(ManifestPath),
                    ManifestPath,
                    HeaderIndex,
                    RequiredColumns
                ),
                {ok, HeaderIndex}
            else
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error,
                {missing_manifest,
                    parent_legal_path(ManifestPath),
                    {malformed_csv, ManifestPath, {1, Reason}}}}
    end.

-spec ensure_required_columns(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()]
) -> ok | {error, term()}.
ensure_required_columns(_LegalPath, _ManifestPath, _HeaderIndex, []) ->
    ok;
ensure_required_columns(LegalPath, ManifestPath, HeaderIndex, [Column | Rest]) ->
    case maps:is_key(Column, HeaderIndex) of
        true ->
            ensure_required_columns(LegalPath, ManifestPath, HeaderIndex, Rest);
        false ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_column, Column}}}}
    end.

-spec parse_rows(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    #{binary() => pos_integer()},
    [binary()],
    pos_integer(),
    [smelterl:br_package_entry()]
) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_rows(
    _LegalPath,
    _ManifestPath,
    _ManifestKind,
    _HeaderIndex,
    [],
    _LineNumber,
    Acc
) ->
    {ok, lists:reverse(Acc)};
parse_rows(
    LegalPath,
    ManifestPath,
    ManifestKind,
    HeaderIndex,
    [Line | Rest],
    LineNumber,
    Acc
) ->
    case parse_csv_line(Line) of
        {ok, Fields} ->
            maybe
                {ok, Entry} ?=
                    build_package_entry(
                        LegalPath,
                        ManifestPath,
                        ManifestKind,
                        HeaderIndex,
                        Fields,
                        LineNumber
                    ),
                parse_rows(
                    LegalPath,
                    ManifestPath,
                    ManifestKind,
                    HeaderIndex,
                    Rest,
                    LineNumber + 1,
                    [Entry | Acc]
                )
            else
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error,
                {missing_manifest,
                    LegalPath,
                    {malformed_csv, ManifestPath, {LineNumber, Reason}}}}
    end.

-spec build_package_entry(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    #{binary() => pos_integer()},
    [binary()],
    pos_integer()
) ->
    {ok, smelterl:br_package_entry()} | {error, term()}.
build_package_entry(
    LegalPath,
    ManifestPath,
    ManifestKind,
    HeaderIndex,
    Fields,
    LineNumber
) ->
    maybe
        {ok, Name} ?= required_csv_field(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"package">>,
            LineNumber
        ),
        {ok, Version} ?= required_csv_field_allow_empty(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"version">>,
            LineNumber
        ),
        {ok, License} ?= required_csv_field(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"license">>,
            LineNumber
        ),
        LicenseRoot = license_root(LegalPath, ManifestKind, Name, Version),
        LicenseFiles = parse_license_files(
            optional_csv_field(HeaderIndex, Fields, <<"license files">>),
            LicenseRoot
        ),
        {ok,
            #{
                name => Name,
                version => Version,
                license => License,
                license_files => LicenseFiles
            }}
    else
        {error, _} = Error ->
            Error
    end.

-spec required_csv_field(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()],
    binary(),
    pos_integer()
) -> {ok, binary()} | {error, term()}.
required_csv_field(LegalPath, ManifestPath, HeaderIndex, Fields, Column, LineNumber) ->
    case optional_csv_field(HeaderIndex, Fields, Column) of
        undefined ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_field, Column, LineNumber}}}};
        <<>> ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {empty_field, Column, LineNumber}}}};
        Value ->
            {ok, Value}
    end.

-spec required_csv_field_allow_empty(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()],
    binary(),
    pos_integer()
) -> {ok, binary()} | {error, term()}.
required_csv_field_allow_empty(LegalPath, ManifestPath, HeaderIndex, Fields, Column, LineNumber) ->
    case optional_csv_field(HeaderIndex, Fields, Column) of
        undefined ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_field, Column, LineNumber}}}};
        Value ->
            {ok, Value}
    end.

-spec optional_csv_field(#{binary() => pos_integer()}, [binary()], binary()) ->
    binary() | undefined.
optional_csv_field(HeaderIndex, Fields, Column) ->
    Index = maps:get(Column, HeaderIndex),
    case length(Fields) >= Index of
        true ->
            trim_binary(lists:nth(Index, Fields));
        false ->
            undefined
    end.

-spec extract_buildroot_version([smelterl:br_package_entry()]) ->
    {binary(), [smelterl:br_package_entry()]}.
extract_buildroot_version(HostPackages) ->
    extract_buildroot_version(HostPackages, <<>>, []).

extract_buildroot_version([], Version, Acc) ->
    {Version, lists:reverse(Acc)};
extract_buildroot_version([#{name := <<"buildroot">>, version := Version} | Rest], _Prev, Acc) ->
    extract_buildroot_version(Rest, Version, Acc);
extract_buildroot_version([Entry | Rest], Version, Acc) ->
    extract_buildroot_version(Rest, Version, [Entry | Acc]).

-spec parse_license_files(binary() | undefined, smelterl:file_path()) ->
    [smelterl:file_path()].
parse_license_files(undefined, _LicenseRoot) ->
    [];
parse_license_files(Value, LicenseRoot) ->
    Trimmed = trim_binary(Value),
    case Trimmed of
        <<>> ->
            [];
        <<"not saved">> ->
            [];
        <<"unknown">> ->
            [];
        _ ->
            [
                join_relative_path(LicenseRoot, Part)
             || Part <- binary:split(Trimmed, <<" ">>, [global]),
                Part =/= <<>>
            ]
    end.

-spec license_root(
    smelterl:file_path(),
    target | host,
    binary(),
    binary()
) -> smelterl:file_path().
license_root(LegalPath, ManifestKind, Name, Version) ->
    LicenseBase =
        case ManifestKind of
            target -> <<"licenses">>;
            host -> <<"host-licenses">>
        end,
    Candidates = license_root_candidates(LegalPath, LicenseBase, Name, Version),
    choose_existing_license_root(Candidates, fallback_license_root(LicenseBase, Name, Version)).

-spec license_root_candidates(
    smelterl:file_path(),
    smelterl:file_path(),
    binary(),
    binary()
) -> [{smelterl:file_path(), smelterl:file_path()}].
license_root_candidates(LegalPath, LicenseBase, Name, Version) ->
    RelativeCandidates =
        case {Name, Version} of
            {<<"buildroot">>, _} ->
                [join_relative_path(LicenseBase, Name)];
            {_, <<>>} ->
                [join_relative_path(LicenseBase, Name)];
            _ ->
                [
                    join_relative_path(
                        LicenseBase,
                        <<Name/binary, "-", Version/binary>>
                    ),
                    join_relative_path(LicenseBase, Name)
                ]
        end,
    [
        {RelativePath, join_os_path(LegalPath, RelativePath)}
     || RelativePath <- RelativeCandidates
    ].

-spec choose_existing_license_root(
    [{smelterl:file_path(), smelterl:file_path()}],
    smelterl:file_path()
) -> smelterl:file_path().
choose_existing_license_root([], Fallback) ->
    Fallback;
choose_existing_license_root([{RelativePath, FullPath} | Rest], Fallback) ->
    case filelib:is_dir(binary_to_list(FullPath)) of
        true ->
            RelativePath;
        false ->
            choose_existing_license_root(Rest, Fallback)
    end.

-spec fallback_license_root(smelterl:file_path(), binary(), binary()) ->
    smelterl:file_path().
fallback_license_root(LicenseBase, <<"buildroot">>, _Version) ->
    join_relative_path(LicenseBase, <<"buildroot">>);
fallback_license_root(LicenseBase, Name, <<>>) ->
    join_relative_path(LicenseBase, Name);
fallback_license_root(LicenseBase, Name, Version) ->
    join_relative_path(LicenseBase, <<Name/binary, "-", Version/binary>>).

-spec nonempty_lines(binary()) -> [binary()].
nonempty_lines(Content) ->
    [
        strip_cr(Line)
     || Line <- binary:split(Content, <<"\n">>, [global]),
        trim_binary(strip_cr(Line)) =/= <<>>
    ].

-spec parse_csv_line(binary()) -> {ok, [binary()]} | {error, term()}.
parse_csv_line(Line) ->
    parse_csv_chars(binary_to_list(Line), [], [], field_start).

parse_csv_chars([], FieldAcc, FieldsAcc, field_start) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], FieldAcc, FieldsAcc, unquoted) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], FieldAcc, FieldsAcc, quoted_end) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], _FieldAcc, _FieldsAcc, quoted) ->
    {error, unterminated_quote};
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, unquoted) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, quoted_end) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$" | Rest], [], FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [], FieldsAcc, quoted);
parse_csv_chars([$" | Rest], FieldAcc, FieldsAcc, quoted) ->
    case Rest of
        [$" | More] ->
            parse_csv_chars(More, [$" | FieldAcc], FieldsAcc, quoted);
        _ ->
            case quote_closes_field(Rest) of
                true ->
                    parse_csv_chars(Rest, FieldAcc, FieldsAcc, quoted_end);
                false ->
                    parse_csv_chars(Rest, [$" | FieldAcc], FieldsAcc, quoted)
            end
    end;
parse_csv_chars([$" | _Rest], _FieldAcc, _FieldsAcc, unquoted) ->
    {error, unexpected_quote};
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, unquoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, unquoted) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, unquoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, quoted) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, quoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, quoted_end)
        when Char =:= $\s; Char =:= $\t ->
    parse_csv_chars(Rest, FieldAcc, FieldsAcc, quoted_end);
parse_csv_chars(_Chars, _FieldAcc, _FieldsAcc, quoted_end) ->
    {error, trailing_characters_after_quote}.

-spec field_binary([char()]) -> binary().
field_binary(FieldAcc) ->
    trim_binary(unicode:characters_to_binary(lists:reverse(FieldAcc))).

-spec normalize_header(binary()) -> binary().
normalize_header(Value) ->
    unicode:characters_to_binary(
        string:lowercase(binary_to_list(trim_binary(Value)))
    ).

-spec trim_binary(binary()) -> binary().
trim_binary(Value) ->
    trim_trailing_whitespace(trim_leading_whitespace(Value)).

trim_leading_whitespace(<<Char, Rest/binary>>) when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
    trim_leading_whitespace(Rest);
trim_leading_whitespace(Value) ->
    Value.

trim_trailing_whitespace(Value) ->
    trim_trailing_whitespace(Value, byte_size(Value)).

trim_trailing_whitespace(_Value, 0) ->
    <<>>;
trim_trailing_whitespace(Value, Size) ->
    case binary:at(Value, Size - 1) of
        Char when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
            trim_trailing_whitespace(binary:part(Value, 0, Size - 1), Size - 1);
        _ ->
            Value
    end.

-spec strip_cr(binary()) -> binary().
strip_cr(Value) ->
    trim_trailing_whitespace(Value).

-spec parent_legal_path(smelterl:file_path()) -> smelterl:file_path().
parent_legal_path(ManifestPath) ->
    unicode:characters_to_binary(filename:dirname(binary_to_list(ManifestPath))).

-spec absolute_binary_path(smelterl:file_path()) -> smelterl:file_path().
absolute_binary_path(Path) ->
    unicode:characters_to_binary(filename:absname(binary_to_list(Path))).

-spec path_to_binary(smelterl:file_path() | string()) -> smelterl:file_path().
path_to_binary(Path) when is_binary(Path) ->
    Path;
path_to_binary(Path) ->
    unicode:characters_to_binary(Path).

-spec join_relative_path(smelterl:file_path(), smelterl:file_path()) ->
    smelterl:file_path().
join_relative_path(Left, Right) ->
    unicode:characters_to_binary(
        filename:join(binary_to_list(Left), binary_to_list(Right))
    ).

-spec join_os_path(smelterl:file_path(), smelterl:file_path()) -> smelterl:file_path().
join_os_path(Left, Right) ->
    unicode:characters_to_binary(
        filename:join(binary_to_list(Left), binary_to_list(Right))
    ).

-spec quote_closes_field([char()]) -> boolean().
quote_closes_field([]) ->
    true;
quote_closes_field([$, | _Rest]) ->
    true;
quote_closes_field([Char | Rest]) when Char =:= $\s; Char =:= $\t ->
    quote_closes_field(Rest);
quote_closes_field(_Rest) ->
    false.
