%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_cmd_generate).
-moduledoc """
`smelterl generate` command implementation.

This initial generate-stage command handler owns CLI option parsing and
selected-target validation. It loads one precomputed build plan, enforces the
main-target-only option matrix, and resolves either the main or one auxiliary
target without rerunning planning work.
""".

-behaviour(smelterl_command).

%=== EXPORTS ===================================================================

-export([actions/0]).
-export([help/1]).
-export([options_spec/1]).
-export([run/2]).


%=== BEHAVIOUR smelterl_command CALLBACKS ======================================

actions() ->
    [generate].

options_spec(generate) ->
    [
        #{name => plan, long => "plan", type => value},
        #{name => auxiliary, long => "auxiliary", type => value},
        #{name => output_external_desc, long => "output-external-desc", type => value},
        #{name => output_config_in, long => "output-config-in", type => value},
        #{name => output_external_mk, long => "output-external-mk", type => value},
        #{name => output_defconfig, long => "output-defconfig", type => value},
        #{name => output_context, long => "output-context", type => value},
        #{name => buildroot_legal, long => "buildroot-legal", type => accum},
        #{name => export_legal, long => "export-legal", type => value},
        #{name => include_sources, long => "include-sources", type => flag},
        #{name => output_manifest, long => "output-manifest", type => value},
        #{name => log, long => "log", type => value},
        #{name => verbose, long => "verbose", type => flag},
        #{name => debug, long => "debug", type => flag}
    ].

help(generate) ->
    [
        "Usage: smelterl generate [OPTIONS]\n\n",
        "Required:\n",
        "  --plan PATH                 Input path for build_plan.term\n\n",
        "Optional target selection:\n",
        "  --auxiliary AUX_ID          Generate one auxiliary target instead of main\n\n",
        "Common outputs:\n",
        "  --output-external-desc PATH Output path for external.desc\n",
        "  --output-config-in PATH     Output path for Config.in\n",
        "  --output-external-mk PATH   Output path for external.mk\n",
        "  --output-defconfig PATH     Output path for defconfig\n",
        "  --output-context PATH       Output path for alloy_context.sh\n\n",
        "Main-target only:\n",
        "  --buildroot-legal PATH      Repeatable Buildroot legal-info input\n",
        "  --export-legal PATH         Export directory relative to manifest\n",
        "  --include-sources           Include source trees in legal export\n",
        "  --output-manifest PATH      Output path for ALLOY_SDK_MANIFEST\n\n",
        "Logging:\n",
        "  --log LEVEL                 Logging level\n",
        "  --verbose                   Enable verbose logging\n",
        "  --debug                     Enable debug logging\n",
        "  --help, -h                  Show this help text\n"
    ].

run(generate, Opts) ->
    maybe
        ok ?= require_options(Opts),
        ok ?= validate_option_matrix(Opts),
        run_generate(Opts)
    else
        {error, Message} ->
            smelterl_log:error("~ts~n", [Message]),
            2
    end.


%=== INTERNAL FUNCTIONS ========================================================

run_generate(Opts) ->
    PlanPath = maps:get(plan, Opts),
    TargetId = selected_target_id(Opts),
    maybe
        {ok, Plan} ?= load_plan(PlanPath),
        {ok, Target} ?= select_target(TargetId, Plan),
        ok ?= maybe_write_external_desc(Opts, Plan, Target),
        0
    else
        {plan_error, Reason} ->
            smelterl_log:error("~ts~n", [format_plan_error(PlanPath, Reason)]),
            1;
        {target_error, Reason} ->
            smelterl_log:error("~ts~n", [format_target_error(Reason)]),
            1;
        {generate_error, Reason} ->
            smelterl_log:error("~ts~n", [format_generate_error(Reason)]),
            1
    end.

require_options(Opts) ->
    maybe
        {ok, _PlanPath} ?= required_option(Opts, plan, "generate requires --plan."),
        ok
    else
        {error, _} = Error ->
            Error
    end.

required_option(Opts, Key, Message) ->
    case maps:get(Key, Opts, undefined) of
        undefined ->
            {error, Message};
        [] ->
            {error, Message};
        Value ->
            {ok, Value}
    end.

validate_option_matrix(Opts) ->
    maybe
        ok ?= validate_auxiliary_restrictions(Opts),
        ok ?= validate_manifest_dependencies(Opts),
        ok
    else
        {error, _} = Error ->
            Error
    end.

validate_auxiliary_restrictions(Opts) ->
    case option_present(Opts, auxiliary) of
        false ->
            ok;
        true ->
            validate_auxiliary_main_only_options(Opts)
    end.

validate_auxiliary_main_only_options(Opts) ->
    case first_present_option(
        Opts,
        [output_manifest, buildroot_legal, export_legal, include_sources]
    ) of
        undefined ->
            ok;
        output_manifest ->
            {error,
                "generate: --output-manifest is only valid for main-target generation."};
        buildroot_legal ->
            {error,
                "generate: --buildroot-legal is only valid for main-target generation."};
        export_legal ->
            {error,
                "generate: --export-legal is only valid for main-target generation."};
        include_sources ->
            {error,
                "generate: --include-sources is only valid for main-target generation."}
    end.

validate_manifest_dependencies(Opts) ->
    case option_present(Opts, include_sources) of
        true ->
            validate_include_sources_dependencies(Opts);
        false ->
            validate_export_legal_dependencies(Opts)
    end.

validate_include_sources_dependencies(Opts) ->
    case option_present(Opts, export_legal) of
        false ->
            {error, "generate: --include-sources requires --export-legal."};
        true ->
            validate_export_legal_dependencies(Opts)
    end.

validate_export_legal_dependencies(Opts) ->
    case option_present(Opts, export_legal) of
        true ->
            case option_present(Opts, output_manifest) of
                true ->
                    ok;
                false ->
                    {error, "generate: --export-legal requires --output-manifest."}
            end;
        _ ->
            ok
    end.

option_present(Opts, Key) ->
    case maps:get(Key, Opts, undefined) of
        undefined ->
            false;
        [] ->
            false;
        _Value ->
            true
    end.

first_present_option(_Opts, []) ->
    undefined;
first_present_option(Opts, [Key | Rest]) ->
    case option_present(Opts, Key) of
        true ->
            Key;
        false ->
            first_present_option(Opts, Rest)
    end.

selected_target_id(Opts) ->
    case maps:get(auxiliary, Opts, undefined) of
        undefined ->
            main;
        AuxiliaryId ->
            list_to_atom(AuxiliaryId)
    end.

load_plan(Path) ->
    case smelterl_plan:read_file(Path) of
        {ok, _Plan} = Ok ->
            Ok;
        {error, Reason} ->
            {plan_error, Reason}
    end.

select_target(TargetId, Plan) ->
    case smelterl_plan:select_target(TargetId, Plan) of
        {ok, Target} ->
            {ok, Target};
        {error, {unknown_target, main}} ->
            {target_error, missing_main_target};
        {error, {unknown_target, AuxiliaryId}} ->
            {target_error, {unknown_auxiliary_target, AuxiliaryId}}
    end.

maybe_write_external_desc(Opts, Plan, Target) ->
    case maps:get(output_external_desc, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            write_external_desc(Path, maps:get(product, Plan), Target)
    end.

write_external_desc(Path, ProductId, Target) ->
    Motherlode = maps:get(motherlode, Target, #{}),
    case with_output_device(Path, fun(Device) ->
        smelterl_gen_external_desc:generate(ProductId, Motherlode, Device)
    end) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {external_desc_open_failed, OutputPath, Posix}};
        {error, Reason} ->
            {generate_error, {external_desc_failed, Reason}}
    end.

with_output_device("-", Fun) ->
    Fun(standard_io);
with_output_device(Path, Fun) ->
    PathString = path_to_list(Path),
    case file:open(PathString, [write, binary]) of
        {ok, Device} ->
            Result = Fun(Device),
            _ = file:close(Device),
            Result;
        {error, Posix} ->
            {error, {open_failed, path_to_binary(PathString), Posix}}
    end.

format_plan_error(Path, {read_failed, _ResolvedPath, Posix}) ->
    io_lib:format(
        "generate: failed to read build plan '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_plan_error(Path, {unsupported_plan_version, Version}) ->
    io_lib:format(
        "generate: unsupported build plan version '~ts' in '~ts'.",
        [Version, Path]
    );
format_plan_error(Path, {invalid_plan_file, Reason}) ->
    io_lib:format(
        "generate: invalid build plan file '~ts': ~tp",
        [Path, Reason]
    );
format_plan_error(Path, {invalid_plan_fields, Reason}) ->
    io_lib:format(
        "generate: invalid build plan file '~ts': ~tp",
        [Path, Reason]
    );
format_plan_error(Path, Reason) ->
    io_lib:format("generate: failed to load build plan '~ts': ~tp", [Path, Reason]).

format_target_error(missing_main_target) ->
    "generate: build plan is missing the main target.";
format_target_error({unknown_auxiliary_target, AuxiliaryId}) ->
    io_lib:format(
        "generate: unknown auxiliary target '~ts'.",
        [atom_to_binary(AuxiliaryId, utf8)]
    ).

format_generate_error({external_desc_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open external.desc output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({external_desc_failed, {missing_product_metadata, ProductId}}) ->
    io_lib:format(
        "generate: build plan motherlode is missing product metadata for '~ts'.",
        [atom_to_binary(ProductId, utf8)]
    );
format_generate_error({external_desc_failed, {render_failed, external_desc, Detail}}) ->
    io_lib:format(
        "generate: failed to render external.desc: ~tp",
        [Detail]
    );
format_generate_error({external_desc_failed, {write_failed, _PathOrDevice, Detail}}) ->
    io_lib:format(
        "generate: failed to write external.desc: ~tp",
        [Detail]
    );
format_generate_error({external_desc_failed, Reason}) ->
    io_lib:format(
        "generate: external.desc generation failed: ~tp",
        [Reason]
    ).

path_to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
path_to_list(Path) ->
    Path.

path_to_binary(Path) when is_binary(Path) ->
    Path;
path_to_binary(Path) ->
    unicode:characters_to_binary(Path).
