%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_template).
-moduledoc """
Template loading and rendering helpers for generated text artefacts.

This module provides the generate-stage template path: load a template from
`priv/templates/`, render it from structured data using a small Mustache-style
subset (`{{name}}`, `{{{name}}}`, `{{#section}}...{{/section}}`, and
standalone section lines), and optionally write the rendered output to a path
or IO device.
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
Render one named template using structured template data.
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
template_filename(external_mk) ->
    "external.mk.mustache";
template_filename(<<"external_mk">>) ->
    "external.mk.mustache";
template_filename(defconfig) ->
    "defconfig.mustache";
template_filename(<<"defconfig">>) ->
    "defconfig.mustache";
template_filename(alloy_context) ->
    "alloy_context.sh.mustache";
template_filename(<<"alloy_context">>) ->
    "alloy_context.sh.mustache";
template_filename(legal_readme) ->
    "README.mustache";
template_filename(<<"legal_readme">>) ->
    "README.mustache";
template_filename(_TemplateKey) ->
    undefined.

render_template(TemplateKey, Template, Data) ->
    case parse_template(strip_standalone_lines(Template)) of
        {ok, Nodes} ->
            render_template_nodes(TemplateKey, Nodes, [Data]);
        {error, Detail} ->
            {error, {render_failed, TemplateKey, Detail}}
    end.

render_template_nodes(TemplateKey, Nodes, ContextStack) ->
    case render_nodes(Nodes, ContextStack) of
        {ok, Content} ->
            {ok, Content};
        {error, Detail} ->
            {error, {render_failed, TemplateKey, Detail}}
    end.

parse_template(Template) ->
    parse_nodes(Template, root, []).

parse_nodes(Template, EndSection, Acc) ->
    case next_tag(Template) of
        nomatch ->
            finalize_parse(Template, EndSection, Acc);
        {ok, Prefix, {comment, _Key}, Rest} ->
            parse_nodes(Rest, EndSection, maybe_prepend_text(Prefix, Acc));
        {ok, Prefix, {variable, Key}, Rest} ->
            parse_nodes(
                Rest,
                EndSection,
                [{variable, Key, escaped} | maybe_prepend_text(Prefix, Acc)]
            );
        {ok, Prefix, {unescaped_variable, Key}, Rest} ->
            parse_nodes(
                Rest,
                EndSection,
                [{variable, Key, raw} | maybe_prepend_text(Prefix, Acc)]
            );
        {ok, Prefix, {section_start, Key}, Rest} ->
            case parse_nodes(Rest, Key, []) of
                {ok, SectionNodes, NextRest} ->
                    parse_nodes(
                        NextRest,
                        EndSection,
                        [{section, Key, SectionNodes} | maybe_prepend_text(Prefix, Acc)]
                    );
                {error, _} = Error ->
                    Error
            end;
        {ok, Prefix, {section_end, Key}, Rest} ->
            case EndSection of
                Key ->
                    {ok, finalize_nodes(Prefix, Acc), Rest};
                root ->
                    {error, {unexpected_section_end, Key}};
                _ ->
                    {error, {mismatched_section_end, EndSection, Key}}
            end;
        {error, _} = Error ->
            Error
    end.

finalize_parse(Rest, root, Acc) ->
    {ok, finalize_nodes(Rest, Acc)};
finalize_parse(_Rest, EndSection, _Acc) ->
    {error, {unclosed_section, EndSection}}.

finalize_nodes(Rest, Acc) ->
    lists:reverse(maybe_prepend_text(Rest, Acc)).

maybe_prepend_text(<<>>, Acc) ->
    Acc;
maybe_prepend_text(Text, Acc) ->
    [{text, Text} | Acc].

next_tag(Template) ->
    case binary:match(Template, <<"{{">>) of
        nomatch ->
            nomatch;
        {Start, _Length} ->
            Prefix = binary:part(Template, 0, Start),
            Rest0 = binary:part(Template, Start, byte_size(Template) - Start),
            parse_tag(Prefix, Rest0)
    end.

parse_tag(Prefix, <<"{{{", Rest0/binary>>) ->
    case binary:match(Rest0, <<"}}}">>) of
        nomatch ->
            {error, {unterminated_tag, unescaped_variable}};
        {End, _Length} ->
            Tag = binary:part(Rest0, 0, End),
            Rest = binary:part(Rest0, End + 3, byte_size(Rest0) - End - 3),
            case normalize_tag_key(Tag) of
                {ok, Key} ->
                    {ok, Prefix, {unescaped_variable, Key}, Rest};
                {error, _} = Error ->
                    Error
            end
    end;
parse_tag(Prefix, <<"{{", Rest0/binary>>) ->
    case binary:match(Rest0, <<"}}">>) of
        nomatch ->
            {error, {unterminated_tag, variable}};
        {End, _Length} ->
            Tag = binary:part(Rest0, 0, End),
            Rest = binary:part(Rest0, End + 2, byte_size(Rest0) - End - 2),
            classify_tag(Prefix, Tag, Rest)
    end.

classify_tag(Prefix, Tag0, Rest) ->
    Tag = trim_tag(Tag0),
    case Tag of
        <<>> ->
            {error, empty_tag};
        <<"#", Key/binary>> ->
            classify_keyed_tag(Prefix, section_start, Key, Rest);
        <<"/", Key/binary>> ->
            classify_keyed_tag(Prefix, section_end, Key, Rest);
        <<"!", _/binary>> ->
            {ok, Prefix, {comment, ignored}, Rest};
        <<"&", Key/binary>> ->
            classify_keyed_tag(Prefix, unescaped_variable, Key, Rest);
        _ ->
            classify_keyed_tag(Prefix, variable, Tag, Rest)
    end.

normalize_tag_key(Tag) ->
    Key = trim_tag(Tag),
    case Key of
        <<>> ->
            {error, empty_tag};
        _ ->
            {ok, Key}
    end.

classify_keyed_tag(Prefix, Kind, Key0, Rest) ->
    case normalize_tag_key(Key0) of
        {ok, Key} ->
            {ok, Prefix, {Kind, Key}, Rest};
        {error, _} = Error ->
            Error
    end.

render_nodes(Nodes, ContextStack) ->
    render_nodes(Nodes, ContextStack, []).

render_nodes([], _ContextStack, Acc) ->
    {ok, lists:reverse(Acc)};
render_nodes([{text, Text} | Rest], ContextStack, Acc) ->
    render_nodes(Rest, ContextStack, [Text | Acc]);
render_nodes([{variable, Key, Mode} | Rest], ContextStack, Acc) ->
    case resolve_value(Key, ContextStack) of
        {ok, Value} ->
            render_nodes(Rest, ContextStack, [render_value(Value, Mode) | Acc]);
        {error, _} = Error ->
            Error
    end;
render_nodes([{section, Key, SectionNodes} | Rest], ContextStack, Acc0) ->
    case resolve_value(Key, ContextStack) of
        {ok, Value} ->
            case render_section(Value, SectionNodes, ContextStack) of
                {ok, SectionContent} ->
                    render_nodes(Rest, ContextStack, [SectionContent | Acc0]);
                {error, _} = Error ->
                    Error
            end;
        {error, _} = Error ->
            Error
    end.

render_section(false, _SectionNodes, _ContextStack) ->
    {ok, []};
render_section(<<>>, _SectionNodes, _ContextStack) ->
    {ok, []};
render_section([], _SectionNodes, _ContextStack) ->
    {ok, []};
render_section(Value, SectionNodes, ContextStack) when is_list(Value) ->
    render_section_items(Value, SectionNodes, ContextStack, []);
render_section(Value, SectionNodes, ContextStack) ->
    render_nodes(SectionNodes, [normalize_value(Value) | ContextStack]).

render_section_items([], _SectionNodes, _ContextStack, Acc) ->
    {ok, lists:reverse(Acc)};
render_section_items([Item | Rest], SectionNodes, ContextStack, Acc) ->
    case render_nodes(SectionNodes, [normalize_value(Item) | ContextStack]) of
        {ok, Content} ->
            render_section_items(Rest, SectionNodes, ContextStack, [Content | Acc]);
        {error, _} = Error ->
            Error
    end.

resolve_value(<<".">>, [Current | _Rest]) ->
    {ok, Current};
resolve_value(Key, ContextStack) ->
    resolve_from_contexts(Key, split_key(Key), ContextStack).

resolve_from_contexts(Key, _Path, []) ->
    {error, {missing_variable, Key}};
resolve_from_contexts(Key, Path, [Context | Rest]) ->
    case resolve_from_context(Path, Context) of
        {ok, _} = Match ->
            Match;
        error ->
            resolve_from_contexts(Key, Path, Rest)
    end.

resolve_from_context([], Value) ->
    {ok, Value};
resolve_from_context([Key | Rest], Context) when is_map(Context) ->
    case maps:get(Key, Context, undefined) of
        undefined ->
            error;
        Value ->
            resolve_from_context(Rest, Value)
    end;
resolve_from_context(_Path, _Context) ->
    error.

split_key(Key) ->
    binary:split(Key, <<".">>, [global]).

render_value(Value, escaped) ->
    to_binary(Value);
render_value(Value, raw) ->
    to_binary(Value).

strip_standalone_lines(Template) ->
    re:replace(
        Template,
        <<"(?m)^[ \\t]*(\\{\\{[#!/][^\\r\\n]*\\}\\})[ \\t]*(?:\\r?\\n|$)">>,
        <<"\\1">>,
        [global, {return, binary}]
    ).

trim_tag(Tag) ->
    unicode:characters_to_binary(string:trim(Tag)).

normalize_data(Data) ->
    maps:from_list([
        {normalize_key(Key), normalize_value(Value)}
     || {Key, Value} <- maps:to_list(Data)
    ]).

normalize_value(Value) when is_map(Value) ->
    normalize_data(Value);
normalize_value(Value) when is_list(Value) ->
    case io_lib:printable_unicode_list(Value) of
        true ->
            unicode:characters_to_binary(Value);
        false ->
            [normalize_value(Item) || Item <- Value]
    end;
normalize_value(Value) ->
    Value.

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
    case application:get_env(smelterl, priv_dir) of
        {ok, Dir} ->
            Dir;
        undefined ->
            case code:priv_dir(smelterl) of
                {error, bad_name} ->
                    BeamPath = code:which(?MODULE),
                    filename:join(
                        filename:dirname(filename:dirname(BeamPath)),
                        "priv"
                    );
                Dir ->
                    Dir
            end
    end.

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value, utf8);
to_binary(Value) when is_map(Value) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Value]));
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value);
to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
to_binary(Value) ->
    unicode:characters_to_binary(io_lib:format("~tp", [Value])).
