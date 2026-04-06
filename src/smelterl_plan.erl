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

to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
to_list(Path) ->
    Path.

to_binary(Path) when is_binary(Path) ->
    Path;
to_binary(Path) ->
    unicode:characters_to_binary(Path).
