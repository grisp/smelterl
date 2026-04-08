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
        smelterl_template:render(
            external_desc,
            #{
                name => uppercase_product_name(ProductId),
                desc => description_text(ProductNugget)
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
    Description = maps:get(description, ProductNugget, <<>>),
    Version = maps:get(version, ProductNugget, undefined),
    maybe_append_version(Description, Version).

maybe_append_version(Description, Version)
  when is_binary(Description), Description =/= <<>>, is_binary(Version), Version =/= <<>> ->
    <<Description/binary, " - Version ", Version/binary>>;
maybe_append_version(Description, _Version)
  when is_binary(Description), Description =/= <<>> ->
    Description;
maybe_append_version(_Description, Version)
  when is_binary(Version), Version =/= <<>> ->
    <<"Version ", Version/binary>>;
maybe_append_version(_Description, _Version) ->
    <<>>.
