%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_external_mk).
-moduledoc """
Render the Buildroot `external.mk` file for one selected target plan.

The generator includes root-level and per-package `.mk` files discovered under
each nugget's Buildroot packages path, preserving deterministic target-topology
order and deterministic alphabetical traversal within each nugget.
""".


%=== EXPORTS ===================================================================

-export([generate/2]).
-export([generate/3]).


%=== API FUNCTIONS =============================================================

-doc """
Build `external.mk` content for one selected target.
""".
-spec generate(smelterl:nugget_topology_order(), smelterl:motherlode()) ->
    {ok, iodata()} | {error, term()}.
generate(Topology, Motherlode) ->
    maybe
        {ok, Packages} ?= collect_packages(Topology, Motherlode),
        smelterl_template:render(
            external_mk,
            #{
                packages => Packages
            }
        )
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Render `external.mk` and write it to one open IO device.
""".
-spec generate(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    file:io_device()
) ->
    ok | {error, term()}.
generate(Topology, Motherlode, Out) ->
    maybe
        {ok, Content} ?= generate(Topology, Motherlode),
        smelterl_file:write_iodata(Out, Content)
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

collect_packages(Topology, Motherlode) ->
    collect_packages(Topology, Motherlode, []).

collect_packages([], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
collect_packages([NuggetId | Rest], Motherlode, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, Includes} ?= nugget_includes(NuggetId, Nugget),
        Acc1 =
            case Includes of
                [] ->
                    Acc0;
                _ ->
                    [package_template_data(NuggetId, Nugget, Includes) | Acc0]
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

nugget_includes(NuggetId, Nugget) ->
    maybe
        {ok, PackagesRelPath} ?= packages_relpath(NuggetId, Nugget),
        case PackagesRelPath of
            undefined ->
                {ok, []};
            _ ->
                collect_package_includes(NuggetId, Nugget, PackagesRelPath)
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

collect_package_includes(NuggetId, Nugget, PackagesRelPath) ->
    PackagesDir = smelterl_file:resolve_path(PackagesRelPath, nugget_dir(Nugget)),
    maybe
        ok ?= ensure_directory_exists(NuggetId, PackagesDir),
        {ok, Entries} ?= list_directory(NuggetId, PackagesDir),
        {ok, RootInclude} ?= root_external_mk(Nugget, PackagesDir, PackagesRelPath),
        {ok, PackageIncludes} ?= package_includes(
            NuggetId,
            Nugget,
            PackagesDir,
            PackagesRelPath,
            lists:sort(Entries)
        ),
        {ok, maybe_cons(RootInclude, PackageIncludes)}
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

root_external_mk(Nugget, PackagesDir, PackagesRelPath) ->
    RootMkPath = filename:join(to_list(PackagesDir), "external.mk"),
    case filelib:is_regular(RootMkPath) of
        true ->
            {ok, include_path(Nugget, filename:join(to_list(PackagesRelPath), "external.mk"))};
        false ->
            {ok, undefined}
    end.

package_includes(_NuggetId, _Nugget, _PackagesDir, _PackagesRelPath, []) ->
    {ok, []};
package_includes(NuggetId, Nugget, PackagesDir, PackagesRelPath, [Entry | Rest]) ->
    EntryDir = filename:join(to_list(PackagesDir), Entry),
    case filelib:is_dir(EntryDir) of
        false ->
            package_includes(NuggetId, Nugget, PackagesDir, PackagesRelPath, Rest);
        true ->
            maybe
                {ok, RestIncludes} ?= package_includes(
                    NuggetId,
                    Nugget,
                    PackagesDir,
                    PackagesRelPath,
                    Rest
                ),
                {ok, EntryIncludes} ?= package_dir_includes(
                    NuggetId,
                    Nugget,
                    PackagesRelPath,
                    EntryDir,
                    Entry
                ),
                {ok, EntryIncludes ++ RestIncludes}
            else
                {error, _} = Error ->
                    Error
            end
    end.

package_dir_includes(NuggetId, Nugget, PackagesRelPath, EntryDir, Entry) ->
    case file:list_dir_all(EntryDir) of
        {ok, PackageEntries} ->
            MkFiles = [
                PackageEntry
             || PackageEntry <- lists:sort(PackageEntries),
                filelib:is_regular(filename:join(EntryDir, PackageEntry)),
                filename:extension(PackageEntry) =:= ".mk"
            ],
            {ok, [
                include_path(
                    Nugget,
                    filename:join([
                        to_list(PackagesRelPath),
                        Entry,
                        PackageFile
                    ])
                )
             || PackageFile <- MkFiles
            ]};
        {error, Reason} ->
            {error,
                {package_dir_unreadable,
                    NuggetId,
                    to_binary(filename:absname(EntryDir)),
                    Reason}}
    end.

include_path(Nugget, RelativePath) ->
    RepoName = atom_to_binary(maps:get(repository, Nugget), utf8),
    NuggetRelPath = maps:get(nugget_relpath, Nugget),
    RelativeBinary = to_binary(RelativePath),
    case NuggetRelPath of
        <<".">> ->
            <<"$(ALLOY_MOTHERLODE)/", RepoName/binary, "/", RelativeBinary/binary>>;
        _ ->
            <<"$(ALLOY_MOTHERLODE)/", RepoName/binary, "/", NuggetRelPath/binary, "/",
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

package_template_data(NuggetId, Nugget, Includes) ->
    #{
        name => atom_to_binary(NuggetId, utf8),
        description => description_text(Nugget),
        includes => [
            #{path => IncludePath}
         || IncludePath <- Includes
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

maybe_cons(undefined, List) ->
    List;
maybe_cons(Value, List) ->
    [Value | List].

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value).

to_list(Value) when is_binary(Value) ->
    unicode:characters_to_list(Value).
