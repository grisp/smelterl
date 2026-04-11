%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_legal).
-moduledoc """
Parse Buildroot `legal-info/` CSV manifests into one reusable data structure.

This task only implements single-tree parsing. Merging and export of multiple
legal trees remain separate follow-up work.
""".

-include_lib("kernel/include/file.hrl").


%=== EXPORTS ===================================================================

-export([parse_legal/1]).


%=== API FUNCTIONS =============================================================

-doc """
Parse one Buildroot `legal-info/` directory.
""".
-spec parse_legal(smelterl:file_path()) ->
    {ok, smelterl:br_legal_info()} | {error, term()}.
parse_legal(Path) ->
    LegalPath = absolute_binary_path(Path),
    maybe
        ok ?= ensure_legal_dir(LegalPath),
        {ok, Packages} ?= parse_manifest(LegalPath, <<"manifest.csv">>, target),
        {ok, HostPackages0} ?= parse_manifest(
            LegalPath,
            <<"host-manifest.csv">>,
            host
        ),
        {BuildrootVersion, HostPackages} = extract_buildroot_version(HostPackages0),
        {ok,
            #{
                path => LegalPath,
                br_version => BuildrootVersion,
                packages => Packages,
                host_packages => HostPackages
            }}
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

-spec ensure_legal_dir(smelterl:file_path()) -> ok | {error, term()}.
ensure_legal_dir(LegalPath) ->
    case file:read_file_info(binary_to_list(LegalPath)) of
        {ok, #file_info{type = directory, access = Access}}
                when Access =:= read; Access =:= read_write ->
            ok;
        {ok, #file_info{type = directory}} ->
            ok;
        {ok, _Info} ->
            {error, {invalid_path, LegalPath, not_directory}};
        {error, Posix} ->
            {error, {invalid_path, LegalPath, Posix}}
    end.

-spec parse_manifest(smelterl:file_path(), binary(), target | host) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_manifest(LegalPath, FileName, ManifestKind) ->
    ManifestPath = filename:join(binary_to_list(LegalPath), binary_to_list(FileName)),
    case file:read_file(ManifestPath) of
        {ok, Content} ->
            parse_manifest_content(
                LegalPath,
                unicode:characters_to_binary(filename:absname(ManifestPath)),
                ManifestKind,
                Content
            );
        {error, Posix} ->
            {error,
                {missing_manifest, LegalPath, {open_failed, FileName, Posix}}}
    end.

-spec parse_manifest_content(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    binary()
) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_manifest_content(LegalPath, ManifestPath, ManifestKind, Content) ->
    Lines = nonempty_lines(Content),
    maybe
        {ok, HeaderLine, DataLines} ?= split_header_and_rows(ManifestPath, Lines),
        {ok, HeaderIndex} ?= parse_header(ManifestPath, HeaderLine),
        parse_rows(
            LegalPath,
            ManifestPath,
            ManifestKind,
            HeaderIndex,
            DataLines,
            2,
            []
        )
    else
        {error, _} = Error ->
            Error
    end.

-spec split_header_and_rows(smelterl:file_path(), [binary()]) ->
    {ok, binary(), [binary()]} | {error, term()}.
split_header_and_rows(_ManifestPath, [Header | Rows]) ->
    {ok, Header, Rows};
split_header_and_rows(ManifestPath, []) ->
    {error, {missing_manifest, parent_legal_path(ManifestPath), {malformed_csv, ManifestPath, empty_file}}}.

-spec parse_header(smelterl:file_path(), binary()) ->
    {ok, #{binary() => pos_integer()}} | {error, term()}.
parse_header(ManifestPath, HeaderLine) ->
    RequiredColumns = [<<"package">>, <<"version">>, <<"license">>, <<"license files">>],
    case parse_csv_line(HeaderLine) of
        {ok, HeaderFields} ->
            HeaderIndex = #{
                normalize_header(Field) => Index
             || {Field, Index} <- lists:zip(
                    HeaderFields,
                    lists:seq(1, length(HeaderFields))
                )
            },
            maybe
                ok ?= ensure_required_columns(
                    parent_legal_path(ManifestPath),
                    ManifestPath,
                    HeaderIndex,
                    RequiredColumns
                ),
                {ok, HeaderIndex}
            else
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error,
                {missing_manifest,
                    parent_legal_path(ManifestPath),
                    {malformed_csv, ManifestPath, {1, Reason}}}}
    end.

-spec ensure_required_columns(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()]
) -> ok | {error, term()}.
ensure_required_columns(_LegalPath, _ManifestPath, _HeaderIndex, []) ->
    ok;
ensure_required_columns(LegalPath, ManifestPath, HeaderIndex, [Column | Rest]) ->
    case maps:is_key(Column, HeaderIndex) of
        true ->
            ensure_required_columns(LegalPath, ManifestPath, HeaderIndex, Rest);
        false ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_column, Column}}}}
    end.

-spec parse_rows(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    #{binary() => pos_integer()},
    [binary()],
    pos_integer(),
    [smelterl:br_package_entry()]
) ->
    {ok, [smelterl:br_package_entry()]} | {error, term()}.
parse_rows(
    _LegalPath,
    _ManifestPath,
    _ManifestKind,
    _HeaderIndex,
    [],
    _LineNumber,
    Acc
) ->
    {ok, lists:reverse(Acc)};
parse_rows(
    LegalPath,
    ManifestPath,
    ManifestKind,
    HeaderIndex,
    [Line | Rest],
    LineNumber,
    Acc
) ->
    case parse_csv_line(Line) of
        {ok, Fields} ->
            maybe
                {ok, Entry} ?=
                    build_package_entry(
                        LegalPath,
                        ManifestPath,
                        ManifestKind,
                        HeaderIndex,
                        Fields,
                        LineNumber
                    ),
                parse_rows(
                    LegalPath,
                    ManifestPath,
                    ManifestKind,
                    HeaderIndex,
                    Rest,
                    LineNumber + 1,
                    [Entry | Acc]
                )
            else
                {error, _} = Error ->
                    Error
            end;
        {error, Reason} ->
            {error,
                {missing_manifest,
                    LegalPath,
                    {malformed_csv, ManifestPath, {LineNumber, Reason}}}}
    end.

-spec build_package_entry(
    smelterl:file_path(),
    smelterl:file_path(),
    target | host,
    #{binary() => pos_integer()},
    [binary()],
    pos_integer()
) ->
    {ok, smelterl:br_package_entry()} | {error, term()}.
build_package_entry(
    LegalPath,
    ManifestPath,
    ManifestKind,
    HeaderIndex,
    Fields,
    LineNumber
) ->
    maybe
        {ok, Name} ?= required_csv_field(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"package">>,
            LineNumber
        ),
        {ok, Version} ?= required_csv_field_allow_empty(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"version">>,
            LineNumber
        ),
        {ok, License} ?= required_csv_field(
            LegalPath,
            ManifestPath,
            HeaderIndex,
            Fields,
            <<"license">>,
            LineNumber
        ),
        LicenseRoot = license_root(LegalPath, ManifestKind, Name, Version),
        LicenseFiles = parse_license_files(
            optional_csv_field(HeaderIndex, Fields, <<"license files">>),
            LicenseRoot
        ),
        {ok,
            #{
                name => Name,
                version => Version,
                license => License,
                license_files => LicenseFiles
            }}
    else
        {error, _} = Error ->
            Error
    end.

-spec required_csv_field(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()],
    binary(),
    pos_integer()
) -> {ok, binary()} | {error, term()}.
required_csv_field(LegalPath, ManifestPath, HeaderIndex, Fields, Column, LineNumber) ->
    case optional_csv_field(HeaderIndex, Fields, Column) of
        undefined ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_field, Column, LineNumber}}}};
        <<>> ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {empty_field, Column, LineNumber}}}};
        Value ->
            {ok, Value}
    end.

-spec required_csv_field_allow_empty(
    smelterl:file_path(),
    smelterl:file_path(),
    #{binary() => pos_integer()},
    [binary()],
    binary(),
    pos_integer()
) -> {ok, binary()} | {error, term()}.
required_csv_field_allow_empty(LegalPath, ManifestPath, HeaderIndex, Fields, Column, LineNumber) ->
    case optional_csv_field(HeaderIndex, Fields, Column) of
        undefined ->
            {error,
                {missing_manifest, LegalPath, {malformed_csv, ManifestPath, {missing_field, Column, LineNumber}}}};
        Value ->
            {ok, Value}
    end.

-spec optional_csv_field(#{binary() => pos_integer()}, [binary()], binary()) ->
    binary() | undefined.
optional_csv_field(HeaderIndex, Fields, Column) ->
    Index = maps:get(Column, HeaderIndex),
    case length(Fields) >= Index of
        true ->
            trim_binary(lists:nth(Index, Fields));
        false ->
            undefined
    end.

-spec extract_buildroot_version([smelterl:br_package_entry()]) ->
    {binary(), [smelterl:br_package_entry()]}.
extract_buildroot_version(HostPackages) ->
    extract_buildroot_version(HostPackages, <<>>, []).

extract_buildroot_version([], Version, Acc) ->
    {Version, lists:reverse(Acc)};
extract_buildroot_version([#{name := <<"buildroot">>, version := Version} | Rest], _Prev, Acc) ->
    extract_buildroot_version(Rest, Version, Acc);
extract_buildroot_version([Entry | Rest], Version, Acc) ->
    extract_buildroot_version(Rest, Version, [Entry | Acc]).

-spec parse_license_files(binary() | undefined, smelterl:file_path()) ->
    [smelterl:file_path()].
parse_license_files(undefined, _LicenseRoot) ->
    [];
parse_license_files(Value, LicenseRoot) ->
    Trimmed = trim_binary(Value),
    case Trimmed of
        <<>> ->
            [];
        <<"not saved">> ->
            [];
        <<"unknown">> ->
            [];
        _ ->
            [
                join_relative_path(LicenseRoot, Part)
             || Part <- binary:split(Trimmed, <<" ">>, [global]),
                Part =/= <<>>
            ]
    end.

-spec license_root(
    smelterl:file_path(),
    target | host,
    binary(),
    binary()
) -> smelterl:file_path().
license_root(LegalPath, ManifestKind, Name, Version) ->
    LicenseBase =
        case ManifestKind of
            target -> <<"licenses">>;
            host -> <<"host-licenses">>
        end,
    Candidates = license_root_candidates(LegalPath, LicenseBase, Name, Version),
    choose_existing_license_root(Candidates, fallback_license_root(LicenseBase, Name, Version)).

-spec license_root_candidates(
    smelterl:file_path(),
    smelterl:file_path(),
    binary(),
    binary()
) -> [{smelterl:file_path(), smelterl:file_path()}].
license_root_candidates(LegalPath, LicenseBase, Name, Version) ->
    RelativeCandidates =
        case {Name, Version} of
            {<<"buildroot">>, _} ->
                [join_relative_path(LicenseBase, Name)];
            {_, <<>>} ->
                [join_relative_path(LicenseBase, Name)];
            _ ->
                [
                    join_relative_path(
                        LicenseBase,
                        <<Name/binary, "-", Version/binary>>
                    ),
                    join_relative_path(LicenseBase, Name)
                ]
        end,
    [
        {RelativePath, join_os_path(LegalPath, RelativePath)}
     || RelativePath <- RelativeCandidates
    ].

-spec choose_existing_license_root(
    [{smelterl:file_path(), smelterl:file_path()}],
    smelterl:file_path()
) -> smelterl:file_path().
choose_existing_license_root([], Fallback) ->
    Fallback;
choose_existing_license_root([{RelativePath, FullPath} | Rest], Fallback) ->
    case filelib:is_dir(binary_to_list(FullPath)) of
        true ->
            RelativePath;
        false ->
            choose_existing_license_root(Rest, Fallback)
    end.

-spec fallback_license_root(smelterl:file_path(), binary(), binary()) ->
    smelterl:file_path().
fallback_license_root(LicenseBase, <<"buildroot">>, _Version) ->
    join_relative_path(LicenseBase, <<"buildroot">>);
fallback_license_root(LicenseBase, Name, <<>>) ->
    join_relative_path(LicenseBase, Name);
fallback_license_root(LicenseBase, Name, Version) ->
    join_relative_path(LicenseBase, <<Name/binary, "-", Version/binary>>).

-spec nonempty_lines(binary()) -> [binary()].
nonempty_lines(Content) ->
    [
        strip_cr(Line)
     || Line <- binary:split(Content, <<"\n">>, [global]),
        trim_binary(strip_cr(Line)) =/= <<>>
    ].

-spec parse_csv_line(binary()) -> {ok, [binary()]} | {error, term()}.
parse_csv_line(Line) ->
    parse_csv_chars(binary_to_list(Line), [], [], field_start).

parse_csv_chars([], FieldAcc, FieldsAcc, field_start) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], FieldAcc, FieldsAcc, unquoted) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], FieldAcc, FieldsAcc, quoted_end) ->
    {ok, lists:reverse([field_binary(FieldAcc) | FieldsAcc])};
parse_csv_chars([], _FieldAcc, _FieldsAcc, quoted) ->
    {error, unterminated_quote};
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, unquoted) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$, | Rest], FieldAcc, FieldsAcc, quoted_end) ->
    parse_csv_chars(Rest, [], [field_binary(FieldAcc) | FieldsAcc], field_start);
parse_csv_chars([$" | Rest], [], FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [], FieldsAcc, quoted);
parse_csv_chars([$" | Rest], FieldAcc, FieldsAcc, quoted) ->
    case Rest of
        [$" | More] ->
            parse_csv_chars(More, [$" | FieldAcc], FieldsAcc, quoted);
        _ ->
            case quote_closes_field(Rest) of
                true ->
                    parse_csv_chars(Rest, FieldAcc, FieldsAcc, quoted_end);
                false ->
                    parse_csv_chars(Rest, [$" | FieldAcc], FieldsAcc, quoted)
            end
    end;
parse_csv_chars([$" | _Rest], _FieldAcc, _FieldsAcc, unquoted) ->
    {error, unexpected_quote};
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, field_start) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, unquoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, unquoted) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, unquoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, quoted) ->
    parse_csv_chars(Rest, [Char | FieldAcc], FieldsAcc, quoted);
parse_csv_chars([Char | Rest], FieldAcc, FieldsAcc, quoted_end)
        when Char =:= $\s; Char =:= $\t ->
    parse_csv_chars(Rest, FieldAcc, FieldsAcc, quoted_end);
parse_csv_chars(_Chars, _FieldAcc, _FieldsAcc, quoted_end) ->
    {error, trailing_characters_after_quote}.

-spec field_binary([char()]) -> binary().
field_binary(FieldAcc) ->
    trim_binary(unicode:characters_to_binary(lists:reverse(FieldAcc))).

-spec normalize_header(binary()) -> binary().
normalize_header(Value) ->
    unicode:characters_to_binary(
        string:lowercase(binary_to_list(trim_binary(Value)))
    ).

-spec trim_binary(binary()) -> binary().
trim_binary(Value) ->
    trim_trailing_whitespace(trim_leading_whitespace(Value)).

trim_leading_whitespace(<<Char, Rest/binary>>) when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
    trim_leading_whitespace(Rest);
trim_leading_whitespace(Value) ->
    Value.

trim_trailing_whitespace(Value) ->
    trim_trailing_whitespace(Value, byte_size(Value)).

trim_trailing_whitespace(_Value, 0) ->
    <<>>;
trim_trailing_whitespace(Value, Size) ->
    case binary:at(Value, Size - 1) of
        Char when Char =:= $\s; Char =:= $\t; Char =:= $\r ->
            trim_trailing_whitespace(binary:part(Value, 0, Size - 1), Size - 1);
        _ ->
            Value
    end.

-spec strip_cr(binary()) -> binary().
strip_cr(Value) ->
    trim_trailing_whitespace(Value).

-spec parent_legal_path(smelterl:file_path()) -> smelterl:file_path().
parent_legal_path(ManifestPath) ->
    unicode:characters_to_binary(filename:dirname(binary_to_list(ManifestPath))).

-spec absolute_binary_path(smelterl:file_path()) -> smelterl:file_path().
absolute_binary_path(Path) ->
    unicode:characters_to_binary(filename:absname(binary_to_list(Path))).

-spec join_relative_path(smelterl:file_path(), smelterl:file_path()) ->
    smelterl:file_path().
join_relative_path(Left, Right) ->
    unicode:characters_to_binary(
        filename:join(binary_to_list(Left), binary_to_list(Right))
    ).

-spec join_os_path(smelterl:file_path(), smelterl:file_path()) -> smelterl:file_path().
join_os_path(Left, Right) ->
    unicode:characters_to_binary(
        filename:join(binary_to_list(Left), binary_to_list(Right))
    ).

-spec quote_closes_field([char()]) -> boolean().
quote_closes_field([]) ->
    true;
quote_closes_field([$, | _Rest]) ->
    true;
quote_closes_field([Char | Rest]) when Char =:= $\s; Char =:= $\t ->
    quote_closes_field(Rest);
quote_closes_field(_Rest) ->
    false.
