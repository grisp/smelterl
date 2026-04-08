-module(smelterl_gen_external_desc_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    generate_renders_external_desc_from_product_metadata/1,
    generate_reports_missing_product_metadata/1
]).

all() ->
    [
        generate_renders_external_desc_from_product_metadata,
        generate_reports_missing_product_metadata
    ].

generate_renders_external_desc_from_product_metadata(_Config) ->
    Motherlode = #{
        nuggets => #{
            demo_product => #{
                id => demo_product,
                description => <<"Demo product BSP">>,
                version => <<"1.2.3">>
            }
        },
        repositories => #{}
    },
    {ok, Content} = smelterl_gen_external_desc:generate(demo_product, Motherlode),
    assert_equal(
        <<"name: DEMO_PRODUCT\n"
          "desc: Demo product BSP - Version 1.2.3\n">>,
        iolist_to_binary(Content)
    ).

generate_reports_missing_product_metadata(_Config) ->
    Motherlode = #{nuggets => #{}, repositories => #{}},
    assert_equal(
        {error, {missing_product_metadata, demo_product}},
        smelterl_gen_external_desc:generate(demo_product, Motherlode)
    ).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
