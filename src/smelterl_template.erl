%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_template).
-moduledoc """
Template loading and rendering helpers for generated text artefacts.

This module provides a small template path for the generate-stage work: load a
template from `priv/templates/`, substitute flat `{{key}}` placeholders from a
data map, and optionally write the rendered output to a path or IO device.
""".


%=== EXPORTS ===================================================================

-export([render/2]).
-export([render_to_file/3]).
-export([substitute/2]).


%=== API FUNCTIONS =============================================================

-doc """
Replace `[[KEY]]` markers in `String` using one consolidated config map.
""".
-spec substitute(binary() | string(), smelterl:config()) ->
    {ok, binary()} | {error, term()}.
substitute(String, Config) when is_map(Config) ->
    substitute_markers(to_binary(String), Config, []).

-doc """
Render one named template using a flat data map.
""".
-spec render(atom() | binary(), map()) -> {ok, iodata()} | {error, term()}.
render(TemplateKey, Data) when is_map(Data) ->
    case load_template(TemplateKey) of
        {ok, Template} ->
            render_template(
                normalize_template_key(TemplateKey),
                Template,
                normalize_data(Data)
            );
        {error, _} = Error ->
            Error
    end.

-doc """
Render one template and write it to a path or IO device.
""".
-spec render_to_file(atom() | binary(), map(), smelterl:file_path() | file:io_device()) ->
    ok | {error, term()}.
render_to_file(TemplateKey, Data, PathOrDevice) ->
    case render(TemplateKey, Data) of
        {ok, Content} ->
            case smelterl_file:write_iodata(PathOrDevice, Content) of
                ok ->
                    ok;
                {error, Detail} ->
                    {error, {write_failed, PathOrDevice, Detail}}
            end;
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

substitute_markers(String, Config, Acc) ->
    case binary:match(String, <<"[[">>) of
        nomatch ->
            {ok, iolist_to_binary(lists:reverse([String | Acc]))};
        {Start, _Length} ->
            Prefix = binary:part(String, 0, Start),
            Rest0 = binary:part(String, Start + 2, byte_size(String) - Start - 2),
            case binary:match(Rest0, <<"]]">>) of
                nomatch ->
                    {error, {unterminated_marker, String}};
                {MarkerEnd, _} ->
                    Key = binary:part(Rest0, 0, MarkerEnd),
                    Rest = binary:part(
                        Rest0,
                        MarkerEnd + 2,
                        byte_size(Rest0) - MarkerEnd - 2
                    ),
                    case maps:get(Key, Config, undefined) of
                        {_Kind, _Origin, Value} ->
                            substitute_markers(
                                Rest,
                                Config,
                                [to_binary(Value), Prefix | Acc]
                            );
                        undefined ->
                            {error, {unresolved_key, Key}}
                    end
            end
    end.

load_template(TemplateKey) ->
    case template_path(TemplateKey) of
        {ok, Path} ->
            case file:read_file(Path) of
                {ok, Template} ->
                    {ok, Template};
                {error, Reason} ->
                    {error,
                        {template_load_failed, normalize_template_key(TemplateKey), Reason}}
            end;
        {error, _} = Error ->
            Error
    end.

template_path(TemplateKey) ->
    case template_filename(TemplateKey) of
        undefined ->
            {error, {template_not_found, normalize_template_key(TemplateKey)}};
        Filename ->
            {ok, filename:join(priv_dir(), filename:join("templates", Filename))}
    end.

template_filename(external_desc) ->
    "external.desc.mustache";
template_filename(<<"external_desc">>) ->
    "external.desc.mustache";
template_filename(config_in) ->
    "Config.in.mustache";
template_filename(<<"config_in">>) ->
    "Config.in.mustache";
template_filename(_TemplateKey) ->
    undefined.

render_template(TemplateKey, Template, Data) ->
    case placeholder_keys(Template) of
        {ok, Keys} ->
            render_template_keys(TemplateKey, Keys, Template, Data);
        {error, Detail} ->
            {error, {render_failed, TemplateKey, Detail}}
    end.

render_template_keys(_TemplateKey, [], Template, _Data) ->
    {ok, Template};
render_template_keys(TemplateKey, [Key | Rest], Template0, Data) ->
    case maps:get(Key, Data, undefined) of
        undefined ->
            {error, {render_failed, TemplateKey, {missing_variable, Key}}};
        Value ->
            Placeholder = <<"{{", Key/binary, "}}">>,
            Template1 = binary:replace(Template0, Placeholder, Value, [global]),
            render_template_keys(TemplateKey, Rest, Template1, Data)
    end.

placeholder_keys(Template) ->
    case re:run(
        Template,
        <<"\\{\\{([a-zA-Z0-9_]+)\\}\\}">>,
        [global, {capture, all_but_first, binary}]
    ) of
        {match, Matches} ->
            {ok, unique_binaries([Key || [Key] <- Matches])};
        nomatch ->
            {ok, []};
        {error, Reason} ->
            {error, {invalid_template, Reason}}
    end.

unique_binaries(Binaries) ->
    unique_binaries(Binaries, sets:new([{version, 2}]), []).

unique_binaries([], _Seen, Acc) ->
    lists:reverse(Acc);
unique_binaries([Binary | Rest], Seen0, Acc) ->
    case sets:is_element(Binary, Seen0) of
        true ->
            unique_binaries(Rest, Seen0, Acc);
        false ->
            unique_binaries(Rest, sets:add_element(Binary, Seen0), [Binary | Acc])
    end.

normalize_data(Data) ->
    maps:from_list([
        {normalize_key(Key), to_binary(Value)}
     || {Key, Value} <- maps:to_list(Data)
    ]).

normalize_key(Key) when is_atom(Key) ->
    atom_to_binary(Key, utf8);
normalize_key(Key) when is_binary(Key) ->
    Key;
normalize_key(Key) ->
    unicode:characters_to_binary(Key).

normalize_template_key(Key) when is_atom(Key) ->
    Key;
normalize_template_key(Key) when is_binary(Key) ->
    binary_to_atom(Key, utf8).

priv_dir() ->
    case code:priv_dir(smelterl) of
        {error, bad_name} ->
            BeamPath = code:which(?MODULE),
            filename:join(
                filename:dirname(filename:dirname(BeamPath)),
                "priv"
            );
        Dir ->
            Dir
    end.

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value);
to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
to_binary(Value) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Value])).
