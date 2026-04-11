-module(smelterl_gen_external_desc_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    generate_renders_external_desc_from_product_metadata/1,
    generate_renders_external_desc_for_description_and_version_combinations/1,
    generate_reports_missing_product_metadata/1
]).

all() ->
    [
        generate_renders_external_desc_from_product_metadata,
        generate_renders_external_desc_for_description_and_version_combinations,
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

generate_renders_external_desc_for_description_and_version_combinations(_Config) ->
    assert_external_desc(
        demo_desc_only,
        #{
            nuggets => #{
                demo_desc_only => #{
                    id => demo_desc_only,
                    description => <<"Description only">>
                }
            },
            repositories => #{}
        },
        <<"name: DEMO_DESC_ONLY\n"
          "desc: Description only\n">>
    ),
    assert_external_desc(
        demo_version_only,
        #{
            nuggets => #{
                demo_version_only => #{
                    id => demo_version_only,
                    version => <<"2.0.0">>
                }
            },
            repositories => #{}
        },
        <<"name: DEMO_VERSION_ONLY\n"
          "desc: Version 2.0.0\n">>
    ),
    assert_external_desc(
        demo_empty,
        #{
            nuggets => #{
                demo_empty => #{
                    id => demo_empty
                }
            },
            repositories => #{}
        },
        <<"name: DEMO_EMPTY\n"
          "desc: \n">>
    ).

generate_reports_missing_product_metadata(_Config) ->
    Motherlode = #{nuggets => #{}, repositories => #{}},
    assert_equal(
        {error, {missing_product_metadata, demo_product}},
        smelterl_gen_external_desc:generate(demo_product, Motherlode)
    ).

assert_external_desc(ProductId, Motherlode, Expected) ->
    {ok, Content} = smelterl_gen_external_desc:generate(ProductId, Motherlode),
    assert_equal(Expected, iolist_to_binary(Content)).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
