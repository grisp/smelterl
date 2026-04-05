%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_manifest).
-moduledoc """
Build the deterministic manifest seed carried by the Smelterl plan pipeline.

This module currently implements the plan-stage seed preparation only. The
later generate-stage manifest finalization remains a separate backlog task.
""".


%=== EXPORTS ===================================================================

-export([prepare_seed/7]).


%=== TYPES =====================================================================

-type repo_state() :: #{
    entries := [{smelterl:repo_id(), map()}],
    ids_by_url := #{binary() => smelterl:repo_id()},
    next_suffix_by_base := #{smelterl:repo_id() => non_neg_integer()}
}.


%=== API FUNCTIONS =============================================================

-doc """
Build the deterministic main-target manifest seed from plan-stage inputs.

The returned structure is independent from later runtime environment fields,
Buildroot legal-info parsing, manifest-path relativization, and integrity
computation.
""".
-spec prepare_seed(
    smelterl:nugget_id(),
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    smelterl:config(),
    smelterl:firmware_capabilities(),
    [smelterl:auxiliary_target()],
    smelterl:smelterl_build_info()
) ->
    {ok, smelterl:manifest_seed()} | {error, term()}.
prepare_seed(
    ProductId,
    Topology,
    Motherlode,
    Config,
    Capabilities,
    AuxiliaryMeta,
    BuildInfo
) ->
    maybe
        {ok, ProductNugget} ?= lookup_nugget(ProductId, Motherlode),
        {ok, TargetArch} ?= target_arch_triplet(ProductId, Config),
        {ok, Repositories, NuggetRepoMap, SmelterlRepoId} ?=
            build_repository_seed(Topology, Motherlode, BuildInfo),
        {ok, Nuggets} ?= build_nugget_seed(
            Topology,
            Motherlode,
            NuggetRepoMap
        ),
        {ok, AuxiliaryProducts} ?= build_auxiliary_seed(AuxiliaryMeta),
        {ok, ManifestCapabilities} ?= build_capabilities_seed(Capabilities),
        {ok, SdkOutputs} ?= build_sdk_outputs_seed(
            Capabilities,
            AuxiliaryMeta
        ),
        {ok, ExternalComponents} ?= build_external_components_seed(
            Topology,
            Motherlode
        ),
        {ok,
            #{
                product => ProductId,
                target_arch => TargetArch,
                product_fields => product_fields(ProductNugget),
                repositories => Repositories,
                nugget_repo_map => NuggetRepoMap,
                nuggets => Nuggets,
                auxiliary_products => AuxiliaryProducts,
                capabilities => ManifestCapabilities,
                sdk_outputs => SdkOutputs,
                external_components => ExternalComponents,
                smelterl_repository => SmelterlRepoId
            }}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec target_arch_triplet(smelterl:nugget_id(), smelterl:config()) ->
    {ok, binary()} | {error, term()}.
target_arch_triplet(ProductId, Config) ->
    case maps:get(<<"ALLOY_CONFIG_TARGET_ARCH_TRIPLET">>, Config, undefined) of
        {_Kind, _OriginNuggetId, Value} when is_binary(Value), Value =/= <<>> ->
            {ok, Value};
        undefined ->
            {error, {missing_target_arch_triplet, ProductId}};
        {_Kind, _OriginNuggetId, Value} ->
            {error, {invalid_seed_input, {invalid_target_arch_triplet, ProductId, Value}}}
    end.

-spec product_fields(map()) -> map().
product_fields(ProductNugget) ->
    maybe_put_optional(
        version,
        maps:get(version, ProductNugget, undefined),
        maybe_put_optional(
            description,
            maps:get(description, ProductNugget, undefined),
            maybe_put_optional(name, maps:get(name, ProductNugget, undefined), #{})
        )
    ).

-spec build_repository_seed(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    smelterl:smelterl_build_info()
) ->
    {ok, [{smelterl:repo_id(), map()}], #{smelterl:nugget_id() => smelterl:repo_id() | undefined}, smelterl:repo_id()} |
    {error, term()}.
build_repository_seed(Topology, Motherlode, BuildInfo) ->
    maybe
        {ok, SmelterlRepoInfo, RelPath} ?= validate_build_info(BuildInfo),
        {SmelterlRepoId, RepoState1} = ensure_repository(
            SmelterlRepoInfo,
            optional_nonempty_binary(RelPath),
            initial_repo_state()
        ),
        {ok, RepoState2, NuggetRepoMap} = build_nugget_repo_map(
            Topology,
            Motherlode,
            RepoState1,
            #{}
        ),
        {ok, maps:get(entries, RepoState2), NuggetRepoMap, SmelterlRepoId}
    else
        {error, _} = Error ->
            Error
    end.

-spec validate_build_info(term()) -> {ok, smelterl:vcs_info(), binary()} | {error, term()}.
validate_build_info(
    #{name := Name, relpath := RelPath, repo := RepoInfo}
) when is_binary(Name), is_binary(RelPath) ->
    case validate_vcs_info(RepoInfo) of
        {ok, RepoFields} ->
            {ok, RepoFields#{name => Name}, RelPath};
        {error, _} = Error ->
            Error
    end;
validate_build_info(BuildInfo) ->
    {error, {invalid_build_info, BuildInfo}}.

-spec validate_vcs_info(term()) -> {ok, smelterl:vcs_info()} | {error, term()}.
validate_vcs_info(
    #{
        name := Name,
        url := Url,
        commit := Commit,
        describe := Describe,
        dirty := Dirty
    } = RepoInfo
) when
    is_binary(Name),
    is_binary(Url),
    is_binary(Commit),
    is_binary(Describe),
    is_boolean(Dirty)
->
    {ok, RepoInfo};
validate_vcs_info(RepoInfo) ->
    {error, {invalid_build_info, RepoInfo}}.

-spec initial_repo_state() -> repo_state().
initial_repo_state() ->
    #{
        entries => [],
        ids_by_url => #{},
        next_suffix_by_base => #{}
    }.

-spec build_nugget_repo_map(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    repo_state(),
    #{smelterl:nugget_id() => smelterl:repo_id() | undefined}
) ->
    {ok, repo_state(), #{smelterl:nugget_id() => smelterl:repo_id() | undefined}} |
    {error, term()}.
build_nugget_repo_map([], _Motherlode, RepoState, NuggetRepoMap) ->
    {ok, RepoState, NuggetRepoMap};
build_nugget_repo_map([NuggetId | Rest], Motherlode, RepoState0, NuggetRepoMap0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {RepoId, RepoState1} = maybe_assign_nugget_repo(Nugget, Motherlode, RepoState0),
        build_nugget_repo_map(
            Rest,
            Motherlode,
            RepoState1,
            maps:put(NuggetId, RepoId, NuggetRepoMap0)
        )
    else
        {error, _} = Error ->
            Error
    end.

-spec maybe_assign_nugget_repo(map(), smelterl:motherlode(), repo_state()) ->
    {smelterl:repo_id() | undefined, repo_state()}.
maybe_assign_nugget_repo(Nugget, Motherlode, RepoState0) ->
    RepoKey = maps:get(repository, Nugget, undefined),
    Repositories = maps:get(repositories, Motherlode, #{}),
    case maps:get(RepoKey, Repositories, undefined) of
        undefined ->
            {undefined, RepoState0};
        RepoInfo ->
            {RepoId, RepoState1} = ensure_repository(RepoInfo, undefined, RepoState0),
            {RepoId, RepoState1}
    end.

-spec ensure_repository(smelterl:vcs_info(), binary() | undefined, repo_state()) ->
    {smelterl:repo_id(), repo_state()}.
ensure_repository(RepoInfo, PathInRepo, RepoState0) ->
    Url = maps:get(url, RepoInfo),
    RepoIdsByUrl = maps:get(ids_by_url, RepoState0),
    case maps:get(Url, RepoIdsByUrl, undefined) of
        undefined ->
            {RepoId, RepoState1} = allocate_repo_id(RepoInfo, RepoState0),
            Entry = {
                RepoId,
                maybe_put_optional(
                    path_in_repo,
                    PathInRepo,
                    RepoInfo#{
                        type => git
                    }
                )
            },
            {
                RepoId,
                RepoState1#{
                    entries := maps:get(entries, RepoState1) ++ [Entry],
                    ids_by_url := maps:put(Url, RepoId, RepoIdsByUrl)
                }
            };
        RepoId ->
            {RepoId, RepoState0}
    end.

-spec allocate_repo_id(smelterl:vcs_info(), repo_state()) ->
    {smelterl:repo_id(), repo_state()}.
allocate_repo_id(RepoInfo, RepoState) ->
    BaseId = repo_base_id(RepoInfo),
    NextSuffixes = maps:get(next_suffix_by_base, RepoState),
    Suffix = maps:get(BaseId, NextSuffixes, 1),
    RepoId =
        case Suffix of
            1 -> BaseId;
            _ -> list_to_atom(atom_to_list(BaseId) ++ integer_to_list(Suffix))
        end,
    {
        RepoId,
        RepoState#{
            next_suffix_by_base := maps:put(BaseId, Suffix + 1, NextSuffixes)
        }
    }.

-spec repo_base_id(smelterl:vcs_info()) -> smelterl:repo_id().
repo_base_id(RepoInfo) ->
    Name =
        case repo_name_from_url(maps:get(url, RepoInfo)) of
            <<>> -> maps:get(name, RepoInfo);
            Derived -> Derived
        end,
    binary_to_atom(sanitize_repo_name(Name), utf8).

-spec repo_name_from_url(binary()) -> binary().
repo_name_from_url(Url) ->
    Candidate0 =
        case binary:split(Url, <<"/">>, [global, trim_all]) of
            [] ->
                Url;
            SlashParts ->
                lists:last(SlashParts)
        end,
    Candidate1 =
        case binary:split(Candidate0, <<":">>, [global]) of
            [] ->
                Candidate0;
            ColonParts ->
                lists:last(ColonParts)
        end,
    trim_git_suffix(Candidate1).

-spec trim_git_suffix(binary()) -> binary().
trim_git_suffix(Name) ->
    case binary:split(Name, <<".git">>) of
        [Base, <<>>] -> Base;
        _ -> Name
    end.

-spec sanitize_repo_name(binary()) -> binary().
sanitize_repo_name(Name) ->
    Sanitized =
        << <<(sanitize_repo_char(Char))/utf8>> || <<Char/utf8>> <= Name >>,
    case Sanitized of
        <<>> -> <<"repo">>;
        _ -> Sanitized
    end.

-spec sanitize_repo_char(char()) -> char().
sanitize_repo_char(Char) when Char >= $a, Char =< $z ->
    Char;
sanitize_repo_char(Char) when Char >= $0, Char =< $9 ->
    Char;
sanitize_repo_char($_) ->
    $_;
sanitize_repo_char(Char) when Char >= $A, Char =< $Z ->
    Char + 32;
sanitize_repo_char(_Char) ->
    $_.

-spec build_nugget_seed(
    smelterl:nugget_topology_order(),
    smelterl:motherlode(),
    #{smelterl:nugget_id() => smelterl:repo_id() | undefined}
) ->
    {ok, [map()]} | {error, term()}.
build_nugget_seed(Topology, Motherlode, NuggetRepoMap) ->
    build_nugget_seed(Topology, Motherlode, NuggetRepoMap, []).

build_nugget_seed([], _Motherlode, _NuggetRepoMap, Acc) ->
    {ok, lists:reverse(Acc)};
build_nugget_seed([NuggetId | Rest], Motherlode, NuggetRepoMap, Acc) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        Entry = #{
            id => NuggetId,
            fields => nugget_fields(
                Nugget,
                maps:get(NuggetId, NuggetRepoMap, undefined)
            )
        },
        build_nugget_seed(Rest, Motherlode, NuggetRepoMap, [Entry | Acc])
    else
        {error, _} = Error ->
            Error
    end.

-spec nugget_fields(map(), smelterl:repo_id() | undefined) -> map().
nugget_fields(Nugget, RepoId) ->
    Fields0 = #{category => maps:get(category, Nugget)},
    Fields1 = maybe_put_optional(version, maps:get(version, Nugget, undefined), Fields0),
    Fields2 = maybe_put_optional(repository, RepoId, Fields1),
    Fields3 = maybe_put_optional(provides, maps:get(provides, Nugget, undefined), Fields2),
    Fields4 = maybe_put_optional(license, sbom_field_value(license, Nugget), Fields3),
    maybe_put_optional(
        license_files,
        sbom_field_value(license_files, Nugget),
        Fields4
    ).

-spec build_auxiliary_seed([smelterl:auxiliary_target()]) -> {ok, [map()]}.
build_auxiliary_seed(AuxiliaryMeta) ->
    {ok,
        [
            maybe_put_optional(
                constraints,
                maps:get(constraints, Auxiliary, []),
                #{
                    id => maps:get(id, Auxiliary),
                    root_nugget => maps:get(root_nugget, Auxiliary)
                }
            )
         || Auxiliary <- AuxiliaryMeta
        ]}.

-spec build_capabilities_seed(smelterl:firmware_capabilities()) ->
    {ok, map()} | {error, term()}.
build_capabilities_seed(Capabilities) ->
    {ok,
        #{
            firmware_variants => maps:get(firmware_variants, Capabilities, []),
            selectable_outputs =>
                [maps:get(id, Output) || Output <- maps:get(selectable_outputs, Capabilities, [])],
            firmware_parameters => maps:get(firmware_parameters, Capabilities, [])
        }}.

-spec build_sdk_outputs_seed(
    smelterl:firmware_capabilities(),
    [smelterl:auxiliary_target()]
) ->
    {ok, [map()]}.
build_sdk_outputs_seed(Capabilities, AuxiliaryMeta) ->
    OutputsByTarget = maps:get(sdk_outputs_by_target, Capabilities, #{}),
    TargetIds = [main] ++ [maps:get(id, Auxiliary) || Auxiliary <- AuxiliaryMeta],
    {ok,
        [
            #{
                target => TargetId,
                outputs =>
                    [
                        prune_undefined(#{
                            id => maps:get(id, Output),
                            nugget => maps:get(nugget, Output),
                            name => maps:get(name, Output, undefined),
                            description => maps:get(description, Output, undefined)
                        })
                     || Output <- maps:get(TargetId, OutputsByTarget, [])
                    ]
            }
         || TargetId <- TargetIds
        ]}.

-spec build_external_components_seed(
    smelterl:nugget_topology_order(),
    smelterl:motherlode()
) ->
    {ok, [map()]} | {error, term()}.
build_external_components_seed(Topology, Motherlode) ->
    build_external_components_seed(Topology, Motherlode, #{}, []).

build_external_components_seed([], _Motherlode, _SeenIds, Acc) ->
    {ok, lists:reverse(Acc)};
build_external_components_seed([NuggetId | Rest], Motherlode, SeenIds0, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, SeenIds1, Acc1} ?= collect_external_components(
            NuggetId,
            maps:get(external_components, Nugget, []),
            SeenIds0,
            Acc0
        ),
        build_external_components_seed(Rest, Motherlode, SeenIds1, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

-spec collect_external_components(
    smelterl:nugget_id(),
    term(),
    #{atom() => smelterl:nugget_id()},
    [map()]
) ->
    {ok, #{atom() => smelterl:nugget_id()}, [map()]} | {error, term()}.
collect_external_components(_NuggetId, [], SeenIds, Acc) ->
    {ok, SeenIds, Acc};
collect_external_components(NuggetId, [ComponentSpec | Rest], SeenIds0, Acc0) ->
    maybe
        {ok, ComponentId, ComponentEntry} ?= normalize_external_component(
            NuggetId,
            ComponentSpec
        ),
        ok ?= ensure_unique_component(ComponentId, NuggetId, SeenIds0),
        collect_external_components(
            NuggetId,
            Rest,
            maps:put(ComponentId, NuggetId, SeenIds0),
            [ComponentEntry | Acc0]
        )
    else
        {error, _} = Error ->
            Error
    end;
collect_external_components(NuggetId, Invalid, _SeenIds, _Acc) ->
    {error, {invalid_seed_input, {invalid_external_components, NuggetId, Invalid}}}.

-spec normalize_external_component(smelterl:nugget_id(), term()) ->
    {ok, atom(), map()} | {error, term()}.
normalize_external_component(NuggetId, Props) when is_list(Props) ->
    case proplists:get_value(id, Props, undefined) of
        ComponentId when is_binary(ComponentId), ComponentId =/= <<>> ->
            Entry0 = #{
                id => binary_to_atom(ComponentId, utf8),
                nugget => NuggetId
            },
            Entry1 = maybe_put_optional(name, proplists:get_value(name, Props, undefined), Entry0),
            Entry2 = maybe_put_optional(
                description,
                proplists:get_value(description, Props, undefined),
                Entry1
            ),
            Entry3 = maybe_put_optional(
                version,
                proplists:get_value(version, Props, undefined),
                Entry2
            ),
            Entry4 = maybe_put_optional(
                license,
                proplists:get_value(license, Props, undefined),
                Entry3
            ),
            Entry5 = maybe_put_optional(
                license_files,
                proplists:get_value(license_files, Props, undefined),
                Entry4
            ),
            Entry6 = maybe_put_optional(
                source_dir,
                proplists:get_value(source_dir, Props, undefined),
                Entry5
            ),
            Entry7 = maybe_put_optional(
                source_archive,
                proplists:get_value(source_archive, Props, undefined),
                Entry6
            ),
            {ok, maps:get(id, Entry7), Entry7};
        _ ->
            {error, {invalid_seed_input, {invalid_external_component, NuggetId, Props}}}
    end;
normalize_external_component(NuggetId, Invalid) ->
    {error, {invalid_seed_input, {invalid_external_component, NuggetId, Invalid}}}.

-spec ensure_unique_component(atom(), smelterl:nugget_id(), #{atom() => smelterl:nugget_id()}) ->
    ok | {error, term()}.
ensure_unique_component(ComponentId, NuggetId, SeenIds) ->
    case maps:get(ComponentId, SeenIds, undefined) of
        undefined ->
            ok;
        FirstNuggetId ->
            {error,
                {invalid_seed_input,
                    {duplicate_external_component,
                        ComponentId,
                        FirstNuggetId,
                        NuggetId}}}
    end.

-spec lookup_nugget(smelterl:nugget_id(), smelterl:motherlode()) ->
    {ok, map()} | {error, term()}.
lookup_nugget(NuggetId, Motherlode) ->
    case maps:get(NuggetId, maps:get(nuggets, Motherlode), undefined) of
        undefined ->
            {error, {invalid_seed_input, {unknown_nugget, NuggetId}}};
        Nugget ->
            {ok, Nugget}
    end.

-spec sbom_field_value(atom(), map()) -> term().
sbom_field_value(Field, Nugget) ->
    case maps:get(Field, Nugget, undefined) of
        {_Source, Value} ->
            Value;
        Value ->
            Value
    end.

-spec maybe_put_optional(atom(), term(), map()) -> map().
maybe_put_optional(_Key, undefined, Acc) ->
    Acc;
maybe_put_optional(_Key, [], Acc) ->
    Acc;
maybe_put_optional(Key, Value, Acc) ->
    maps:put(Key, Value, Acc).

-spec optional_nonempty_binary(binary()) -> binary() | undefined.
optional_nonempty_binary(<<>>) ->
    undefined;
optional_nonempty_binary(Value) ->
    Value.

-spec prune_undefined(map()) -> map().
prune_undefined(Map) ->
    maps:filter(
        fun(_Key, Value) ->
            Value =/= undefined
        end,
        Map
    ).
