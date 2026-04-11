%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_context).
-moduledoc """
Render selected-target `alloy_context.sh` files from the serialized build plan.

This generator consumes the selected target's plan-carried topology,
motherlode, config, and capability data, then renders the target-scoped shell
context used by SDK-time and firmware-time orchestration.
""".


%=== EXPORTS ===================================================================

-export([render/2]).
-export([render/3]).


%=== MACROS ====================================================================

-define(SDK_HOOK_TYPES, [pre_build, post_build, post_image, post_fakeroot]).
-define(FIRMWARE_HOOK_TYPES, [pre_firmware, firmware_build, post_firmware]).


%=== API FUNCTIONS =============================================================

-doc """
Render one selected-target `alloy_context.sh` from build-plan data.
""".
-spec render(smelterl:nugget_id(), smelterl:build_target()) ->
    {ok, iodata()} | {error, term()}.
render(PlanProductId, Target) when is_atom(PlanProductId), is_map(Target) ->
    maybe
        {ok, Data} ?= template_data(PlanProductId, Target),
        smelterl_template:render(alloy_context, Data)
    else
        {error, _} = Error ->
            Error
    end;
render(PlanProductId, Target) ->
    {error, {invalid_context_input, PlanProductId, Target}}.

-doc """
Render one selected-target `alloy_context.sh` and write it to one open IO
device.
""".
-spec render(smelterl:nugget_id(), smelterl:build_target(), file:io_device()) ->
    ok | {error, term()}.
render(PlanProductId, Target, Out) ->
    maybe
        {ok, Content} ?= render(PlanProductId, Target),
        smelterl_file:write_iodata(Out, Content)
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec template_data(smelterl:nugget_id(), smelterl:build_target()) ->
    {ok, map()} | {error, term()}.
template_data(PlanProductId, Target) ->
    Kind = maps:get(kind, Target, main),
    TargetId = maps:get(id, Target, main),
    Tree = maps:get(tree, Target, #{root => PlanProductId, edges => #{}}),
    Topology = maps:get(topology, Target, []),
    Motherlode = maps:get(motherlode, Target, #{}),
    Config = maps:get(config, Target, #{}),
    Capabilities = maps:get(capabilities, Target, #{}),
    ProductNuggetId = selected_product_nugget_id(PlanProductId, Target),
    maybe
        {ok, ProductNugget} ?= lookup_nugget(ProductNuggetId, Motherlode),
        {ok, Flavors} ?= smelterl_validate:resolved_flavors(Tree, Motherlode),
        {ok, NuggetSections} ?= nugget_sections(Topology, Motherlode, Flavors),
        {ConfigSections, GlobalConfigVars} = config_sections(Topology, Config),
        {ok, SdkHookArrays} ?= sdk_hook_arrays(Kind, TargetId, Topology, Motherlode),
        {ok, SdkOutputs} ?= sdk_outputs(TargetId, Capabilities),
        {ok, MainData} ?= main_context_data(Kind, Topology, Motherlode, Capabilities),
        {ok,
            maps:merge(
                #{
                    header_product => Kind =:= main,
                    header_product_id => atom_binary(ProductNuggetId),
                    header_product_version => optional_binary(version, ProductNugget),
                    header_product_has_version =>
                        maps:get(version, ProductNugget, undefined) =/= undefined,
                    header_auxiliary => Kind =:= auxiliary,
                    header_auxiliary_id => atom_binary(TargetId),
                    nuggets_present => NuggetSections =/= [],
                    nuggets => NuggetSections,
                    product_vars => product_vars(PlanProductId, TargetId, Kind, ProductNugget),
                    has_any_config =>
                        (ConfigSections =/= []) orelse (GlobalConfigVars =/= []),
                    config_sections => ConfigSections,
                    has_global_config => GlobalConfigVars =/= [],
                    global_config_vars => GlobalConfigVars,
                    nugget_order_items =>
                        shell_array_items([atom_binary(NuggetId) || NuggetId <- Topology]),
                    sdk_hook_arrays => SdkHookArrays,
                    sdk_outputs_items =>
                        shell_array_items([maps:get(id, Output) || Output <- SdkOutputs]),
                    sdk_outputs => sdk_output_template_data(SdkOutputs),
                    main => Kind =:= main,
                    helper_has_sdk_output_lookup => Kind =:= main
                },
                MainData
            )}
    else
        {error, _} = Error ->
            Error
    end.

selected_product_nugget_id(_PlanProductId, #{kind := auxiliary} = Target) ->
    maps:get(aux_root, Target, maps:get(root, maps:get(tree, Target)));
selected_product_nugget_id(PlanProductId, _Target) ->
    PlanProductId.

product_vars(PlanProductId, _TargetId, main, ProductNugget) ->
    [
        export_var(<<"ALLOY_PRODUCT">>, atom_binary(PlanProductId)),
        export_var(<<"ALLOY_IS_AUXILIARY">>, <<"false">>),
        export_var(<<"ALLOY_AUXILIARY">>, <<>>),
        export_var(<<"ALLOY_PRODUCT_NAME">>, optional_binary(name, ProductNugget)),
        export_var(<<"ALLOY_PRODUCT_DESC">>, optional_binary(description, ProductNugget)),
        export_var(<<"ALLOY_PRODUCT_VERSION">>, optional_binary(version, ProductNugget))
    ];
product_vars(_PlanProductId, TargetId, auxiliary, ProductNugget) ->
    [
        export_var(<<"ALLOY_PRODUCT">>, atom_binary(TargetId)),
        export_var(<<"ALLOY_IS_AUXILIARY">>, <<"true">>),
        export_var(<<"ALLOY_AUXILIARY">>, atom_binary(TargetId)),
        export_var(<<"ALLOY_PRODUCT_NAME">>, optional_binary(name, ProductNugget)),
        export_var(<<"ALLOY_PRODUCT_DESC">>, optional_binary(description, ProductNugget)),
        export_var(<<"ALLOY_PRODUCT_VERSION">>, optional_binary(version, ProductNugget))
    ].

nugget_sections(Topology, Motherlode, Flavors) ->
    nugget_sections(Topology, Motherlode, Flavors, []).

nugget_sections([], _Motherlode, _Flavors, Acc) ->
    {ok, lists:reverse(Acc)};
nugget_sections([NuggetId | Rest], Motherlode, Flavors, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        Vars = nugget_vars(NuggetId, Nugget, Flavors, Motherlode),
        nugget_sections(
            Rest,
            Motherlode,
            Flavors,
            [
                #{
                    header => nugget_section_header(NuggetId, Nugget),
                    vars => Vars
                }
             | Acc0
            ]
        )
    else
        {error, _} = Error ->
            Error
    end.

nugget_vars(NuggetId, Nugget, Flavors, Motherlode) ->
    Prefix = nugget_prefix(NuggetId),
    BaseVars = [
        export_var(<<Prefix/binary>>, atom_binary(NuggetId)),
        export_var(<<Prefix/binary, "_DIR">>, nugget_motherlode_prefix(NuggetId, Motherlode))
    ],
    OptionalVars0 = maybe_add_optional_var(
        <<Prefix/binary, "_NAME">>,
        maps:get(name, Nugget, undefined),
        BaseVars
    ),
    OptionalVars1 = maybe_add_optional_var(
        <<Prefix/binary, "_DESC">>,
        maps:get(description, Nugget, undefined),
        OptionalVars0
    ),
    OptionalVars2 = maybe_add_optional_var(
        <<Prefix/binary, "_VERSION">>,
        maps:get(version, Nugget, undefined),
        OptionalVars1
    ),
    maybe_add_optional_var(
        <<Prefix/binary, "_FLAVOR">>,
        case maps:get(NuggetId, Flavors, undefined) of
            undefined -> undefined;
            Flavor -> atom_binary(Flavor)
        end,
        OptionalVars2
    ).

nugget_section_header(NuggetId, Nugget) ->
    Description = optional_binary(description, Nugget),
    case Description of
        <<>> ->
            atom_binary(NuggetId);
        _ ->
            <<(atom_binary(NuggetId))/binary, ": ", Description/binary>>
    end.

config_sections(Topology, Config) ->
    NuggetSections = [
        begin
            Vars = nugget_config_vars(NuggetId, Config),
            #{
                header => nugget_section_header_from_config(NuggetId),
                vars => Vars
            }
        end
     || NuggetId <- Topology,
        nugget_config_vars(NuggetId, Config) =/= []
    ],
    {NuggetSections, global_config_vars(Config)}.

nugget_section_header_from_config(NuggetId) ->
    atom_binary(NuggetId).

nugget_config_vars(NuggetId, Config) ->
    lists:sort([
        export_var(EnvKey, Value)
     || {EnvKey, {nugget, NuggetId0, Value}} <- maps:to_list(Config),
        NuggetId0 =:= NuggetId
    ]).

global_config_vars(Config) ->
    lists:sort([
        export_var(EnvKey, Value)
     || {EnvKey, {global, undefined, Value}} <- maps:to_list(Config)
    ]).

sdk_hook_arrays(Kind, TargetId, Topology, Motherlode) ->
    maybe
        {ok,
            [
                hook_array(<<"ALLOY_PRE_BUILD_HOOKS">>, pre_build, Kind, TargetId, Topology, Motherlode),
                hook_array(<<"ALLOY_POST_BUILD_HOOKS">>, post_build, Kind, TargetId, Topology, Motherlode),
                hook_array(<<"ALLOY_POST_IMAGE_HOOKS">>, post_image, Kind, TargetId, Topology, Motherlode),
                hook_array(
                    <<"ALLOY_POST_FAKEROOT_HOOKS">>,
                    post_fakeroot,
                    Kind,
                    TargetId,
                    Topology,
                    Motherlode
                )
            ]}
    else
        {error, _} = Error ->
            Error
    end.

hook_array(Name, HookType, Kind, TargetId, Topology, Motherlode) ->
    maybe
        {ok, Entries} ?= hook_entries(HookType, Kind, TargetId, Topology, Motherlode),
        #{
            name => Name,
            items => shell_array_items(Entries)
        }
    else
        {error, _} = Error ->
            Error
    end.

hook_entries(HookType, Kind, TargetId, Topology, Motherlode) ->
    hook_entries(HookType, Kind, TargetId, Topology, Motherlode, []).

hook_entries(_HookType, _Kind, _TargetId, [], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
hook_entries(HookType, Kind, TargetId, [NuggetId | Rest], Motherlode, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, Hooks} ?= parse_hooks(NuggetId, maps:get(hooks, Nugget, [])),
        Matching = [
            <<(atom_binary(NuggetId))/binary, ":", Script/binary>>
         || #{type := Type, script := Script, scope := Scope} <- Hooks,
            Type =:= HookType,
            hook_matches_target(Kind, TargetId, Scope)
        ],
        hook_entries(
            HookType,
            Kind,
            TargetId,
            Rest,
            Motherlode,
            lists:reverse(Matching) ++ Acc0
        )
    else
        {error, _} = Error ->
            Error
    end.

hook_matches_target(main, _TargetId, main) ->
    true;
hook_matches_target(main, _TargetId, all) ->
    true;
hook_matches_target(main, _TargetId, _Scope) ->
    false;
hook_matches_target(auxiliary, _TargetId, auxiliary) ->
    true;
hook_matches_target(auxiliary, _TargetId, all) ->
    true;
hook_matches_target(auxiliary, TargetId, Scope) when is_atom(Scope) ->
    Scope =:= TargetId;
hook_matches_target(auxiliary, _TargetId, _Scope) ->
    false.

main_context_data(main, Topology, Motherlode, Capabilities) ->
    maybe
        {ok, FirmwareHookArrays} ?= firmware_hook_arrays(
            Topology,
            Motherlode,
            Capabilities
        ),
        {ok, EmbedImages, EmbedHost, EmbedNuggets} ?= embed_arrays(Topology, Motherlode),
        {ok, FsPriorityVars, FsPriorityFragments} ?= fs_priorities(Topology, Motherlode),
        {ok, FirmwareOutputs} ?= firmware_outputs(Topology, Motherlode),
        {ok,
            #{
                firmware_variants_items =>
                    shell_array_items(maps:get(firmware_variants, Capabilities, [])),
                firmware_hook_arrays => FirmwareHookArrays,
                embed_images_items => shell_array_items(EmbedImages),
                embed_host_items => shell_array_items(EmbedHost),
                embed_nuggets_items => shell_array_items(EmbedNuggets),
                fs_priority_vars => FsPriorityVars,
                fs_priority_fragments_items => shell_array_items(FsPriorityFragments),
                firmware_outputs_items =>
                    shell_array_items([maps:get(id, Output) || Output <- FirmwareOutputs]),
                firmware_outputs => firmware_output_template_data(FirmwareOutputs),
                selectable_outputs_items =>
                    shell_array_items([
                        maps:get(id, Output)
                     || Output <- maps:get(selectable_outputs, Capabilities, [])
                    ]),
                firmware_parameters_items =>
                    shell_array_items([
                        maps:get(id, Parameter)
                     || Parameter <- maps:get(firmware_parameters, Capabilities, [])
                    ]),
                firmware_parameters =>
                    firmware_parameter_template_data(
                        maps:get(firmware_parameters, Capabilities, [])
                    )
            }}
    else
        {error, _} = Error ->
            Error
    end;
main_context_data(auxiliary, _Topology, _Motherlode, _Capabilities) ->
    {ok, #{}}.

firmware_hook_arrays(Topology, Motherlode, Capabilities) ->
    Variants = maps:get(firmware_variants, Capabilities, []),
    firmware_hook_arrays(Variants, Topology, Motherlode, Capabilities, []).

firmware_hook_arrays([], _Topology, _Motherlode, _Capabilities, Acc) ->
    {ok, lists:reverse(Acc)};
firmware_hook_arrays([Variant | Rest], Topology, Motherlode, Capabilities, Acc0) ->
    VariantToken = env_token(Variant),
    maybe
        {ok, PreHooks} ?= firmware_hook_entries(
            pre_firmware,
            Variant,
            Topology,
            Motherlode,
            Capabilities
        ),
        {ok, BuildHooks} ?= firmware_hook_entries(
            firmware_build,
            Variant,
            Topology,
            Motherlode,
            Capabilities
        ),
        {ok, PostHooks} ?= firmware_hook_entries(
            post_firmware,
            Variant,
            Topology,
            Motherlode,
            Capabilities
        ),
        firmware_hook_arrays(
            Rest,
            Topology,
            Motherlode,
            Capabilities,
            [
                #{name => <<"ALLOY_POST_FIRMWARE_HOOKS_", VariantToken/binary>>,
                    items => shell_array_items(PostHooks)},
                #{name => <<"ALLOY_FIRMWARE_BUILD_HOOKS_", VariantToken/binary>>,
                    items => shell_array_items(BuildHooks)},
                #{name => <<"ALLOY_PRE_FIRMWARE_HOOKS_", VariantToken/binary>>,
                    items => shell_array_items(PreHooks)}
             | Acc0
            ]
        )
    else
        {error, _} = Error ->
            Error
    end.

firmware_hook_entries(HookType, Variant, Topology, Motherlode, Capabilities) ->
    VariantNuggets = maps:get(variant_nuggets, Capabilities, #{}),
    DeclaringNuggets = maps:get(Variant, VariantNuggets, []),
    firmware_hook_entries(
        HookType,
        Variant,
        DeclaringNuggets,
        Topology,
        Motherlode,
        []
    ).

firmware_hook_entries(_HookType, _Variant, _DeclaringNuggets, [], _Motherlode, Acc) ->
    {ok, lists:reverse(Acc)};
firmware_hook_entries(
    HookType,
    Variant,
    DeclaringNuggets,
    [NuggetId | Rest],
    Motherlode,
    Acc0
) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, Hooks} ?= parse_hooks(NuggetId, maps:get(hooks, Nugget, [])),
        Matching =
            case nugget_in_variant(NuggetId, Nugget, Variant, DeclaringNuggets) of
                true ->
                    [
                        <<(atom_binary(NuggetId))/binary, ":", Script/binary>>
                     || #{type := Type, script := Script} <- Hooks,
                        Type =:= HookType
                    ];
                false ->
                    []
            end,
        firmware_hook_entries(
            HookType,
            Variant,
            DeclaringNuggets,
            Rest,
            Motherlode,
            lists:reverse(Matching) ++ Acc0
        )
    else
        {error, _} = Error ->
            Error
    end.

nugget_in_variant(NuggetId, Nugget, _Variant, DeclaringNuggets) ->
    case maps:get(firmware_variant, Nugget, undefined) of
        undefined ->
            true;
        _ ->
            lists:member(NuggetId, DeclaringNuggets)
    end.

embed_arrays(Topology, Motherlode) ->
    embed_arrays(Topology, Motherlode, [], [], []).

embed_arrays([], _Motherlode, Images, Host, Nuggets) ->
    {ok, lists:reverse(Images), lists:reverse(Host), lists:reverse(Nuggets)};
embed_arrays([NuggetId | Rest], Motherlode, Images0, Host0, Nuggets0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, ExplicitImages, ExplicitHost, ExplicitNuggets} ?= parse_embed(
            NuggetId,
            maps:get(embed, Nugget, [])
        ),
        {ok, Hooks} ?= parse_hooks(NuggetId, maps:get(hooks, Nugget, [])),
        AutoHookEmbeds = [
            <<(atom_binary(NuggetId))/binary, ":", Script/binary>>
         || #{type := Type, script := Script} <- Hooks,
            lists:member(Type, ?FIRMWARE_HOOK_TYPES)
        ],
        {ok, AutoPriorityEmbeds} ?= auto_priority_embeds(NuggetId, Nugget),
        embed_arrays(
            Rest,
            Motherlode,
            append_unique(ExplicitImages, Images0),
            append_unique(ExplicitHost, Host0),
            append_unique(
                ExplicitNuggets ++ AutoHookEmbeds ++ AutoPriorityEmbeds,
                Nuggets0
            )
        )
    else
        {error, _} = Error ->
            Error
    end.

auto_priority_embeds(NuggetId, Nugget) ->
    case maps:get(fs_priorities, Nugget, undefined) of
        Path when is_binary(Path) ->
            {ok, [<<(atom_binary(NuggetId))/binary, ":", Path/binary>>]};
        undefined ->
            {ok, []};
        Invalid ->
            {error, {invalid_fs_priorities_metadata, NuggetId, Invalid}}
    end.

fs_priorities(Topology, Motherlode) ->
    fs_priorities(Topology, Motherlode, [], []).

fs_priorities([], _Motherlode, VarsAcc, FragmentsAcc) ->
    {ok, lists:reverse(VarsAcc), lists:reverse(FragmentsAcc)};
fs_priorities([NuggetId | Rest], Motherlode, VarsAcc0, FragmentsAcc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        case maps:get(fs_priorities, Nugget, undefined) of
            Path when is_binary(Path) ->
                Prefix = nugget_prefix(NuggetId),
                ResolvedPath = motherlode_path(NuggetId, Path, Motherlode),
                fs_priorities(
                    Rest,
                    Motherlode,
                    [
                        export_var(
                            <<Prefix/binary, "_FS_PRIORITIES">>,
                            ResolvedPath
                        )
                     | VarsAcc0
                    ],
                    [
                        <<(atom_binary(NuggetId))/binary, ":", ResolvedPath/binary>>
                     | FragmentsAcc0
                    ]
                );
            undefined ->
                fs_priorities(Rest, Motherlode, VarsAcc0, FragmentsAcc0);
            Invalid ->
                {error, {invalid_fs_priorities_metadata, NuggetId, Invalid}}
        end
    else
        {error, _} = Error ->
            Error
    end.

firmware_outputs(Topology, Motherlode) ->
    firmware_outputs(Topology, Motherlode, #{}, []).

firmware_outputs([], _Motherlode, _Seen, Acc) ->
    {ok, lists:reverse(Acc)};
firmware_outputs([NuggetId | Rest], Motherlode, Seen0, Acc0) ->
    maybe
        {ok, Nugget} ?= lookup_nugget(NuggetId, Motherlode),
        {ok, NuggetOutputs} ?= parse_firmware_outputs(
            NuggetId,
            maps:get(firmware_outputs, Nugget, undefined)
        ),
        {ok, Seen1, Acc1} ?= add_firmware_outputs(
            NuggetId,
            NuggetOutputs,
            Seen0,
            Acc0
        ),
        firmware_outputs(Rest, Motherlode, Seen1, Acc1)
    else
        {error, _} = Error ->
            Error
    end.

add_firmware_outputs(_NuggetId, [], Seen, Acc) ->
    {ok, Seen, Acc};
add_firmware_outputs(NuggetId, [Output | Rest], Seen0, Acc0) ->
    OutputId = maps:get(id, Output),
    case maps:get(OutputId, Seen0, undefined) of
        undefined ->
            add_firmware_outputs(
                NuggetId,
                Rest,
                maps:put(OutputId, NuggetId, Seen0),
                [Output#{nugget => NuggetId} | Acc0]
            );
        PreviousNuggetId ->
            {error,
                {duplicate_firmware_output,
                    OutputId,
                    PreviousNuggetId,
                    NuggetId}}
    end.

sdk_outputs(TargetId, Capabilities) ->
    OutputsByTarget = maps:get(sdk_outputs_by_target, Capabilities, #{}),
    {ok, maps:get(TargetId, OutputsByTarget, [])}.

sdk_output_template_data(Outputs) ->
    [
        #{
            id_upper => env_token(maps:get(id, Output)),
            vars =>
                output_metadata_vars(
                    <<"ALLOY_SDK_OUTPUT_", (env_token(maps:get(id, Output)))/binary>>,
                    Output
                )
        }
     || Output <- Outputs
    ].

firmware_output_template_data(Outputs) ->
    [
        #{
            id_upper => env_token(maps:get(id, Output)),
            vars => firmware_output_vars(Output)
        }
     || Output <- Outputs
    ].

firmware_output_vars(Output) ->
    Prefix = <<"ALLOY_FIRMWARE_OUT_", (env_token(maps:get(id, Output)))/binary>>,
    Base = [
        export_var(<<Prefix/binary, "_NUGGET">>, atom_binary(maps:get(nugget, Output))),
        export_var(<<Prefix/binary, "_SELECTABLE">>, boolean_binary(maps:get(selectable, Output, false))),
        export_var(<<Prefix/binary, "_DEFAULT">>, boolean_binary(maps:get(default, Output, true)))
    ],
    Optional0 = maybe_add_optional_var(
        <<Prefix/binary, "_NAME">>,
        maps:get(name, Output, undefined),
        Base
    ),
    maybe_add_optional_var(
        <<Prefix/binary, "_DESCRIPTION">>,
        maps:get(description, Output, undefined),
        Optional0
    ).

firmware_parameter_template_data(Parameters) ->
    [
        #{
            id_upper => env_token(maps:get(id, Parameter)),
            vars => firmware_parameter_vars(Parameter)
        }
     || Parameter <- Parameters
    ].

firmware_parameter_vars(Parameter) ->
    Prefix = <<"ALLOY_FIRMWARE_PARAM_", (env_token(maps:get(id, Parameter)))/binary>>,
    Base = [
        export_var(<<Prefix/binary, "_TYPE">>, atom_binary(maps:get(type, Parameter))),
        export_var(
            <<Prefix/binary, "_REQUIRED">>,
            boolean_binary(maps:get(required, Parameter, false))
        )
    ],
    Optional0 = maybe_add_optional_var(
        <<Prefix/binary, "_DEFAULT">>,
        case maps:get(default, Parameter, undefined) of
            undefined -> undefined;
            Default -> value_binary(Default)
        end,
        Base
    ),
    Optional1 = maybe_add_optional_var(
        <<Prefix/binary, "_NAME">>,
        maps:get(name, Parameter, undefined),
        Optional0
    ),
    maybe_add_optional_var(
        <<Prefix/binary, "_DESCRIPTION">>,
        maps:get(description, Parameter, undefined),
        Optional1
    ).

output_metadata_vars(Prefix, Output) ->
    Optional0 = maybe_add_optional_var(
        <<Prefix/binary, "_NAME">>,
        maps:get(name, Output, undefined),
        []
    ),
    maybe_add_optional_var(
        <<Prefix/binary, "_DESCRIPTION">>,
        maps:get(description, Output, undefined),
        Optional0
    ).

parse_hooks(_NuggetId, undefined) ->
    {ok, []};
parse_hooks(_NuggetId, []) ->
    {ok, []};
parse_hooks(NuggetId, Hooks) when is_list(Hooks) ->
    parse_hooks(NuggetId, Hooks, []);
parse_hooks(NuggetId, Hooks) ->
    {error, {invalid_hooks_metadata, NuggetId, Hooks}}.

parse_hooks(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
parse_hooks(NuggetId, [{HookType, ScriptPath} | Rest], Acc)
  when is_atom(HookType), is_binary(ScriptPath) ->
    parse_hooks(
        NuggetId,
        Rest,
        [#{type => HookType, script => ScriptPath, scope => main} | Acc]
    );
parse_hooks(NuggetId, [{HookType, ScriptPath, Scope} | Rest], Acc)
  when is_atom(HookType), is_binary(ScriptPath), is_atom(Scope) ->
    parse_hooks(
        NuggetId,
        Rest,
        [#{type => HookType, script => ScriptPath, scope => Scope} | Acc]
    );
parse_hooks(NuggetId, [Hook | _Rest], _Acc) ->
    {error, {invalid_hook, NuggetId, Hook}}.

parse_embed(_NuggetId, undefined) ->
    {ok, [], [], []};
parse_embed(_NuggetId, []) ->
    {ok, [], [], []};
parse_embed(NuggetId, Embed) when is_list(Embed) ->
    parse_embed(NuggetId, Embed, [], [], []);
parse_embed(NuggetId, Embed) ->
    {error, {invalid_embed_metadata, NuggetId, Embed}}.

parse_embed(_NuggetId, [], Images, Host, Nuggets) ->
    {ok, lists:reverse(Images), lists:reverse(Host), lists:reverse(Nuggets)};
parse_embed(NuggetId, [{images, Path} | Rest], Images, Host, Nuggets)
  when is_binary(Path) ->
    parse_embed(NuggetId, Rest, [Path | Images], Host, Nuggets);
parse_embed(NuggetId, [{host, Path} | Rest], Images, Host, Nuggets)
  when is_binary(Path) ->
    parse_embed(NuggetId, Rest, Images, [Path | Host], Nuggets);
parse_embed(NuggetId, [{nugget, Path} | Rest], Images, Host, Nuggets)
  when is_binary(Path) ->
    parse_embed(
        NuggetId,
        Rest,
        Images,
        Host,
        [<<(atom_binary(NuggetId))/binary, ":", Path/binary>> | Nuggets]
    );
parse_embed(NuggetId, [Entry | _Rest], _Images, _Host, _Nuggets) ->
    {error, {invalid_embed_entry, NuggetId, Entry}}.

parse_firmware_outputs(_NuggetId, undefined) ->
    {ok, []};
parse_firmware_outputs(NuggetId, Outputs) when is_list(Outputs) ->
    parse_firmware_outputs(NuggetId, Outputs, []);
parse_firmware_outputs(NuggetId, Value) ->
    {error, {invalid_firmware_outputs_metadata, NuggetId, Value}}.

parse_firmware_outputs(_NuggetId, [], Acc) ->
    {ok, lists:reverse(Acc)};
parse_firmware_outputs(NuggetId, [Output | Rest], Acc) ->
    maybe
        {ok, Parsed} ?= parse_firmware_output(NuggetId, Output),
        parse_firmware_outputs(NuggetId, Rest, [Parsed | Acc])
    else
        {error, _} = Error ->
            Error
    end;
parse_firmware_outputs(NuggetId, Value, _Acc) ->
    {error, {invalid_firmware_outputs_metadata, NuggetId, Value}}.

parse_firmware_output(NuggetId, {OutputId, Fields})
  when is_atom(OutputId), is_list(Fields) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Fields,
        #{id => OutputId, selectable => false, default => true}
    );
parse_firmware_output(NuggetId, Output) ->
    {error, {invalid_firmware_output, NuggetId, Output}}.

parse_firmware_output_fields(_NuggetId, _OutputId, [], Output) ->
    {ok, Output};
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{selectable, Selectable} | Rest],
    Output
)
  when is_boolean(Selectable) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{selectable := Selectable}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{default, Default} | Rest],
    Output
)
  when is_boolean(Default) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{default := Default}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{display_name, Name} | Rest],
    Output
)
  when is_binary(Name) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{name => Name}
    );
parse_firmware_output_fields(
    NuggetId,
    OutputId,
    [{description, Description} | Rest],
    Output
)
  when is_binary(Description) ->
    parse_firmware_output_fields(
        NuggetId,
        OutputId,
        Rest,
        Output#{description => Description}
    );
parse_firmware_output_fields(NuggetId, OutputId, [Field | _Rest], _Output) ->
    {error, {invalid_firmware_output_field, NuggetId, OutputId, Field}}.

lookup_nugget(NuggetId, Motherlode) ->
    Nuggets = maps:get(nuggets, Motherlode, #{}),
    case maps:get(NuggetId, Nuggets, undefined) of
        Nugget when is_map(Nugget) ->
            {ok, Nugget};
        undefined ->
            {error, {missing_nugget_metadata, NuggetId}}
    end.

nugget_prefix(NuggetId) ->
    <<"ALLOY_NUGGET_", (env_token(NuggetId))/binary>>.

env_token(Value) when is_atom(Value) ->
    env_token(atom_binary(Value));
env_token(Value) when is_binary(Value) ->
    Upper = string:uppercase(binary_to_list(Value)),
    unicode:characters_to_binary([if Ch =:= $- -> $_; true -> Ch end || Ch <- Upper]).

optional_binary(Key, Map) ->
    case maps:get(Key, Map, undefined) of
        Value when is_binary(Value) ->
            Value;
        _ ->
            <<>>
    end.

boolean_binary(true) ->
    <<"true">>;
boolean_binary(false) ->
    <<"false">>.

value_binary(Value) when is_binary(Value) ->
    Value;
value_binary(Value) when is_atom(Value) ->
    atom_binary(Value);
value_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
value_binary(Value) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Value])).

export_var(Name, Value) ->
    #{
        name => Name,
        value => shell_literal(value_binary(Value))
    }.

maybe_add_optional_var(_Name, undefined, Vars) ->
    Vars;
maybe_add_optional_var(_Name, <<>>, Vars) ->
    Vars;
maybe_add_optional_var(Name, Value, Vars) ->
    Vars ++ [export_var(Name, Value)].

shell_array_items(Values) ->
    iolist_to_binary(lists:join(<<" ">>, [shell_literal(value_binary(Value)) || Value <- Values])).

shell_literal(Value) when is_binary(Value) ->
    Escaped0 = binary:replace(Value, <<"\\">>, <<"\\\\">>, [global]),
    Escaped1 = binary:replace(Escaped0, <<"\"">>, <<"\\\"">>, [global]),
    Escaped2 = binary:replace(Escaped1, <<"`">>, <<"\\`">>, [global]),
    <<"\"", Escaped2/binary, "\"">>.

append_unique(NewItems, ExistingReversed) ->
    lists:foldl(
        fun(Item, Acc) ->
            case lists:member(Item, Acc) of
                true -> Acc;
                false -> [Item | Acc]
            end
        end,
        ExistingReversed,
        lists:reverse(NewItems)
    ).

atom_binary(Value) ->
    atom_to_binary(Value, utf8).

motherlode_path(NuggetId, RelativePath, Motherlode) ->
    Prefix = nugget_motherlode_prefix(NuggetId, Motherlode),
    <<Prefix/binary, "/", RelativePath/binary>>.

nugget_motherlode_prefix(NuggetId, Motherlode) ->
    {ok, Nugget} = lookup_nugget(NuggetId, Motherlode),
    Repo = atom_binary(maps:get(repository, Nugget)),
    case maps:get(nugget_relpath, Nugget, <<>>) of
        <<>> ->
            <<"${ALLOY_MOTHERLODE}/", Repo/binary>>;
        RelPath ->
            <<"${ALLOY_MOTHERLODE}/", Repo/binary, "/", RelPath/binary>>
    end.
