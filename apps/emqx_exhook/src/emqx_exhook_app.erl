%%--------------------------------------------------------------------
%% Copyright (c) 2020-2022 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_exhook_app).

-behaviour(application).

-include("emqx_exhook.hrl").

-emqx_plugin(extension).

-export([ start/2
        , stop/1
        , prep_stop/1
        ]).

%%--------------------------------------------------------------------
%% Application callbacks
%%--------------------------------------------------------------------

start(_StartType, _StartArgs) ->
    {ok, Sup} = emqx_exhook_sup:start_link(),
    emqx_ctl:register_command(exhook, {emqx_exhook_cli, cli}, []),
    {ok, Sup}.

prep_stop(State) ->
    emqx_ctl:unregister_command(exhook),
    State.

stop(_State) ->
    ok.