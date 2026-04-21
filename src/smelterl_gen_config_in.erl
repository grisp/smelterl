%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_config_in).
-moduledoc """
Render the Buildroot `Config.in` file for one selected target plan.

The generator declares the plan-carried extra-config keys as Buildroot
environment-backed Kconfig variables and sources every nugget package
`Config.in` file discovered in deterministic target-topology order.
""".


%=== EXPORTS ===================================================================

-export([generate/3]).
-export([generate/4]).


%=== API FUNCTIONS =============================================================

-doc """
Build `Config.in` content for one selected target.
""".
-spec generate(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    [binary()]
) ->
    {ok, iodata()} | {error, term()}.
generate(Topology, Motherlode, ExtraConfigKeys) ->
    maybe
        {ok, NormalizedExtraConfigKeys} ?= normalize_extra_config_keys(ExtraConfigKeys),
        {ok, Packages} ?= collect_packages(Topology, Motherlode),
        smelterl_template:render(
            config_in,
            #{
                extra_config => extra_config_template_data(NormalizedExtraConfigKeys),
                packages => Packages
            }
        )
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Render `Config.in` and write it to one open IO device.
""".
-spec generate(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    [binary()],
    file:io_device()
) ->
    ok | {error, term()}.
generate(Topology, Motherlode, ExtraConfigKeys, Out) ->
    maybe
        {ok, Content} ?= generate(Topology, Motherlode, ExtraConfigKeys),
        smelterl_file:write_iodata(Out, Content)
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

normalize_extra_config_keys(Keys) when is_list(Keys) ->
    Normalized0 = [to_binary(Key) || Key <- Keys],
    Normalized1 = lists:sort(lists:usort(Normalized0)),
    {ok,
        [<<"ALLOY_MOTHERLODE">>] ++ [
            Key
         || Key <- Normalized1, Key =/= <<"ALLOY_MOTHERLODE">>
        ]};
normalize_extra_config_keys(Keys) ->
    {error, {invalid_extra_config_keys, Keys}}.

collect_packages(Topology, Motherlode) ->
    collect_packages(Topology, Motherlode, []).

collect_packages([], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
collect_packages([NuggetId | Rest], Motherlode, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, Sources} ?= nugget_sources(NuggetId, Nugget),
        Acc1 =
            case Sources of
                [] ->
                    Acc0;
                _ ->
                    [package_template_data(NuggetId, Nugget, Sources) | Acc0]
            end,
        collect_packages(Rest, Motherlode, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

lookup_nugget(NuggetId, Motherlode) ->
    Nuggets = maps:get(nuggets, Motherlode, #{}),
    case maps:get(NuggetId, Nuggets, undefined) of
        Nugget when is_map(Nugget) ->
            {ok, Nugget};
        undefined ->
            {error, {missing_nugget_metadata, NuggetId}}
    end.

nugget_sources(NuggetId, Nugget) ->
    maybe
        {ok, PackagesRelPath} ?= packages_relpath(NuggetId, Nugget),
        case PackagesRelPath of
            undefined ->
                {ok, []};
            _ ->
                collect_package_sources(NuggetId, Nugget, PackagesRelPath)
        end
    else
        {error, _} = Error ->
            Error
    end.

packages_relpath(NuggetId, Nugget) ->
    case maps:get(buildroot, Nugget, []) of
        BuildrootSpecs when is_list(BuildrootSpecs) ->
            case proplists:get_value(packages, BuildrootSpecs, undefined) of
                undefined ->
                    {ok, undefined};
                Path when is_binary(Path) ->
                    {ok, Path};
                InvalidPath ->
                    {error, {invalid_packages_path, NuggetId, InvalidPath}}
            end;
        InvalidBuildroot ->
            {error, {invalid_buildroot_metadata, NuggetId, InvalidBuildroot}}
    end.

collect_package_sources(NuggetId, Nugget, PackagesRelPath) ->
    PackagesDir = smelterl_file:resolve_path(PackagesRelPath, nugget_dir(Nugget)),
    maybe
        ok ?= ensure_directory_exists(NuggetId, PackagesDir),
        {ok, Entries} ?= list_directory(NuggetId, PackagesDir),
        {ok, RootConfigSource} ?= root_config_source(
            Nugget,
            PackagesDir,
            PackagesRelPath
        ),
        {ok, PackageSources} ?= package_sources(
            Nugget,
            PackagesDir,
            PackagesRelPath,
            lists:sort(Entries)
        ),
        {ok, maybe_cons(RootConfigSource, PackageSources)}
    else
        {error, _} = Error ->
            Error
    end.

ensure_directory_exists(NuggetId, PackagesDir) ->
    case filelib:is_dir(to_list(PackagesDir)) of
        true ->
            ok;
        false ->
            {error, {missing_packages_dir, NuggetId, PackagesDir}}
    end.

list_directory(NuggetId, PackagesDir) ->
    case file:list_dir_all(to_list(PackagesDir)) of
        {ok, Entries} ->
            {ok, Entries};
        {error, Reason} ->
            {error, {packages_dir_unreadable, NuggetId, PackagesDir, Reason}}
    end.

root_config_source(Nugget, PackagesDir, PackagesRelPath) ->
    RootConfigPath = filename:join(to_list(PackagesDir), "Config.in"),
    case filelib:is_regular(RootConfigPath) of
        true ->
            {ok, root_config_source(Nugget, PackagesRelPath)};
        false ->
            {ok, undefined}
    end.

root_config_source(Nugget, PackagesRelPath) ->
    source_path(Nugget, filename:join(to_list(PackagesRelPath), "Config.in")).

package_sources(_Nugget, _PackagesDir, _PackagesRelPath, []) ->
    {ok, []};
package_sources(Nugget, PackagesDir, PackagesRelPath, [Entry | Rest]) ->
    EntryDir = filename:join(to_list(PackagesDir), Entry),
    case filelib:is_dir(EntryDir) of
        false ->
            package_sources(Nugget, PackagesDir, PackagesRelPath, Rest);
        true ->
            ConfigPath = filename:join(EntryDir, "Config.in"),
            maybe
                {ok, RestSources} ?= package_sources(
                    Nugget,
                    PackagesDir,
                    PackagesRelPath,
                    Rest
                ),
                case filelib:is_regular(ConfigPath) of
                    true ->
                        RelativePath = filename:join([
                            to_list(PackagesRelPath),
                            Entry,
                            "Config.in"
                        ]),
                        {ok, [source_path(Nugget, RelativePath) | RestSources]};
                    false ->
                        {ok, RestSources}
                end
            else
                {error, _} = Error ->
                    Error
            end
    end.

source_path(Nugget, RelativePath) ->
    RepoName = atom_to_binary(maps:get(repository, Nugget), utf8),
    NuggetRelPath = maps:get(nugget_relpath, Nugget),
    RelativeBinary = to_binary(RelativePath),
    case NuggetRelPath of
        <<".">> ->
            <<"$ALLOY_MOTHERLODE/", RepoName/binary, "/", RelativeBinary/binary>>;
        _ ->
            <<"$ALLOY_MOTHERLODE/", RepoName/binary, "/", NuggetRelPath/binary, "/",
              RelativeBinary/binary>>
    end.

nugget_dir(Nugget) ->
    RepoPath = maps:get(repo_path, Nugget),
    NuggetRelPath = maps:get(nugget_relpath, Nugget),
    case NuggetRelPath of
        <<".">> ->
            RepoPath;
        _ ->
            smelterl_file:resolve_path(NuggetRelPath, RepoPath)
    end.

package_template_data(NuggetId, Nugget, Sources) ->
    #{
        name => atom_to_binary(NuggetId, utf8),
        description => description_text(Nugget),
        sources => [
            #{path => SourcePath}
         || SourcePath <- Sources
        ]
    }.

description_text(Nugget) ->
    case maps:get(description, Nugget, undefined) of
        Description when is_binary(Description) ->
            Description;
        _ ->
            case maps:get(name, Nugget, undefined) of
                Name when is_binary(Name) ->
                    Name;
                _ ->
                    <<>>
            end
    end.

extra_config_template_data(Keys) ->
    [
        #{key => Key}
     || Key <- Keys
    ].

maybe_cons(undefined, List) ->
    List;
maybe_cons(Value, List) ->
    [Value | List].

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value).

to_list(Value) when is_binary(Value) ->
    unicode:characters_to_list(Value).
