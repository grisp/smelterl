-module(smelterl_legal_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    parse_legal_extracts_target_and_host_packages/1,
    parse_legal_resolves_license_paths_relative_to_legal_info_root/1,
    parse_legal_accepts_buildroot_bare_quotes_inside_license_field/1,
    parse_legal_rejects_invalid_path/1,
    parse_legal_rejects_missing_manifest_file/1,
    parse_legal_rejects_malformed_manifest/1
]).

all() ->
    [
        parse_legal_extracts_target_and_host_packages,
        parse_legal_resolves_license_paths_relative_to_legal_info_root,
        parse_legal_accepts_buildroot_bare_quotes_inside_license_field,
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

assert_equal(Expected, Actual) ->
    case Actual of
        Expected ->
            ok;
        _ ->
            ct:fail("Expected ~tp but got ~tp", [Expected, Actual])
    end.

make_temp_dir(Prefix) ->
    Base = os:getenv("TMPDIR", "/tmp"),
    Unique = integer_to_list(erlang:unique_integer([positive])),
    Path = filename:join(Base, Prefix ++ "-" ++ Unique),
    ok = filelib:ensure_dir(filename:join(Path, "dummy")),
    Path.

write_manifest(Path, Lines) ->
    file:write_file(Path, Lines).

make_license_tree(_LegalDir, []) ->
    ok;
make_license_tree(LegalDir, [RelativePath | Rest]) ->
    FullPath = filename:join(LegalDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, <<"license fixture\n">>),
    make_license_tree(LegalDir, Rest).
