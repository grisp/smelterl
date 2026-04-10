-module(smelterl_template_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    render_supports_nested_sections_and_current_value/1,
    render_reports_missing_variable_in_section/1,
    render_rejects_mismatched_section_end/1
]).

all() ->
    [
        render_supports_nested_sections_and_current_value,
        render_reports_missing_variable_in_section,
        render_rejects_mismatched_section_end
    ].

render_supports_nested_sections_and_current_value(_Config) ->
    Template = <<
        "# Generated\n"
        "\n"
        "{{#packages}}\n"
        "# {{{name}}}{{#description}}: {{{.}}}{{/description}}\n"
        "{{#includes}}\n"
        "include {{{path}}}\n"
        "{{/includes}}\n"
        "\n"
        "{{/packages}}"
    >>,
    {ok, Rendered} = render_template(Template, #{
        packages => [
            #{
                name => <<"alpha">>,
                description => <<"Alpha BSP">>,
                includes => [
                    #{path => <<"alpha/root.mk">>},
                    #{path => <<"alpha/pkg.mk">>}
                ]
            },
            #{
                name => <<"beta">>,
                description => <<>>,
                includes => [
                    #{path => <<"beta/pkg.mk">>}
                ]
            }
        ]
    }),
    assert_equal(
        <<"# Generated\n"
          "\n"
          "# alpha: Alpha BSP\n"
          "include alpha/root.mk\n"
          "include alpha/pkg.mk\n"
          "\n"
          "# beta\n"
          "include beta/pkg.mk\n"
          "\n">>,
        iolist_to_binary(Rendered)
    ).

render_reports_missing_variable_in_section(_Config) ->
    Template = <<
        "{{#packages}}\n"
        "{{name}}\n"
        "{{/packages}}\n"
    >>,
    assert_equal(
        {error, {render_failed, external_mk, {missing_variable, <<"name">>}}},
        render_template(Template, #{packages => [#{}]})
    ).

render_rejects_mismatched_section_end(_Config) ->
    Template = <<
        "{{#packages}}\n"
        "{{/includes}}\n"
    >>,
    assert_equal(
        {error,
            {render_failed,
                external_mk,
                {mismatched_section_end, <<"packages">>, <<"includes">>}}},
        render_template(Template, #{packages => []})
    ).

render_template(Template, Data) ->
    RootDir = make_temp_dir("smelterl-template-suite"),
    PrivDir = filename:join(RootDir, "priv/templates"),
    PreviousPrivDir = application:get_env(smelterl, priv_dir),
    ok = filelib:ensure_dir(filename:join(PrivDir, "dummy")),
    ok = file:write_file(filename:join(PrivDir, "external.mk.mustache"), Template),
    set_priv_dir(RootDir),
    Result = smelterl_template:render(external_mk, Data),
    restore_priv_dir(PreviousPrivDir),
    Result.

set_priv_dir(RootDir) ->
    ok = ensure_app_loaded(smelterl),
    ok = application:set_env(smelterl, priv_dir, filename:join(RootDir, "priv")).

restore_priv_dir({ok, PrivDir}) ->
    ok = application:set_env(smelterl, priv_dir, PrivDir);
restore_priv_dir(undefined) ->
    ok = application:unset_env(smelterl, priv_dir).

ensure_app_loaded(App) ->
    case application:load(App) of
        ok ->
            ok;
        {error, {already_loaded, App}} ->
            ok
    end.

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

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
