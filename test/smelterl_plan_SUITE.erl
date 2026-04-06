-module(smelterl_plan_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    write_and_read_roundtrip_build_plan/1,
    read_rejects_unsupported_plan_version/1
]).

all() ->
    [
        write_and_read_roundtrip_build_plan,
        read_rejects_unsupported_plan_version
    ].

write_and_read_roundtrip_build_plan(_Config) ->
    OutputDir = make_temp_dir("smelterl-plan-roundtrip"),
    OutputPath = filename:join(OutputDir, "build_plan.term"),
    BuildPlan = sample_plan(),
    ok = smelterl_plan:write_file(OutputPath, BuildPlan),
    {ok, FileContents} = file:read_file(OutputPath),
    assert_contains(FileContents, <<"%% coding: utf-8">>),
    assert_contains(FileContents, <<"{build_plan,<<\"1.0\">>">>),
    {ok, ReadPlan} = smelterl_plan:read_file(OutputPath),
    assert_equal(BuildPlan, ReadPlan),
    {ok, MainTarget} = smelterl_plan:select_target(main, ReadPlan),
    assert_equal(main, maps:get(kind, MainTarget)).

read_rejects_unsupported_plan_version(_Config) ->
    OutputDir = make_temp_dir("smelterl-plan-unsupported"),
    OutputPath = filename:join(OutputDir, "build_plan.term"),
    ok = file:write_file(
        OutputPath,
        unicode:characters_to_binary(
            smelterl_file:format_term({build_plan, <<"9.9">>, []})
        )
    ),
    assert_equal(
        {error, {unsupported_plan_version, <<"9.9">>}},
        smelterl_plan:read_file(OutputPath)
    ).

sample_plan() ->
    Target = #{
        id => main,
        kind => main,
        tree => #{root => demo, edges => #{demo => []}},
        topology => [demo],
        motherlode => #{nuggets => #{}, repositories => #{}},
        config => #{
            <<"ALLOY_CONFIG_TARGET_ARCH_TRIPLET">> =>
                {global, undefined, <<"arm-buildroot-linux-gnueabihf">>}
        },
        defconfig => #{regular => [], cumulative => []},
        capabilities => #{
            firmware_variants => [plain],
            variant_nuggets => #{plain => []},
            selectable_outputs => [],
            firmware_parameters => [],
            sdk_outputs_by_target => #{main => []}
        }
    },
    {ok, Plan} = smelterl_plan:new(
        demo,
        #{<<"ALLOY_MOTHERLODE">> => <<"${ALLOY_MOTHERLODE}">>},
        #{main => Target},
        [],
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
            make_temp_dir(Prefix, Attempt + 1)
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
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
