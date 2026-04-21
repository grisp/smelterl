-module(smelterl_gen_context_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    render_main_context_includes_main_only_sections/1,
    render_auxiliary_context_omits_main_only_sections/1
]).

all() ->
    [
        render_main_context_includes_main_only_sections,
        render_auxiliary_context_omits_main_only_sections
    ].

render_main_context_includes_main_only_sections(_Config) ->
    {PlanProductId, MainTarget, _AuxTarget} = sample_targets(),
    {ok, Content} = smelterl_gen_context:render(PlanProductId, MainTarget),
    Output = iolist_to_binary(Content),
    assert_contains(Output, <<"export ALLOY_PRODUCT=\"demo_product\"">>),
    assert_contains(Output, <<"export ALLOY_FIRMWARE_VARIANTS=(\"plain\" \"secure\")">>),
    assert_contains(Output, <<"ALLOY_PRE_BUILD_HOOKS=(\"platform_core:scripts/pre-build.sh\")">>),
    assert_contains(
        Output,
        <<"ALLOY_FIRMWARE_BUILD_HOOKS_PLAIN=(\"bootflow_plain:scripts/build-plain.sh\")">>
    ),
    assert_contains(
        Output,
        <<"ALLOY_FIRMWARE_BUILD_HOOKS_SECURE=(\"security_secure:scripts/build-secure.sh\")">>
    ),
    assert_contains(Output, <<"ALLOY_FS_PRIORITIES_FRAGMENTS=(">>),
    assert_contains(Output, <<"ALLOY_EMBED_IMAGES=(\"rootfs.img\")">>),
    assert_contains(Output, <<"export ALLOY_FIRMWARE_OUTPUTS=(">>),
    assert_contains(Output, <<"export ALLOY_FIRMWARE_PARAMETERS=(">>),
    assert_contains(
        Output,
        <<"export ALLOY_PRODUCT_VERSION=\"9.9.9\"\n\n## Firmware Variants ##">>
    ),
    assert_contains(
        Output,
        <<"export ALLOY_CONFIG_PLATFORM_MODE=\"imx8\"\n\n## Registries ##">>
    ),
    assert_contains(
        Output,
        <<"export ALLOY_SDK_OUTPUT_SYMBOLS_NAME=\"Symbols\"\n\n## Helper Functions ##">>
    ),
    assert_contains(Output, <<"alloy_sdk_output_from_aux()">>).

render_auxiliary_context_omits_main_only_sections(_Config) ->
    {PlanProductId, _MainTarget, AuxTarget} = sample_targets(),
    {ok, Content} = smelterl_gen_context:render(PlanProductId, AuxTarget),
    Output = iolist_to_binary(Content),
    assert_contains(Output, <<"export ALLOY_PRODUCT=\"aux_init\"">>),
    assert_contains(Output, <<"export ALLOY_IS_AUXILIARY=\"true\"">>),
    assert_contains(Output, <<"ALLOY_PRE_BUILD_HOOKS=(\"aux_root:scripts/pre-build.sh\")">>),
    assert_contains(Output, <<"export ALLOY_SDK_OUTPUTS=(\"initramfs\")">>),
    assert_not_contains(Output, <<"ALLOY_FIRMWARE_VARIANTS">>),
    assert_not_contains(Output, <<"ALLOY_EMBED_IMAGES">>),
    assert_not_contains(Output, <<"ALLOY_FS_PRIORITIES_FRAGMENTS">>),
    assert_not_contains(Output, <<"ALLOY_FIRMWARE_OUTPUTS">>),
    assert_not_contains(Output, <<"alloy_sdk_output_from_aux()">>).

sample_targets() ->
    Motherlode = sample_motherlode(),
    MainTarget = #{
        id => main,
        kind => main,
        tree => #{
            root => demo_product,
            edges => #{
                builder_core => [],
                toolchain_core => [],
                platform_core => [],
                system_core => [platform_core],
                security_secure => [system_core],
                bootflow_plain => [system_core],
                demo_product =>
                    [
                        builder_core,
                        toolchain_core,
                        platform_core,
                        system_core,
                        security_secure,
                        bootflow_plain
                    ]
            }
        },
        topology =>
            [
                builder_core,
                toolchain_core,
                platform_core,
                system_core,
                security_secure,
                bootflow_plain,
                demo_product
            ],
        motherlode => Motherlode,
        config => #{
            <<"ALLOY_NUGGET_PLATFORM_CORE_CONFIG_PLATFORM_MODE">> =>
                {nugget, platform_core, <<"imx8">>},
            <<"ALLOY_NUGGET_DEMO_PRODUCT_CONFIG_DEVICE_NAME">> =>
                {nugget, demo_product, <<"demo-box">>},
            <<"ALLOY_CONFIG_PLATFORM_MODE">> =>
                {global, undefined, <<"imx8">>},
            <<"ALLOY_CONFIG_DEVICE_NAME">> =>
                {global, undefined, <<"demo-box">>}
        },
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities()
    },
    AuxTarget = #{
        id => aux_init,
        kind => auxiliary,
        aux_root => aux_root,
        constraints => [],
        tree => #{
            root => aux_root,
            edges => #{
                builder_core => [],
                toolchain_core => [],
                platform_core => [],
                system_core => [platform_core],
                aux_root => [builder_core, toolchain_core, platform_core, system_core]
            }
        },
        topology => [builder_core, toolchain_core, platform_core, system_core, aux_root],
        motherlode => Motherlode,
        config => #{
            <<"ALLOY_NUGGET_AUX_ROOT_CONFIG_INITRAMFS_COMPRESSION">> =>
                {nugget, aux_root, <<"gzip">>},
            <<"ALLOY_CONFIG_INITRAMFS_COMPRESSION">> =>
                {global, undefined, <<"gzip">>}
        },
        defconfig => #{regular => [], cumulative => []},
        capabilities => sample_capabilities()
    },
    {demo_product, MainTarget, AuxTarget}.

sample_capabilities() ->
    #{
        firmware_variants => [plain, secure],
        variant_nuggets => #{
            plain => [bootflow_plain],
            secure => [security_secure]
        },
        selectable_outputs => [
            #{
                id => plain_image,
                default => true,
                name => <<"Plain image">>,
                description => <<"Default firmware image">>
            }
        ],
        firmware_parameters => [
            #{
                id => serial_number,
                type => string,
                required => true,
                name => <<"Serial number">>,
                description => <<"Factory serial number">>
            }
        ],
        sdk_outputs_by_target => #{
            main => [
                #{id => symbols, nugget => demo_product, name => <<"Symbols">>}
            ],
            aux_init => [
                #{
                    id => initramfs,
                    nugget => aux_root,
                    name => <<"Initramfs">>,
                    description => <<"Auxiliary initramfs image">>
                }
            ]
        }
    }.

sample_motherlode() ->
    #{
        nuggets => #{
            platform_core => #{
                id => platform_core,
                category => platform,
                repository => builtin,
                nugget_relpath => <<"platform_core">>,
                name => <<"Platform Core">>,
                description => <<"Core platform">>,
                version => <<"1.0.0">>,
                hooks => [
                    {pre_build, <<"scripts/pre-build.sh">>},
                    {post_build, <<"scripts/post-build.sh">>, all}
                ],
                embed => [
                    {images, <<"rootfs.img">>},
                    {host, <<"bin/tool">>}
                ],
                fs_priorities => <<"fs.prio">>
            },
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
            system_core => #{
                id => system_core,
                category => system,
                repository => builtin,
                nugget_relpath => <<"system_core">>,
                name => <<"System Core">>,
                version => <<"1.0.0">>
            },
            security_secure => #{
                id => security_secure,
                category => feature,
                repository => builtin,
                nugget_relpath => <<"security_secure">>,
                name => <<"Secure Boot">>,
                description => <<"Secure firmware support">>,
                version => <<"2.0.0">>,
                firmware_variant => [secure],
                hooks => [
                    {pre_firmware, <<"scripts/pre-secure.sh">>},
                    {firmware_build, <<"scripts/build-secure.sh">>}
                ],
                embed => [
                    {nugget, <<"scripts/pre-secure.sh">>}
                ],
                firmware_outputs => [
                    {signed_boot, [
                        {display_name, <<"Signed boot">>},
                        {description, <<"Secure boot artefact">>}
                    ]}
                ]
            },
            bootflow_plain => #{
                id => bootflow_plain,
                category => bootflow,
                repository => builtin,
                nugget_relpath => <<"bootflow_plain">>,
                name => <<"Plain Bootflow">>,
                description => <<"Plain firmware assembly">>,
                version => <<"1.1.0">>,
                firmware_variant => [plain],
                hooks => [
                    {firmware_build, <<"scripts/build-plain.sh">>}
                ],
                firmware_outputs => [
                    {plain_image, [
                        {selectable, true},
                        {display_name, <<"Plain image">>},
                        {description, <<"Default firmware image">>}
                    ]}
                ]
            },
            demo_product => #{
                id => demo_product,
                category => feature,
                repository => builtin,
                nugget_relpath => <<"demo_product">>,
                name => <<"Demo Product">>,
                description => <<"Demo product BSP">>,
                version => <<"9.9.9">>,
                hooks => [
                    {post_fakeroot, <<"scripts/post-fakeroot.sh">>, all},
                    {post_firmware, <<"scripts/post-firmware.sh">>}
                ],
                sdk_outputs => [
                    {symbols, [{display_name, <<"Symbols">>}]}
                ]
            },
            aux_root => #{
                id => aux_root,
                category => feature,
                repository => builtin,
                nugget_relpath => <<"aux_root">>,
                name => <<"Aux Initramfs">>,
                description => <<"Auxiliary initramfs">>,
                version => <<"0.2.0">>,
                hooks => [
                    {pre_build, <<"scripts/pre-build.sh">>, auxiliary},
                    {post_build, <<"scripts/post-build.sh">>, aux_init},
                    {post_image, <<"scripts/post-image.sh">>, all}
                ],
                sdk_outputs => [
                    {initramfs, [
                        {display_name, <<"Initramfs">>},
                        {description, <<"Auxiliary initramfs image">>}
                    ]}
                ]
            }
        },
        repositories => #{}
    }.

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
