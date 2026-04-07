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
    generate_reports_unknown_auxiliary_target/1
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
        generate_reports_unknown_auxiliary_target
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
    MainManifest = filename:join(OutputDir, "ALLOY_SDK_MANIFEST"),
    {StatusMain, OutputMain} = run_main([
        "generate",
        "--plan", PlanPath,
        "--output-manifest", MainManifest,
        "--buildroot-legal", filename:join(OutputDir, "legal-main"),
        "--export-legal", "legal-info",
        "--include-sources"
    ]),
    assert_equal(0, StatusMain),
    assert_equal(<<>>, OutputMain),
    {StatusAux, OutputAux} = run_main([
        "generate",
        "--plan", PlanPath,
        "--auxiliary", "aux_alpha",
        "--output-context", filename:join(OutputDir, "alloy_context.sh")
    ]),
    assert_equal(0, StatusAux),
    assert_equal(<<>>, OutputAux).

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
        tree => #{root => demo, edges => #{demo => []}},
        topology => [demo],
        motherlode => #{nuggets => #{}, repositories => #{}},
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
        topology => [aux_alpha_root],
        motherlode => #{nuggets => #{}, repositories => #{}},
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
        #{
            product => demo,
            target_arch => <<"arm-buildroot-linux-gnueabihf">>,
            product_fields => #{},
            repositories => [],
            nugget_repo_map => #{demo => undefined},
            nuggets => [],
            auxiliary_products => [],
            capabilities => #{},
            sdk_outputs => [],
            external_components => [],
            smelterl_repository => smelterl
        }
    ),
    Plan.

sample_capabilities(AuxiliaryIds) ->
    #{
        firmware_variants => [plain],
        variant_nuggets => #{plain => []},
        selectable_outputs => [],
        firmware_parameters => [],
        sdk_outputs_by_target =>
            maps:from_list([{TargetId, []} || TargetId <- [main | AuxiliaryIds]])
    }.

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

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp but got ~tp", [Expected, Actual])
    end.
