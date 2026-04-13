-module(smelterl_plan_generate_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    plan_then_generate_main_and_auxiliary_from_sample_motherlode/1,
    generate_uses_serialized_plan_after_motherlode_mutation/1
]).

all() ->
    [
        plan_then_generate_main_and_auxiliary_from_sample_motherlode,
        generate_uses_serialized_plan_after_motherlode_mutation
    ].

plan_then_generate_main_and_auxiliary_from_sample_motherlode(_Config) ->
    Fixture = write_sample_motherlode("smelterl-plan-generate-sample"),
    OutputDir = make_temp_dir("smelterl-plan-generate-output"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),
    PlanEnvPath = filename:join(OutputDir, "build_plan.env"),

    {StatusPlan, OutputPlan} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", maps:get(motherlode_dir, Fixture),
        "--output-plan", PlanPath,
        "--output-plan-env", PlanEnvPath,
        "--extra-config", "ALLOY_BUILD_DIR=${ALLOY_BUILD_DIR}",
        "--extra-config", "ALLOY_CACHE_DIR=${ALLOY_CACHE_DIR}"
    ]),
    assert_command_success(StatusPlan, OutputPlan),

    {ok, Plan} = smelterl_plan:read_file(PlanPath),
    assert_equal([aux_alpha], maps:get(auxiliary_ids, Plan)),
    {ok, MainTarget} = smelterl_plan:select_target(main, Plan),
    {ok, AuxTarget} = smelterl_plan:select_target(aux_alpha, Plan),
    assert_equal(main, maps:get(kind, MainTarget)),
    assert_equal(auxiliary, maps:get(kind, AuxTarget)),
    assert_file_contains(
        PlanEnvPath,
        [
            <<"ALLOY_PLAN_AUXILIARY_IDS=('aux_alpha')">>,
            <<"[\'ALLOY_BUILD_DIR\']='${ALLOY_BUILD_DIR}'">>,
            <<"[\'ALLOY_CACHE_DIR\']='${ALLOY_CACHE_DIR}'">>
        ]
    ),

    AuxDir = filename:join(OutputDir, "auxiliary"),
    AuxExternalDesc = filename:join(AuxDir, "external.desc"),
    AuxConfigIn = filename:join(AuxDir, "Config.in"),
    AuxExternalMk = filename:join(AuxDir, "external.mk"),
    AuxDefconfig = filename:join(AuxDir, "aux_alpha_defconfig"),
    AuxContext = filename:join(AuxDir, "alloy_context.sh"),
    ok = filelib:ensure_dir(AuxExternalDesc),
    {StatusAux, OutputAux} = run_main([
        "generate",
        "--plan", PlanPath,
        "--auxiliary", "aux_alpha",
        "--output-external-desc", AuxExternalDesc,
        "--output-config-in", AuxConfigIn,
        "--output-external-mk", AuxExternalMk,
        "--output-defconfig", AuxDefconfig,
        "--output-context", AuxContext
    ]),
    assert_command_success(StatusAux, OutputAux),
    assert_file_contains(
        AuxExternalDesc,
        [
            <<"name: DEMO">>,
            <<"desc: Demo product BSP - Version 1.2.3">>
        ]
    ),
    assert_file_contains(
        AuxConfigIn,
        [
            <<"config ALLOY_MOTHERLODE">>,
            <<"config ALLOY_BUILD_DIR">>,
            <<"source \"$(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/Config.in\"">>,
            <<"source \"$(ALLOY_MOTHERLODE)/builtin/aux_alpha_root/packages/aux_pkg/Config.in\"">>
        ]
    ),
    assert_not_contains(
        read_file(AuxConfigIn),
        <<"$(ALLOY_MOTHERLODE)/builtin/demo/packages/app_pkg/Config.in">>
    ),
    assert_file_contains(
        AuxExternalMk,
        [
            <<"include $(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/external.mk">>,
            <<"include $(ALLOY_MOTHERLODE)/builtin/aux_alpha_root/packages/aux_pkg/aux.mk">>
        ]
    ),
    assert_not_contains(
        read_file(AuxExternalMk),
        <<"$(ALLOY_MOTHERLODE)/builtin/demo/packages/app_pkg/app.mk">>
    ),
    assert_file_contains(
        AuxDefconfig,
        [
            <<"BR2_PACKAGE_PLATFORM_BASE=y">>,
            <<"BR2_PACKAGE_AUX_PAYLOAD=y">>,
            <<"BR2_ROOTFS_POST_BUILD_SCRIPT=\"$(BR2_EXTERNAL)/board/aux_alpha/scripts/post-build.sh\"">>
        ]
    ),
    assert_file_contains(
        AuxContext,
        [
            <<"export ALLOY_PRODUCT=\"aux_alpha\"">>,
            <<"export ALLOY_IS_AUXILIARY=\"true\"">>,
            <<"export ALLOY_AUXILIARY=\"aux_alpha\"">>,
            <<"export ALLOY_SDK_OUTPUTS=(\"initramfs\")">>,
            <<"ALLOY_PRE_BUILD_HOOKS=()">>
        ]
    ),
    assert_not_contains(read_file(AuxContext), <<"ALLOY_FIRMWARE_VARIANTS">>),
    assert_bash_syntax(AuxContext),
    assert_context_sources_in_bash(AuxContext, <<"aux_alpha">>, <<"initramfs_mode">>, <<"gzip">>),

    MainDir = filename:join(OutputDir, "main"),
    MainExternalDesc = filename:join(MainDir, "external.desc"),
    MainConfigIn = filename:join(MainDir, "Config.in"),
    MainExternalMk = filename:join(MainDir, "external.mk"),
    MainDefconfig = filename:join(MainDir, "main_defconfig"),
    MainContext = filename:join(MainDir, "alloy_context.sh"),
    MainManifest = filename:join(MainDir, "ALLOY_SDK_MANIFEST"),
    ok = filelib:ensure_dir(MainExternalDesc),
    {StatusMain, OutputMain} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-external-desc", MainExternalDesc,
        "--output-config-in", MainConfigIn,
        "--output-external-mk", MainExternalMk,
        "--output-defconfig", MainDefconfig,
        "--output-context", MainContext,
        "--output-manifest", MainManifest
    ]),
    assert_command_success(StatusMain, OutputMain),
    assert_file_contains(
        MainExternalDesc,
        [
            <<"name: DEMO">>,
            <<"desc: Demo product BSP - Version 1.2.3">>
        ]
    ),
    assert_file_contains(
        MainConfigIn,
        [
            <<"config ALLOY_MOTHERLODE">>,
            <<"config ALLOY_BUILD_DIR">>,
            <<"source \"$(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/Config.in\"">>,
            <<"source \"$(ALLOY_MOTHERLODE)/builtin/demo/packages/app_pkg/Config.in\"">>
        ]
    ),
    assert_not_contains(
        read_file(MainConfigIn),
        <<"$(ALLOY_MOTHERLODE)/builtin/aux_alpha_root/packages/aux_pkg/Config.in">>
    ),
    assert_file_contains(
        MainExternalMk,
        [
            <<"include $(ALLOY_MOTHERLODE)/builtin/platform_core/buildroot/external.mk">>,
            <<"include $(ALLOY_MOTHERLODE)/builtin/demo/packages/app_pkg/app.mk">>
        ]
    ),
    assert_not_contains(
        read_file(MainExternalMk),
        <<"$(ALLOY_MOTHERLODE)/builtin/aux_alpha_root/packages/aux_pkg/aux.mk">>
    ),
    assert_file_contains(
        MainDefconfig,
        [
            <<"BR2_PACKAGE_PLATFORM_BASE=y">>,
            <<"BR2_PACKAGE_DEMO_APP=y">>,
            <<"BR2_ROOTFS_POST_BUILD_SCRIPT=\"$(BR2_EXTERNAL)/board/main/scripts/post-build.sh\"">>
        ]
    ),
    assert_file_contains(
        MainContext,
        [
            <<"export ALLOY_PRODUCT=\"demo\"">>,
            <<"export ALLOY_IS_AUXILIARY=\"false\"">>,
            <<"export ALLOY_FIRMWARE_VARIANTS=(\"plain\")">>,
            <<"export ALLOY_SDK_OUTPUTS=(\"symbols\")">>,
            <<"ALLOY_PRE_BUILD_HOOKS=(\"demo:scripts/pre-build.sh\")">>
        ]
    ),
    assert_bash_syntax(MainContext),
    assert_context_sources_in_bash(MainContext, <<"demo">>, <<"device_name">>, <<"demo-box">>),

    {ok, [{sdk_manifest, <<"1.0">>, ManifestFields}]} = file:consult(MainManifest),
    assert_equal(
        [
            {auxiliary, aux_alpha, [
                {root_nugget, aux_alpha_root}
            ]}
        ],
        field_value(auxiliary_products, ManifestFields)
    ),
    assert_equal(
        [
            {firmware_variants, [plain]},
            {selectable_outputs, []},
            {firmware_parameters, []}
        ],
        field_value(capabilities, ManifestFields)
    ),
    assert_equal(
        [
            {target, main, [
                {output, symbols, [
                    {nugget, demo},
                    {name, <<"Symbols">>},
                    {description, <<"Main symbols bundle">>}
                ]}
            ]},
            {target, aux_alpha, [
                {output, initramfs, [
                    {nugget, aux_alpha_root},
                    {name, <<"Initramfs">>},
                    {description, <<"Auxiliary initramfs image">>}
                ]}
            ]}
        ],
        field_value(sdk_outputs, ManifestFields)
    ).

generate_uses_serialized_plan_after_motherlode_mutation(_Config) ->
    Fixture = write_sample_motherlode("smelterl-plan-generate-mutation"),
    OutputDir = make_temp_dir("smelterl-plan-generate-mutation-output"),
    PlanPath = filename:join(OutputDir, "build_plan.term"),

    {StatusPlan, OutputPlan} = run_main([
        "plan",
        "--product", "demo",
        "--motherlode", maps:get(motherlode_dir, Fixture),
        "--output-plan", PlanPath
    ]),
    assert_command_success(StatusPlan, OutputPlan),

    RepoDir = maps:get(repo_dir, Fixture),
    ok = file:write_file(filename:join(RepoDir, ".nuggets"), <<"not a valid erlang term\n">>),
    ok = file:write_file(
        filename:join(RepoDir, "demo/demo.nugget"),
        <<"not a valid nugget term either\n">>
    ),

    ExternalDesc = filename:join(OutputDir, "external.desc"),
    Defconfig = filename:join(OutputDir, "main_defconfig"),
    Context = filename:join(OutputDir, "alloy_context.sh"),
    Manifest = filename:join(OutputDir, "ALLOY_SDK_MANIFEST"),
    ok = filelib:ensure_dir(ExternalDesc),
    {StatusGenerate, OutputGenerate} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-external-desc", ExternalDesc,
        "--output-defconfig", Defconfig,
        "--output-context", Context,
        "--output-manifest", Manifest
    ]),
    assert_command_success(StatusGenerate, OutputGenerate),
    assert_file_contains(
        ExternalDesc,
        [<<"desc: Demo product BSP - Version 1.2.3">>]
    ),
    assert_file_contains(
        Defconfig,
        [
            <<"BR2_PACKAGE_PLATFORM_BASE=y">>,
            <<"BR2_PACKAGE_DEMO_APP=y">>
        ]
    ),
    assert_file_contains(
        Context,
        [
            <<"export ALLOY_PRODUCT=\"demo\"">>,
            <<"export ALLOY_FIRMWARE_VARIANTS=(\"plain\")">>,
            <<"export ALLOY_SDK_OUTPUTS=(\"symbols\")">>
        ]
    ),
    {ok, [{sdk_manifest, <<"1.0">>, ManifestFields}]} = file:consult(Manifest),
    assert_equal(<<"Demo product BSP">>, field_value(product_description, ManifestFields)),
    assert_bash_syntax(Context),
    assert_context_sources_in_bash(Context, <<"demo">>, <<"device_name">>, <<"demo-box">>).

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

write_sample_motherlode(Prefix) ->
    MotherlodeDir = make_temp_dir(Prefix),
    RepoDir = filename:join(MotherlodeDir, "builtin"),
    ok = ensure_file(filename:join(RepoDir, ".nuggets"), registry_contents()),
    ok = ensure_file(filename:join(RepoDir, ".alloy_repo_info"), repo_info_contents()),
    ok = ensure_file(filename:join(RepoDir, "demo/demo.nugget"), demo_nugget_contents()),
    ok = ensure_file(
        filename:join(RepoDir, "aux_alpha_root/aux_alpha_root.nugget"),
        aux_alpha_root_nugget_contents()
    ),
    ok = ensure_file(
        filename:join(RepoDir, "builder_core/builder_core.nugget"),
        simple_nugget(builder_core, builder)
    ),
    ok = ensure_file(
        filename:join(RepoDir, "toolchain_core/toolchain_core.nugget"),
        simple_nugget(toolchain_core, toolchain)
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/platform_core.nugget"),
        platform_core_nugget_contents()
    ),
    ok = ensure_file(
        filename:join(RepoDir, "system_core/system_core.nugget"),
        simple_nugget(system_core, system)
    ),
    ok = ensure_file(
        filename:join(RepoDir, "bootflow_plain/bootflow_plain.nugget"),
        bootflow_plain_nugget_contents()
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/Config.in"),
        <<"# platform root\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/external.mk"),
        <<"# platform root mk\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/pkg_platform/Config.in"),
        <<"# platform package\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot/pkg_platform/platform.mk"),
        <<"# platform package mk\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "demo/packages/app_pkg/Config.in"),
        <<"# demo app\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "demo/packages/app_pkg/app.mk"),
        <<"# demo app mk\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "aux_alpha_root/packages/aux_pkg/Config.in"),
        <<"# aux package\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "aux_alpha_root/packages/aux_pkg/aux.mk"),
        <<"# aux package mk\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "platform_core/buildroot.defconfig.fragment"),
        <<"BR2_PACKAGE_PLATFORM_BASE=y\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "demo/buildroot.defconfig.fragment"),
        <<"BR2_PACKAGE_DEMO_APP=y\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "aux_alpha_root/buildroot.defconfig.fragment"),
        <<"BR2_PACKAGE_AUX_PAYLOAD=y\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "demo/scripts/pre-build.sh"),
        <<"#!/bin/sh\nexit 0\n">>
    ),
    ok = ensure_file(
        filename:join(RepoDir, "aux_alpha_root/scripts/pre-build.sh"),
        <<"#!/bin/sh\nexit 0\n">>
    ),
    #{motherlode_dir => MotherlodeDir, repo_dir => RepoDir}.

registry_contents() ->
    <<
        "{nugget_registry, <<\"1.0\">>, [\n"
        "    {nuggets, [\n"
        "        <<\"demo/demo.nugget\">>,\n"
        "        <<\"aux_alpha_root/aux_alpha_root.nugget\">>,\n"
        "        <<\"builder_core/builder_core.nugget\">>,\n"
        "        <<\"toolchain_core/toolchain_core.nugget\">>,\n"
        "        <<\"platform_core/platform_core.nugget\">>,\n"
        "        <<\"system_core/system_core.nugget\">>,\n"
        "        <<\"bootflow_plain/bootflow_plain.nugget\">>\n"
        "    ]}\n"
        "]}.\n"
    >>.

repo_info_contents() ->
    <<
        "NAME=demo-builtin\n"
        "URL=https://example.com/demo/builtin.git\n"
        "COMMIT=1111111111111111111111111111111111111111\n"
        "DESCRIBE=v1.2.3\n"
        "DIRTY=false\n"
    >>.

demo_nugget_contents() ->
    <<
        "{nugget, <<\"1.0\">>, [\n"
        "    {id, demo},\n"
        "    {category, feature},\n"
        "    {name, <<\"Demo Product\">>},\n"
        "    {description, <<\"Demo product BSP\">>},\n"
        "    {version, <<\"1.2.3\">>},\n"
        "    {depends_on, [\n"
        "        {required, nugget, builder_core},\n"
        "        {required, nugget, toolchain_core},\n"
        "        {required, nugget, platform_core},\n"
        "        {required, nugget, system_core},\n"
        "        {required, nugget, bootflow_plain}\n"
        "    ]},\n"
        "    {auxiliary_products, [{aux_alpha, aux_alpha_root}]},\n"
        "    {config, [{device_name, <<\"demo-box\">>}]},\n"
        "    {hooks, [{pre_build, <<\"scripts/pre-build.sh\">>}]},\n"
        "    {sdk_outputs, [\n"
        "        {symbols, [\n"
        "            {display_name, <<\"Symbols\">>},\n"
        "            {description, <<\"Main symbols bundle\">>}\n"
        "        ]}\n"
        "    ]},\n"
        "    {buildroot, [\n"
        "        {packages, <<\"packages\">>},\n"
        "        {defconfig_fragment, <<\"buildroot.defconfig.fragment\">>}\n"
        "    ]}\n"
        "]}.\n"
    >>.

aux_alpha_root_nugget_contents() ->
    <<
        "{nugget, <<\"1.0\">>, [\n"
        "    {id, aux_alpha_root},\n"
        "    {category, feature},\n"
        "    {name, <<\"Aux Alpha Root\">>},\n"
        "    {description, <<\"Auxiliary initramfs builder\">>},\n"
        "    {version, <<\"0.2.0\">>},\n"
        "    {config, [{initramfs_mode, <<\"gzip\">>}]},\n"
        "    {hooks, [{pre_build, <<\"scripts/pre-build.sh\">>}]},\n"
        "    {sdk_outputs, [\n"
        "        {initramfs, [\n"
        "            {display_name, <<\"Initramfs\">>},\n"
        "            {description, <<\"Auxiliary initramfs image\">>}\n"
        "        ]}\n"
        "    ]},\n"
        "    {buildroot, [\n"
        "        {packages, <<\"packages\">>},\n"
        "        {defconfig_fragment, <<\"buildroot.defconfig.fragment\">>}\n"
        "    ]}\n"
        "]}.\n"
    >>.

platform_core_nugget_contents() ->
    <<
        "{nugget, <<\"1.0\">>, [\n"
        "    {id, platform_core},\n"
        "    {category, platform},\n"
        "    {name, <<\"Platform Core\">>},\n"
        "    {version, <<\"1.0.0\">>},\n"
        "    {exports, [\n"
        "        {target_arch_triplet, <<\"arm-buildroot-linux-gnueabihf\">>}\n"
        "    ]},\n"
        "    {buildroot, [\n"
        "        {packages, <<\"buildroot\">>},\n"
        "        {defconfig_fragment, <<\"buildroot.defconfig.fragment\">>}\n"
        "    ]}\n"
        "]}.\n"
    >>.

bootflow_plain_nugget_contents() ->
    <<
        "{nugget, <<\"1.0\">>, [\n"
        "    {id, bootflow_plain},\n"
        "    {category, bootflow},\n"
        "    {firmware_variant, [plain]}\n"
        "]}.\n"
    >>.

simple_nugget(Id, Category) ->
    iolist_to_binary(
        io_lib:format(
            "{nugget, <<\"1.0\">>, [\n"
            "    {id, ~p},\n"
            "    {category, ~p}\n"
            "]}.\n",
            [Id, Category]
        )
    ).

ensure_file(Path, Content) ->
    ok = filelib:ensure_dir(Path),
    ok = file:write_file(Path, Content).

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Content} ->
            Content;
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

assert_file_contains(Path, Needles) ->
    Content = read_file(Path),
    lists:foreach(fun(Needle) -> assert_contains(Content, Needle) end, Needles).

assert_contains(Haystack, Needle) ->
    case binary:match(Haystack, Needle) of
        nomatch ->
            ct:fail("Expected ~tp to contain ~tp", [Haystack, Needle]);
        _ ->
            ok
    end.

assert_not_contains(Haystack, Needle) ->
    case binary:match(Haystack, Needle) of
        nomatch ->
            ok;
        _ ->
            ct:fail("Expected ~tp not to contain ~tp", [Haystack, Needle])
    end.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp but got ~tp", [Expected, Actual])
    end.

assert_command_success(Status, Output) ->
    case {Status, Output} of
        {0, <<>>} ->
            ok;
        {0, _} ->
            ct:fail("Expected empty command output, got ~ts", [Output]);
        _ ->
            ct:fail("Expected successful command, got status ~tp with output ~ts", [
                Status, Output
            ])
    end.

assert_bash_syntax(Path) ->
    {Status, Output} = run_process("bash", ["-n", Path]),
    case Status of
        0 ->
            ok;
        _ ->
            ct:fail("bash -n failed for ~ts: ~ts", [Path, Output])
    end.

assert_context_sources_in_bash(Path, ExpectedProduct, ConfigKey, ExpectedValue) ->
    Script = io_lib:format(
        "set -euo pipefail\n"
        "export ALLOY_MOTHERLODE=/tmp/alloy-motherlode\n"
        "source \"$1\"\n"
        "[ \"$ALLOY_PRODUCT\" = \"$2\" ]\n"
        "[ \"$(alloy_config \"$3\")\" = \"$4\" ]\n",
        []
    ),
    {Status, Output} = run_process(
        "bash",
        [
            "-c",
            lists:flatten(Script),
            "bash",
            Path,
            binary_to_list(ExpectedProduct),
            binary_to_list(ConfigKey),
            binary_to_list(ExpectedValue)
        ]
    ),
    case Status of
        0 ->
            ok;
        _ ->
            ct:fail("sourcing generated context failed for ~ts: ~ts", [Path, Output])
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
