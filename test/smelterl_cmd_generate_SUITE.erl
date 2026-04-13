-module(smelterl_cmd_generate_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    global_help_lists_generate_command/1,
    command_help_shows_generate_usage/1,
    generate_requires_plan/1,
    generate_rejects_unknown_argument/1,
    generate_rejects_main_only_options_for_auxiliary/1,
    generate_requires_output_manifest_for_export_legal/1,
    generate_requires_export_legal_for_include_sources/1,
    generate_accepts_valid_main_and_auxiliary_target_selection/1,
    generate_writes_manifest_with_exported_buildroot_legal/1,
    generate_exports_merged_legal_tree/1,
    generate_reports_unknown_auxiliary_target/1,
    generate_writes_config_in_from_plan_extra_config/1,
    generate_writes_external_mk_from_plan/1,
    generate_writes_defconfig_from_plan_model/1,
    generate_writes_context_from_plan/1,
    generated_context_passes_bash_validation/1
]).

all() ->
    [
        global_help_lists_generate_command,
        command_help_shows_generate_usage,
        generate_requires_plan,
        generate_rejects_unknown_argument,
        generate_rejects_main_only_options_for_auxiliary,
        generate_requires_output_manifest_for_export_legal,
        generate_requires_export_legal_for_include_sources,
        generate_accepts_valid_main_and_auxiliary_target_selection,
        generate_writes_manifest_with_exported_buildroot_legal,
        generate_exports_merged_legal_tree,
        generate_reports_unknown_auxiliary_target,
        generate_writes_config_in_from_plan_extra_config,
        generate_writes_external_mk_from_plan,
        generate_writes_defconfig_from_plan_model,
        generate_writes_context_from_plan,
        generated_context_passes_bash_validation
    ].

global_help_lists_generate_command(_Config) ->
    {Status, Output} = run_main(["--help"]),
    assert_equal(0, Status),
    assert_contains(Output, <<"Usage: smelterl">>),
    assert_contains(Output, <<"  generate">>).

command_help_shows_generate_usage(_Config) ->
    {Status, Output} = run_main(["generate", "--help"]),
    assert_equal(0, Status),
    assert_contains(Output, <<"Usage: smelterl generate [OPTIONS]">>),
    assert_contains(Output, <<"--plan PATH">>),
    assert_contains(Output, <<"--auxiliary AUX_ID">>).

generate_requires_plan(_Config) ->
    {Status, Output} = run_main(["generate"]),
    assert_equal(2, Status),
    assert_contains(Output, <<"generate requires --plan.">>).

generate_rejects_unknown_argument(_Config) ->
    {Status, Output} = run_main([
        "generate",
        "--plan", "/tmp/build_plan.term",
        "--bogus"
    ]),
    assert_equal(2, Status),
    assert_contains(Output, <<"generate: unknown argument '--bogus'">>).

generate_rejects_main_only_options_for_auxiliary(_Config) ->
    PlanPath = write_sample_plan_file(),
    assert_auxiliary_rejection(
        PlanPath,
        ["--output-manifest", "/tmp/ALLOY_SDK_MANIFEST"],
        <<"generate: --output-manifest is only valid for main-target generation.">>
    ),
    assert_auxiliary_rejection(
        PlanPath,
        ["--buildroot-legal", "/tmp/legal-info"],
        <<"generate: --buildroot-legal is only valid for main-target generation.">>
    ),
    assert_auxiliary_rejection(
        PlanPath,
        ["--export-legal", "legal-info"],
        <<"generate: --export-legal is only valid for main-target generation.">>
    ),
    assert_auxiliary_rejection(
        PlanPath,
        ["--include-sources"],
        <<"generate: --include-sources is only valid for main-target generation.">>
    ).

generate_requires_output_manifest_for_export_legal(_Config) ->
    PlanPath = write_sample_plan_file(),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--export-legal", "legal-info"
    ]),
    assert_equal(2, Status),
    assert_contains(
        Output,
        <<"generate: --export-legal requires --output-manifest.">>
    ).

generate_requires_export_legal_for_include_sources(_Config) ->
    PlanPath = write_sample_plan_file(),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--include-sources"
    ]),
    assert_equal(2, Status),
    assert_contains(
        Output,
        <<"generate: --include-sources requires --export-legal.">>
    ).

generate_accepts_valid_main_and_auxiliary_target_selection(_Config) ->
    PlanPath = write_sample_plan_file(),
    OutputDir = make_temp_dir("smelterl-generate-output"),
    MainExternalDesc = filename:join(OutputDir, "main.external.desc"),
    AuxiliaryExternalDesc = filename:join(OutputDir, "aux.external.desc"),
    {StatusMain, OutputMain} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-external-desc", MainExternalDesc,
        "--output-manifest", filename:join(OutputDir, "ALLOY_SDK_MANIFEST")
    ]),
    assert_equal(0, StatusMain),
    assert_equal(<<>>, OutputMain),
    assert_file_content(MainExternalDesc, expected_external_desc()),
    {StatusAux, OutputAux} = run_main([
        "generate",
        "--plan", PlanPath,
        "--auxiliary", "aux_alpha",
        "--output-external-desc", AuxiliaryExternalDesc
    ]),
    assert_equal(0, StatusAux),
    assert_equal(<<>>, OutputAux),
    assert_file_content(AuxiliaryExternalDesc, expected_external_desc()).

generate_writes_manifest_with_exported_buildroot_legal(_Config) ->
    PlanPath = write_sample_plan_file(),
    OutputDir = make_temp_dir("smelterl-generate-manifest-output"),
    {AuxLegalDir, MainLegalDir} = write_generate_legal_inputs(OutputDir),
    MainManifest = filename:join(OutputDir, "ALLOY_SDK_MANIFEST"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-manifest", MainManifest,
        "--buildroot-legal", AuxLegalDir,
        "--buildroot-legal", MainLegalDir,
        "--export-legal", "legal-info"
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    {ok, [{sdk_manifest, <<"1.0">>, Fields}]} = file:consult(MainManifest),
    BuildEnv = field_value(build_environment, Fields),
    assert_member({buildroot_version, <<"2025.02.1">>}, BuildEnv),
    BuildrootPackages = field_value(buildroot_packages, Fields),
    assert_member(
        {package, <<"auxpkg">>, [
            {version, <<"0.1.0">>},
            {license, <<"Apache-2.0">>},
            {license_files, [<<"legal-info/licenses/auxpkg-0.1.0/LICENSE">>]}
        ]},
        BuildrootPackages
    ),
    assert_member(
        {package, <<"mainpkg">>, [
            {version, <<"1.0.0">>},
            {license, <<"BSD-3-Clause">>},
            {license_files, [<<"legal-info/licenses/mainpkg-1.0.0/LICENSE">>]}
        ]},
        BuildrootPackages
    ),
    HostPackages = field_value(buildroot_host_packages, Fields),
    assert_member(
        {package, <<"host-main">>, [
            {version, <<"1.1">>},
            {license, <<"Apache-2.0">>},
            {license_files, [<<"legal-info/host-licenses/host-main-1.1/LICENSE">>]}
        ]},
        HostPackages
    ),
    Integrity = field_value(integrity, Fields),
    assert_member({digest_algorithm, sha256}, Integrity),
    assert_member({canonical_form, basic_term_canon}, Integrity).

generate_exports_merged_legal_tree(_Config) ->
    PlanPath = write_sample_plan_file(),
    OutputDir = make_temp_dir("smelterl-generate-legal-export"),
    {AuxLegalDir, MainLegalDir} = write_generate_legal_inputs(OutputDir),
    MainManifest = filename:join(OutputDir, "ALLOY_SDK_MANIFEST"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-manifest", MainManifest,
        "--buildroot-legal", AuxLegalDir,
        "--buildroot-legal", MainLegalDir,
        "--export-legal", "legal-info"
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_file_contains(
        filename:join(OutputDir, "legal-info/README"),
        [
            <<"--- From Buildroot (auxiliary: aux_alpha) ---">>,
            <<"Aux target README">>,
            <<"--- From Buildroot (main) ---">>,
            <<"Main target README">>
        ]
    ),
    assert_file_content(
        filename:join(OutputDir, "legal-info/buildroot.config"),
        <<"BR2_TARGET=main\n">>
    ).

generate_reports_unknown_auxiliary_target(_Config) ->
    PlanPath = write_sample_plan_file(),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--auxiliary", "missing_aux"
    ]),
    assert_equal(1, Status),
    assert_contains(
        Output,
        <<"generate: unknown auxiliary target 'missing_aux'.">>
    ).

generate_writes_config_in_from_plan_extra_config(_Config) ->
    {PlanPath, ExpectedConfigIn, _ExpectedExternalMk} = write_sample_plan_with_packages_file(),
    OutputDir = make_temp_dir("smelterl-generate-config-in-output"),
    ConfigInPath = filename:join(OutputDir, "Config.in"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-config-in", ConfigInPath
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_file_content(ConfigInPath, ExpectedConfigIn).

generate_writes_external_mk_from_plan(_Config) ->
    {PlanPath, _ExpectedConfigIn, ExpectedExternalMk} = write_sample_plan_with_packages_file(),
    OutputDir = make_temp_dir("smelterl-generate-external-mk-output"),
    ExternalMkPath = filename:join(OutputDir, "external.mk"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-external-mk", ExternalMkPath
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_file_content(ExternalMkPath, ExpectedExternalMk).

generate_writes_defconfig_from_plan_model(_Config) ->
    {PlanPath, ExpectedDefconfig} = write_sample_plan_with_defconfig_file(),
    OutputDir = make_temp_dir("smelterl-generate-defconfig-output"),
    DefconfigPath = filename:join(OutputDir, "main_defconfig"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-defconfig", DefconfigPath
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_file_content(DefconfigPath, ExpectedDefconfig).

generate_writes_context_from_plan(_Config) ->
    {PlanPath, ExpectedLines} = write_sample_plan_with_context_file(),
    OutputDir = make_temp_dir("smelterl-generate-context-output"),
    ContextPath = filename:join(OutputDir, "alloy_context.sh"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-context", ContextPath
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_file_contains(ContextPath, ExpectedLines).

generated_context_passes_bash_validation(_Config) ->
    {PlanPath, _ExpectedLines} = write_sample_plan_with_context_file(),
    OutputDir = make_temp_dir("smelterl-generate-context-bash-output"),
    ContextPath = filename:join(OutputDir, "alloy_context.sh"),
    {Status, Output} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-context", ContextPath
    ]),
    assert_equal(0, Status),
    assert_equal(<<>>, Output),
    assert_bash_syntax(ContextPath),
    assert_context_sources_in_bash(ContextPath),
    assert_shellcheck_clean(ContextPath).

run_main(Argv) ->
    ScriptDir = filename:dirname(code:which(?MODULE)),
    SmelterlEbin = filename:join(filename:dirname(ScriptDir), "ebin"),
    Eval = io_lib:format("halt(smelterl:main(~tp)).", [Argv]),
    Port =
        open_port(
            {spawn_executable, os:find_executable("erl")},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                use_stdio,
                {args, ["-noshell", "-pa", SmelterlEbin, "-eval", lists:flatten(Eval)]}
            ]
        ),
    collect_port_output(Port, []).

collect_port_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_port_output(Port, [Data | Acc]);
        {Port, {exit_status, Status}} ->
            {Status, iolist_to_binary(lists:reverse(Acc))}
    end.

assert_auxiliary_rejection(PlanPath, ExtraArgs, ExpectedMessage) ->
    {Status, Output} = run_main(
        [
            "generate",
            "--plan", PlanPath,
            "--auxiliary", "aux_alpha"
         ] ++ ExtraArgs
    ),
    assert_equal(2, Status),
    assert_contains(Output, ExpectedMessage).

write_sample_plan_file() ->
    OutputDir = make_temp_dir("smelterl-generate-plan"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),
    ok = smelterl_plan:write_file(PlanPath, sample_plan()),
    PlanPath.

sample_plan() ->
    MainTarget = #{
        id => main,
        kind => main,
        tree => #{
            root => demo,
            edges => #{
                builder_core => [],
                toolchain_core => [],
                platform_core => [],
                system_core => [platform_core],
                demo => [builder_core, toolchain_core, platform_core, system_core]
            }
        },
        topology => [builder_core, toolchain_core, platform_core, system_core, demo],
        motherlode => sample_motherlode(),
        config => #{},
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities([aux_alpha])
    },
    AuxiliaryTarget = #{
        id => aux_alpha,
        kind => auxiliary,
        aux_root => aux_alpha_root,
        constraints => [],
        tree => #{
            root => aux_alpha_root,
            edges => #{
                builder_core => [],
                toolchain_core => [],
                platform_core => [],
                system_core => [platform_core],
                aux_alpha_root =>
                    [builder_core, toolchain_core, platform_core, system_core]
            }
        },
        topology =>
            [builder_core, toolchain_core, platform_core, system_core, aux_alpha_root],
        motherlode => sample_motherlode(),
        config => #{},
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities([aux_alpha])
    },
    {ok, Plan} = smelterl_plan:new(
        demo,
        #{<<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>},
        #{
            main => MainTarget,
            aux_alpha => AuxiliaryTarget
        },
        [aux_alpha],
        sample_manifest_seed()
    ),
    Plan.

write_sample_plan_with_packages_file() ->
    {Topology, Motherlode, ExpectedConfigIn, ExpectedExternalMk} = sample_target_with_packages(),
    OutputDir = make_temp_dir("smelterl-generate-plan-with-packages"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),
    MainTarget = #{
        id => main,
        kind => main,
        tree => #{root => demo, edges => #{demo => []}},
        topology => Topology,
        motherlode => Motherlode,
        config => #{},
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities([aux_alpha])
    },
    AuxiliaryTarget = #{
        id => aux_alpha,
        kind => auxiliary,
        aux_root => aux_alpha_root,
        constraints => [],
        tree => #{root => aux_alpha_root, edges => #{aux_alpha_root => []}},
        topology => Topology,
        motherlode => Motherlode,
        config => #{},
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities([aux_alpha])
    },
    {ok, Plan} = smelterl_plan:new(
        demo,
        #{
            <<"ALLOY_CACHE_DIR">> => <<"${ALLOY_CACHE_DIR}">>,
            <<"ALLOY_BUILD_DIR">> => <<"${ALLOY_BUILD_DIR}">>,
            <<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>
        },
        #{
            main => MainTarget,
            aux_alpha => AuxiliaryTarget
        },
        [aux_alpha],
        sample_manifest_seed()
    ),
    ok = smelterl_plan:write_file(PlanPath, Plan),
    {PlanPath, ExpectedConfigIn, ExpectedExternalMk}.

write_sample_plan_with_defconfig_file() ->
    OutputDir = make_temp_dir("smelterl-generate-plan-with-defconfig"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),
    DefconfigModel = #{
        regular => [
            {<<"BR2_PACKAGE_DEMO">>, <<"y">>},
            {<<"BR2_TARGET_GENERIC_HOSTNAME">>, <<"\"demo-device\"">>}
        ],
        cumulative => [
            {<<"BR2_ROOTFS_OVERLAY">>,
                <<"\"${ALLOY_MOTHERLODE}/builtin/demo/overlay "
                  "${ALLOY_MOTHERLODE}/builtin/demo/overlay-extra\"">>},
            {<<"BR2_ROOTFS_POST_BUILD_SCRIPT">>,
                <<"\"$(BR2_EXTERNAL)/board/main/scripts/post-build.sh\"">>}
        ]
    },
    MainTarget = #{
        id => main,
        kind => main,
        tree => #{root => demo, edges => #{demo => []}},
        topology => [demo],
        motherlode => sample_motherlode(),
        config => #{},
        defconfig => DefconfigModel,
        capabilities => sample_capabilities([aux_alpha])
    },
    AuxiliaryTarget = #{
        id => aux_alpha,
        kind => auxiliary,
        aux_root => aux_alpha_root,
        constraints => [],
        tree => #{root => aux_alpha_root, edges => #{aux_alpha_root => []}},
        topology => [aux_alpha_root],
        motherlode => sample_motherlode(),
        config => #{},
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities([aux_alpha])
    },
    {ok, Plan} = smelterl_plan:new(
        demo,
        #{<<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>},
        #{
            main => MainTarget,
            aux_alpha => AuxiliaryTarget
        },
        [aux_alpha],
        sample_manifest_seed()
    ),
    ok = smelterl_plan:write_file(PlanPath, Plan),
    ExpectedDefconfig =
        <<"# Generated by smelterl - do not edit\n"
          "\n"
          "## Regular Configuration ##\n"
          "\n"
          "BR2_PACKAGE_DEMO=y\n"
          "BR2_TARGET_GENERIC_HOSTNAME=\"demo-device\"\n"
          "\n"
          "## Cumulative Configuration ##\n"
          "\n"
          "BR2_ROOTFS_OVERLAY=\"${ALLOY_MOTHERLODE}/builtin/demo/overlay "
          "${ALLOY_MOTHERLODE}/builtin/demo/overlay-extra\"\n"
          "BR2_ROOTFS_POST_BUILD_SCRIPT=\"$(BR2_EXTERNAL)/board/main/scripts/post-build.sh\"\n">>,
    {PlanPath, ExpectedDefconfig}.

write_sample_plan_with_context_file() ->
    OutputDir = make_temp_dir("smelterl-generate-plan-with-context"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),
    MainTarget = #{
        id => main,
        kind => main,
        tree => #{
            root => demo,
            edges => #{
                builder_core => [],
                toolchain_core => [],
                platform_core => [],
                system_core => [platform_core],
                demo => [builder_core, toolchain_core, platform_core, system_core]
            }
        },
        topology => [builder_core, toolchain_core, platform_core, system_core, demo],
        motherlode => #{
            nuggets => #{
                builder_core => #{
                    id => builder_core,
                    category => builder,
                    repository => builtin,
                    nugget_relpath => <<"builder_core">>,
                    name => <<"Builder Core">>,
                    version => <<"1.0.0">>
                },
                toolchain_core => #{
                    id => toolchain_core,
                    category => toolchain,
                    repository => builtin,
                    nugget_relpath => <<"toolchain_core">>,
                    name => <<"Toolchain Core">>,
                    version => <<"1.0.0">>
                },
                demo => #{
                    id => demo,
                    category => feature,
                    repository => builtin,
                    nugget_relpath => <<"demo">>,
                    name => <<"Demo Product">>,
                    description => <<"Demo product BSP">>,
                    version => <<"1.2.3">>,
                    sdk_outputs => [
                        {symbols, [{display_name, <<"Symbols">>}]}
                    ]
                },
                platform_core => #{
                    id => platform_core,
                    category => platform,
                    repository => builtin,
                    nugget_relpath => <<"platform_core">>,
                    name => <<"Platform Core">>,
                    version => <<"1.0.0">>,
                    hooks => [{pre_build, <<"scripts/pre-build.sh">>}],
                    embed => [{images, <<"rootfs.img">>}]
                },
                system_core => #{
                    id => system_core,
                    category => system,
                    repository => builtin,
                    nugget_relpath => <<"system_core">>,
                    name => <<"System Core">>,
                    version => <<"1.0.0">>
                }
            },
            repositories => #{}
        },
        config => #{
            <<"ALLOY_CONFIG_DEVICE_NAME">> => {global, undefined, <<"demo-box">>}
        },
        defconfig => #{regular => [], cumulative => []},
        capabilities => #{
            firmware_variants => [plain],
            variant_nuggets => #{plain => []},
            selectable_outputs => [],
            firmware_parameters => [],
            sdk_outputs_by_target => #{
                main => [#{id => symbols, nugget => demo, name => <<"Symbols">>}]
            }
        }
    },
    {ok, Plan} = smelterl_plan:new(
        demo,
        #{},
        #{main => MainTarget},
        [],
        sample_manifest_seed()
    ),
    ok = smelterl_plan:write_file(PlanPath, Plan),
    ExpectedLines = [
        <<"# Generated by smelterl - do not edit">>,
        <<"# Product: demo 1.2.3">>,
        <<"export ALLOY_PRODUCT=\"demo\"">>,
        <<"export ALLOY_FIRMWARE_VARIANTS=(\"plain\")">>,
        <<"ALLOY_PRE_BUILD_HOOKS=(\"platform_core:scripts/pre-build.sh\")">>,
        <<"ALLOY_EMBED_IMAGES=(\"rootfs.img\")">>,
        <<"export ALLOY_SDK_OUTPUTS=(\"symbols\")">>,
        <<"alloy_sdk_output_from_aux()">>
    ],
    {PlanPath, ExpectedLines}.

sample_capabilities(AuxiliaryIds) ->
    #{
        firmware_variants => [plain],
        variant_nuggets => #{plain => []},
        selectable_outputs => [],
        firmware_parameters => [],
        sdk_outputs_by_target =>
            maps:from_list([{TargetId, []} || TargetId <- [main | AuxiliaryIds]])
    }.

sample_motherlode() ->
    #{
        nuggets => #{
            builder_core => #{
                id => builder_core,
                category => builder
            },
            toolchain_core => #{
                id => toolchain_core,
                category => toolchain
            },
            platform_core => #{
                id => platform_core,
                category => platform
            },
            system_core => #{
                id => system_core,
                category => system
            },
            demo => #{
                id => demo,
                category => feature,
                description => <<"Demo product BSP">>,
                version => <<"1.2.3">>,
                name => <<"Demo Product">>
            },
            aux_alpha_root => #{
                id => aux_alpha_root,
                category => feature,
                name => <<"Aux Alpha">>,
                description => <<"Auxiliary alpha target">>,
                version => <<"0.1.0">>
            }
        },
        repositories => #{}
    }.

sample_target_with_packages() ->
    RootDir = make_temp_dir("smelterl-generate-packages"),
    RepoDir = filename:join(RootDir, "builtin"),
    ok = file:make_dir(RepoDir),
    ok = ensure_dir(filename:join(RepoDir, "platform_core/buildroot")),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/Config.in"),
        "# platform root\n"
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/external.mk"),
        "# platform root mk\n"
    ),
    ok = ensure_dir(filename:join(RepoDir, "platform_core/buildroot/pkg_alpha")),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/pkg_alpha/Config.in"),
        "# alpha\n"
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/pkg_alpha/pkg-alpha.mk"),
        "# alpha mk\n"
    ),
    ok = ensure_dir(filename:join(RepoDir, "product_core/packages/app_pkg")),
    ok = ensure_file(
        filename:join(RepoDir, "product_core/packages/app_pkg/Config.in"),
        "# app\n"
    ),
    ok = ensure_file(
        filename:join(RepoDir, "product_core/packages/app_pkg/app.mk"),
        "# app mk\n"
    ),
    Topology = [platform_core, product_core],
    Motherlode = #{
        nuggets => #{
            demo => #{
                id => demo,
                description => <<"Demo product BSP">>,
                version => <<"1.2.3">>
            },
            platform_core => #{
                id => platform_core,
                description => <<"Platform BSP">>,
                repository => builtin,
                repo_path => path_binary(RepoDir),
                nugget_relpath => <<"platform_core">>,
                buildroot => [{packages, <<"buildroot">>}]
            },
            product_core => #{
                id => product_core,
                description => <<"Product BSP">>,
                repository => builtin,
                repo_path => path_binary(RepoDir),
                nugget_relpath => <<"product_core">>,
                buildroot => [{packages, <<"packages">>}]
            },
            aux_alpha_root => #{
                id => aux_alpha_root
            }
        },
        repositories => #{}
    },
    ExpectedConfigIn =
        <<"# Generated by smelterl - do not edit\n"
          "\n"
          "## Extra Buildroot Environment ##\n"
          "\n"
          "config ALLOY_MOTHERLODE\n"
          "\tstring\n"
          "\toption env=\"ALLOY_MOTHERLODE\"\n"
          "\n"
          "config ALLOY_BUILD_DIR\n"
          "\tstring\n"
          "\toption env=\"ALLOY_BUILD_DIR\"\n"
          "\n"
          "config ALLOY_CACHE_DIR\n"
          "\tstring\n"
          "\toption env=\"ALLOY_CACHE_DIR\"\n"
          "\n"
          "## Nugget Packages ##\n"
          "\n"
          "# platform_core: Platform BSP\n"
          "source \"$(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/Config.in\"\n"
          "source \"$(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/pkg_alpha/Config.in\"\n"
          "\n"
          "# product_core: Product BSP\n"
          "source \"$(ALLOY_MOTHERLODE)/builtin/product_core/packages/app_pkg/Config.in\"\n"
          "\n">>,
    ExpectedExternalMk =
        <<"# Generated by smelterl - do not edit\n"
          "\n"
          "## Nugget Packages ##\n"
          "\n"
          "# platform_core: Platform BSP\n"
          "include $(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/external.mk\n"
          "include $(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/pkg_alpha/pkg-alpha.mk\n"
          "\n"
          "# product_core: Product BSP\n"
          "include $(ALLOY_MOTHERLODE)/builtin/product_core/packages/app_pkg/app.mk\n"
          "\n">>,
    {Topology, Motherlode, ExpectedConfigIn, ExpectedExternalMk}.

expected_external_desc() ->
    <<"name: DEMO\n"
      "desc: Demo product BSP - Version 1.2.3\n">>.

write_generate_legal_inputs(OutputDir) ->
    AuxLegalDir = filename:join(OutputDir, "targets/aux_alpha/workspace/legal-info"),
    MainLegalDir = filename:join(OutputDir, "targets/main/workspace/legal-info"),
    write_generate_legal_input(
        AuxLegalDir,
        <<"Aux target README\n">>,
        <<"BR2_TARGET=aux\n">>,
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"auxpkg\",\"0.1.0\",\"Apache-2.0\",\"LICENSE\"\n">>
        ],
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\"\n">>
        ],
        [
            "licenses/auxpkg-0.1.0/LICENSE",
            "host-licenses/buildroot/COPYING"
        ]
    ),
    write_generate_legal_input(
        MainLegalDir,
        <<"Main target README\n">>,
        <<"BR2_TARGET=main\n">>,
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"mainpkg\",\"1.0.0\",\"BSD-3-Clause\",\"LICENSE\"\n">>
        ],
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\"\n">>,
            <<"\"host-main\",\"1.1\",\"Apache-2.0\",\"LICENSE\"\n">>
        ],
        [
            "licenses/mainpkg-1.0.0/LICENSE",
            "host-licenses/buildroot/COPYING",
            "host-licenses/host-main-1.1/LICENSE"
        ]
    ),
    {AuxLegalDir, MainLegalDir}.

write_generate_legal_input(
    LegalDir,
    Readme,
    BuildrootConfig,
    ManifestLines,
    HostManifestLines,
    LicensePaths
) ->
    ok = filelib:ensure_dir(filename:join(LegalDir, "dummy")),
    ok = file:write_file(filename:join(LegalDir, "manifest.csv"), ManifestLines),
    ok = file:write_file(filename:join(LegalDir, "host-manifest.csv"), HostManifestLines),
    ok = file:write_file(filename:join(LegalDir, "README"), Readme),
    ok = file:write_file(filename:join(LegalDir, "buildroot.config"), BuildrootConfig),
    lists:foreach(
        fun(RelativePath) ->
            FullPath = filename:join(LegalDir, RelativePath),
            ok = filelib:ensure_dir(FullPath),
            ok = file:write_file(FullPath, <<"fixture\n">>)
        end,
        LicensePaths
    ).

make_temp_dir(Prefix) ->
    make_temp_dir(Prefix, 0).

make_temp_dir(Prefix, Attempt) ->
    Suffix =
        integer_to_list(erlang:system_time(nanosecond)) ++ "-" ++
        integer_to_list(erlang:unique_integer([monotonic, positive])) ++ "-" ++
        integer_to_list(Attempt),
    Base = filename:join(os:getenv("TMPDIR", "/tmp"), Prefix ++ "-" ++ Suffix),
    case file:make_dir(Base) of
        ok ->
            Base;
        {error, eexist} ->
            make_temp_dir(Prefix, Attempt + 1);
        {error, Reason} ->
            ct:fail("Failed to create temp dir ~ts: ~tp", [Base, Reason])
    end.

assert_contains(Haystack, Needle) ->
    case binary:match(Haystack, Needle) of
        nomatch ->
            ct:fail("Expected ~tp to contain ~tp", [Haystack, Needle]);
        _ ->
            ok
    end.

assert_file_content(Path, Expected) ->
    case file:read_file(Path) of
        {ok, Expected} ->
            ok;
        {ok, Actual} ->
            ct:fail("Expected ~ts to contain ~tp, got ~tp", [Path, Expected, Actual]);
        {error, Reason} ->
            ct:fail("Failed to read ~ts: ~tp", [Path, Reason])
    end.

assert_file_contains(Path, Needles) ->
    case file:read_file(Path) of
        {ok, Content} ->
            lists:foreach(fun(Needle) -> assert_contains(Content, Needle) end, Needles);
        {error, Reason} ->
            ct:fail("Failed to read ~ts: ~tp", [Path, Reason])
    end.

field_value(Key, Fields) ->
    case lists:keyfind(Key, 1, Fields) of
        {Key, Value} ->
            Value;
        false ->
            ct:fail("Missing field ~tp in ~tp", [Key, Fields])
    end.

assert_bash_syntax(Path) ->
    {Status, Output} = run_process("bash", ["-n", Path]),
    case Status of
        0 ->
            ok;
        _ ->
            ct:fail("bash -n failed for ~ts: ~ts", [Path, Output])
    end.

assert_context_sources_in_bash(Path) ->
    Script =
        "set -euo pipefail\n"
        "export ALLOY_MOTHERLODE=/tmp/alloy-motherlode\n"
        "source \"$1\"\n"
        "[ \"$ALLOY_PRODUCT\" = demo ]\n"
        "declare -p ALLOY_NUGGET_ORDER >/dev/null\n"
        "[ \"$(alloy_config device_name)\" = demo-box ]\n",
    {Status, Output} = run_process("bash", ["-c", Script, "bash", Path]),
    case Status of
        0 ->
            ok;
        _ ->
            ct:fail("sourcing generated context failed for ~ts: ~ts", [Path, Output])
    end.

assert_shellcheck_clean(Path) ->
    case os:find_executable("shellcheck") of
        false ->
            ct:comment("shellcheck not available; skipping generated-context lint check"),
            ok;
        Shellcheck ->
            {Status, Output} = run_process(
                Shellcheck,
                ["-s", "bash", "-e", "SC2034", Path]
            ),
            case Status of
                0 ->
                    ok;
                _ ->
                    ct:fail("shellcheck failed for ~ts: ~ts", [Path, Output])
            end
    end.

run_process(Executable, Args) ->
    ExecutablePath =
        case os:find_executable(Executable) of
            false ->
                ct:fail("Executable not found on PATH: ~ts", [Executable]);
            Path ->
                Path
        end,
    Port =
        open_port(
            {spawn_executable, ExecutablePath},
            [
                binary,
                exit_status,
                stderr_to_stdout,
                use_stdio,
                {args, Args}
            ]
        ),
    collect_port_output(Port, []).

ensure_dir(Path) ->
    ok = filelib:ensure_dir(filename:join(Path, "dummy")),
    ok.

ensure_file(Path, Content) ->
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Content).

path_binary(Path) ->
    list_to_binary(filename:absname(Path)).

sample_manifest_seed() ->
    #{
        product => demo,
        target_arch => <<"arm-buildroot-linux-gnueabihf">>,
        product_fields => #{
            name => <<"Demo Product">>,
            version => <<"1.2.3">>
        },
        repositories => [
            {smelterl, #{
                name => <<"smelterl">>,
                type => git,
                url => <<"https://github.com/grisp/smelterl.git">>,
                commit => <<"0123456789abcdef">>,
                describe => <<"v0.1.0">>,
                dirty => false
            }}
        ],
        nugget_repo_map => #{demo => undefined},
        nuggets => [],
        auxiliary_products => [],
        capabilities => #{
            firmware_variants => [plain],
            selectable_outputs => [],
            firmware_parameters => []
        },
        sdk_outputs => [],
        external_components => [],
        smelterl_repository => smelterl
    }.

assert_member(Expected, Values) ->
    case lists:member(Expected, Values) of
        true ->
            ok;
        false ->
            ct:fail("Expected ~tp to contain ~tp", [Values, Expected])
    end.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp but got ~tp", [Expected, Actual])
    end.
