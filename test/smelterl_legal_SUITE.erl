-module(smelterl_legal_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    parse_legal_extracts_target_and_host_packages/1,
    parse_legal_resolves_license_paths_relative_to_legal_info_root/1,
    parse_legal_accepts_buildroot_bare_quotes_inside_license_field/1,
    export_legal_merges_buildroot_trees_and_preserves_readme_blocks/1,
    export_legal_includes_sources_when_requested/1,
    export_legal_rejects_existing_export_directory/1,
    export_alloy_writes_manifest_licenses_and_sources/1,
    parse_legal_rejects_invalid_path/1,
    parse_legal_rejects_missing_manifest_file/1,
    parse_legal_rejects_malformed_manifest/1
]).

all() ->
    [
        parse_legal_extracts_target_and_host_packages,
        parse_legal_resolves_license_paths_relative_to_legal_info_root,
        parse_legal_accepts_buildroot_bare_quotes_inside_license_field,
        export_legal_merges_buildroot_trees_and_preserves_readme_blocks,
        export_legal_includes_sources_when_requested,
        export_legal_rejects_existing_export_directory,
        export_alloy_writes_manifest_licenses_and_sources,
        parse_legal_rejects_invalid_path,
        parse_legal_rejects_missing_manifest_file,
        parse_legal_rejects_malformed_manifest
    ].

parse_legal_extracts_target_and_host_packages(_Config) ->
    LegalDir = make_temp_dir("smelterl-legal-parse"),
    ok = write_manifest(
        filename:join(LegalDir, "manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\",\"SOURCE ARCHIVE\",\"SOURCE SITE\",\"DEPENDENCIES WITH LICENSES\"\n">>,
            <<"\"busybox\",\"1.36.1\",\"GPL-2.0+\",\"LICENSE\",\"busybox-1.36.1.tar.bz2\",\"https://busybox.net\",\"glibc [LGPL-2.1+]\"\n">>,
            <<"\"erlang\",\"26.2.5\",\"Apache-2.0, OpenSSL-exception\",\"LICENSE.txt NOTICE\",\"otp_src_26.2.5.tar.gz\",\"https://erlang.org\",\"\"\n">>
        ]
    ),
    ok = write_manifest(
        filename:join(LegalDir, "host-manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\",\"SOURCE ARCHIVE\",\"SOURCE SITE\",\"DEPENDENCIES WITH LICENSES\"\n">>,
            <<"\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\",\"not saved\",\"not saved\",\"\"\n">>,
            <<"\"host-gcc-final\",\"13.3.0\",\"GPL-3.0+\",\"COPYING\",\"gcc-13.3.0.tar.xz\",\"https://gcc.gnu.org\",\"\"\n">>,
            <<"\"go-src\",\"\",\"BSD-3-Clause\",\"LICENSE\",\"go1.23.10.src.tar.gz\",\"https://storage.googleapis.com/golang\",\"\"\n">>,
            <<"\"go-bin\",\"\",\"BSD-3-Clause\",\"LICENSE\",\"go1.23.10.src.tar.gz\",\"https://go.dev/dl\",\"\"\n">>
        ]
    ),
    make_license_tree(
        LegalDir,
        [
            "licenses/busybox-1.36.1/LICENSE",
            "licenses/erlang-26.2.5/LICENSE.txt",
            "licenses/erlang-26.2.5/NOTICE",
            "host-licenses/buildroot/COPYING",
            "host-licenses/host-gcc-final-13.3.0/COPYING",
            "host-licenses/go-src/LICENSE",
            "host-licenses/go-bin/LICENSE"
        ]
    ),
    {ok, LegalInfo} = smelterl_legal:parse_legal(unicode:characters_to_binary(LegalDir)),
    assert_equal(
        unicode:characters_to_binary(filename:absname(LegalDir)),
        maps:get(path, LegalInfo)
    ),
    assert_equal(<<"2025.02.1">>, maps:get(br_version, LegalInfo)),
    assert_equal(
        [
            #{
                name => <<"busybox">>,
                version => <<"1.36.1">>,
                license => <<"GPL-2.0+">>,
                license_files => [<<"licenses/busybox-1.36.1/LICENSE">>]
            },
            #{
                name => <<"erlang">>,
                version => <<"26.2.5">>,
                license => <<"Apache-2.0, OpenSSL-exception">>,
                license_files => [
                    <<"licenses/erlang-26.2.5/LICENSE.txt">>,
                    <<"licenses/erlang-26.2.5/NOTICE">>
                ]
            }
        ],
        maps:get(packages, LegalInfo)
    ),
    assert_equal(
        [
            #{
                name => <<"host-gcc-final">>,
                version => <<"13.3.0">>,
                license => <<"GPL-3.0+">>,
                license_files => [<<"host-licenses/host-gcc-final-13.3.0/COPYING">>]
            },
            #{
                name => <<"go-src">>,
                version => <<>>,
                license => <<"BSD-3-Clause">>,
                license_files => [<<"host-licenses/go-src/LICENSE">>]
            },
            #{
                name => <<"go-bin">>,
                version => <<>>,
                license => <<"BSD-3-Clause">>,
                license_files => [<<"host-licenses/go-bin/LICENSE">>]
            }
        ],
        maps:get(host_packages, LegalInfo)
    ).

parse_legal_resolves_license_paths_relative_to_legal_info_root(_Config) ->
    LegalDir = make_temp_dir("smelterl-legal-license-paths"),
    ok = write_manifest(
        filename:join(LegalDir, "manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"systemd\",\"256.7\",\"LGPL-2.1+\",\"LICENSE.GPL2 LICENSES/README.md\"\n">>
        ]
    ),
    ok = write_manifest(
        filename:join(LegalDir, "host-manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"buildroot\",\"-gfcde5363aa\",\"GPL-2.0+\",\"COPYING\"\n">>,
            <<"\"ccache\",\"4.11.2\",\"GPL-3.0+, others\",\"LICENSE.adoc GPL-3.0.txt\"\n">>
        ]
    ),
    make_license_tree(
        LegalDir,
        [
            "licenses/systemd-256.7/LICENSE.GPL2",
            "licenses/systemd-256.7/LICENSES/README.md",
            "host-licenses/buildroot/COPYING",
            "host-licenses/ccache-4.11.2/LICENSE.adoc",
            "host-licenses/ccache-4.11.2/GPL-3.0.txt"
        ]
    ),
    {ok, LegalInfo} = smelterl_legal:parse_legal(unicode:characters_to_binary(LegalDir)),
    assert_equal(
        [
            #{
                name => <<"systemd">>,
                version => <<"256.7">>,
                license => <<"LGPL-2.1+">>,
                license_files => [
                    <<"licenses/systemd-256.7/LICENSE.GPL2">>,
                    <<"licenses/systemd-256.7/LICENSES/README.md">>
                ]
            }
        ],
        maps:get(packages, LegalInfo)
    ),
    assert_equal(
        [
            #{
                name => <<"ccache">>,
                version => <<"4.11.2">>,
                license => <<"GPL-3.0+, others">>,
                license_files => [
                    <<"host-licenses/ccache-4.11.2/LICENSE.adoc">>,
                    <<"host-licenses/ccache-4.11.2/GPL-3.0.txt">>
                ]
            }
        ],
        maps:get(host_packages, LegalInfo)
    ),
    assert_equal(<<"-gfcde5363aa">>, maps:get(br_version, LegalInfo)).

parse_legal_accepts_buildroot_bare_quotes_inside_license_field(_Config) ->
    LegalDir = make_temp_dir("smelterl-legal-bare-quotes"),
    ok = write_manifest(
        filename:join(LegalDir, "manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"busybox\",\"1.36.1\",\"GPL-2.0+\",\"LICENSE\"\n">>
        ]
    ),
    ok = write_manifest(
        filename:join(LegalDir, "host-manifest.csv"),
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"uuu\",\"1.5.201\",\"BSD 3-Clause \"New\" or \"Revised\" License\",\"LICENSE\"\n">>
        ]
    ),
    make_license_tree(
        LegalDir,
        [
            "licenses/busybox-1.36.1/LICENSE",
            "host-licenses/uuu-1.5.201/LICENSE"
        ]
    ),
    {ok, LegalInfo} = smelterl_legal:parse_legal(unicode:characters_to_binary(LegalDir)),
    assert_equal(
        [
            #{
                name => <<"uuu">>,
                version => <<"1.5.201">>,
                license => <<"BSD 3-Clause \"New\" or \"Revised\" License">>,
                license_files => [<<"host-licenses/uuu-1.5.201/LICENSE">>]
            }
        ],
        maps:get(host_packages, LegalInfo)
    ).

export_legal_merges_buildroot_trees_and_preserves_readme_blocks(Config) ->
    {AuxLegalDir, MainLegalDir} = make_export_legal_inputs(Config),
    ExportDir = filename:join(make_temp_dir(Config, "smelterl-legal-export"), "legal-info"),
    ok = smelterl_legal:export_legal(
        [
            unicode:characters_to_binary(AuxLegalDir),
            unicode:characters_to_binary(MainLegalDir)
        ],
        unicode:characters_to_binary(ExportDir),
        false
    ),
    assert_file_content(
        filename:join(ExportDir, "manifest.csv"),
        expected_merged_manifest_csv()
    ),
    assert_file_content(
        filename:join(ExportDir, "host-manifest.csv"),
        expected_merged_host_manifest_csv()
    ),
    assert_file_content(
        filename:join(ExportDir, "buildroot.config"),
        <<"BR2_TARGET=main\n">>
    ),
    assert_file_contains(
        filename:join(ExportDir, "README"),
        [
            <<"--- From Buildroot (auxiliary: aux_alpha) ---">>,
            <<"Aux target README">>,
            <<"WARNING: aux warning">>,
            <<"--- From Buildroot (main) ---">>,
            <<"Main target README">>,
            <<"WARNING: main warning">>
        ]
    ),
    assert_file_exists(filename:join(ExportDir, "licenses/auxpkg-0.1.0/LICENSE")),
    assert_file_exists(filename:join(ExportDir, "licenses/mainpkg-1.0.0/LICENSE")),
    assert_file_exists(filename:join(ExportDir, "licenses/sharedpkg-2.0.0/COPYING")),
    assert_file_exists(filename:join(ExportDir, "host-licenses/host-aux-1.0/LICENSE")),
    assert_file_exists(filename:join(ExportDir, "host-licenses/host-main-1.1/LICENSE")),
    assert_file_exists(filename:join(ExportDir, "host-licenses/shared-host-3.0/COPYING")),
    assert_file_missing(filename:join(ExportDir, "sources")),
    assert_file_missing(filename:join(ExportDir, "host-sources")),
    assert_file_contains(
        filename:join(ExportDir, "legal-info.sha256"),
        [
            <<"README">>,
            <<"buildroot.config">>,
            <<"manifest.csv">>,
            <<"host-manifest.csv">>
        ]
    ).

export_legal_includes_sources_when_requested(Config) ->
    {AuxLegalDir, MainLegalDir} = make_export_legal_inputs(Config),
    ExportDir = filename:join(make_temp_dir(Config, "smelterl-legal-export-sources"), "legal-info"),
    ok = smelterl_legal:export_legal(
        [
            unicode:characters_to_binary(AuxLegalDir),
            unicode:characters_to_binary(MainLegalDir)
        ],
        unicode:characters_to_binary(ExportDir),
        true
    ),
    assert_file_exists(filename:join(ExportDir, "sources/auxpkg-0.1.0/source.txt")),
    assert_file_exists(filename:join(ExportDir, "sources/mainpkg-1.0.0/source.txt")),
    assert_file_exists(filename:join(ExportDir, "host-sources/host-main-1.1/source.txt")),
    assert_file_contains(
        filename:join(ExportDir, "README"),
        [<<"sources/">>, <<"host-sources/">>]
    ).

export_legal_rejects_existing_export_directory(Config) ->
    {AuxLegalDir, MainLegalDir} = make_export_legal_inputs(Config),
    ExportDir = make_temp_dir(Config, "smelterl-legal-export-existing"),
    {error, {export_exists, _Path}} = smelterl_legal:export_legal(
        [
            unicode:characters_to_binary(AuxLegalDir),
            unicode:characters_to_binary(MainLegalDir)
        ],
        unicode:characters_to_binary(ExportDir),
        false
    ).

export_alloy_writes_manifest_licenses_and_sources(_Config) ->
    RepoDir = filename:join(make_temp_dir("smelterl-alloy-export-repo"), "builtin"),
    NuggetDir = filename:join(RepoDir, "demo"),
    CacheDir = make_temp_dir("smelterl-alloy-export-cache"),
    ExportDir = filename:join(make_temp_dir("smelterl-alloy-export"), "legal-info"),
    DemoLicense = filename:join(NuggetDir, "licenses/LICENSE"),
    ComponentLicense = filename:join(NuggetDir, "licenses/THIRD_PARTY.txt"),
    NuggetSource = filename:join(NuggetDir, "source.txt"),
    ComponentArchive = filename:join(CacheDir, "tooling-src.tar.gz"),
    ok = filelib:ensure_dir(DemoLicense),
    ok = file:write_file(DemoLicense, <<"demo license\n">>),
    ok = file:write_file(ComponentLicense, <<"component license\n">>),
    ok = file:write_file(NuggetSource, <<"nugget source\n">>),
    ok = file:write_file(ComponentArchive, <<"archive source\n">>),
    ok = filelib:ensure_dir(filename:join(ExportDir, "dummy")),
    ok = file:write_file(filename:join(ExportDir, "README"), <<"Buildroot-free export\n">>),
    Seed = #{
        product => demo,
        target_arch => <<"arm-buildroot-linux-gnueabihf">>,
        product_fields => #{},
        repositories => [],
        nugget_repo_map => #{demo => undefined},
        nuggets => [
            #{
                id => demo,
                fields => #{
                    version => <<"1.2.3">>,
                    category => feature,
                    license => <<"Proprietary">>,
                    license_files => [path_binary(DemoLicense)]
                }
            }
        ],
        auxiliary_products => [],
        capabilities => #{},
        sdk_outputs => [],
        external_components => [
            #{
                id => tooling,
                nugget => demo,
                version => <<"9.1">>,
                license => <<"BSD-3-Clause">>,
                license_files => [<<"licenses/THIRD_PARTY.txt">>],
                source_archive => {computed, <<"[[ALLOY_CACHE_DIR]]/tooling-src.tar.gz">>}
            }
        ],
        smelterl_repository => smelterl
    },
    Target = #{
        id => main,
        kind => main,
        motherlode => #{
            nuggets => #{
                demo => #{
                    id => demo,
                    repo_path => path_binary(RepoDir),
                    nugget_relpath => <<"demo">>,
                    version => <<"1.2.3">>
                }
            }
        },
        config => #{}
    },
    {ok, ExportedSeed} = smelterl_legal:export_alloy(
        Seed,
        Target,
        #{<<"ALLOY_CACHE_DIR">> => path_binary(CacheDir)},
        path_binary(ExportDir),
        true
    ),
    assert_file_exists(filename:join(ExportDir, "alloy-manifest.csv")),
    assert_file_exists(filename:join(ExportDir, "alloy-licenses/demo-1.2.3/LICENSE")),
    assert_file_exists(filename:join(ExportDir, "alloy-licenses/demo-1.2.3/tooling-9.1/THIRD_PARTY.txt")),
    assert_file_exists(filename:join(ExportDir, "alloy-sources/demo-1.2.3/source.txt")),
    assert_file_exists(filename:join(ExportDir, "alloy-sources/demo-1.2.3/tooling-9.1/tooling-src.tar.gz")),
    assert_file_contains(
        filename:join(ExportDir, "alloy-manifest.csv"),
        [
            <<"\"demo\",\"1.2.3\",\"Proprietary\",\"alloy-licenses/demo-1.2.3/LICENSE\",\"alloy-sources/demo-1.2.3\"">>,
            <<"\"tooling\",\"9.1\",\"BSD-3-Clause\",\"alloy-licenses/demo-1.2.3/tooling-9.1/THIRD_PARTY.txt\",\"alloy-sources/demo-1.2.3/tooling-9.1/tooling-src.tar.gz\"">>
        ]
    ),
    assert_file_contains(
        filename:join(ExportDir, "README"),
        [<<"alloy-manifest.csv">>, <<"alloy-licenses/">>, <<"alloy-sources/">>]
    ),
    assert_file_contains(
        filename:join(ExportDir, "legal-info.sha256"),
        [<<"alloy-manifest.csv">>, <<"alloy-licenses/demo-1.2.3/LICENSE">>]
    ),
    [#{fields := DemoFields}] = maps:get(nuggets, ExportedSeed),
    assert_equal(
        [<<"alloy-licenses/demo-1.2.3/LICENSE">>],
        relativize_paths(maps:get(license_files, DemoFields), path_binary(ExportDir))
    ).

parse_legal_rejects_invalid_path(_Config) ->
    MissingDir = unicode:characters_to_binary(filename:join(make_temp_dir("smelterl-legal-missing"), "missing")),
    {error, {invalid_path, MissingDir, _Detail}} = smelterl_legal:parse_legal(MissingDir).

parse_legal_rejects_missing_manifest_file(_Config) ->
    LegalDir = make_temp_dir("smelterl-legal-missing-manifest"),
    ok = write_manifest(
        filename:join(LegalDir, "manifest.csv"),
        [
            <<"package,version,license,license files\n">>,
            <<"busybox,1.36.1,GPL-2.0+,licenses/busybox-1.36.1/LICENSE\n">>
        ]
    ),
    LegalPath = unicode:characters_to_binary(filename:absname(LegalDir)),
    {error, {missing_manifest, LegalPath, _Detail}} =
        smelterl_legal:parse_legal(LegalPath).

parse_legal_rejects_malformed_manifest(_Config) ->
    LegalDir = make_temp_dir("smelterl-legal-malformed"),
    ok = write_manifest(
        filename:join(LegalDir, "manifest.csv"),
        [
            <<"package,version,license,license files\n">>,
            <<"busybox,1.36.1,\"GPL-2.0+,licenses/busybox-1.36.1/LICENSE\n">>
        ]
    ),
    ok = write_manifest(
        filename:join(LegalDir, "host-manifest.csv"),
        [
            <<"package,version,license,license files\n">>,
            <<"buildroot,2025.02.1,GPL-2.0+,\n">>
        ]
    ),
    LegalPath = unicode:characters_to_binary(filename:absname(LegalDir)),
    {error, {missing_manifest, LegalPath, _Detail}} =
        smelterl_legal:parse_legal(LegalPath).

make_export_legal_inputs(Config) ->
    BaseDir = make_temp_dir(Config, "smelterl-legal-export-inputs"),
    AuxLegalDir = filename:join(BaseDir, "targets/aux_alpha/workspace/legal-info"),
    MainLegalDir = filename:join(BaseDir, "targets/main/workspace/legal-info"),
    write_export_input(
        AuxLegalDir,
        <<"Aux target README\nWARNING: aux warning\n">>,
        <<"BR2_TARGET=aux\n">>,
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"auxpkg\",\"0.1.0\",\"Apache-2.0\",\"LICENSE\"\n">>,
            <<"\"sharedpkg\",\"2.0.0\",\"MIT\",\"COPYING\"\n">>
        ],
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\"\n">>,
            <<"\"host-aux\",\"1.0\",\"BSD-2-Clause\",\"LICENSE\"\n">>,
            <<"\"shared-host\",\"3.0\",\"Zlib\",\"COPYING\"\n">>
        ],
        [
            "licenses/auxpkg-0.1.0/LICENSE",
            "licenses/sharedpkg-2.0.0/COPYING",
            "host-licenses/buildroot/COPYING",
            "host-licenses/host-aux-1.0/LICENSE",
            "host-licenses/shared-host-3.0/COPYING"
        ],
        [
            "sources/auxpkg-0.1.0/source.txt",
            "host-sources/host-aux-1.0/source.txt"
        ]
    ),
    write_export_input(
        MainLegalDir,
        <<"Main target README\nWARNING: main warning\n">>,
        <<"BR2_TARGET=main\n">>,
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"mainpkg\",\"1.0.0\",\"BSD-3-Clause\",\"LICENSE\"\n">>,
            <<"\"sharedpkg\",\"2.0.0\",\"MIT\",\"COPYING\"\n">>
        ],
        [
            <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n">>,
            <<"\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\"\n">>,
            <<"\"host-main\",\"1.1\",\"Apache-2.0\",\"LICENSE\"\n">>,
            <<"\"shared-host\",\"3.0\",\"Zlib\",\"COPYING\"\n">>
        ],
        [
            "licenses/mainpkg-1.0.0/LICENSE",
            "licenses/sharedpkg-2.0.0/COPYING",
            "host-licenses/buildroot/COPYING",
            "host-licenses/host-main-1.1/LICENSE",
            "host-licenses/shared-host-3.0/COPYING"
        ],
        [
            "sources/mainpkg-1.0.0/source.txt",
            "host-sources/host-main-1.1/source.txt"
        ]
    ),
    {AuxLegalDir, MainLegalDir}.

write_export_input(
    LegalDir,
    Readme,
    BuildrootConfig,
    ManifestLines,
    HostManifestLines,
    LicensePaths,
    SourcePaths
) ->
    ok = filelib:ensure_dir(filename:join(LegalDir, "dummy")),
    ok = write_manifest(filename:join(LegalDir, "manifest.csv"), ManifestLines),
    ok = write_manifest(filename:join(LegalDir, "host-manifest.csv"), HostManifestLines),
    ok = file:write_file(filename:join(LegalDir, "README"), Readme),
    ok = file:write_file(filename:join(LegalDir, "buildroot.config"), BuildrootConfig),
    ok = make_license_tree(LegalDir, LicensePaths),
    ok = make_source_tree(LegalDir, SourcePaths).

expected_merged_manifest_csv() ->
    <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n"
      "\"auxpkg\",\"0.1.0\",\"Apache-2.0\",\"LICENSE\"\n"
      "\"mainpkg\",\"1.0.0\",\"BSD-3-Clause\",\"LICENSE\"\n"
      "\"sharedpkg\",\"2.0.0\",\"MIT\",\"COPYING\"\n">>.

expected_merged_host_manifest_csv() ->
    <<"\"PACKAGE\",\"VERSION\",\"LICENSE\",\"LICENSE FILES\"\n"
      "\"buildroot\",\"2025.02.1\",\"GPL-2.0+\",\"COPYING\"\n"
      "\"host-aux\",\"1.0\",\"BSD-2-Clause\",\"LICENSE\"\n"
      "\"host-main\",\"1.1\",\"Apache-2.0\",\"LICENSE\"\n"
      "\"shared-host\",\"3.0\",\"Zlib\",\"COPYING\"\n">>.

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp but got ~tp", [Expected, Actual])
    end.

assert_file_exists(Path) ->
    case file:read_file_info(Path) of
        {ok, _Info} ->
            ok;
        {error, Reason} ->
            ct:fail("Expected file ~ts to exist: ~tp", [Path, Reason])
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

assert_file_missing(Path) ->
    case file:read_file_info(Path) of
        {error, enoent} ->
            ok;
        {ok, _Info} ->
            ct:fail("Expected ~ts to be missing", [Path]);
        {error, Reason} ->
            ct:fail("Unexpected file-info result for ~ts: ~tp", [Path, Reason])
    end.

assert_file_contains(Path, Needles) ->
    case file:read_file(Path) of
        {ok, Content} ->
            lists:foreach(fun(Needle) -> assert_contains(Content, Needle) end, Needles);
        {error, Reason} ->
            ct:fail("Failed to read ~ts: ~tp", [Path, Reason])
    end.

assert_contains(Haystack, Needle) ->
    case binary:match(Haystack, Needle) of
        nomatch ->
            ct:fail("Expected ~tp to contain ~tp", [Haystack, Needle]);
        _ ->
            ok
    end.

make_temp_dir(Prefix) ->
    make_temp_dir(undefined, Prefix).

make_temp_dir(Config, Prefix) ->
    Base0 =
        case Config of
            undefined ->
                os:getenv("TMPDIR", "/tmp");
            _ ->
                proplists:get_value(priv_dir, Config, os:getenv("TMPDIR", "/tmp"))
        end,
    Base = filename:absname(Base0),
    ok = filelib:ensure_dir(filename:join(Base, "dummy")),
    make_temp_dir_attempt(Base, Prefix, 0).

make_temp_dir_attempt(_Base, Prefix, Attempt) when Attempt >= 64 ->
    ct:fail("Unable to create unique temp dir for prefix ~ts after ~B attempts", [Prefix, Attempt]);
make_temp_dir_attempt(Base, Prefix, Attempt) ->
    Unique = integer_to_list(erlang:unique_integer([positive, monotonic])),
    Path = filename:join(Base, Prefix ++ "-" ++ Unique),
    case file:make_dir(Path) of
        ok ->
            Path;
        {error, eexist} ->
            make_temp_dir_attempt(Base, Prefix, Attempt + 1);
        {error, Reason} ->
            ct:fail("Failed to create temp dir ~ts: ~tp", [Path, Reason])
    end.

write_manifest(Path, Lines) ->
    file:write_file(Path, Lines).

make_license_tree(_LegalDir, []) ->
    ok;
make_license_tree(LegalDir, [RelativePath | Rest]) ->
    FullPath = filename:join(LegalDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, <<"license fixture\n">>),
    make_license_tree(LegalDir, Rest).

make_source_tree(_LegalDir, []) ->
    ok;
make_source_tree(LegalDir, [RelativePath | Rest]) ->
    FullPath = filename:join(LegalDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, <<"source fixture\n">>),
    make_source_tree(LegalDir, Rest).

path_binary(Path) ->
    unicode:characters_to_binary(filename:absname(Path)).

relativize_paths(Paths, BasePath) ->
    [
        smelterl_file:relativize(Path, BasePath)
     || Path <- Paths
    ].
