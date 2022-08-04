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

-module(emqx_exhook_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include("emqx_exhook.hrl").

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-define(OTHER_CLUSTER_NAME_ATOM, test_emqx_cluster).
-define(OTHER_CLUSTER_NAME_STRING, "test_emqx_cluster").

%%--------------------------------------------------------------------
%% Setups
%%--------------------------------------------------------------------

all() -> emqx_ct:all(?MODULE).

init_per_suite(Cfg) ->
    _ = emqx_exhook_demo_svr:start(),
    emqx_ct_helpers:start_apps([emqx_exhook], fun set_special_cfgs/1),
    Cfg.

end_per_suite(_Cfg) ->
    emqx_ct_helpers:stop_apps([emqx_exhook]),
    emqx_exhook_demo_svr:stop().

set_special_cfgs(emqx) ->
    application:set_env(emqx, allow_anonymous, false),
    application:set_env(emqx, enable_acl_cache, false),
    application:set_env(emqx, plugins_loaded_file, undefined),
    application:set_env(emqx, modules_loaded_file, undefined),
    application:set_env(ekka, cluster_name, ?OTHER_CLUSTER_NAME_ATOM);
set_special_cfgs(emqx_exhook) ->
    ok.

%%--------------------------------------------------------------------
%% Test cases
%%--------------------------------------------------------------------

t_noserver_nohook(_) ->
    emqx_exhook:disable(default),
    ?assertEqual([], ets:tab2list(emqx_hooks)),
    ok = emqx_exhook:enable(default),
    ?assertNotEqual([], ets:tab2list(emqx_hooks)).

t_access_failed_if_no_server_running(_) ->
    emqx_exhook:disable(default),
    ClientInfo = #{clientid => <<"user-id-1">>,
                   username => <<"usera">>,
                   peerhost => {127,0,0,1},
                   sockport => 1883,
                   protocol => mqtt,
                   mountpoint => undefined
                  },
    ?assertMatch({stop, #{auth_result := not_authorized}},
                 emqx_exhook_handler:on_client_authenticate(ClientInfo, #{auth_result => success})),

    ?assertMatch({stop, deny},
                 emqx_exhook_handler:on_client_check_acl(ClientInfo, publish, <<"t/1">>, allow)),

    Message = emqx_message:make(<<"t/1">>, <<"abc">>),
    ?assertMatch({stop, Message},
                 emqx_exhook_handler:on_message_publish(Message)),
    emqx_exhook:enable(default).

t_cli_list(_) ->
    meck_print(),
    ?assertEqual( [[emqx_exhook_server:format(emqx_exhook_mngr:server(Name)) || Name  <- emqx_exhook:list()]]
                , emqx_exhook_cli:cli(["server", "list"])
                ),
    unmeck_print().

t_cli_enable_disable(_) ->
    meck_print(),
    ?assertEqual([already_started], emqx_exhook_cli:cli(["server", "enable", "default"])),
    ?assertEqual(ok, emqx_exhook_cli:cli(["server", "disable", "default"])),
    ?assertEqual([["name=default, hooks=#{}, active=false"]], emqx_exhook_cli:cli(["server", "list"])),

    ?assertEqual([not_running], emqx_exhook_cli:cli(["server", "disable", "default"])),
    ?assertEqual(ok, emqx_exhook_cli:cli(["server", "enable", "default"])),
    unmeck_print().

t_cli_stats(_) ->
    meck_print(),
    _ = emqx_exhook_cli:cli(["server", "stats"]),
    _ = emqx_exhook_cli:cli(x),
    unmeck_print().

t_priority(_) ->
    restart_apps_with_envs([ {emqx, fun set_special_cfgs/1}
                           , {emqx_exhook, [{hook_priority, 1}]}]),

    emqx_exhook:disable(default),
    ok = emqx_exhook:enable(default),
    [Callback | _] = emqx_hooks:lookup('client.connected'),
    ?assertEqual(1, emqx_hooks:callback_priority(Callback)).

t_cluster_name(_) ->
    SetEnvFun =
        fun(emqx) ->
                set_special_cfgs(emqx),
                application:set_env(ekka, cluster_name, ?OTHER_CLUSTER_NAME_ATOM);
           (emqx_exhook) ->
                application:set_env(emqx_exhook, hook_priority, 1)
        end,

    emqx_ct_helpers:stop_apps([emqx, emqx_exhook]),
    emqx_ct_helpers:start_apps([emqx, emqx_exhook], SetEnvFun),

    ?assertEqual(?OTHER_CLUSTER_NAME_STRING, emqx_sys:cluster_name()),

    emqx_exhook:disable(default),
    ok = emqx_exhook:enable(default),
    %% See emqx_exhook_demo_svr:on_provider_loaded/2
    ?assertEqual([], emqx_hooks:lookup('session.created')),
    ?assertEqual([], emqx_hooks:lookup('message_publish')),

    [Callback | _] = emqx_hooks:lookup('client.connected'),
    ?assertEqual(1, emqx_hooks:callback_priority(Callback)).

%%--------------------------------------------------------------------
%% Utils
%%--------------------------------------------------------------------

%% TODO: make it more general and move to `emqx_ct_helpers`
restart_app_with_envs(App, Fun)
  when is_function(Fun) ->
    emqx_ct_helpers:stop_apps([App]),
    emqx_ct_helpers:start_apps([App], Fun);

restart_app_with_envs(App, Envs)
  when is_list(Envs) ->
    emqx_ct_helpers:stop_apps([App]),
    HandlerFun =
        fun(AppName) ->
                lists:foreach(fun({Key, Val}) ->
                                      application:set_env(AppName, Key, Val)
                              end, Envs)
        end,
    emqx_ct_helpers:start_apps([App], HandlerFun).

restart_apps_with_envs([]) ->
    ok;
restart_apps_with_envs([{App, Envs} | Rest]) ->
    restart_app_with_envs(App, Envs),
    restart_apps_with_envs(Rest).

meck_print() ->
    meck:new(emqx_ctl, [passthrough, no_history, no_link]),
    meck:expect(emqx_ctl, print, fun(_) -> ok end),
    meck:expect(emqx_ctl, print, fun(_, Args) -> Args end).

unmeck_print() ->
    meck:unload(emqx_ctl).