#!/usr/bin/env escript
%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0
%%! -noshell

-mode(compile).

-type cumulative_kind() :: path | plain.
-type generator_options() :: #{
    command_name => binary(),
    generated_at => binary(),
    includes => [binary()],
    output => binary(),
    overrides => #{binary() => cumulative_kind()}
}.
-type symbol_meta() :: #{
    block_texts := [binary()],
    key := binary(),
    sources := [binary()],
    type := binary() | undefined
}.

main(Argv) ->
    case parse_cli(Argv, default_cli_options()) of
        {ok, Opts} ->
            BuildrootDir = maps:get(buildroot, Opts),
            OutputPath = maps:get(output, Opts),
            GeneratorOpts = #{
                command_name => maps:get(command_name, Opts),
                generated_at => generated_at(),
                includes => maps:get(includes, Opts, []),
                output => maps:get(output, Opts),
                overrides => maps:get(overrides, Opts, #{})
            },
            case write_file(BuildrootDir, OutputPath, GeneratorOpts) of
                ok ->
                    halt(0);
                {error, Reason} ->
                    print_error(format_error(Reason)),
                    halt(1)
            end;
        {help, HelpText} ->
            io:put_chars(HelpText),
            halt(0);
        {error, Message} ->
            print_error(Message),
            halt(2)
    end.

-spec generate(file:name_all(), generator_options()) ->
    {ok, binary()} | {error, term()}.
generate(BuildrootDir, Opts0) ->
    BuildrootPath = path_to_list(BuildrootDir),
    Opts = normalize_options(Opts0),
    maybe
        {ok, Symbols} ?= load_symbols(BuildrootPath),
        ok ?= validate_requested_keys(Symbols, Opts),
        {ok, Version} ?= buildroot_version(BuildrootPath),
        RevisionInfo = buildroot_revision(BuildrootPath),
        {ok, Entries} ?= classify_symbols(Symbols, Opts),
        {ok, render_spec(BuildrootPath, Version, RevisionInfo, Entries, Opts)}
    else
        {error, _} = Error ->
            Error
    end.

-spec write_file(file:name_all(), file:name_all(), generator_options()) ->
    ok | {error, term()}.
write_file(BuildrootDir, OutputPath, Opts0) ->
    Opts = normalize_options(
        Opts0#{
            output => unicode:characters_to_binary(path_to_list(OutputPath))
        }
    ),
    maybe
        {ok, Content} ?= generate(BuildrootDir, Opts),
        ok ?= file:write_file(path_to_list(OutputPath), Content)
    else
        {error, _} = Error ->
            Error
    end.

-spec default_cli_options() -> map().
default_cli_options() ->
    #{
        command_name => <<"./scripts/generate_defconfig_keys.escript">>,
        includes => [],
        output => <<"priv/defconfig-keys.spec">>,
        overrides => #{}
    }.

-spec normalize_options(generator_options()) -> generator_options().
normalize_options(Opts0) ->
    Opts1 = maps:merge(
        #{
            command_name => <<"./scripts/generate_defconfig_keys.escript">>,
            generated_at => generated_at(),
            includes => [],
            output => <<"priv/defconfig-keys.spec">>,
            overrides => #{}
        },
        Opts0
    ),
    Opts1#{
        command_name => ensure_binary(maps:get(command_name, Opts1)),
        generated_at => ensure_binary(maps:get(generated_at, Opts1)),
        includes => [ensure_binary(Key) || Key <- maps:get(includes, Opts1, [])],
        output => ensure_binary(maps:get(output, Opts1)),
        overrides => normalize_override_map(maps:get(overrides, Opts1, #{}))
    }.

-spec normalize_override_map(map()) -> #{binary() => cumulative_kind()}.
normalize_override_map(Overrides) ->
    maps:from_list([
        {ensure_binary(Key), Kind}
     || {Key, Kind} <- maps:to_list(Overrides)
    ]).

-spec parse_cli([string()], map()) -> {ok, map()} | {help, binary()} | {error, binary()}.
parse_cli([], Opts) ->
    case maps:get(buildroot, Opts, undefined) of
        undefined ->
            {error, <<"generate_defconfig_keys: missing required --buildroot PATH.">>};
        _ ->
            {ok, Opts}
    end;
parse_cli(["--help" | _Rest], _Opts) ->
    {help, usage()};
parse_cli(["-h" | _Rest], _Opts) ->
    {help, usage()};
parse_cli(["--buildroot", Path | Rest], Opts) ->
    parse_cli(Rest, Opts#{buildroot => unicode:characters_to_binary(Path)});
parse_cli(["--output", Path | Rest], Opts) ->
    parse_cli(Rest, Opts#{output => unicode:characters_to_binary(Path)});
parse_cli(["--command-name", CommandName | Rest], Opts) ->
    parse_cli(
        Rest,
        Opts#{command_name => unicode:characters_to_binary(CommandName)}
    );
parse_cli(["--include", Key | Rest], Opts) ->
    parse_cli(
        Rest,
        Opts#{
            includes => maps:get(includes, Opts, []) ++
                [unicode:characters_to_binary(Key)]
        }
    );
parse_cli(["--override", Override | Rest], Opts) ->
    case parse_override(Override) of
        {ok, Key, Kind} ->
            Overrides0 = maps:get(overrides, Opts, #{}),
            parse_cli(
                Rest,
                Opts#{overrides => maps:put(Key, Kind, Overrides0)}
            );
        {error, Message} ->
            {error, Message}
    end;
parse_cli(["--buildroot"], _Opts) ->
    {error, <<"generate_defconfig_keys: --buildroot requires a value.">>};
parse_cli(["--output"], _Opts) ->
    {error, <<"generate_defconfig_keys: --output requires a value.">>};
parse_cli(["--command-name"], _Opts) ->
    {error, <<"generate_defconfig_keys: --command-name requires a value.">>};
parse_cli(["--include"], _Opts) ->
    {error, <<"generate_defconfig_keys: --include requires a value.">>};
parse_cli(["--override"], _Opts) ->
    {error, <<"generate_defconfig_keys: --override requires a value.">>};
parse_cli([Unknown | _Rest], _Opts) ->
    {error,
        unicode:characters_to_binary(
            io_lib:format(
                "generate_defconfig_keys: unknown argument '~ts'.",
                [Unknown]
            )
        )}.

-spec parse_override(string()) ->
    {ok, binary(), cumulative_kind()} | {error, binary()}.
parse_override(Text) ->
    Override = unicode:characters_to_binary(Text),
    case binary:split(Override, <<"=">>) of
        [Key, <<"path">>] when Key =/= <<>> ->
            {ok, Key, path};
        [Key, <<"plain">>] when Key =/= <<>> ->
            {ok, Key, plain};
        _ ->
            {error,
                <<"generate_defconfig_keys: --override must be KEY=path or "
                  "KEY=plain.">>}
    end.

-spec usage() -> binary().
usage() ->
    <<
        "Usage: ./scripts/generate_defconfig_keys.escript [OPTIONS]\n\n",
        "Required:\n",
        "  --buildroot PATH         Buildroot source directory to scan\n\n",
        "Optional:\n",
        "  --output PATH            Output file (default: priv/defconfig-keys.spec)\n",
        "  --include KEY            Force inclusion of KEY if its kind can be inferred\n",
        "  --override KEY=KIND      Force KEY into the output with KIND = path|plain\n",
        "  --command-name TEXT      Command text written to the generated header\n",
        "  --help, -h               Show this help text\n"
    >>.

-spec load_symbols(file:name_all()) ->
    {ok, #{binary() => symbol_meta()}} | {error, term()}.
load_symbols(BuildrootDir) ->
    case filelib:is_dir(BuildrootDir) of
        false ->
            {error, {buildroot_not_found, unicode:characters_to_binary(BuildrootDir)}};
        true ->
            ConfigFiles = lists:sort(kconfig_files(BuildrootDir)),
            load_symbols_from_files(ConfigFiles, #{})
    end.

-spec kconfig_files(file:name_all()) -> [file:name_all()].
kconfig_files(BuildrootDir) ->
    filelib:fold_files(
        BuildrootDir,
        "Config\\.in(\\..*)?$",
        true,
        fun(Path, Acc) -> [Path | Acc] end,
        []
    ).

-spec load_symbols_from_files([file:name_all()], #{binary() => symbol_meta()}) ->
    {ok, #{binary() => symbol_meta()}} | {error, term()}.
load_symbols_from_files([], Symbols) ->
    {ok, Symbols};
load_symbols_from_files([Path | Rest], Symbols0) ->
    maybe
        {ok, Blocks} ?= parse_kconfig_file(Path),
        Symbols1 = merge_symbol_blocks(Blocks, Symbols0),
        load_symbols_from_files(Rest, Symbols1)
    else
        {error, _} = Error ->
            Error
    end.

-spec parse_kconfig_file(file:name_all()) ->
    {ok, [#{key := binary(), text := binary(), type := binary() | undefined}]}
    | {error, term()}.
parse_kconfig_file(Path) ->
    case file:read_file(Path) of
        {ok, Content} ->
            Lines = binary:split(Content, <<"\n">>, [global]),
            {ok,
                finalize_blocks(
                    collect_blocks(Lines, undefined, []),
                    [],
                    unicode:characters_to_binary(Path)
                )};
        {error, Posix} ->
            {error,
                {read_kconfig_failed, unicode:characters_to_binary(Path), Posix}}
    end.

-spec collect_blocks([binary()], undefined | {binary(), [binary()]}, [tuple()]) ->
    [tuple()].
collect_blocks([], undefined, Acc) ->
    lists:reverse(Acc);
collect_blocks([], {Key, Lines}, Acc) ->
    lists:reverse([{Key, lists:reverse(Lines)} | Acc]);
collect_blocks([Line | Rest], Current, Acc) ->
    case block_start_key(Line) of
        undefined ->
            case Current of
                undefined ->
                    collect_blocks(Rest, undefined, Acc);
                {Key, Lines} ->
                    collect_blocks(Rest, {Key, [Line | Lines]}, Acc)
            end;
        Key ->
            case Current of
                undefined ->
                    collect_blocks(Rest, {Key, [Line]}, Acc);
                {CurrentKey, Lines} ->
                    collect_blocks(
                        Rest,
                        {Key, [Line]},
                        [{CurrentKey, lists:reverse(Lines)} | Acc]
                    )
            end
    end.

-spec finalize_blocks([tuple()], [map()], binary()) -> [map()].
finalize_blocks([], Acc, _Source) ->
    lists:reverse(Acc);
finalize_blocks([{Key, Lines} | Rest], Acc, Source) ->
    BlockText = binary:join(Lines, <<"\n">>),
    finalize_blocks(
        Rest,
        [
            #{
                key => Key,
                source => Source,
                text => BlockText,
                type => block_type(Lines)
            }
         | Acc],
        Source
    ).

-spec block_start_key(binary()) -> binary() | undefined.
block_start_key(Line) ->
    Trimmed = trim_binary(Line),
    case binary:split(Trimmed, <<" ">>, [global]) of
        [<<"config">>, Key] when Key =/= <<>> ->
            maybe_br2_key(Key);
        [<<"menuconfig">>, Key] when Key =/= <<>> ->
            maybe_br2_key(Key);
        _ ->
            undefined
    end.

-spec maybe_br2_key(binary()) -> binary() | undefined.
maybe_br2_key(<<"BR2_", _/binary>> = Key) ->
    Key;
maybe_br2_key(_Key) ->
    undefined.

-spec block_type(nonempty_list(binary())) -> binary() | undefined.
block_type([_Header | Rest]) ->
    block_type_lines(Rest).

-spec block_type_lines(list(binary())) -> binary() | undefined.
block_type_lines([]) ->
    undefined;
block_type_lines([Line | Rest]) ->
    case trimmed_prefix(Line, [<<"string">>, <<"bool">>, <<"hex">>, <<"int">>]) of
        undefined ->
            block_type_lines(Rest);
        Type ->
            Type
    end.

-spec trimmed_prefix(binary(), [binary()]) -> binary() | undefined.
trimmed_prefix(Line, Prefixes) ->
    Trimmed = trim_binary(Line),
    trimmed_prefix(Trimmed, Prefixes, undefined).

-spec trimmed_prefix(binary(), [binary()], term()) -> binary() | undefined.
trimmed_prefix(_Trimmed, [], _Sentinel) ->
    undefined;
trimmed_prefix(Trimmed, [Prefix | Rest], Sentinel) ->
    PrefixSize = byte_size(Prefix),
    case Trimmed of
        <<Prefix:PrefixSize/binary, _/binary>> ->
            Prefix;
        _ ->
            trimmed_prefix(Trimmed, Rest, Sentinel)
    end.

-spec merge_symbol_blocks(list(map()), map()) -> map().
merge_symbol_blocks(Blocks, Symbols0) ->
    lists:foldl(
        fun(Block, SymbolsAcc) ->
            Key = maps:get(key, Block),
            Type = maps:get(type, Block),
            Text = maps:get(text, Block),
            Source = maps:get(source, Block, <<>>),
            case maps:get(Key, SymbolsAcc, undefined) of
                undefined ->
                    maps:put(
                        Key,
                        #{
                            block_texts => [Text],
                            key => Key,
                            sources => [Source],
                            type => Type
                        },
                        SymbolsAcc
                    );
                Existing ->
                    ExistingType = maps:get(type, Existing),
                    MergedType =
                        case ExistingType of
                            undefined ->
                                Type;
                            _ ->
                                ExistingType
                        end,
                    maps:put(
                        Key,
                        Existing#{
                            block_texts => maps:get(block_texts, Existing) ++ [Text],
                            sources => maps:get(sources, Existing) ++ [Source],
                            type => MergedType
                        },
                        SymbolsAcc
                    )
            end
        end,
        Symbols0,
        Blocks
    ).

-spec validate_requested_keys(map(), generator_options()) ->
    ok | {error, term()}.
validate_requested_keys(Symbols, Opts) ->
    Requested = maps:get(includes, Opts, []) ++ maps:keys(maps:get(overrides, Opts, #{})),
    validate_requested_key_list(Requested, Symbols).

-spec validate_requested_key_list(list(binary()), map()) ->
    ok | {error, term()}.
validate_requested_key_list([], _Symbols) ->
    ok;
validate_requested_key_list([Key | Rest], Symbols) ->
    case maps:find(Key, Symbols) of
        {ok, _Meta} ->
            validate_requested_key_list(Rest, Symbols);
        error ->
            {error, {unknown_requested_key, Key}}
    end.

-spec buildroot_version(file:name_all()) -> {ok, binary()} | {error, term()}.
buildroot_version(BuildrootDir) ->
    Makefile = filename:join(BuildrootDir, "Makefile"),
    case file:read_file(Makefile) of
        {ok, Content} ->
            Lines = binary:split(Content, <<"\n">>, [global]),
            buildroot_version_from_lines(Lines);
        {error, Posix} ->
            {error,
                {read_buildroot_makefile_failed,
                    unicode:characters_to_binary(Makefile),
                    Posix}}
    end.

-spec buildroot_version_from_lines([binary()]) -> {ok, binary()} | {error, term()}.
buildroot_version_from_lines([]) ->
    {error, missing_buildroot_version};
buildroot_version_from_lines([Line | Rest]) ->
    case trim_binary(Line) of
        <<"export BR2_VERSION := ", Version/binary>> when Version =/= <<>> ->
            {ok, trim_binary(Version)};
        <<"BR2_VERSION := ", Version/binary>> when Version =/= <<>> ->
            {ok, trim_binary(Version)};
        _ ->
            buildroot_version_from_lines(Rest)
    end.

-spec buildroot_revision(file:name_all()) -> map().
buildroot_revision(BuildrootDir) ->
    case run_command("git", ["rev-parse", "--verify", "HEAD"], BuildrootDir) of
        {ok, Commit} ->
            Describe =
                case run_command(
                    "git",
                    ["describe", "--tags", "--always", "--dirty"],
                    BuildrootDir
                ) of
                    {ok, Value} ->
                        Value;
                    {error, _} ->
                        <<"unknown">>
                end,
            #{commit => Commit, describe => Describe};
        {error, _} ->
            #{commit => <<"unknown">>, describe => <<"unknown">>}
    end.

-spec classify_symbols(map(), generator_options()) ->
    {ok, list({binary(), cumulative_kind()})} | {error, term()}.
classify_symbols(Symbols, Opts) ->
    Keys = lists:sort(maps:keys(Symbols)),
    classify_symbols(Keys, Symbols, Opts, []).

-spec classify_symbols(
    [binary()],
    map(),
    generator_options(),
    list({binary(), cumulative_kind()})
) ->
    {ok, list({binary(), cumulative_kind()})} | {error, term()}.
classify_symbols([], _Symbols, _Opts, Acc) ->
    {ok, lists:reverse(Acc)};
classify_symbols([Key | Rest], Symbols, Opts, Acc0) ->
    case maps:find(Key, Symbols) of
        {ok, Meta} ->
            case classify_symbol(Meta, Opts) of
                skip ->
                    classify_symbols(Rest, Symbols, Opts, Acc0);
                {include, Kind} ->
                    classify_symbols(Rest, Symbols, Opts, [{Key, Kind} | Acc0]);
                {error, _} = Error ->
                    Error
            end;
        error ->
            {error, {missing_symbol_metadata, Key}}
    end.

-spec classify_symbol(symbol_meta(), generator_options()) ->
    skip | {include, cumulative_kind()} | {error, term()}.
classify_symbol(Meta, Opts) ->
    Key = maps:get(key, Meta),
    Overrides = maps:get(overrides, Opts, #{}),
    Includes = maps:get(includes, Opts, []),
    Forced = lists:member(Key, Includes),
    case maps:get(type, Meta, undefined) of
        <<"string">> ->
            maybe_classify_string_symbol(
                Meta,
                Forced,
                maps:get(Key, Overrides, undefined)
            );
        _OtherType ->
            case maps:get(Key, Overrides, undefined) of
                undefined ->
                    skip;
                Kind ->
                    {include, Kind}
            end
    end.

-spec maybe_classify_string_symbol(
    symbol_meta(),
    boolean(),
    cumulative_kind() | undefined
) ->
    skip | {include, cumulative_kind()} | {error, term()}.
maybe_classify_string_symbol(Meta, Forced, OverrideKind) ->
    case OverrideKind of
        Kind when Kind =:= path; Kind =:= plain ->
            {include, Kind};
        undefined ->
            case cumulative_evidence(Meta) of
                [] when not Forced ->
                    skip;
                _ ->
                    case infer_kind(Meta) of
                        {ok, Kind} ->
                            {include, Kind};
                        {error, Reason} when Forced ->
                            {error,
                                {forced_include_requires_override,
                                    maps:get(key, Meta),
                                    Reason}};
                        {error, _Reason} ->
                            skip
                    end
            end
    end.

-spec cumulative_evidence(symbol_meta()) -> [atom()].
cumulative_evidence(Meta) ->
    Text = lower_text(Meta),
    Key = maps:get(key, Meta),
    Evidence0 =
        case list_help_pattern(Text) of
            true ->
                [help_list];
            false ->
                []
        end,
    case list_name_pattern(Key) of
        true ->
            [name_list | Evidence0];
        false ->
            Evidence0
    end.

-spec infer_kind(symbol_meta()) -> {ok, cumulative_kind()} | {error, term()}.
infer_kind(Meta) ->
    Text = lower_text(Meta),
    Key = maps:get(key, Meta),
    PathEvidence = path_evidence(Key, Text),
    PlainEvidence = plain_evidence(Key, Text),
    case {PathEvidence =/= [], PlainEvidence =/= []} of
        {true, false} ->
            {ok, path};
        {false, true} ->
            {ok, plain};
        {false, false} ->
            {error, unknown_kind};
        {true, true} ->
            {error, ambiguous_kind}
    end.

-spec list_help_pattern(binary()) -> boolean().
list_help_pattern(Text) ->
    matches_any(
        Text,
        [
            <<"space-separated list">>,
            <<"space separated list">>,
            <<"whitespace separated list">>,
            <<"specify a list of">>,
            <<"one or more directories">>,
            <<"one or more files">>,
            <<"one or more binaries">>
        ]
    ).

-spec list_name_pattern(binary()) -> boolean().
list_name_pattern(Key) ->
    ends_with_any(
        Key,
        [
            <<"_CONFIG_FRAGMENT_FILES">>,
            <<"_PATCHES">>,
            <<"_PATCH_DIRS">>,
            <<"_OVERLAYS">>,
            <<"_SCRIPTS">>,
            <<"_TABLES">>,
            <<"_WHITELIST">>,
            <<"_MODULES">>,
            <<"_ENV_VARS">>,
            <<"_ZONELIST">>,
            <<"_ENCODERS">>,
            <<"_DECODERS">>,
            <<"_MUXERS">>,
            <<"_DEMUXERS">>,
            <<"_PARSERS">>,
            <<"_BSFS">>,
            <<"_PROTOCOLS">>,
            <<"_FILTERS">>,
            <<"_FONTS">>,
            <<"_ADD_MODULES">>,
            <<"_C32">>,
            <<"_CONF_FILES">>
        ]
    ).

-spec path_evidence(binary(), binary()) -> [atom()].
path_evidence(Key, Text) ->
    Evidence0 =
        case ends_with_any(
            Key,
            [
                <<"_CONFIG_FRAGMENT_FILES">>,
                <<"_PATCH">>,
                <<"_PATCHES">>,
                <<"_PATCH_DIR">>,
                <<"_PATCH_DIRS">>,
                <<"_OVERLAY">>,
                <<"_OVERLAYS">>,
                <<"_SCRIPT">>,
                <<"_SCRIPTS">>,
                <<"_TABLE">>,
                <<"_TABLES">>,
                <<"_PATH">>,
                <<"_PATHS">>,
                <<"_DIR">>,
                <<"_DIRS">>,
                <<"_CONF_FILES">>,
                <<"_CUSTOM_DTS_PATH">>,
                <<"_CUSTOM_DTS_DIR">>
            ]
        ) of
            true ->
                [name_path];
            false ->
                []
        end,
    case matches_any(
        Text,
        [
            <<" directories">>,
            <<" directory">>,
            <<" path">>,
            <<" paths">>,
            <<" location">>,
            <<" locations">>,
            <<" script">>,
            <<" scripts">>,
            <<" overlay">>,
            <<" overlays">>,
            <<" patch">>,
            <<" patches">>,
            <<" table">>,
            <<" tables">>,
            <<" fragment">>,
            <<" fragments">>,
            <<" dts">>
        ]
    ) of
        true ->
            [help_path | Evidence0];
        false ->
            Evidence0
    end.

-spec plain_evidence(binary(), binary()) -> [atom()].
plain_evidence(Key, Text) ->
    Evidence0 =
        case ends_with_any(
            Key,
            [
                <<"_WHITELIST">>,
                <<"_MODULES">>,
                <<"_ENV_VARS">>,
                <<"_ZONELIST">>,
                <<"_ENCODERS">>,
                <<"_DECODERS">>,
                <<"_MUXERS">>,
                <<"_DEMUXERS">>,
                <<"_PARSERS">>,
                <<"_BSFS">>,
                <<"_PROTOCOLS">>,
                <<"_FILTERS">>,
                <<"_FONTS">>,
                <<"_ADD_MODULES">>,
                <<"_C32">>
            ]
        ) of
            true ->
                [name_plain];
            false ->
                []
        end,
    case matches_any(
        Text,
        [
            <<" locale">>,
            <<" locales">>,
            <<" module">>,
            <<" modules">>,
            <<" environment variable">>,
            <<" environment variables">>,
            <<" encoder">>,
            <<" encoders">>,
            <<" decoder">>,
            <<" decoders">>,
            <<" muxer">>,
            <<" muxers">>,
            <<" demuxer">>,
            <<" demuxers">>,
            <<" parser">>,
            <<" parsers">>,
            <<" protocol">>,
            <<" protocols">>,
            <<" filter">>,
            <<" filters">>,
            <<" font">>,
            <<" fonts">>,
            <<" time zone">>,
            <<" timezone">>,
            <<" file names">>,
            <<" binary">>,
            <<" binaries">>,
            <<" variables">>
        ]
    ) of
        true ->
            [help_plain | Evidence0];
        false ->
            Evidence0
    end.

-spec render_spec(
    file:name_all(),
    binary(),
    map(),
    [{binary(), cumulative_kind()}],
    generator_options()
) -> binary().
render_spec(BuildrootDir, Version, RevisionInfo, Entries, Opts) ->
    BuildrootLabel = sanitize_path_for_header(BuildrootDir),
    OutputLabel = sanitize_path_for_header(maps:get(output, Opts)),
    CommandLine = regenerate_command(BuildrootLabel, OutputLabel, Opts),
    Header = [
        <<"%% Generated by smelterl Buildroot defconfig key spec generator.\n">>,
        <<"%% Buildroot version: ">>, Version, <<"\n">>,
        <<"%% Buildroot describe: ">>, maps:get(describe, RevisionInfo), <<"\n">>,
        <<"%% Buildroot commit: ">>, maps:get(commit, RevisionInfo), <<"\n">>,
        <<"%% Generated at: ">>, maps:get(generated_at, Opts), <<"\n">>,
        <<"%% Explicit includes: ">>,
        format_header_keys(maps:get(includes, Opts, [])),
        <<"\n">>,
        <<"%% Explicit overrides: ">>,
        format_override_header(maps:get(overrides, Opts, #{})),
        <<"\n">>,
        <<"%% Regenerate with:\n">>,
        <<"%%   ">>, CommandLine, <<"\n">>
    ],
    EntriesIo = [
        <<"[\n">>,
        format_entries(Entries),
        <<"].\n">>
    ],
    iolist_to_binary([Header, <<"\n">>, EntriesIo]).

-spec regenerate_command(binary(), binary(), generator_options()) -> binary().
regenerate_command(BuildrootLabel, OutputLabel, Opts) ->
    Parts0 = [
        maps:get(command_name, Opts),
        <<"--buildroot">>,
        BuildrootLabel,
        <<"--output">>,
        OutputLabel
    ],
    IncludeParts = lists:append([
        [<<"--include">>, Key]
     || Key <- lists:sort(maps:get(includes, Opts, []))
    ]),
    OverrideParts = lists:append([
        [<<"--override">>, <<Key/binary, "=", (atom_to_binary(Kind, utf8))/binary>>]
     || {Key, Kind} <- lists:sort(maps:to_list(maps:get(overrides, Opts, #{})))
    ]),
    binary:join(Parts0 ++ IncludeParts ++ OverrideParts, <<" ">>).

-spec format_header_keys([binary()]) -> binary().
format_header_keys([]) ->
    <<"none">>;
format_header_keys(Keys) ->
    binary:join(lists:sort(Keys), <<", ">>).

-spec format_override_header(#{binary() => cumulative_kind()}) -> binary().
format_override_header(Overrides) when map_size(Overrides) =:= 0 ->
    <<"none">>;
format_override_header(Overrides) ->
    binary:join(
        [
            <<Key/binary, "=", (atom_to_binary(Kind, utf8))/binary>>
         || {Key, Kind} <- lists:sort(maps:to_list(Overrides))
        ],
        <<", ">>
    ).

-spec format_entries(list({binary(), cumulative_kind()})) -> iolist().
format_entries([]) ->
    [];
format_entries(Entries) ->
    Lines = [
        [<<"    {<<\"">>, Key, <<"\">>, ">>, atom_to_binary(Kind, utf8), <<"}">>]
     || {Key, Kind} <- Entries
    ],
    [lists:join(<<",\n">>, Lines), <<"\n">>].

-spec sanitize_path_for_header(file:name_all() | binary()) -> binary().
sanitize_path_for_header(Path) ->
    PathString = path_to_list(Path),
    case filename:pathtype(PathString) of
        absolute ->
            unicode:characters_to_binary(filename:basename(PathString));
        _ ->
            unicode:characters_to_binary(PathString)
    end.

-spec generated_at() -> binary().
generated_at() ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
    unicode:characters_to_binary(
        io_lib:format(
            "~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
            [Year, Month, Day, Hour, Minute, Second]
        )
    ).

-spec lower_text(symbol_meta()) -> binary().
lower_text(Meta) ->
    string:lowercase(
        iolist_to_binary(
            binary:join(maps:get(block_texts, Meta), <<"\n\n">>)
        )
    ).

-spec matches_any(binary(), [binary()]) -> boolean().
matches_any(_Text, []) ->
    false;
matches_any(Text, [Pattern | Rest]) ->
    case binary:match(Text, Pattern) of
        nomatch ->
            matches_any(Text, Rest);
        _ ->
            true
    end.

-spec ends_with_any(binary(), [binary()]) -> boolean().
ends_with_any(_Text, []) ->
    false;
ends_with_any(Text, [Suffix | Rest]) ->
    case binary:longest_common_suffix([Text, Suffix]) of
        Size when Size =:= byte_size(Suffix) ->
            true;
        _ ->
            ends_with_any(Text, Rest)
    end.

-spec run_command(string(), [string()], file:name_all()) ->
    {ok, binary()} | {error, term()}.
run_command(Command, Args, Cwd) ->
    case os:find_executable(Command) of
        false ->
            {error, missing_command};
        Executable ->
            Port = open_port(
                {spawn_executable, Executable},
                [
                    binary,
                    eof,
                    exit_status,
                    stderr_to_stdout,
                    use_stdio,
                    {args, Args},
                    {cd, Cwd}
                ]
            ),
            collect_command_output(Port, [])
    end.

-spec collect_command_output(port(), [binary()]) ->
    {ok, binary()} | {error, term()}.
collect_command_output(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect_command_output(Port, [Data | Acc]);
        {Port, eof} ->
            receive
                {Port, {exit_status, 0}} ->
                    port_close(Port),
                    {ok, trim_binary(iolist_to_binary(lists:reverse(Acc)))};
                {Port, {exit_status, Status}} ->
                    port_close(Port),
                    {error,
                        {command_failed,
                            Status,
                            trim_binary(iolist_to_binary(lists:reverse(Acc)))}}
            end
    end.

-spec format_error(term()) -> binary().
format_error({buildroot_not_found, Path}) ->
    <<"generate_defconfig_keys: buildroot directory not found: ", Path/binary>>;
format_error({unknown_requested_key, Key}) ->
    <<"generate_defconfig_keys: requested key not found in Buildroot sources: ",
      Key/binary>>;
format_error({forced_include_requires_override, Key, unknown_kind}) ->
    <<"generate_defconfig_keys: forced include for ", Key/binary,
      " needs an explicit --override because the key kind is unknown.">>;
format_error({forced_include_requires_override, Key, ambiguous_kind}) ->
    <<"generate_defconfig_keys: forced include for ", Key/binary,
      " needs an explicit --override because the key kind is ambiguous.">>;
format_error({read_kconfig_failed, Path, Posix}) ->
    unicode:characters_to_binary(
        io_lib:format(
            "generate_defconfig_keys: failed to read '~ts': ~ts",
            [Path, file:format_error(Posix)]
        )
    );
format_error({read_buildroot_makefile_failed, Path, Posix}) ->
    unicode:characters_to_binary(
        io_lib:format(
            "generate_defconfig_keys: failed to read '~ts': ~ts",
            [Path, file:format_error(Posix)]
        )
    );
format_error(missing_buildroot_version) ->
    <<"generate_defconfig_keys: could not determine BR2_VERSION from "
      "Buildroot Makefile.">>;
format_error({command_failed, Status, Output}) ->
    unicode:characters_to_binary(
        io_lib:format(
            "generate_defconfig_keys: helper command failed with status ~B: ~ts",
            [Status, Output]
        )
    );
format_error(missing_command) ->
    <<"generate_defconfig_keys: required external command is missing.">>;
format_error(Reason) ->
    unicode:characters_to_binary(
        io_lib:format("generate_defconfig_keys: ~tp", [Reason])
    ).

-spec print_error(binary()) -> ok.
print_error(Message) ->
    io:format(standard_error, "~ts~n", [Message]).

-spec ensure_binary(binary() | string()) -> binary().
ensure_binary(Value) when is_binary(Value) ->
    Value;
ensure_binary(Value) ->
    unicode:characters_to_binary(Value).

-spec path_to_list(file:name_all()) -> string().
path_to_list(Path) when is_binary(Path) ->
    unicode:characters_to_list(Path);
path_to_list(Path) ->
    Path.

-spec trim_binary(binary()) -> binary().
trim_binary(Binary) ->
    trim_trailing_binary(trim_leading_binary(Binary)).

-spec trim_leading_binary(binary()) -> binary().
trim_leading_binary(<<Char, Rest/binary>>)
  when Char =:= $\s; Char =:= $\t; Char =:= $\r; Char =:= $\n ->
    trim_leading_binary(Rest);
trim_leading_binary(Binary) ->
    Binary.

-spec trim_trailing_binary(binary()) -> binary().
trim_trailing_binary(Binary) ->
    trim_trailing_binary(Binary, byte_size(Binary)).

-spec trim_trailing_binary(binary(), non_neg_integer()) -> binary().
trim_trailing_binary(_Binary, 0) ->
    <<>>;
trim_trailing_binary(Binary, Size) ->
    case binary:at(Binary, Size - 1) of
        Char when Char =:= $\s; Char =:= $\t; Char =:= $\r; Char =:= $\n ->
            trim_trailing_binary(Binary, Size - 1);
        _ ->
            binary:part(Binary, 0, Size)
    end.
