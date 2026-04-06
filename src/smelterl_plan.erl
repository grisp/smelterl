%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_plan).
-moduledoc """
Build-plan construction and serialization helpers.

The `plan` command writes `build_plan.term` through this module, and later
`generate` steps will load the same structure without re-running dependency
resolution.
""".


%=== EXPORTS ===================================================================

-export([new/5]).
-export([read_file/1]).
-export([select_target/2]).
-export([write_env_file/2]).
-export([write_file/2]).


%=== MACROS ====================================================================

-define(PLAN_TAG, build_plan).
-define(PLAN_VERSION, <<"1.0">>).


%=== API FUNCTIONS =============================================================

-doc """
Build one serialized plan payload from plan-stage pipeline outputs.
""".
-spec new(
    smelterl:nugget_id(),
    smelterl:extra_config(),
    #{smelterl:target_id() => smelterl:build_target()},
    [smelterl:target_id()],
    smelterl:manifest_seed()
) ->
    {ok, smelterl:build_plan()} | {error, term()}.
new(ProductId, ExtraConfig, Targets, AuxiliaryIds, ManifestSeed) when
    is_atom(ProductId),
    is_map(ExtraConfig),
    is_map(Targets),
    is_list(AuxiliaryIds),
    is_map(ManifestSeed)
->
    {ok,
        #{
            product => ProductId,
            extra_config => ExtraConfig,
            targets => Targets,
            auxiliary_ids => AuxiliaryIds,
            manifest_seed => ManifestSeed
        }};
new(ProductId, ExtraConfig, Targets, AuxiliaryIds, ManifestSeed) ->
    {error,
        {invalid_build_plan,
            #{
                product => ProductId,
                extra_config => ExtraConfig,
                targets => Targets,
                auxiliary_ids => AuxiliaryIds,
                manifest_seed => ManifestSeed
            }}}.

-doc """
Write one build plan to the requested output path.
""".
-spec write_file(smelterl:file_path() | string(), smelterl:build_plan()) ->
    ok | {error, term()}.
write_file(Path, Plan) ->
    smelterl_file:write_term(Path, to_term(Plan)).

-doc """
Write one bash-friendly build-plan summary to the requested output path.
""".
-spec write_env_file(smelterl:file_path() | string(), smelterl:build_plan()) ->
    ok | {error, term()}.
write_env_file(Path, Plan) ->
    maybe
        {ok, Content} ?= format_env_file(Plan),
        write_binary_file(Path, unicode:characters_to_binary(Content))
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Read and validate one serialized build plan file.
""".
-spec read_file(smelterl:file_path() | string()) ->
    {ok, smelterl:build_plan()} | {error, term()}.
read_file(Path) ->
    PathString = to_list(Path),
    case file:consult(PathString) of
        {ok, [Term]} ->
            from_term(Term);
        {ok, Terms} ->
            {error, {invalid_plan_file, {multiple_terms, length(Terms)}}};
        {error, Reason} ->
            {error, {read_failed, to_binary(PathString), Reason}}
    end.

-doc """
Resolve one selected target from a loaded build plan.
""".
-spec select_target(main | smelterl:target_id() | undefined, smelterl:build_plan()) ->
    {ok, smelterl:build_target()} | {error, term()}.
select_target(undefined, Plan) ->
    select_target(main, Plan);
select_target(TargetId, Plan) ->
    Targets = maps:get(targets, Plan, #{}),
    case maps:get(TargetId, Targets, undefined) of
        undefined ->
            {error, {unknown_target, TargetId}};
        Target ->
            {ok, Target}
    end.


%=== INTERNAL FUNCTIONS ========================================================

to_term(Plan) ->
    {?PLAN_TAG, ?PLAN_VERSION, [
        {product, maps:get(product, Plan)},
        {extra_config, maps:get(extra_config, Plan)},
        {targets, maps:get(targets, Plan)},
        {auxiliary_ids, maps:get(auxiliary_ids, Plan)},
        {manifest_seed, maps:get(manifest_seed, Plan)}
    ]}.

from_term({?PLAN_TAG, ?PLAN_VERSION, Fields}) when is_list(Fields) ->
    maybe
        {ok, ProductId} ?= required_field(product, Fields),
        {ok, ExtraConfig} ?= required_field(extra_config, Fields),
        {ok, Targets} ?= required_field(targets, Fields),
        {ok, AuxiliaryIds} ?= required_field(auxiliary_ids, Fields),
        {ok, ManifestSeed} ?= required_field(manifest_seed, Fields),
        true ?= is_atom(ProductId),
        true ?= is_map(ExtraConfig),
        true ?= is_map(Targets),
        true ?= is_list(AuxiliaryIds),
        true ?= is_map(ManifestSeed),
        {ok,
            #{
                product => ProductId,
                extra_config => ExtraConfig,
                targets => Targets,
                auxiliary_ids => AuxiliaryIds,
                manifest_seed => ManifestSeed
            }}
    else
        {error, _} = Error ->
            Error;
        false ->
            {error, {invalid_plan_fields, invalid_shape}}
    end;
from_term({?PLAN_TAG, Version, _Fields}) when is_binary(Version) ->
    {error, {unsupported_plan_version, Version}};
from_term({?PLAN_TAG, _Version, _Fields}) ->
    {error, {invalid_plan_file, invalid_version}};
from_term(Term) ->
    {error, {invalid_plan_file, {invalid_root, Term}}}.

required_field(Key, Fields) ->
    case proplists:get_value(Key, Fields, undefined) of
        undefined ->
            {error, {invalid_plan_fields, {missing_field, Key}}};
        Value ->
            {ok, Value}
    end.

format_env_file(Plan) ->
    maybe
        {ok, ProductId} ?= required_plan_field(product, Plan),
        {ok, ExtraConfig} ?= required_plan_field(extra_config, Plan),
        {ok, Targets} ?= required_plan_field(targets, Plan),
        {ok, AuxiliaryIds} ?= required_plan_field(auxiliary_ids, Plan),
        true ?= is_map(ExtraConfig),
        true ?= is_map(Targets),
        {ok, TargetIds} ?= target_ids(AuxiliaryIds),
        {ok, KindEntries} ?= target_entries(TargetIds, Targets, kind),
        {ok, RootEntries} ?= target_entries(TargetIds, Targets, root),
        {ok,
            [
                <<"# Generated by smelterl - do not edit\n">>,
                <<"# Source from bash for plan loop metadata.\n\n">>,
                scalar_assignment("ALLOY_PLAN_PRODUCT", atom_to_binary(ProductId, utf8)),
                scalar_assignment("ALLOY_PLAN_MAIN_TARGET", <<"main">>),
                <<"\n">>,
                array_assignment("ALLOY_PLAN_AUXILIARY_IDS", atom_binaries(AuxiliaryIds)),
                array_assignment("ALLOY_PLAN_TARGET_IDS", atom_binaries(TargetIds)),
                <<"\n">>,
                assoc_array_assignment("ALLOY_PLAN_TARGET_KIND", KindEntries),
                <<"\n">>,
                assoc_array_assignment("ALLOY_PLAN_TARGET_ROOT", RootEntries),
                <<"\n">>,
                assoc_array_assignment("ALLOY_PLAN_EXTRA_CONFIG", sorted_map_entries(ExtraConfig))
            ]}
    else
        {error, _} = Error ->
            Error;
        false ->
            {error, {invalid_plan_fields, invalid_shape}}
    end.

required_plan_field(Key, Plan) ->
    case maps:get(Key, Plan, undefined) of
        undefined ->
            {error, {invalid_plan_fields, {missing_field, Key}}};
        Value ->
            {ok, Value}
    end.

target_ids(AuxiliaryIds) when is_list(AuxiliaryIds) ->
    {ok, AuxiliaryIds ++ [main]};
target_ids(AuxiliaryIds) ->
    {error, {invalid_plan_fields, {invalid_auxiliary_ids, AuxiliaryIds}}}.

target_entries(TargetIds, Targets, kind) ->
    target_entries(TargetIds, Targets, kind, []);
target_entries(TargetIds, Targets, root) ->
    target_entries(TargetIds, Targets, root, []).

target_entries([], _Targets, _Field, Acc) ->
    {ok, lists:reverse(Acc)};
target_entries([TargetId | Rest], Targets, Field, Acc0) ->
    maybe
        {ok, Target} ?= required_target(TargetId, Targets),
        {ok, Value} ?= target_entry(Field, Target),
        target_entries(
            Rest,
            Targets,
            Field,
            [{atom_to_binary(TargetId, utf8), Value} | Acc0]
        )
    else
        {error, _} = Error ->
            Error
    end.

required_target(TargetId, Targets) ->
    case maps:get(TargetId, Targets, undefined) of
        undefined ->
            {error, {invalid_plan_fields, {missing_target, TargetId}}};
        Target when is_map(Target) ->
            {ok, Target};
        Target ->
            {error, {invalid_plan_fields, {invalid_target, TargetId, Target}}}
    end.

target_entry(kind, Target) ->
    case maps:get(kind, Target, undefined) of
        main ->
            {ok, <<"main">>};
        auxiliary ->
            {ok, <<"auxiliary">>};
        Kind ->
            {error, {invalid_plan_fields, {invalid_target_kind, Kind}}}
    end;
target_entry(root, Target) ->
    case maps:get(kind, Target, undefined) of
        main ->
            target_tree_root(Target);
        auxiliary ->
            case maps:get(aux_root, Target, undefined) of
                AuxRoot when is_atom(AuxRoot) ->
                    {ok, atom_to_binary(AuxRoot, utf8)};
                AuxRoot ->
                    {error, {invalid_plan_fields, {invalid_aux_root, AuxRoot}}}
            end;
        Kind ->
            {error, {invalid_plan_fields, {invalid_target_kind, Kind}}}
    end.

target_tree_root(Target) ->
    case maps:get(tree, Target, undefined) of
        #{root := Root} when is_atom(Root) ->
            {ok, atom_to_binary(Root, utf8)};
        Tree ->
            {error, {invalid_plan_fields, {invalid_target_tree, Tree}}}
    end.

atom_binaries(Atoms) ->
    [atom_to_binary(Atom, utf8) || Atom <- Atoms].

sorted_map_entries(Map) ->
    lists:keysort(1, maps:to_list(Map)).

scalar_assignment(Name, Value) ->
    [Name, <<"=">>, shell_quote(Value), <<"\n">>].

array_assignment(Name, Values) ->
    QuotedValues = [shell_quote(Value) || Value <- Values],
    [Name, <<"=(">>, join_with_space(QuotedValues), <<")\n">>].

assoc_array_assignment(Name, Entries) ->
    [
        <<"declare -A ">>, Name, <<"=(\n">>,
        [[<<"  [">>, shell_quote(Key), <<"]=">>, shell_quote(Value), <<"\n">>] ||
            {Key, Value} <- Entries],
        <<")\n">>
    ].

join_with_space([]) ->
    [];
join_with_space([Value]) ->
    Value;
join_with_space([Value | Rest]) ->
    [Value, <<" ">>, join_with_space(Rest)].

shell_quote(Value) when is_atom(Value) ->
    shell_quote(atom_to_binary(Value, utf8));
shell_quote(Value) when is_list(Value) ->
    shell_quote(unicode:characters_to_binary(Value));
shell_quote(Value) when is_binary(Value) ->
    [<<"'">>, binary:replace(Value, <<"\'">>, <<"'\"'\"'">>, [global]), <<"\'">>].

write_binary_file(Path, Content) when is_binary(Path); is_list(Path) ->
    PathString = to_list(Path),
    case file:open(PathString, [write, binary]) of
        {ok, Device} ->
            Result =
                case file:write(Device, Content) of
                    ok ->
                        ok;
                    {error, Reason} ->
                        {error, {write_failed, Reason}}
                end,
            _ = file:close(Device),
            Result;
        {error, Posix} ->
            {error, {open_failed, to_binary(PathString), Posix}}
    end.

to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
to_list(Path) ->
    Path.

to_binary(Path) when is_binary(Path) ->
    Path;
to_binary(Path) ->
    unicode:characters_to_binary(Path).
