%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_manifest).
-moduledoc """
Build and finalize the Smelterl SDK manifest.

The plan stage prepares a deterministic manifest seed that is stored in the
build plan. The main-target generate stage finalizes that seed with runtime
environment fields, optional merged Buildroot legal data, relocatable path
rewrites, and integrity metadata before writing `ALLOY_SDK_MANIFEST`.
""".


%=== EXPORTS ===================================================================

-export([prepare_seed/7]).
-export([build_from_seed/4]).
-export([generate/3]).
-export([generate/4]).


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

-doc """
Finalize a plan-carried manifest seed into one in-memory SDK manifest term.
""".
-spec build_from_seed(
    smelterl:manifest_seed(),
    smelterl:br_legal_info() | undefined,
    smelterl:file_path(),
    map()
) ->
    {ok, term()} | {error, term()}.
build_from_seed(Seed, BuildrootLegal, BasePath, RuntimeEnv) ->
    maybe
        ok ?= validate_manifest_seed(Seed),
        {ok, ProductFields} ?= product_section_fields(Seed, RuntimeEnv),
        {ok, BuildEnvironmentFields} ?= build_environment_fields(
            Seed,
            BuildrootLegal,
            RuntimeEnv
        ),
        {ok, Repositories} ?= repository_section_entries(Seed),
        {ok, Nuggets} ?= nugget_section_entries(
            maps:get(nuggets, Seed, []),
            BasePath
        ),
        {ok, AuxiliaryProducts} ?= auxiliary_section_entries(
            maps:get(auxiliary_products, Seed, [])
        ),
        {ok, Capabilities} ?= capabilities_section_fields(
            maps:get(capabilities, Seed, #{})
        ),
        {ok, SdkOutputs} ?= sdk_outputs_section_entries(
            maps:get(sdk_outputs, Seed, [])
        ),
        {ok, BuildrootSections} ?= buildroot_section_entries(
            BuildrootLegal,
            BasePath
        ),
        {ok, ExternalComponents} ?= external_component_section_entries(
            maps:get(external_components, Seed, []),
            BasePath
        ),
        ManifestWithoutIntegrity =
            {sdk_manifest,
                <<"1.0">>,
                ProductFields ++
                    [
                        {build_environment, BuildEnvironmentFields},
                        {repositories, Repositories},
                        {nuggets, Nuggets},
                        {auxiliary_products, AuxiliaryProducts},
                        {capabilities, Capabilities},
                        {sdk_outputs, SdkOutputs}
                    ] ++
                    BuildrootSections ++
                    [
                        {external_components, ExternalComponents}
                    ]},
        append_integrity(ManifestWithoutIntegrity)
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Finalize a manifest seed and serialize it as one UTF-8 Erlang-term file.
""".
-spec generate(
    smelterl:manifest_seed(),
    smelterl:br_legal_info() | undefined,
    smelterl:file_path()
) ->
    {ok, iodata()} | {error, term()}.
generate(Seed, BuildrootLegal, BasePath) ->
    maybe
        {ok, Manifest} ?= build_from_seed(
            Seed,
            BuildrootLegal,
            BasePath,
            runtime_environment()
        ),
        {ok, smelterl_file:format_term(Manifest)}
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Finalize a manifest seed and write the resulting term file to a path or device.
""".
-spec generate(
    smelterl:manifest_seed(),
    smelterl:br_legal_info() | undefined,
    smelterl:file_path(),
    smelterl:file_path() | file:io_device()
) ->
    ok | {error, term()}.
generate(Seed, BuildrootLegal, BasePath, PathOrDevice) ->
    maybe
        {ok, Manifest} ?= build_from_seed(
            Seed,
            BuildrootLegal,
            BasePath,
            runtime_environment()
        ),
        smelterl_file:write_term(PathOrDevice, Manifest)
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec validate_manifest_seed(term()) -> ok | {error, term()}.
validate_manifest_seed(Seed) when is_map(Seed) ->
    RequiredKeys = [
        product,
        target_arch,
        product_fields,
        repositories,
        nuggets,
        auxiliary_products,
        capabilities,
        sdk_outputs,
        external_components,
        smelterl_repository
    ],
    case [Key || Key <- RequiredKeys, not maps:is_key(Key, Seed)] of
        [] ->
            validate_manifest_seed_repository(Seed);
        Missing ->
            {error, {invalid_manifest_seed, {missing_fields, Missing}}}
    end;
validate_manifest_seed(Seed) ->
    {error, {invalid_manifest_seed, Seed}}.

-spec validate_manifest_seed_repository(smelterl:manifest_seed()) ->
    ok | {error, term()}.
validate_manifest_seed_repository(Seed) ->
    RepositoryIds = [
        RepoId
     || {RepoId, _Fields} <- maps:get(repositories, Seed, [])
    ],
    SmelterlRepository = maps:get(smelterl_repository, Seed),
    case lists:member(SmelterlRepository, RepositoryIds) of
        true ->
            ok;
        false ->
            {error,
                {invalid_manifest_seed,
                    {unknown_smelterl_repository, SmelterlRepository}}}
    end.

-spec product_section_fields(smelterl:manifest_seed(), map()) ->
    {ok, [{atom(), term()}]} | {error, term()}.
product_section_fields(Seed, RuntimeEnv) ->
    maybe
        {ok, BuildDate} ?= required_binary_field(build_date, RuntimeEnv),
        ProductId = maps:get(product, Seed),
        ProductFields = maps:get(product_fields, Seed, #{}),
        {ok,
            [
                {product, ProductId}
            ] ++
                optional_field_tuple(
                    product_name,
                    maps:get(name, ProductFields, undefined)
                ) ++
                optional_field_tuple(
                    product_description,
                    maps:get(description, ProductFields, undefined)
                ) ++
                optional_field_tuple(
                    product_version,
                    maps:get(version, ProductFields, undefined)
                ) ++
                [
                    {target_arch, maps:get(target_arch, Seed)},
                    {build_date, BuildDate}
                ]}
    else
        {error, _} = Error ->
            Error
    end.

-spec build_environment_fields(
    smelterl:manifest_seed(),
    smelterl:br_legal_info() | undefined,
    map()
) ->
    {ok, [{atom(), term()}]} | {error, term()}.
build_environment_fields(Seed, BuildrootLegal, RuntimeEnv) ->
    maybe
        {ok, HostOs} ?= required_binary_field(host_os, RuntimeEnv),
        {ok, HostArch} ?= required_binary_field(host_arch, RuntimeEnv),
        {ok, SmelterlVersion} ?= required_binary_field(
            smelterl_version,
            RuntimeEnv
        ),
        BuildrootVersion = buildroot_version(BuildrootLegal, RuntimeEnv),
        {ok,
            [
                {host_os, HostOs},
                {host_arch, HostArch},
                {smelterl_version, SmelterlVersion},
                {smelterl_repository, maps:get(smelterl_repository, Seed)}
            ] ++
                optional_field_tuple(buildroot_version, BuildrootVersion)}
    else
        {error, _} = Error ->
            Error
    end.

-spec repository_section_entries(smelterl:manifest_seed()) ->
    {ok, [{smelterl:repo_id(), [{atom(), term()}]}]}.
repository_section_entries(Seed) ->
    {ok,
        [
            {RepoId, repository_fields(RepoFields)}
         || {RepoId, RepoFields} <- maps:get(repositories, Seed, [])
        ]}.

-spec repository_fields(map()) -> [{atom(), term()}].
repository_fields(RepoFields) ->
    [
        {name, maps:get(name, RepoFields)},
        {type, maps:get(type, RepoFields)},
        {url, maps:get(url, RepoFields)},
        {commit, maps:get(commit, RepoFields)},
        {describe, maps:get(describe, RepoFields)},
        {dirty, maps:get(dirty, RepoFields)}
    ] ++
        optional_field_tuple(
            path_in_repo,
            maps:get(path_in_repo, RepoFields, undefined)
        ).

-spec nugget_section_entries([map()], smelterl:file_path()) ->
    {ok, [{nugget, smelterl:nugget_id(), [{atom(), term()}]}]} | {error, term()}.
nugget_section_entries(Nuggets, BasePath) ->
    build_named_entries(
        Nuggets,
        fun render_nugget_entry/2,
        BasePath
    ).

-spec render_nugget_entry(map(), smelterl:file_path()) ->
    {ok, {nugget, smelterl:nugget_id(), [{atom(), term()}]}} | {error, term()}.
render_nugget_entry(#{id := NuggetId, fields := Fields}, BasePath) ->
    maybe
        {ok, NuggetFields} ?= relativized_fields(
            Fields,
            [license_files],
            BasePath,
            [version, repository, category, flavor, provides, license, license_files]
        ),
        {ok, {nugget, NuggetId, NuggetFields}}
    else
        {error, _} = Error ->
            Error
    end;
render_nugget_entry(Entry, _BasePath) ->
    {error, {invalid_manifest_seed, {invalid_nugget_entry, Entry}}}.

-spec auxiliary_section_entries([map()]) ->
    {ok, [{auxiliary, smelterl:target_id(), [{atom(), term()}]}]}.
auxiliary_section_entries(AuxiliaryProducts) ->
    {ok,
        [
            {auxiliary,
                maps:get(id, Auxiliary),
                [
                    {root_nugget, maps:get(root_nugget, Auxiliary)}
                ] ++
                    optional_field_tuple(
                        constraints,
                        maps:get(constraints, Auxiliary, [])
                    )}
         || Auxiliary <- AuxiliaryProducts
        ]}.

-spec capabilities_section_fields(map()) -> {ok, [{atom(), term()}]}.
capabilities_section_fields(Capabilities) ->
    {ok,
        [
            {firmware_variants, maps:get(firmware_variants, Capabilities, [])},
            {selectable_outputs, maps:get(selectable_outputs, Capabilities, [])},
            {firmware_parameters,
                [
                    {maps:get(id, Parameter), parameter_fields(Parameter)}
                 || Parameter <- maps:get(firmware_parameters, Capabilities, [])
                ]}
        ]}.

-spec parameter_fields(map()) -> [{atom(), term()}].
parameter_fields(Parameter) ->
    [
        {type, maps:get(type, Parameter)}
    ] ++
        optional_field_tuple(required, maps:get(required, Parameter, undefined)) ++
        optional_field_tuple(name, maps:get(name, Parameter, undefined)) ++
        optional_field_tuple(
            description,
            maps:get(description, Parameter, undefined)
        ) ++
        optional_field_tuple(default, maps:get(default, Parameter, undefined)).

-spec sdk_outputs_section_entries([map()]) ->
    {ok, [{target, smelterl:target_id(), [{output, atom(), [{atom(), term()}]}]}]}.
sdk_outputs_section_entries(SdkOutputs) ->
    {ok,
        [
            {target,
                maps:get(target, TargetEntry),
                [
                    {output, maps:get(id, Output), sdk_output_fields(Output)}
                 || Output <- maps:get(outputs, TargetEntry, [])
                ]}
         || TargetEntry <- SdkOutputs
        ]}.

-spec sdk_output_fields(map()) -> [{atom(), term()}].
sdk_output_fields(Output) ->
    [
        {nugget, maps:get(nugget, Output)}
    ] ++
        optional_field_tuple(name, maps:get(name, Output, undefined)) ++
        optional_field_tuple(
            description,
            maps:get(description, Output, undefined)
        ).

-spec buildroot_section_entries(
    smelterl:br_legal_info() | undefined,
    smelterl:file_path()
) ->
    {ok, [{atom(), term()}]} | {error, term()}.
buildroot_section_entries(undefined, _BasePath) ->
    {ok, []};
buildroot_section_entries(BuildrootLegal, BasePath) ->
    maybe
        {ok, Packages} ?= buildroot_package_entries(
            maps:get(packages, BuildrootLegal, []),
            BasePath
        ),
        {ok, HostPackages} ?= buildroot_package_entries(
            maps:get(host_packages, BuildrootLegal, []),
            BasePath
        ),
        {ok,
            [
                {buildroot_packages, Packages},
                {buildroot_host_packages, HostPackages}
            ]}
    else
        {error, _} = Error ->
            Error
    end.

-spec buildroot_package_entries([smelterl:br_package_entry()], smelterl:file_path()) ->
    {ok, [{package, binary(), [{atom(), term()}]}]} | {error, term()}.
buildroot_package_entries(Packages, BasePath) ->
    maybe
        {ok, Entries} ?= build_named_entries(
            [
                #{id => maps:get(name, Package), fields => Package}
             || Package <- Packages
            ],
            fun render_buildroot_package_entry/2,
            BasePath
        ),
        {ok, Entries}
    else
        {error, _} = Error ->
            Error
    end.

-spec render_buildroot_package_entry(map(), smelterl:file_path()) ->
    {ok, {package, binary(), [{atom(), term()}]}} | {error, term()}.
render_buildroot_package_entry(#{id := Name, fields := Fields}, BasePath) ->
    maybe
        {ok, PackageFields} ?= relativized_fields(
            Fields,
            [license_files],
            BasePath,
            [version, license, license_files]
        ),
        {ok, {package, Name, PackageFields}}
    else
        {error, _} = Error ->
            Error
    end;
render_buildroot_package_entry(Entry, _BasePath) ->
    {error, {invalid_manifest_seed, {invalid_buildroot_package_entry, Entry}}}.

-spec external_component_section_entries([map()], smelterl:file_path()) ->
    {ok, [{component, atom(), [{atom(), term()}]}]} | {error, term()}.
external_component_section_entries(Components, BasePath) ->
    build_named_entries(
        Components,
        fun render_external_component_entry/2,
        BasePath
    ).

-spec render_external_component_entry(map(), smelterl:file_path()) ->
    {ok, {component, atom(), [{atom(), term()}]}} | {error, term()}.
render_external_component_entry(#{id := ComponentId} = Component, BasePath) ->
    maybe
        {ok, ComponentFields} ?= relativized_fields(
            Component,
            [license_files],
            BasePath,
            [nugget, name, description, version, license, license_files]
        ),
        {ok, {component, ComponentId, ComponentFields}}
    else
        {error, _} = Error ->
            Error
    end;
render_external_component_entry(Entry, _BasePath) ->
    {error, {invalid_manifest_seed, {invalid_external_component_entry, Entry}}}.

-spec build_named_entries([map()], fun((map(), smelterl:file_path()) -> {ok, term()} | {error, term()}), smelterl:file_path()) ->
    {ok, [term()]} | {error, term()}.
build_named_entries(Entries, RenderFun, BasePath) ->
    build_named_entries(Entries, RenderFun, BasePath, []).

build_named_entries([], _RenderFun, _BasePath, Acc) ->
    {ok, lists:reverse(Acc)};
build_named_entries([Entry | Rest], RenderFun, BasePath, Acc) ->
    case RenderFun(Entry, BasePath) of
        {ok, RenderedEntry} ->
            build_named_entries(Rest, RenderFun, BasePath, [RenderedEntry | Acc]);
        {error, _} = Error ->
            Error
    end.

-spec relativized_fields(map(), [atom()], smelterl:file_path(), [atom()]) ->
    {ok, [{atom(), term()}]} | {error, term()}.
relativized_fields(Fields, PathKeys, BasePath, OrderedKeys) ->
    relativized_fields(OrderedKeys, Fields, PathKeys, BasePath, []).

relativized_fields([], _Fields, _PathKeys, _BasePath, Acc) ->
    {ok, lists:reverse(Acc)};
relativized_fields([Key | Rest], Fields, PathKeys, BasePath, Acc) ->
    case maps:get(Key, Fields, undefined) of
        undefined ->
            relativized_fields(Rest, Fields, PathKeys, BasePath, Acc);
        [] ->
            relativized_fields(Rest, Fields, PathKeys, BasePath, Acc);
        Value ->
            case maybe_relativize_value(Key, Value, PathKeys, BasePath) of
                {ok, []} ->
                    relativized_fields(Rest, Fields, PathKeys, BasePath, Acc);
                {ok, RelativizedValue} ->
                    relativized_fields(
                        Rest,
                        Fields,
                        PathKeys,
                        BasePath,
                        [{Key, RelativizedValue} | Acc]
                    );
                {error, _} = Error ->
                    Error
            end
    end.

-spec maybe_relativize_value(atom(), term(), [atom()], smelterl:file_path()) ->
    {ok, term()} | {error, term()}.
maybe_relativize_value(Key, Value, PathKeys, BasePath) ->
    case lists:member(Key, PathKeys) of
        false ->
            {ok, Value};
        true ->
            manifest_local_paths(Value, BasePath)
    end.

-spec manifest_local_paths(term(), smelterl:file_path()) ->
    {ok, [smelterl:file_path()]} | {error, term()}.
manifest_local_paths(Paths, BasePath) when is_list(Paths) ->
    manifest_local_paths(Paths, BasePath, []);
manifest_local_paths(_Paths, BasePath) ->
    {error, {relativize_failed, invalid_path_list, BasePath}}.

manifest_local_paths([], _BasePath, Acc) ->
    {ok, lists:reverse(Acc)};
manifest_local_paths([Path | Rest], BasePath, Acc) ->
    case manifest_local_path(Path, BasePath) of
        {ok, RelativePath} ->
            manifest_local_paths(Rest, BasePath, [RelativePath | Acc]);
        skip ->
            manifest_local_paths(Rest, BasePath, Acc);
        {error, _} = Error ->
            Error
    end.

-spec manifest_local_path(term(), smelterl:file_path()) ->
    {ok, smelterl:file_path()} | skip | {error, term()}.
manifest_local_path(Path, BasePath) when is_binary(Path); is_list(Path) ->
    try
        PathString = to_list(Path),
        case filename:pathtype(PathString) of
            absolute ->
                maybe_keep_manifest_local_path(
                    smelterl_file:relativize(
                        to_binary(PathString),
                        BasePath
                    )
                );
            _Relative ->
                maybe_keep_manifest_local_path(to_binary(PathString))
        end
    catch
        _Class:_Reason ->
            {error, {relativize_failed, to_binary(Path), BasePath}}
    end;
manifest_local_path(Path, BasePath) ->
    {error, {relativize_failed, Path, BasePath}}.

-spec maybe_keep_manifest_local_path(smelterl:file_path()) ->
    {ok, smelterl:file_path()} | skip.
maybe_keep_manifest_local_path(Path) ->
    case is_manifest_local_path(Path) of
        true ->
            {ok, Path};
        false ->
            skip
    end.

-spec is_manifest_local_path(smelterl:file_path()) -> boolean().
is_manifest_local_path(Path) ->
    case binary:split(Path, <<"/">>, [global]) of
        [<<"legal-info">> | _Rest] ->
            true;
        _ ->
            false
    end.

-spec append_integrity(term()) -> {ok, term()} | {error, term()}.
append_integrity({sdk_manifest, Version, Fields}) ->
    case manifest_digest({sdk_manifest, Version, Fields}) of
        {ok, Digest} ->
            {ok,
                {sdk_manifest,
                    Version,
                    Fields ++
                        [
                            {integrity,
                                [
                                    {digest_algorithm, sha256},
                                    {canonical_form, basic_term_canon},
                                    {digest, Digest}
                                ]}
                        ]}};
        {error, _} = Error ->
            Error
    end.

-spec manifest_digest(term()) -> {ok, binary()} | {error, term()}.
manifest_digest(Term) ->
    try
        {ok,
            binary_to_hex(
                crypto:hash(
                    sha256,
                    unicode:characters_to_binary(
                        io_lib:format("~0tp.~n", [Term])
                    )
                )
            )}
    catch
        Class:Reason ->
            {error, {integrity_failed, {Class, Reason}}}
    end.

-spec buildroot_version(smelterl:br_legal_info() | undefined, map()) ->
    binary() | undefined.
buildroot_version(undefined, RuntimeEnv) ->
    maps:get(buildroot_version, RuntimeEnv, undefined);
buildroot_version(BuildrootLegal, RuntimeEnv) ->
    case maps:get(br_version, BuildrootLegal, undefined) of
        undefined ->
            maps:get(buildroot_version, RuntimeEnv, undefined);
        <<>> ->
            maps:get(buildroot_version, RuntimeEnv, undefined);
        Version ->
            Version
    end.

-spec required_binary_field(atom(), map()) ->
    {ok, binary()} | {error, term()}.
required_binary_field(Key, RuntimeEnv) ->
    case maps:get(Key, RuntimeEnv, undefined) of
        Value when is_binary(Value), Value =/= <<>> ->
            {ok, Value};
        _ ->
            {error, {invalid_manifest_seed, {invalid_runtime_env, Key}}}
    end.

-spec optional_field_tuple(atom(), term()) -> [{atom(), term()}].
optional_field_tuple(_Key, undefined) ->
    [];
optional_field_tuple(_Key, []) ->
    [];
optional_field_tuple(Key, Value) ->
    [{Key, Value}].

-spec runtime_environment() -> map().
runtime_environment() ->
    #{
        host_os => host_os(),
        host_arch => host_arch(),
        smelterl_version => smelterl_version(),
        build_date => current_utc_timestamp()
    }.

-spec host_os() -> binary().
host_os() ->
    case os:type() of
        {unix, linux} ->
            <<"Linux">>;
        {unix, darwin} ->
            <<"Darwin">>;
        {win32, nt} ->
            <<"Windows">>;
        {_Family, Name} ->
            atom_to_binary(Name, utf8)
    end.

-spec host_arch() -> binary().
host_arch() ->
    Architecture = unicode:characters_to_binary(erlang:system_info(system_architecture)),
    case binary:split(Architecture, <<"-">>) of
        [HostArch | _Rest] ->
            HostArch;
        _ ->
            Architecture
    end.

-spec smelterl_version() -> binary().
smelterl_version() ->
    case application:get_env(smelterl, version) of
        {ok, Version} ->
            to_binary(Version);
        undefined ->
            case application:get_key(smelterl, vsn) of
                {ok, Version} ->
                    to_binary(Version);
                undefined ->
                    <<"dev">>
            end
    end.

-spec current_utc_timestamp() -> binary().
current_utc_timestamp() ->
    unicode:characters_to_binary(
        calendar:system_time_to_rfc3339(
            erlang:system_time(second),
            [{offset, "Z"}, {unit, second}]
        )
    ).

-spec binary_to_hex(binary()) -> binary().
binary_to_hex(Binary) ->
    << <<(hex_digit((Byte bsr 4) band 16#0f))/utf8,
         (hex_digit(Byte band 16#0f))/utf8>> || <<Byte>> <= Binary >>.

-spec hex_digit(0..15) -> char().
hex_digit(Value) when Value < 10 ->
    $0 + Value;
hex_digit(Value) ->
    $a + (Value - 10).

-spec to_list(smelterl:file_path() | string()) -> string().
to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
to_list(Path) ->
    Path.

-spec to_binary(smelterl:file_path() | string()) -> binary().
to_binary(Path) when is_binary(Path) ->
    Path;
to_binary(Path) ->
    unicode:characters_to_binary(Path).

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
