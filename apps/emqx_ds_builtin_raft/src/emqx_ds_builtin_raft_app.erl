%%--------------------------------------------------------------------
%% Copyright (c) 2020-2024 EMQ Technologies Co., Ltd. All Rights Reserved.
%%--------------------------------------------------------------------

-module(emqx_ds_builtin_raft_app).

-export([start/2]).

start(_Type, _Args) ->
    emqx_ds:register_backend(builtin_raft, emqx_ds_replication_layer),
    {ok, self()}.
