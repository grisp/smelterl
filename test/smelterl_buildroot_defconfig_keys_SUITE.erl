%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_buildroot_defconfig_keys_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0]).
-export([
    escript_detects_known_cumulative_keys/1,
    escript_honors_overrides_and_sanitizes_header/1
]).

all() ->
    [
        escript_detects_known_cumulative_keys,
        escript_honors_overrides_and_sanitizes_header
    ].

escript_detects_known_cumulative_keys(_Config) ->
    BuildrootDir = make_buildroot_dir("smelterl-buildroot-defconfig-keys"),
    OutputPath = filename:join(filename:dirname(BuildrootDir), "defconfig-keys.spec"),
    ok = write_file(
        BuildrootDir,
        "Makefile",
        "export BR2_VERSION := 2025.05\n"
    ),
    ok = write_file(
        BuildrootDir,
        "system/Config.in",
        [
            "config BR2_ROOTFS_OVERLAY\n",
            "\tstring \"Root filesystem overlay directories\"\n",
            "\thelp\n",
            "\t  Specify a list of directories that are copied over the target\n",
            "\n",
            "config BR2_ROOTFS_POST_BUILD_SCRIPT\n",
            "\tstring \"Custom scripts to run before creating filesystem images\"\n",
            "\thelp\n",
            "\t  Specify a space-separated list of scripts to be run after the\n",
            "\n",
            "config BR2_ENABLE_LOCALE_WHITELIST\n",
            "\tstring \"Locales to keep\"\n",
            "\thelp\n",
            "\t  Whitespace separated list of locales to allow on target.\n",
            "\n",
            "config BR2_ROOTFS_DEVICE_TABLE\n",
            "\tstring \"Path to the permission table\"\n",
            "\thelp\n",
            "\t  Specify a space-separated list of device table locations,\n"
        ]
    ),
    ok = write_file(
        BuildrootDir,
        "linux/Config.in",
        [
            "config BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES\n",
            "\tstring \"Additional configuration fragment files\"\n",
            "\thelp\n",
            "\t  A space-separated list of kernel configuration fragment files,\n"
        ]
    ),
    ok = write_file(
        BuildrootDir,
        "package/busybox/Config.in",
        [
            "config BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES\n",
            "\tstring \"Additional BusyBox configuration fragment files\"\n",
            "\thelp\n",
            "\t  A space-separated list of configuration fragment files,\n"
        ]
    ),
    {0, <<>>} = run_generator([
        "--buildroot",
        BuildrootDir,
        "--output",
        OutputPath
    ]),
    {ok, [_Entries]} = file:consult(OutputPath),
    {ok, Content} = file:read_file(OutputPath),
    assert_contains(Content, <<"%% Buildroot version: 2025.05\n">>),
    assert_contains(Content, <<"{<<\"BR2_ENABLE_LOCALE_WHITELIST\">>, plain}">>),
    assert_contains(Content, <<"{<<\"BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES\">>, path}">>),
    assert_contains(Content, <<"{<<\"BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES\">>, path}">>),
    assert_contains(Content, <<"{<<\"BR2_ROOTFS_DEVICE_TABLE\">>, path}">>),
    assert_contains(Content, <<"{<<\"BR2_ROOTFS_OVERLAY\">>, path}">>),
    assert_contains(Content, <<"{<<\"BR2_ROOTFS_POST_BUILD_SCRIPT\">>, path}">>).

escript_honors_overrides_and_sanitizes_header(_Config) ->
    BuildrootDir = make_buildroot_dir("smelterl-buildroot-defconfig-keys-abs"),
    OutputPath = filename:join(filename:dirname(BuildrootDir), "defconfig-keys.spec"),
    ok = write_file(
        BuildrootDir,
        "Makefile",
        "export BR2_VERSION := 2025.05\n"
    ),
    ok = write_file(
        BuildrootDir,
        "package/demo/Config.in",
        [
            "config BR2_CUSTOM_FEATURE_SET\n",
            "\tstring \"Feature names\"\n",
            "\thelp\n",
            "\t  Specify a space-separated list of feature names to enable.\n",
            "\n",
            "config BR2_PACKAGE_DEMO_MODULES\n",
            "\tstring \"Modules\"\n",
            "\thelp\n",
            "\t  Specify a space-separated list of modules to load.\n"
        ]
    ),
    {0, <<>>} = run_generator([
        "--buildroot",
        BuildrootDir,
        "--output",
        OutputPath,
        "--include",
        "BR2_CUSTOM_FEATURE_SET",
        "--override",
        "BR2_CUSTOM_FEATURE_SET=plain"
    ]),
    {ok, [_Entries]} = file:consult(OutputPath),
    {ok, Content} = file:read_file(OutputPath),
    BuildrootPathBin = unicode:characters_to_binary(BuildrootDir),
    assert_not_contains(Content, BuildrootPathBin),
    assert_contains(Content, <<"%% Explicit includes: BR2_CUSTOM_FEATURE_SET\n">>),
    assert_contains(Content, <<"%% Explicit overrides: BR2_CUSTOM_FEATURE_SET=plain\n">>),
    assert_contains(Content, <<"--buildroot buildroot">>),
    assert_contains(Content, <<"{<<\"BR2_CUSTOM_FEATURE_SET\">>, plain}">>),
    assert_contains(Content, <<"{<<\"BR2_PACKAGE_DEMO_MODULES\">>, plain}">>).

run_generator(Args) ->
    Root = repo_root(),
    ScriptPath = filename:join([Root, "scripts", "generate_defconfig_keys.escript"]),
    Executable =
        case os:find_executable("escript") of
            false ->
                ct:fail("escript executable not found on PATH");
            Path ->
                Path
        end,
    Port = open_port(
        {spawn_executable, Executable},
        [
            binary,
            eof,
            exit_status,
            stderr_to_stdout,
            use_stdio,
            {cd, Root},
            {args, [ScriptPath | Args]}
        ]
    ),
    collect_port_output(Port, []).

repo_root() ->
    BeamPath = code:which(?MODULE),
    find_repo_root(filename:dirname(BeamPath)).

find_repo_root(Path) ->
    case filelib:is_file(filename:join(Path, "rebar.config")) andalso
        filelib:is_file(
            filename:join([Path, "scripts", "generate_defconfig_keys.escript"])
        ) of
        true ->
            Path;
        false ->
            Parent = filename:dirname(Path),
            case Parent =:= Path of
                true ->
                    ct:fail("Could not locate smelterl repository root from ~ts", [Path]);
                false ->
                    find_repo_root(Parent)
            end
    end.

collect_port_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_port_output(Port, [Data | Acc]);
        {Port, eof} ->
            receive
                {Port, {exit_status, Status}} ->
                    port_close(Port),
                    {Status, trim_binary(iolist_to_binary(lists:reverse(Acc)))}
            end
    end.

make_buildroot_dir(Prefix) ->
    Root = make_temp_dir(Prefix),
    BuildrootDir = filename:join(Root, "buildroot"),
    ok = filelib:ensure_dir(filename:join(BuildrootDir, "placeholder")),
    BuildrootDir.

write_file(BuildrootDir, RelativePath, Contents) ->
    FullPath = filename:join(BuildrootDir, RelativePath),
    ok = filelib:ensure_dir(FullPath),
    ok = file:write_file(FullPath, Contents).

make_temp_dir(Prefix) ->
    Base = os:getenv("TMPDIR", "/tmp"),
    make_temp_dir(Base, Prefix, 0).

make_temp_dir(Base, Prefix, Attempt) ->
    Suffix =
        integer_to_list(erlang:system_time(nanosecond)) ++
        "-" ++
        integer_to_list(erlang:unique_integer([positive])) ++
        "-" ++
        integer_to_list(Attempt),
    Dir = filename:join(Base, Prefix ++ "-" ++ Suffix),
    case file:make_dir(Dir) of
        ok ->
            Dir;
        {error, eexist} ->
            make_temp_dir(Base, Prefix, Attempt + 1)
    end.

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
            ct:fail("Expected ~tp to omit ~tp", [Haystack, Needle])
    end.

trim_binary(Binary) ->
    trim_trailing_binary(trim_leading_binary(Binary)).

trim_leading_binary(<<Char, Rest/binary>>)
  when Char =:= $\s; Char =:= $\t; Char =:= $\r; Char =:= $\n ->
    trim_leading_binary(Rest);
trim_leading_binary(Binary) ->
    Binary.

trim_trailing_binary(Binary) ->
    trim_trailing_binary(Binary, byte_size(Binary)).

trim_trailing_binary(_Binary, 0) ->
    <<>>;
trim_trailing_binary(Binary, Size) ->
    case binary:at(Binary, Size - 1) of
        Char when Char =:= $\s; Char =:= $\t; Char =:= $\r; Char =:= $\n ->
            trim_trailing_binary(Binary, Size - 1);
        _ ->
            binary:part(Binary, 0, Size)
    end.
