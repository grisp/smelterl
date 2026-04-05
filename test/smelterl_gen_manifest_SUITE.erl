-module(smelterl_gen_manifest_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    prepare_seed_builds_deterministic_manifest_seed/1,
    prepare_seed_requires_target_arch_triplet/1
]).

all() ->
    [
        prepare_seed_builds_deterministic_manifest_seed,
        prepare_seed_requires_target_arch_triplet
    ].

prepare_seed_builds_deterministic_manifest_seed(_Config) ->
    SmelterlRepo = #{
        name => <<"smelterl">>,
        url => <<"https://github.com/grisp/smelterl.git">>,
        commit => <<"0123456789abcdef">>,
        describe => <<"v0.1.0">>,
        dirty => false
    },
    BuildInfo = #{
        name => <<"smelterl">>,
        relpath => <<>>,
        repo => SmelterlRepo
    },
    Motherlode = #{
        repositories => #{
            product_checkout => #{
                name => <<"generator-checkout">>,
                url => <<"https://github.com/grisp/smelterl.git">>,
                commit => <<"0123456789abcdef">>,
                describe => <<"v0.1.0">>,
                dirty => false
            },
            core_a => #{
                name => <<"common-a">>,
                url => <<"https://example.com/acme/common.git">>,
                commit => <<"aaaaaaaa">>,
                describe => <<"v1.0.0">>,
                dirty => false
            },
            core_b => #{
                name => <<"common-b">>,
                url => <<"https://example.com/acme/common.git">>,
                commit => <<"aaaaaaaa">>,
                describe => <<"v1.0.0">>,
                dirty => false
            },
            vendor_nuggets_1 => #{
                name => <<"vendor-one">>,
                url => <<"https://example.com/vendor/nuggets.git">>,
                commit => <<"bbbbbbbb">>,
                describe => <<"v2.0.0">>,
                dirty => false
            },
            vendor_nuggets_2 => #{
                name => <<"vendor-two">>,
                url => <<"https://git.example.net/partner/nuggets.git">>,
                commit => <<"cccccccc">>,
                describe => <<"v3.0.0">>,
                dirty => true
            }
        },
        nuggets => #{
            builder_core => nugget(builder_core, builder, core_a, [
                {version, <<"1.0.0">>},
                {license, <<"Apache-2.0">>},
                {license_files, [<<"/licenses/builder/LICENSE">>]}
            ]),
            toolchain_core => nugget(toolchain_core, toolchain, core_b, [
                {version, <<"1.0.0">>},
                {license, <<"Apache-2.0">>},
                {license_files, [<<"/licenses/toolchain/LICENSE">>]}
            ]),
            platform_core => nugget(platform_core, platform, vendor_nuggets_1, [
                {version, <<"2.0.0">>},
                {provides, [secure_boot]},
                {license, <<"GPL-2.0">>},
                {license_files, [<<"/licenses/platform/COPYING">>]},
                {external_components, [[
                    {id, <<"crosstool_ng">>},
                    {name, <<"Crosstool-NG">>},
                    {version, <<"1.25.0">>},
                    {license, <<"GPL-2.0">>},
                    {license_files, [<<"/licenses/components/ctng/COPYING">>]}
                ]]}
            ]),
            system_core => nugget(system_core, system, vendor_nuggets_2, [
                {version, <<"2.1.0">>},
                {license, <<"MIT">>},
                {license_files, [<<"/licenses/system/LICENSE">>]}
            ]),
            product => nugget(product, feature, product_checkout, [
                {name, <<"Demo Product">>},
                {description, <<"Demonstration seed build">>},
                {version, <<"3.4.5">>},
                {license, <<"Proprietary">>},
                {license_files, [<<"/licenses/product/LICENSE">>]}
            ])
        }
    },
    Config = #{
        <<"ALLOY_CONFIG_TARGET_ARCH_TRIPLET">> =>
            {global, undefined, <<"arm-buildroot-linux-gnueabihf">>}
    },
    Capabilities = #{
        firmware_variants => [plain, secure],
        variant_nuggets => #{plain => [], secure => [platform_core]},
        selectable_outputs => [
            #{
                id => fwup_firmware,
                default => true,
                name => <<"FWUP firmware">>,
                description => <<"OTA package">>
            }
        ],
        firmware_parameters => [
            #{
                id => serial_number,
                type => string,
                required => true,
                name => <<"Serial Number">>
            }
        ],
        sdk_outputs_by_target => #{
            main => [
                #{
                    id => debug_symbols,
                    nugget => product,
                    name => <<"Debug symbols">>,
                    description => <<"Main-target symbols">>
                }
            ],
            aux_bundle => [
                #{
                    id => initramfs,
                    nugget => aux_root,
                    name => <<"Encrypted initramfs">>,
                    description => <<"Auxiliary payload">>
                }
            ]
        }
    },
    AuxiliaryMeta = [
        #{
            id => aux_bundle,
            root_nugget => aux_root,
            constraints => [{flavor, encrypted}],
            specific_tree => #{root => aux_root, edges => #{aux_root => []}},
            tree => #{root => aux_root, edges => #{aux_root => []}}
        }
    ],
    {ok, Seed} = smelterl_gen_manifest:prepare_seed(
        product,
        [builder_core, toolchain_core, platform_core, system_core, product],
        Motherlode,
        Config,
        Capabilities,
        AuxiliaryMeta,
        BuildInfo
    ),
    assert_equal(product, maps:get(product, Seed)),
    assert_equal(
        <<"arm-buildroot-linux-gnueabihf">>,
        maps:get(target_arch, Seed)
    ),
    assert_equal(
        #{
            name => <<"Demo Product">>,
            description => <<"Demonstration seed build">>,
            version => <<"3.4.5">>
        },
        maps:get(product_fields, Seed)
    ),
    assert_equal(
        [
            {smelterl, #{
                name => <<"smelterl">>,
                type => git,
                url => <<"https://github.com/grisp/smelterl.git">>,
                commit => <<"0123456789abcdef">>,
                describe => <<"v0.1.0">>,
                dirty => false
            }},
            {common, #{
                name => <<"common-a">>,
                type => git,
                url => <<"https://example.com/acme/common.git">>,
                commit => <<"aaaaaaaa">>,
                describe => <<"v1.0.0">>,
                dirty => false
            }},
            {nuggets, #{
                name => <<"vendor-one">>,
                type => git,
                url => <<"https://example.com/vendor/nuggets.git">>,
                commit => <<"bbbbbbbb">>,
                describe => <<"v2.0.0">>,
                dirty => false
            }},
            {nuggets2, #{
                name => <<"vendor-two">>,
                type => git,
                url => <<"https://git.example.net/partner/nuggets.git">>,
                commit => <<"cccccccc">>,
                describe => <<"v3.0.0">>,
                dirty => true
            }}
        ],
        maps:get(repositories, Seed)
    ),
    assert_equal(
        #{
            builder_core => common,
            toolchain_core => common,
            platform_core => nuggets,
            system_core => nuggets2,
            product => smelterl
        },
        maps:get(nugget_repo_map, Seed)
    ),
    assert_equal(
        [
            #{id => builder_core, fields => #{
                version => <<"1.0.0">>,
                repository => common,
                category => builder,
                license => <<"Apache-2.0">>,
                license_files => [<<"/licenses/builder/LICENSE">>]
            }},
            #{id => toolchain_core, fields => #{
                version => <<"1.0.0">>,
                repository => common,
                category => toolchain,
                license => <<"Apache-2.0">>,
                license_files => [<<"/licenses/toolchain/LICENSE">>]
            }},
            #{id => platform_core, fields => #{
                version => <<"2.0.0">>,
                repository => nuggets,
                category => platform,
                provides => [secure_boot],
                license => <<"GPL-2.0">>,
                license_files => [<<"/licenses/platform/COPYING">>]
            }},
            #{id => system_core, fields => #{
                version => <<"2.1.0">>,
                repository => nuggets2,
                category => system,
                license => <<"MIT">>,
                license_files => [<<"/licenses/system/LICENSE">>]
            }},
            #{id => product, fields => #{
                version => <<"3.4.5">>,
                repository => smelterl,
                category => feature,
                license => <<"Proprietary">>,
                license_files => [<<"/licenses/product/LICENSE">>]
            }}
        ],
        maps:get(nuggets, Seed)
    ),
    assert_equal(
        [
            #{
                id => aux_bundle,
                root_nugget => aux_root,
                constraints => [{flavor, encrypted}]
            }
        ],
        maps:get(auxiliary_products, Seed)
    ),
    assert_equal(
        #{
            firmware_variants => [plain, secure],
            selectable_outputs => [fwup_firmware],
            firmware_parameters => [
                #{
                    id => serial_number,
                    type => string,
                    required => true,
                    name => <<"Serial Number">>
                }
            ]
        },
        maps:get(capabilities, Seed)
    ),
    assert_equal(
        [
            #{
                target => main,
                outputs => [
                    #{
                        id => debug_symbols,
                        nugget => product,
                        name => <<"Debug symbols">>,
                        description => <<"Main-target symbols">>
                    }
                ]
            },
            #{
                target => aux_bundle,
                outputs => [
                    #{
                        id => initramfs,
                        nugget => aux_root,
                        name => <<"Encrypted initramfs">>,
                        description => <<"Auxiliary payload">>
                    }
                ]
            }
        ],
        maps:get(sdk_outputs, Seed)
    ),
    assert_equal(
        [
            #{
                id => crosstool_ng,
                nugget => platform_core,
                name => <<"Crosstool-NG">>,
                version => <<"1.25.0">>,
                license => <<"GPL-2.0">>,
                license_files => [<<"/licenses/components/ctng/COPYING">>]
            }
        ],
        maps:get(external_components, Seed)
    ),
    assert_equal(smelterl, maps:get(smelterl_repository, Seed)).

prepare_seed_requires_target_arch_triplet(_Config) ->
    Motherlode = #{
        repositories => #{},
        nuggets => #{
            product => nugget(product, feature, undefined, [])
        }
    },
    BuildInfo = #{
        name => <<"smelterl">>,
        relpath => <<>>,
        repo => #{
            name => <<"smelterl">>,
            url => <<"https://github.com/grisp/smelterl.git">>,
            commit => <<"0123456789abcdef">>,
            describe => <<"v0.1.0">>,
            dirty => false
        }
    },
    assert_equal(
        {error, {missing_target_arch_triplet, product}},
        smelterl_gen_manifest:prepare_seed(
            product,
            [product],
            Motherlode,
            #{},
            #{
                firmware_variants => [plain],
                variant_nuggets => #{plain => []},
                selectable_outputs => [],
                firmware_parameters => [],
                sdk_outputs_by_target => #{main => []}
            },
            [],
            BuildInfo
        )
    ).

nugget(Id, Category, Repository, ExtraFields) ->
    maps:merge(
        #{
            id => Id,
            category => Category,
            repository => Repository
        },
        maps:from_list(ExtraFields)
    ).

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp, got ~tp", [Expected, Actual])
    end.
