-module(smelterl_gen_manifest_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    prepare_seed_builds_deterministic_manifest_seed/1,
    prepare_seed_requires_target_arch_triplet/1,
    build_from_seed_finalizes_manifest_without_buildroot_legal/1,
    build_from_seed_finalizes_manifest_with_buildroot_legal/1
]).

all() ->
    [
        prepare_seed_builds_deterministic_manifest_seed,
        prepare_seed_requires_target_arch_triplet,
        build_from_seed_finalizes_manifest_without_buildroot_legal,
        build_from_seed_finalizes_manifest_with_buildroot_legal
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

build_from_seed_finalizes_manifest_without_buildroot_legal(_Config) ->
    BaseDir = make_temp_dir("smelterl-manifest-finalize"),
    ManifestBase = path_binary(filename:join(BaseDir, "sdk")),
    {Seed, ExpectedPaths} = sample_manifest_seed(ManifestBase),
    RuntimeEnv = #{
        host_os => <<"Linux">>,
        host_arch => <<"x86_64">>,
        smelterl_version => <<"2.0.0">>,
        build_date => <<"2026-04-13T12:31:49Z">>
    },
    {ok, Manifest} = smelterl_gen_manifest:build_from_seed(
        Seed,
        undefined,
        ManifestBase,
        RuntimeEnv
    ),
    {sdk_manifest, <<"1.0">>, Fields} = Manifest,
    assert_equal(demo, field_value(product, Fields)),
    assert_equal(<<"Demo Product">>, field_value(product_name, Fields)),
    assert_equal(
        <<"arm-buildroot-linux-gnueabihf">>,
        field_value(target_arch, Fields)
    ),
    assert_equal(
        <<"2026-04-13T12:31:49Z">>,
        field_value(build_date, Fields)
    ),
    assert_equal(
        [
            {host_os, <<"Linux">>},
            {host_arch, <<"x86_64">>},
            {smelterl_version, <<"2.0.0">>},
            {smelterl_repository, smelterl}
        ],
        field_value(build_environment, Fields)
    ),
    assert_equal(
        [
            {nugget, platform_core, [
                {version, <<"2.0.0">>},
                {repository, product_repo},
                {category, platform},
                {provides, [secure_boot]},
                {license, <<"GPL-2.0">>},
                {license_files, [maps:get(platform_license, ExpectedPaths)]}
            ]},
            {nugget, demo, [
                {version, <<"3.4.5">>},
                {repository, product_repo},
                {category, feature},
                {license, <<"Proprietary">>},
                {license_files, [maps:get(product_license, ExpectedPaths)]}
            ]}
        ],
        field_value(nuggets, Fields)
    ),
    assert_equal(
        [
            {auxiliary, aux_alpha, [
                {root_nugget, aux_root},
                {constraints, [{flavor, encrypted}]}
            ]}
        ],
        field_value(auxiliary_products, Fields)
    ),
    assert_equal(
        [
            {firmware_variants, [plain, secure]},
            {selectable_outputs, [fwup_firmware]},
            {firmware_parameters, [
                {serial_number, [
                    {type, string},
                    {required, true},
                    {name, <<"Serial Number">>}
                ]}
            ]}
        ],
        field_value(capabilities, Fields)
    ),
    assert_equal(
        [
            {target, main, [
                {output, debug_symbols, [
                    {nugget, demo},
                    {name, <<"Debug symbols">>},
                    {description, <<"Main-target symbols">>}
                ]}
            ]},
            {target, aux_alpha, [
                {output, initramfs, [
                    {nugget, aux_root},
                    {name, <<"Encrypted initramfs">>},
                    {description, <<"Auxiliary payload">>}
                ]}
            ]}
        ],
        field_value(sdk_outputs, Fields)
    ),
    assert_equal(
        [
            {component, crosstool_ng, [
                {nugget, platform_core},
                {name, <<"Crosstool-NG">>},
                {version, <<"1.25.0">>},
                {license, <<"GPL-2.0">>},
                {license_files, [maps:get(component_license, ExpectedPaths)]}
            ]}
        ],
        field_value(external_components, Fields)
    ),
    assert_missing_field(buildroot_packages, Fields),
    assert_missing_field(buildroot_host_packages, Fields),
    assert_valid_integrity(Manifest).

build_from_seed_finalizes_manifest_with_buildroot_legal(_Config) ->
    BaseDir = make_temp_dir("smelterl-manifest-finalize-legal"),
    ManifestBase = path_binary(filename:join(BaseDir, "sdk")),
    ExportDir = path_binary(filename:join(binary_to_list(ManifestBase), "legal-info")),
    {Seed, _ExpectedPaths} = sample_manifest_seed(ManifestBase),
    RuntimeEnv = #{
        host_os => <<"Linux">>,
        host_arch => <<"x86_64">>,
        smelterl_version => <<"2.0.0">>,
        build_date => <<"2026-04-13T12:31:49Z">>
    },
    BuildrootLegal = #{
        path => ExportDir,
        br_version => <<"2025.02.1">>,
        packages => [
            #{
                name => <<"busybox">>,
                version => <<"1.36.1">>,
                license => <<"GPL-2.0">>,
                license_files => [
                    path_binary(
                        filename:join(
                            [binary_to_list(ExportDir), "licenses", "busybox-1.36.1", "LICENSE"]
                        )
                    )
                ]
            }
        ],
        host_packages => [
            #{
                name => <<"host-gcc">>,
                version => <<"13.2.0">>,
                license => <<"GPL-3.0">>,
                license_files => [
                    path_binary(
                        filename:join(
                            [binary_to_list(ExportDir), "host-licenses", "host-gcc-13.2.0", "COPYING"]
                        )
                    )
                ]
            }
        ]
    },
    {ok, Manifest} = smelterl_gen_manifest:build_from_seed(
        Seed,
        BuildrootLegal,
        ManifestBase,
        RuntimeEnv
    ),
    {sdk_manifest, <<"1.0">>, Fields} = Manifest,
    assert_contains_tuple(
        {buildroot_version, <<"2025.02.1">>},
        field_value(build_environment, Fields)
    ),
    assert_equal(
        [
            {package, <<"busybox">>, [
                {version, <<"1.36.1">>},
                {license, <<"GPL-2.0">>},
                {license_files, [<<"legal-info/licenses/busybox-1.36.1/LICENSE">>]}
            ]}
        ],
        field_value(buildroot_packages, Fields)
    ),
    assert_equal(
        [
            {package, <<"host-gcc">>, [
                {version, <<"13.2.0">>},
                {license, <<"GPL-3.0">>},
                {license_files, [<<"legal-info/host-licenses/host-gcc-13.2.0/COPYING">>]}
            ]}
        ],
        field_value(buildroot_host_packages, Fields)
    ),
    assert_valid_integrity(Manifest).

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

field_value(Key, Fields) ->
    case lists:keyfind(Key, 1, Fields) of
        {Key, Value} ->
            Value;
        false ->
            ct:fail("Missing field ~tp in ~tp", [Key, Fields])
    end.

assert_missing_field(Key, Fields) ->
    case lists:keyfind(Key, 1, Fields) of
        false ->
            ok;
        Field ->
            ct:fail("Expected field ~tp to be absent, found ~tp", [Key, Field])
    end.

assert_contains_tuple(Expected, Tuples) ->
    case lists:member(Expected, Tuples) of
        true ->
            ok;
        false ->
            ct:fail("Expected ~tp to contain tuple ~tp", [Tuples, Expected])
    end.

assert_valid_integrity({sdk_manifest, <<"1.0">>, Fields} = Manifest) ->
    Integrity = field_value(integrity, Fields),
    StrippedFields = [Field || {Key, _Value} = Field <- Fields, Key =/= integrity],
    ExpectedDigest = hex_encode(
        crypto:hash(
            sha256,
            unicode:characters_to_binary(
                io_lib:format("~0tp.~n", [{sdk_manifest, <<"1.0">>, StrippedFields}])
            )
        )
    ),
    assert_equal(
        [
            {digest_algorithm, sha256},
            {canonical_form, basic_term_canon},
            {digest, ExpectedDigest}
        ],
        Integrity
    ),
    assert_equal(
        {sdk_manifest, <<"1.0">>, StrippedFields ++ [{integrity, Integrity}]},
        Manifest
    ).

sample_manifest_seed(ManifestBase) ->
    PlatformLicense = absolute_child(
        ManifestBase,
        ["legal-info", "alloy-licenses", "platform_core-2.0.0", "COPYING"]
    ),
    ProductLicense = absolute_child(
        ManifestBase,
        ["legal-info", "alloy-licenses", "demo-3.4.5", "LICENSE"]
    ),
    ComponentLicense = absolute_child(
        ManifestBase,
        ["legal-info", "alloy-licenses", "platform_core-2.0.0", "crosstool-ng", "COPYING"]
    ),
    {#{
        product => demo,
        target_arch => <<"arm-buildroot-linux-gnueabihf">>,
        product_fields => #{
            name => <<"Demo Product">>,
            description => <<"Demonstration seed build">>,
            version => <<"3.4.5">>
        },
        repositories => [
            {smelterl, #{
                name => <<"smelterl">>,
                type => git,
                url => <<"https://github.com/grisp/smelterl.git">>,
                commit => <<"0123456789abcdef">>,
                describe => <<"v0.1.0">>,
                dirty => false
            }},
            {product_repo, #{
                name => <<"demo-repo">>,
                type => git,
                url => <<"https://example.com/demo.git">>,
                commit => <<"feedface">>,
                describe => <<"v3.4.5">>,
                dirty => false
            }}
        ],
        nugget_repo_map => #{
            platform_core => product_repo,
            demo => product_repo
        },
        nuggets => [
            #{id => platform_core, fields => #{
                version => <<"2.0.0">>,
                repository => product_repo,
                category => platform,
                provides => [secure_boot],
                license => <<"GPL-2.0">>,
                license_files => [PlatformLicense]
            }},
            #{id => demo, fields => #{
                version => <<"3.4.5">>,
                repository => product_repo,
                category => feature,
                license => <<"Proprietary">>,
                license_files => [ProductLicense]
            }}
        ],
        auxiliary_products => [
            #{
                id => aux_alpha,
                root_nugget => aux_root,
                constraints => [{flavor, encrypted}]
            }
        ],
        capabilities => #{
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
        sdk_outputs => [
            #{
                target => main,
                outputs => [
                    #{
                        id => debug_symbols,
                        nugget => demo,
                        name => <<"Debug symbols">>,
                        description => <<"Main-target symbols">>
                    }
                ]
            },
            #{
                target => aux_alpha,
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
        external_components => [
            #{
                id => crosstool_ng,
                nugget => platform_core,
                name => <<"Crosstool-NG">>,
                version => <<"1.25.0">>,
                license => <<"GPL-2.0">>,
                license_files => [ComponentLicense]
            }
        ],
        smelterl_repository => smelterl
    },
    #{
        platform_license => <<"legal-info/alloy-licenses/platform_core-2.0.0/COPYING">>,
        product_license => <<"legal-info/alloy-licenses/demo-3.4.5/LICENSE">>,
        component_license => <<"legal-info/alloy-licenses/platform_core-2.0.0/crosstool-ng/COPYING">>
    }}.

absolute_child(Base, RelativeParts) ->
    path_binary(
        filename:join([binary_to_list(Base) | RelativeParts])
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

path_binary(Path) ->
    list_to_binary(filename:absname(Path)).

hex_encode(Binary) ->
    << <<(hex_digit((Byte bsr 4) band 16#0f))/utf8,
         (hex_digit(Byte band 16#0f))/utf8>> || <<Byte>> <= Binary >>.

hex_digit(Value) when Value < 10 ->
    $0 + Value;
hex_digit(Value) ->
    $a + (Value - 10).
