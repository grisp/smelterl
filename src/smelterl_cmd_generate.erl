%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_cmd_generate).
-moduledoc """
`smelterl generate` command implementation.

This generate-stage command handler owns CLI option parsing, selected-target
validation, and target-scoped artefact writing from a precomputed build plan.
For main-target generation it also finalizes the SDK manifest, optionally
consuming merged Buildroot legal data and exporting the merged legal tree.
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
    case resolve_log_level(Opts) of
        {ok, LogLevel} ->
            smelterl_log:with_log_level(
                LogLevel,
                fun() ->
                    maybe
                        ok ?= require_options(Opts),
                        ok ?= validate_option_matrix(Opts),
                        run_generate(Opts)
                    else
                        {error, Message} ->
                            smelterl_log:error("~ts~n", [Message]),
                            2
                    end
                end
            );
        {error, Message} ->
            smelterl_log:error("~ts~n", [Message]),
            2
    end.


%=== INTERNAL FUNCTIONS ========================================================

run_generate(Opts) ->
    PlanPath = maps:get(plan, Opts),
    TargetId = selected_target_id(Opts),
    maybe
        smelterl_log:info("generate: loading build plan '~ts'.~n", [PlanPath]),
        {ok, Plan} ?= load_plan(PlanPath),
        {ok, Target} ?= select_target(TargetId, Plan),
        smelterl_log:info(
            "generate: rendering target '~ts' (~ts).~n",
            [
                selected_target_label(TargetId),
                atom_to_binary(maps:get(kind, Target), utf8)
            ]
        ),
        smelterl_log:debug(
            "generate: target topology has ~B nuggets.~n",
            [length(maps:get(topology, Target, []))]
        ),
        ok ?= maybe_write_external_desc(Opts, Plan, Target),
        ok ?= maybe_write_config_in(Opts, Plan, Target),
        ok ?= maybe_write_external_mk(Opts, Target),
        ok ?= maybe_write_defconfig(Opts, Target),
        ok ?= maybe_write_context(Opts, Plan, Target),
        {ok, BuildrootLegal, ManifestSeed} ?= maybe_prepare_manifest_legal(
            Opts,
            Plan,
            Target
        ),
        ok ?= maybe_write_manifest(Opts, ManifestSeed, BuildrootLegal),
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

resolve_log_level(Opts) ->
    BaseLevel =
        case maps:get(log, Opts, undefined) of
            undefined ->
                {ok, warning};
            Value ->
                case smelterl_log:parse_level(Value) of
                    {ok, Level} ->
                        {ok, Level};
                    error ->
                        {error,
                            io_lib:format(
                                "generate: invalid log level '~ts'. Expected error, warning, info, or debug.",
                                [Value]
                            )}
                end
        end,
    case BaseLevel of
        {error, _} = Error ->
            Error;
        {ok, Level0} ->
            Level1 =
                case maps:get(verbose, Opts, false) of
                    true -> info;
                    false -> Level0
                end,
            Level2 =
                case maps:get(debug, Opts, false) of
                    true -> debug;
                    false -> Level1
                end,
            {ok, Level2}
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

selected_target_label(main) ->
    <<"main">>;
selected_target_label(TargetId) ->
    atom_to_binary(TargetId, utf8).

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
            smelterl_log:debug("generate: writing external.desc to '~ts'.~n", [Path]),
            write_external_desc(Path, maps:get(product, Plan), Target)
    end.

maybe_write_config_in(Opts, Plan, Target) ->
    case maps:get(output_config_in, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            smelterl_log:debug("generate: writing Config.in to '~ts'.~n", [Path]),
            write_config_in(Path, Plan, Target)
    end.

maybe_write_external_mk(Opts, Target) ->
    case maps:get(output_external_mk, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            smelterl_log:debug("generate: writing external.mk to '~ts'.~n", [Path]),
            write_external_mk(Path, Target)
    end.

maybe_write_defconfig(Opts, Target) ->
    case maps:get(output_defconfig, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            smelterl_log:debug("generate: writing defconfig to '~ts'.~n", [Path]),
            write_defconfig(Path, Target)
    end.

maybe_write_context(Opts, Plan, Target) ->
    case maps:get(output_context, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            smelterl_log:debug("generate: writing alloy_context.sh to '~ts'.~n", [Path]),
            write_context(Path, Plan, Target)
    end.

maybe_prepare_manifest_legal(Opts, Plan, Target) ->
    ManifestSeed0 = maps:get(manifest_seed, Plan),
    BuildrootPaths = [
        path_to_binary(Path)
     || Path <- maps:get(buildroot_legal, Opts, [])
    ],
    case maps:get(export_legal, Opts, undefined) of
        undefined ->
            collect_manifest_legal(
                BuildrootPaths,
                undefined,
                Opts,
                ManifestSeed0,
                Plan,
                Target
            );
        [] ->
            collect_manifest_legal(
                BuildrootPaths,
                undefined,
                Opts,
                ManifestSeed0,
                Plan,
                Target
            );
        ExportLegalPath ->
            collect_manifest_legal(
                BuildrootPaths,
                export_dir(Opts, ExportLegalPath),
                Opts,
                ManifestSeed0,
                Plan,
                Target
            )
    end.

collect_manifest_legal([], undefined, _Opts, ManifestSeed, _Plan, _Target) ->
    {ok, undefined, ManifestSeed};
collect_manifest_legal([], _ExportDir, Opts, ManifestSeed0, Plan, Target) ->
    case export_legal(Opts, maps:get(export_legal, Opts)) of
        ok ->
            export_alloy_legal(ManifestSeed0, Plan, Target, Opts, undefined);
        {generate_error, _} = Error ->
            Error
    end;
collect_manifest_legal(BuildrootPaths, _ExportDir, Opts, ManifestSeed0, Plan, Target) ->
    IncludeSources = maps:get(include_sources, Opts, false),
    case smelterl_legal:collect_legal(
        BuildrootPaths,
        case maps:get(export_legal, Opts, undefined) of
            undefined ->
                undefined;
            [] ->
                undefined;
            ExportLegalPath ->
                export_dir(Opts, ExportLegalPath)
        end,
        IncludeSources
    ) of
        {ok, LegalInfo} ->
            export_alloy_legal(ManifestSeed0, Plan, Target, Opts, LegalInfo);
        {error, Reason} ->
            {generate_error, {legal_collect_failed, Reason}}
    end.

export_alloy_legal(ManifestSeed0, Plan, Target, Opts, BuildrootLegal) ->
    case maps:get(export_legal, Opts, undefined) of
        undefined ->
            {ok, BuildrootLegal, ManifestSeed0};
        [] ->
            {ok, BuildrootLegal, ManifestSeed0};
        ExportLegalPath ->
            ExportDir = export_dir(Opts, ExportLegalPath),
            IncludeSources = maps:get(include_sources, Opts, false),
            smelterl_log:info(
                "generate: exporting alloy legal metadata to '~ts'.~n",
                [ExportDir]
            ),
            case smelterl_legal:export_alloy(
                ManifestSeed0,
                Target,
                maps:get(extra_config, Plan, #{}),
                ExportDir,
                IncludeSources
            ) of
                {ok, ManifestSeed} ->
                    {ok, BuildrootLegal, ManifestSeed};
                {error, Reason} ->
                    {generate_error, {legal_export_failed, Reason}}
            end
    end.

maybe_write_manifest(Opts, ManifestSeed, BuildrootLegal) ->
    case maps:get(output_manifest, Opts, undefined) of
        undefined ->
            ok;
        [] ->
            ok;
        Path ->
            write_manifest(Path, ManifestSeed, BuildrootLegal)
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

write_config_in(Path, Plan, Target) ->
    Topology = maps:get(topology, Target, []),
    Motherlode = maps:get(motherlode, Target, #{}),
    ExtraConfigKeys = maps:keys(maps:get(extra_config, Plan, #{})),
    case with_output_device(Path, fun(Device) ->
        smelterl_gen_config_in:generate(
            Topology,
            Motherlode,
            ExtraConfigKeys,
            Device
        )
    end) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {config_in_open_failed, OutputPath, Posix}};
        {error, Reason} ->
            {generate_error, {config_in_failed, Reason}}
    end.

write_external_mk(Path, Target) ->
    Topology = maps:get(topology, Target, []),
    Motherlode = maps:get(motherlode, Target, #{}),
    case with_output_device(Path, fun(Device) ->
        smelterl_gen_external_mk:generate(Topology, Motherlode, Device)
    end) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {external_mk_open_failed, OutputPath, Posix}};
        {error, Reason} ->
            {generate_error, {external_mk_failed, Reason}}
    end.

write_defconfig(Path, Target) ->
    DefconfigModel = maps:get(defconfig, Target, #{}),
    case with_output_device(Path, fun(Device) ->
        smelterl_gen_defconfig:render(DefconfigModel, Device)
    end) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {defconfig_open_failed, OutputPath, Posix}};
        {error, Reason} ->
            {generate_error, {defconfig_failed, Reason}}
    end.

write_context(Path, Plan, Target) ->
    ProductId = maps:get(product, Plan),
    case with_output_device(Path, fun(Device) ->
        smelterl_gen_context:render(ProductId, Target, Device)
    end) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {context_open_failed, OutputPath, Posix}};
        {error, Reason} ->
            {generate_error, {context_failed, Reason}}
    end.

export_legal(Opts, ExportLegalPath) ->
    ExportDir = export_dir(Opts, ExportLegalPath),
    BuildrootPaths = [
        path_to_binary(Path)
     || Path <- maps:get(buildroot_legal, Opts, [])
    ],
    IncludeSources = maps:get(include_sources, Opts, false),
    case smelterl_legal:export_legal(BuildrootPaths, ExportDir, IncludeSources) of
        ok ->
            ok;
        {error, Reason} ->
            {generate_error, {legal_export_failed, Reason}}
    end.

export_dir(Opts, ExportLegalPath) ->
    ManifestPath = maps:get(output_manifest, Opts),
    ExportRoot = manifest_base_path(ManifestPath),
    smelterl_file:resolve_path(ExportLegalPath, ExportRoot).

write_manifest(Path, ManifestSeed, BuildrootLegal) ->
    BasePath = path_to_binary(manifest_base_path(Path)),
    PathOrDevice =
        case Path of
            "-" ->
                standard_io;
            _ ->
                Path
        end,
    case smelterl_gen_manifest:generate(
        ManifestSeed,
        BuildrootLegal,
        BasePath,
        PathOrDevice
    ) of
        ok ->
            ok;
        {error, {open_failed, OutputPath, Posix}} ->
            {generate_error, {manifest_open_failed, OutputPath, Posix}};
        {error, {write_failed, Reason}} ->
            {generate_error, {manifest_write_failed, Reason}};
        {error, Reason} ->
            {generate_error, {manifest_failed, Reason}}
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
    );
format_generate_error({config_in_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open Config.in output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({config_in_failed, {missing_nugget_metadata, NuggetId}}) ->
    io_lib:format(
        "generate: build plan target is missing nugget metadata for '~ts'.",
        [atom_to_binary(NuggetId, utf8)]
    );
format_generate_error({config_in_failed, {missing_packages_dir, NuggetId, Path}}) ->
    io_lib:format(
        "generate: nugget '~ts' packages directory is missing: ~ts",
        [atom_to_binary(NuggetId, utf8), Path]
    );
format_generate_error({config_in_failed, {render_failed, config_in, Detail}}) ->
    io_lib:format(
        "generate: failed to render Config.in: ~tp",
        [Detail]
    );
format_generate_error({config_in_failed, {write_failed, _PathOrDevice, Detail}}) ->
    io_lib:format(
        "generate: failed to write Config.in: ~tp",
        [Detail]
    );
format_generate_error({config_in_failed, Reason}) ->
    io_lib:format(
        "generate: Config.in generation failed: ~tp",
        [Reason]
    );
format_generate_error({external_mk_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open external.mk output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({external_mk_failed, {missing_nugget_metadata, NuggetId}}) ->
    io_lib:format(
        "generate: build plan target is missing nugget metadata for '~ts'.",
        [atom_to_binary(NuggetId, utf8)]
    );
format_generate_error({external_mk_failed, {missing_packages_dir, NuggetId, Path}}) ->
    io_lib:format(
        "generate: nugget '~ts' packages directory is missing: ~ts",
        [atom_to_binary(NuggetId, utf8), Path]
    );
format_generate_error({external_mk_failed, {render_failed, external_mk, Detail}}) ->
    io_lib:format(
        "generate: failed to render external.mk: ~tp",
        [Detail]
    );
format_generate_error({external_mk_failed, {write_failed, _PathOrDevice, Detail}}) ->
    io_lib:format(
        "generate: failed to write external.mk: ~tp",
        [Detail]
    );
format_generate_error({external_mk_failed, Reason}) ->
    io_lib:format(
        "generate: external.mk generation failed: ~tp",
        [Reason]
    );
format_generate_error({defconfig_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open defconfig output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({defconfig_failed, {render_failed, defconfig, Detail}}) ->
    io_lib:format(
        "generate: failed to render defconfig: ~tp",
        [Detail]
    );
format_generate_error({defconfig_failed, {write_failed, _PathOrDevice, Detail}}) ->
    io_lib:format(
        "generate: failed to write defconfig: ~tp",
        [Detail]
    );
format_generate_error({defconfig_failed, Reason}) ->
    io_lib:format(
        "generate: defconfig generation failed: ~tp",
        [Reason]
    );
format_generate_error({context_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open alloy_context.sh output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({context_failed, {missing_nugget_metadata, NuggetId}}) ->
    io_lib:format(
        "generate: build plan target is missing nugget metadata for '~ts'.",
        [atom_to_binary(NuggetId, utf8)]
    );
format_generate_error({context_failed, {render_failed, alloy_context, Detail}}) ->
    io_lib:format(
        "generate: failed to render alloy_context.sh: ~tp",
        [Detail]
    );
format_generate_error({context_failed, {write_failed, _PathOrDevice, Detail}}) ->
    io_lib:format(
        "generate: failed to write alloy_context.sh: ~tp",
        [Detail]
    );
format_generate_error({legal_export_failed, {export_exists, Path}}) ->
    io_lib:format(
        "generate: legal export directory already exists: ~ts",
        [Path]
    );
format_generate_error({legal_collect_failed, {export_exists, Path}}) ->
    io_lib:format(
        "generate: legal export directory already exists: ~ts",
        [Path]
    );
format_generate_error({legal_collect_failed, Reason}) ->
    io_lib:format(
        "generate: failed to collect Buildroot legal data: ~tp",
        [Reason]
    );
format_generate_error({legal_export_failed, Reason}) ->
    io_lib:format(
        "generate: legal-info export failed: ~tp",
        [Reason]
    );
format_generate_error({manifest_open_failed, Path, Posix}) ->
    io_lib:format(
        "generate: failed to open ALLOY_SDK_MANIFEST output '~ts': ~ts",
        [Path, file:format_error(Posix)]
    );
format_generate_error({manifest_write_failed, Reason}) ->
    io_lib:format(
        "generate: failed to write ALLOY_SDK_MANIFEST: ~tp",
        [Reason]
    );
format_generate_error({manifest_failed, Reason}) ->
    io_lib:format(
        "generate: ALLOY_SDK_MANIFEST generation failed: ~tp",
        [Reason]
    );
format_generate_error({context_failed, Reason}) ->
    io_lib:format(
        "generate: alloy_context.sh generation failed: ~tp",
        [Reason]
    ).

manifest_base_path("-") ->
    {ok, CurrentDir} = file:get_cwd(),
    CurrentDir;
manifest_base_path(Path) ->
    filename:dirname(path_to_list(Path)).

path_to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
path_to_list(Path) ->
    Path.

path_to_binary(Path) when is_binary(Path) ->
    Path;
path_to_binary(Path) ->
    unicode:characters_to_binary(Path).
