%% SPDX-FileCopyrightText: 2026 Stritzinger GmbH <peer@stritzinger.com>
%% SPDX-License-Identifier: Apache-2.0

-module(smelterl_gen_external_desc).
-moduledoc """
Render the Buildroot `external.desc` file for one selected target plan.

The descriptor always uses the main product identifier for the Buildroot
external name and reads the product nugget metadata from the selected target's
motherlode view.
""".


%=== EXPORTS ===================================================================

-export([generate/2]).
-export([generate/3]).


%=== API FUNCTIONS =============================================================

-doc """
Build `external.desc` content for one product and motherlode view.
""".
-spec generate(smelterl:nugget_id(), smelterl:motherlode()) ->
    {ok, iodata()} | {error, term()}.
generate(ProductId, Motherlode) ->
    maybe
        {ok, ProductNugget} ?= lookup_product_nugget(ProductId, Motherlode),
        Description = description_text(ProductNugget),
        Version = version_text(ProductNugget),
        smelterl_template:render(
            external_desc,
            #{
                name => uppercase_product_name(ProductId),
                description => Description,
                has_description => has_text(Description),
                version => Version,
                has_version => has_text(Version)
            }
        )
    else
        {error, _} = Error ->
            Error
    end.

-doc """
Render `external.desc` and write it to one open IO device.
""".
-spec generate(smelterl:nugget_id(), smelterl:motherlode(), file:io_device()) ->
    ok | {error, term()}.
generate(ProductId, Motherlode, Out) ->
    maybe
        {ok, Content} ?= generate(ProductId, Motherlode),
        smelterl_file:write_iodata(Out, Content)
    else
        {error, _} = Error ->
            Error
    end.


%=== INTERNAL FUNCTIONS ========================================================

lookup_product_nugget(ProductId, Motherlode) ->
    Nuggets = maps:get(nuggets, Motherlode, #{}),
    case maps:get(ProductId, Nuggets, undefined) of
        Nugget when is_map(Nugget) ->
            {ok, Nugget};
        undefined ->
            {error, {missing_product_metadata, ProductId}}
    end.

uppercase_product_name(ProductId) ->
    unicode:characters_to_binary(
        string:uppercase(atom_to_list(ProductId))
    ).

description_text(ProductNugget) ->
    maps:get(description, ProductNugget, <<>>).

version_text(ProductNugget) ->
    maps:get(version, ProductNugget, <<>>).

has_text(Value) when is_binary(Value), Value =/= <<>> ->
    true;
has_text(_Value) ->
    false.
