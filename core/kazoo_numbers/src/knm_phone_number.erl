%%%-----------------------------------------------------------------------------
%%% @copyright (C) 2015-2020, 2600Hz
%%% @doc
%%% @author Peter Defebvre
%%% @author Pierre Fenoll
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at https://mozilla.org/MPL/2.0/.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(knm_phone_number).

-export([fetch/1, fetch/2
        ,fetch_pipe/1
        ,save/1
        ,delete/1
        ,new/1
        ]).

-export([to_json/1
        ,to_public_json/1
        ,from_json_with_options/2
        ,from_number/1, from_number_with_options/2
        ,is_phone_number/1
        ]).

-export([setters/2
        ,is_dirty/1, set_dirty/2
        ,number/1
        ,number_db/1
        ,assign_to/1, set_assign_to/2
        ,assigned_to/1, set_assigned_to/2
        ,prev_assigned_to/1
        ,used_by/1, set_used_by/2
        ,features/1, features_list/1, set_features/2, reset_features/1
        ,feature/2, set_feature/3
        ,features_allowed/1, features_denied/1
        ,add_allowed_feature/2, remove_allowed_feature/2, add_denied_feature/2, remove_denied_feature/2
        ,remove_denied_features/1
        ,state/1, set_state/2
        ,reserve_history/1, add_reserve_history/2, push_reserve_history/1, unwind_reserve_history/1
        ,ported_in/1, set_ported_in/2
        ,module_name/1, set_module_name/2
        ,carrier_data/1, set_carrier_data/2, update_carrier_data/2
        ,region/1, set_region/2
        ,auth_by/1, set_auth_by/2
        ,is_authorized/1, is_admin/1, is_reserved_from_parent/1
        ,dry_run/1, set_dry_run/2
        ,batch_run/1, set_batch_run/2
        ,mdn_run/1, set_mdn_run/2
        ,locality/1, set_locality/2
        ,doc/1, update_doc/2, reset_doc/2, reset_doc/1
        ,current_doc/1
        ,modified/1, set_modified/2
        ,created/1, set_created/2
        ]).

-export([is_state/1]).
-export([list_attachments/2]).

-export([on_success/1
        ,add_on_success/2
        ,reset_on_success/1
        ]).

-type callback_fun_1() :: fun((record()) -> any()).
-type callback_fun_2() :: fun((record(), any()) -> any()).
-type callback_fun_3() :: fun((record(), any(), any()) -> any()).
-type callback_fun_4() :: fun((record(), any(), any(), any()) -> any()).
-type callback_fun() :: callback_fun_1() | callback_fun_2() | callback_fun_3() | callback_fun_4().
-type callback() :: {callback_fun() , list()}.
-type callbacks() :: [callback()].

-export_type([callback/0
             ,callbacks/0
             ]).

-include("knm.hrl").

%% Used by from_json/1
-define(DEFAULT_FEATURES, kz_json:new()).
-define(DEFAULT_RESERVE_HISTORY, []).
-define(DEFAULT_PORTED_IN, 'false').
-define(DEFAULT_MODULE_NAME, knm_carriers:default_carrier()).
-define(DEFAULT_CARRIER_DATA, kz_json:new()).
-define(DEFAULT_DOC, kz_json:new()).
-define(DEFAULT_FEATURES_ALLOWED, []).
-define(DEFAULT_FEATURES_DENIED, []).

%% The '%%%' suffixes show what Dialyzer requires for that one record instantiation in from_json/1.
%% Without 'undefined' there, Dialyzer outputs 'false' positives.
%% It has trouble inferring what is happening in from_json/1's setters.
%% And all this is because we need to set is_dirty reliably.
-record(knm_phone_number, {number :: kz_term:api_ne_binary()             %%%
                          ,number_db :: kz_term:api_ne_binary()          %%%
                          ,rev :: kz_term:api_ne_binary()
                          ,assign_to :: kz_term:api_ne_binary()
                          ,assigned_to :: kz_term:api_ne_binary()
                          ,prev_assigned_to :: kz_term:api_ne_binary()
                          ,used_by :: kz_term:api_ne_binary()
                          ,features :: kz_term:api_object()
                          ,state :: kz_term:api_ne_binary()              %%%
                          ,reserve_history :: kz_term:api_ne_binaries()  %%%
                          ,ported_in :: kz_term:api_boolean()            %%%
                          ,module_name :: kz_term:api_ne_binary()        %%%
                          ,carrier_data :: kz_term:api_object()
                          ,region :: kz_term:api_ne_binary()
                          ,auth_by :: kz_term:api_ne_binary()
                          ,dry_run = 'false' :: boolean()
                          ,batch_run = 'false' :: boolean()
                          ,mdn_run = 'false' :: boolean()
                          ,locality :: kz_term:api_object()
                          ,doc :: kz_term:api_object()
                          ,current_doc :: kz_term:api_object()
                          ,modified :: kz_time:api_seconds()             %%%
                          ,created :: kz_time:api_seconds()              %%%
                          ,is_dirty = 'false' :: boolean()
                          ,features_allowed :: kz_term:api_ne_binaries() %%%
                          ,features_denied :: kz_term:api_ne_binaries()  %%%
                          ,on_success = [] :: callbacks()
                          }).
-type record() :: #knm_phone_number{}.

-type records() :: [record(), ...].
-type bulk_change_error_fun() :: fun((kz_term:ne_binary()
                                     ,kz_datamgr:data_error()
                                     ,knm_pipe:collection()
                                     ) -> knm_pipe:collection()
                                              ).
-type bulk_change_retry_fun() :: fun((kz_term:ne_binary()
                                     ,grouped_phone_numbers()
                                     ,kz_term:ne_binary()
                                     ,knm_pipe:collection()
                                     ) -> knm_pipe:collection()
                                              ).

-type return() :: {'ok', record()} |
                  {'error', any()}.


-export_type([record/0
             ,records/0
             ,set_function/0
             ,set_functions/0
             ,return/0
             ]).

-ifdef(FUNCTION_NAME).
-define(DIRTY(PN),
        begin
            dev:debug("dirty ~s ~s/~p", [number(PN), ?FUNCTION_NAME, ?FUNCTION_ARITY]),
            (PN)#knm_phone_number{is_dirty = 'true'
                                 ,modified = kz_time:now_s()
                                 }
        end).
-else.
-define(DIRTY(PN),
        begin
            dev:debug("dirty ~s", [number(PN)]),
            (PN)#knm_phone_number{is_dirty = 'true'
                                 ,modified = kz_time:now_s()
                                 }
        end).
-endif.



%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec new(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
new(T=#{'todo' := Nums, 'options' := Options}) ->
    Setters = new_setters(Options),
    PNs = [do_new(DID, Setters) || DID <- Nums],
    knm_pipe:set_succeeded(T, PNs).

-spec new_setters(knm_options:options()) -> set_functions().
new_setters(Options) ->
    knm_options:to_phone_number_setters(options_for_new_setters(Options)).

-spec options_for_new_setters(knm_options:options()) -> knm_options:options().
options_for_new_setters(Options) ->
    case {knm_options:ported_in(Options)
         ,?NUMBER_STATE_PORT_IN =:= knm_options:state(Options)
         }
    of
        {'true', 'false'} -> props:set_value('module_name', ?PORT_IN_MODULE_NAME, Options);
        {_, 'true'} ->       props:set_value('module_name', ?CARRIER_LOCAL, Options);
        _ -> Options
    end.

-spec do_new(kz_term:ne_binary(), set_functions()) -> record().
do_new(DID, Setters) ->
    {'ok', PN} = setters(from_number(DID), Setters),
    PN.

-spec from_number(kz_term:ne_binary()) -> record().
from_number(DID) ->
    from_json(kz_doc:set_id(kzd_phone_numbers:new(), DID)).

-spec from_number_with_options(kz_term:ne_binary(), knm_options:options()) -> record().
from_number_with_options(DID, Options) ->
    do_new(DID, new_setters(Options)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec fetch(kz_term:ne_binary()) -> return().
fetch(<<Num/binary>>) ->
    fetch(Num, knm_options:default()).

-spec fetch(kz_term:ne_binary(), knm_options:options()) -> return().
fetch(<<Num/binary>>, Options) ->
    NormalizedNum = knm_converters:normalize(Num),
    NumberDb = knm_converters:to_db(NormalizedNum),
    case do_fetch(NumberDb, NormalizedNum, Options) of
        {'ok', JObj} -> handle_fetch(JObj, Options);
        {'error', 'not_found'}=Error ->
            ?LOG_DEBUG("number is not exists ~s/~s", [NumberDb, NormalizedNum]),
            Error;
        {'error', _R}=Error -> Error
    end.

-spec do_fetch(kz_term:api_ne_binary(), kz_term:ne_binary(), knm_options:options()) ->
          {'ok', kz_json:object()} |
          kazoo_data:data_error().
do_fetch('undefined', _Normalized, _Options) ->
    ?LOG_INFO("no database for number ~s", [_Normalized]),
    {'error', 'not_found'};
do_fetch(NumberDb, NormalizedNum, Options) ->
    case knm_options:batch_run(Options) of
        'true' -> kz_datamgr:open_doc(NumberDb, NormalizedNum);
        'false' -> kz_datamgr:open_cache_doc(NumberDb, NormalizedNum)
    end.

-spec handle_fetch(kz_json:object(), knm_options:options()) ->
          {'ok', record()} |
          {'error', 'unauthorized'}.
handle_fetch(JObj, Options) ->
    PN = from_json_with_options(JObj, Options),
    case state(PN) =:= ?NUMBER_STATE_AVAILABLE
        orelse is_authorized(PN)
        orelse is_reserved_from_parent(PN)
    of
        'true' -> {'ok', PN};
        'false' -> {'error', 'unauthorized'}
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec fetch_pipe(knm_pipe:collection()) -> knm_pipe:collection().
fetch_pipe(Collection) ->
    Pairs = group_by(lists:usort(knm_converters:normalize(knm_pipe:todo(Collection)))
                    ,fun group_number_by_db/2
                    ),
    maps:fold(fun fetch_pipe/3, Collection, Pairs).

-spec fetch_pipe(kz_term:ne_binary(), kz_term:ne_binaries(), knm_pipe:collection()) ->
          knm_pipe:collection().
fetch_pipe(NumberDb, NormalizedNums, Collection) ->
    case maybe_bulk_fetch(NumberDb, NormalizedNums, knm_pipe:options(Collection)) of
        {'error', Reason} ->
            ?LOG_DEBUG("bulk read failed with reason '~s' in db ~s for number(s) ~s"
                      ,[Reason, NumberDb, kz_binary:join(NormalizedNums)]
                      ),
            knm_pipe:set_failed(Collection, NormalizedNums, Reason);
        {'ok', JObjs} when is_list(JObjs) ->
            lists:foldl(fun handle_bulk_fetch/2, Collection, JObjs);
        {'ok', JObj} ->
            handle_single_pipe_fetch(Collection, JObj)
    end.

-spec maybe_bulk_fetch(kz_term:ne_binary(), kz_term:ne_binaries(), knm_options:options()) ->
          {'ok', kz_json:objects() | kz_json:object()} |
          kazoo_data:data_error().
maybe_bulk_fetch(NumberDb, [Num], Options) ->
    do_fetch(NumberDb, Num, Options);
maybe_bulk_fetch(NumberDb, Nums, Options) ->
    case knm_options:batch_run(Options) of
        'true' -> kz_datamgr:open_docs(NumberDb, Nums);
        'false' -> kz_datamgr:open_cache_docs(NumberDb, Nums)
    end.

-spec handle_bulk_fetch(kz_json:objects(), knm_pipe:collection()) -> knm_pipe:collection().
handle_bulk_fetch(JObj, Collection) ->
    Num = kz_json:get_ne_value(<<"key">>, JObj),
    case kz_json:get_ne_value(<<"doc">>, JObj) of
        'undefined' ->
            R = kz_json:get_ne_value(<<"error">>, JObj),
            lager:warning("failed reading ~s: ~p", [Num, R]),
            knm_pipe:set_failed(Collection, Num, kz_term:to_atom(R, 'true'));
        Doc ->
            handle_single_pipe_fetch(Collection, Doc)
    end.

-spec handle_single_pipe_fetch(knm_pipe:collection(), kz_json:object()) -> knm_pipe:collection().
handle_single_pipe_fetch(Collection, Doc) ->
    case handle_fetch(Doc, knm_pipe:options(Collection)) of
        {'ok', PN} ->
            knm_pipe:set_succeeded(Collection, PN);
        {'error', Reason} ->
            knm_pipe:set_failed(Collection, kz_doc:id(Doc), knm_errors:to_json(Reason))
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec save(knm_pipe:collection()) -> knm_pipe:collection().
save(T0) ->
    {T, NotToSave} = take_not_to_save(T0),
    Ta = knm_pipe:set_succeeded(T, NotToSave),
    Tb = knm_pipe:pipe(T, [fun is_mdn_for_mdn_run/1
                          ,fun save_to_number_db/1
                          ,fun assign/1
                          ,fun unassign_from_prev/1
                          ]),
    knm_pipe:merge_okkos(Ta, Tb).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_mdn_for_mdn_run(knm_pipe:collection()) -> knm_pipe:collection().
is_mdn_for_mdn_run(Collection0) ->
    IsMDNRun = knm_options:mdn_run(knm_pipe:options(Collection0)),
    F = fun (PN, Collection) ->
                case is_mdn_for_mdn_run(PN, IsMDNRun) of
                    'true' ->
                        ?LOG_DEBUG("~s is an mdn", [number(PN)]),
                        knm_pipe:set_succeeded(Collection, PN);
                    'false' -> knm_pipe:set_failed(Collection, number(PN), error_unauthorized())
                end
        end,
    lists:foldl(F, Collection0, knm_pipe:todo(Collection0)).

-spec is_mdn_for_mdn_run(record(), boolean()) -> boolean().
is_mdn_for_mdn_run(#knm_phone_number{auth_by = ?KNM_DEFAULT_AUTH_BY}, _) ->
    ?LOG_DEBUG("mdn check disabled by auth_by"),
    'true';
is_mdn_for_mdn_run(PN, IsMDNRun) ->
    IsMDN = ?CARRIER_MDN =:= module_name(PN),
    kz_term:xnor(IsMDNRun, IsMDN).

-spec take_not_to_save(knm_pipe:collection()) -> {knm_pipe:collection(), records()}.
take_not_to_save(T0=#{'todo' := PNs, 'options' := Options}) ->
    case knm_options:dry_run(Options) of
        'true' ->
            ?LOG_DEBUG("dry_run-ing btw"),
            %% FIXME: opaque
            T = T0#{'todo' => [], 'succeeded' => []},
            {T, PNs};
        'false' ->
            %% FIXME: opaque
            T = T0#{'todo' => []},
            lists:foldl(fun take_not_to_save_fold/2, {T, []}, PNs)
    end.

take_not_to_save_fold(PN, {T, NotToSave}) ->
    NotDirty = not PN#knm_phone_number.is_dirty,
    case NotDirty
        orelse ?NUMBER_STATE_DELETED =:= state(PN)
    of
        'false' -> {knm_pipe:set_succeeded(T, PN), NotToSave};
        'true' ->
            log_why_not_to_save(NotDirty, number(PN)),
            {T, [PN|NotToSave]}
    end.

log_why_not_to_save('true', _Num) ->
    ?LOG_DEBUG("not dirty, skip saving ~s", [_Num]);
log_why_not_to_save('false', _Num) ->
    ?LOG_DEBUG("deleted, skip saving ~s", [_Num]).

%%------------------------------------------------------------------------------
%% @doc To call only from knm_ops:delete/2 (only for sysadmins).
%% @end
%%------------------------------------------------------------------------------
-spec delete(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
delete(T=#{'todo' := PNs, 'options' := Options}) ->
    case knm_options:dry_run(Options) of
        'true' ->
            ?LOG_DEBUG("dry_run-ing btw, not deleting anything"),
            knm_pipe:set_succeeded(T, PNs);
        'false' ->
            knm_pipe:pipe(T, [fun log_permanent_deletion/1
                             ,fun try_delete_account_doc/1
                             ,fun try_delete_number_doc/1
                             ,fun unassign_from_prev/1
                             ,fun set_state_deleted/1
                             ])
    end.

-spec log_permanent_deletion(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
log_permanent_deletion(T=#{'todo' := PNs}) ->
    F = fun (_PN) -> ?LOG_DEBUG("deleting permanently ~s", [number(_PN)]) end,
    lists:foreach(F, PNs),
    knm_pipe:set_succeeded(T, PNs).

-spec set_state_deleted(knm_pipe:collection()) -> knm_pipe:collection().
set_state_deleted(T) ->
    setters(T, [{fun set_state/2, ?NUMBER_STATE_DELETED}]).

%%------------------------------------------------------------------------------
%% @doc Returns same fields view `phone_numbers.json' returns.
%% @end
%%------------------------------------------------------------------------------
-spec to_public_json(record()) -> kz_json:object().
to_public_json(PN) ->
    JObj = to_json(PN),
    State = {<<"state">>, state(PN)},
    UsedBy = {<<"used_by">>, used_by(PN)},
    Features = {<<"features">>, features_list(PN)},
    ModuleName = case module_name(PN) of
                     <<"knm_", Carrier/binary>> -> Carrier;
                     _ -> 'undefined'
                 end,
    Available = knm_providers:available_features(PN),
    Settings = knm_providers:settings(PN, Available),
    ReadOnlyFeatures = [{<<"available">>, Available}
                       ,{<<"settings">>, Settings}
                       ],
    ReadOnly =
        kz_json:from_list(
          props:filter_empty(
            [{<<"created">>, kz_doc:created(JObj)}
            ,{<<"modified">>, kz_doc:modified(JObj)}
            ,{<<"features">>, kz_json:from_list(ReadOnlyFeatures)}
            ,{<<"carrier_module">>, ModuleName}
            ,{<<"is_deleted">>, is_deleted(PN)}
            ])
         ),
    Values = props:filter_empty(
               [State
               ,UsedBy
               ,Features
               ]),
    Root = kz_json:set_values(Values, kz_doc:public_fields(JObj)),
    kz_json:set_value(<<"_read_only">>, ReadOnly, Root).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec to_json(record()) -> kz_json:object().
to_json(PN=#knm_phone_number{doc=JObj}) ->
    Setters = [{fun kz_doc:set_id/2, number(PN)}
              ,{fun kz_doc:set_created/2, created(PN)}
              ,{fun kz_doc:set_modified/2, modified(PN)}
              ,{fun kz_doc:set_type/2, kzd_phone_numbers:type()}
              ,{fun kzd_phone_numbers:set_pvt_db_name/2, number_db(PN)}
              ,{fun kzd_phone_numbers:set_pvt_module_name/2, module_name(PN)}
              ,{fun kzd_phone_numbers:set_pvt_ported_in/2, ported_in(PN)}
              ,{fun kzd_phone_numbers:set_pvt_state/2, state(PN)}
               | props:filter_empty(
                   [{fun kz_doc:set_revision/2, rev(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_assigned_to/2, assigned_to(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_carrier_data/2, carrier_data(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_features/2, features(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_features_allowed/2, features_allowed(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_features_denied/2, features_denied(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_previously_assigned_to/2, prev_assigned_to(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_region/2, region(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_reserve_history/2, reserve_history(PN)}
                   ,{fun kzd_phone_numbers:set_pvt_used_by/2, used_by(PN)}
                   ])
              ],
    kz_doc:setters(sanitize_public_fields(JObj), Setters).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec from_json(kz_json:object()) -> record().
from_json(JObj) ->
    {'ok', PN} =
        setters(#knm_phone_number{}
                %% Order matters
               ,[{fun set_number/2, knm_converters:normalize(kz_doc:id(JObj))}
                ,{fun set_assigned_to/3
                 ,kzd_phone_numbers:pvt_assigned_to(JObj)
                 ,kzd_phone_numbers:pvt_used_by(JObj)
                 }
                ,{fun set_prev_assigned_to/2, kzd_phone_numbers:pvt_previously_assigned_to(JObj)}
                ,{fun set_reserve_history/2, kzd_phone_numbers:pvt_reserve_history(JObj, ?DEFAULT_RESERVE_HISTORY)}

                ,{fun set_modified/2, kz_doc:modified(JObj)}
                ,{fun set_created/2, kz_doc:created(JObj)}

                ,{fun set_doc/2, sanitize_public_fields(JObj)}
                ,{fun set_current_doc/2, JObj}
                ,{fun maybe_migrate_features/2, kzd_phone_numbers:pvt_features(JObj)}

                ,{fun set_state/2, kzd_phone_numbers:pvt_state(JObj, kz_json:get_value(?PVT_STATE_LEGACY, JObj))}
                ,{fun set_ported_in/2, kzd_phone_numbers:pvt_ported_in(JObj, ?DEFAULT_PORTED_IN)}
                ,{fun set_module_name/2, kzd_phone_numbers:pvt_module_name(JObj, ?DEFAULT_MODULE_NAME)}
                ,{fun set_carrier_data/2, kzd_phone_numbers:pvt_carrier_data(JObj, ?DEFAULT_CARRIER_DATA)}
                ,{fun set_region/2, kzd_phone_numbers:pvt_region(JObj)}
                ,{fun set_auth_by/2, kzd_phone_numbers:pvt_authorizing_account(JObj)}
                ,{fun set_features_allowed/2, kzd_phone_numbers:pvt_features_allowed(JObj, ?DEFAULT_FEATURES_ALLOWED)}
                ,{fun set_features_denied/2, kzd_phone_numbers:pvt_features_denied(JObj, ?DEFAULT_FEATURES_DENIED)}

                ,fun ensure_features_defined/1
                ,{fun ensure_pvt_state_legacy_undefined/2, kz_json:get_value(?PVT_STATE_LEGACY, JObj)}

                 | props:filter_undefined([{fun set_rev/2, kz_doc:revision(JObj)}])
                ]),
    PN.

maybe_migrate_features(PN, 'undefined') ->
    reset_features(PN);
maybe_migrate_features(PN, FeaturesList)
  when is_list(FeaturesList) ->
    Features1 = migrate_features(FeaturesList, doc(PN)),
    Features = maybe_rename_features(Features1),
    ?DIRTY(set_features(PN, Features));
maybe_migrate_features(PN, FeaturesJObj) ->
    Features = maybe_rename_features(FeaturesJObj),
    case kz_json:are_equal(FeaturesJObj, Features) of
        'true' -> set_features(PN, Features);
        'false' -> ?DIRTY(set_features(PN, Features))
    end.

%% Note: the above setters may not have set any features yet,
%% since more than one of them may set features.
-spec ensure_features_defined(record()) -> record().
ensure_features_defined(PN=#knm_phone_number{features = 'undefined'}) ->
    PN#knm_phone_number{features = ?DEFAULT_FEATURES};
ensure_features_defined(PN) -> PN.

ensure_pvt_state_legacy_undefined(PN, 'undefined') -> PN;
ensure_pvt_state_legacy_undefined(PN, _State) ->
    ?LOG_DEBUG("~s was set to ~p, moving to ~s", [?PVT_STATE_LEGACY, _State, kzd_phone_numbers:pvt_state_path()]),
    ?DIRTY(PN).

%% Handle moving away from provider-specific E911
maybe_rename_features(Features) ->
    Fs = kz_json:delete_keys([?LEGACY_DASH_E911, ?LEGACY_VITELITY_E911], Features),
    case {kz_json:get_ne_value(?LEGACY_DASH_E911, Features)
         ,kz_json:get_ne_value(?LEGACY_VITELITY_E911, Features)
         }
    of
        {'undefined', 'undefined'} -> Features;
        {Dash, 'undefined'} -> kz_json:set_value(?FEATURE_E911, Dash, Fs);
        {'undefined', Vitelity} -> kz_json:set_value(?FEATURE_E911, Vitelity, Fs);
        {_Dash, Vitelity} -> kz_json:set_value(?FEATURE_E911, Vitelity, Fs)
    end.

maybe_rename_public_features(JObj) ->
    case {kz_json:get_ne_value(?LEGACY_DASH_E911, JObj)
         ,kz_json:get_ne_value(?LEGACY_VITELITY_E911, JObj)
         }
    of
        {'undefined', 'undefined'} -> JObj;
        {Dash, 'undefined'} -> kz_json:set_value(?FEATURE_E911, Dash, JObj);
        {'undefined', Vitelity} -> kz_json:set_value(?FEATURE_E911, Vitelity, JObj);
        {_Dash, Vitelity} -> kz_json:set_value(?FEATURE_E911, Vitelity, JObj)
    end.

%% Handle 3.22 -> 4.0 features migration.
migrate_features(FeaturesList, JObj) ->
    F = fun (Feature, A) -> features_fold(Feature, A, JObj) end,
    lists:foldl(F, ?DEFAULT_FEATURES, FeaturesList).

%% Note: if a feature matches here that means it was enabled in 3.22.
features_fold(Feature=?FEATURE_FORCE_OUTBOUND, Acc, JObj) ->
    Data = kz_json:is_true(Feature, JObj),
    kz_json:set_value(Feature, Data, Acc);
features_fold(Feature=?FEATURE_RINGBACK, Acc, JObj) ->
    Data = kz_json:from_list(
             [{?RINGBACK_EARLY, kz_json:get_ne_value([Feature, ?RINGBACK_EARLY], JObj)}
             ,{?RINGBACK_TRANSFER, kz_json:get_ne_value([Feature, ?RINGBACK_TRANSFER], JObj)}
             ]),
    kz_json:set_value(Feature, Data, Acc);
features_fold(Feature=?FEATURE_FAILOVER, Acc, JObj) ->
    Data = kz_json:from_list(
             [{?FAILOVER_E164, kz_json:get_ne_value([Feature, ?FAILOVER_E164], JObj)}
             ,{?FAILOVER_SIP, kz_json:get_ne_value([Feature, ?FAILOVER_SIP], JObj)}
             ]),
    kz_json:set_value(Feature, Data, Acc);
features_fold(Feature=?FEATURE_PREPEND, Acc, JObj) ->
    IsEnabled = kz_json:is_true([Feature, ?PREPEND_ENABLED], JObj),
    Data0 = kz_json:get_ne_value(Feature, JObj, kz_json:new()),
    Data = kz_json:set_value(?PREPEND_ENABLED, IsEnabled, Data0),
    kz_json:set_value(Feature, Data, Acc);
features_fold(Feature=?FEATURE_CNAM_OUTBOUND, Acc, JObj) ->
    DisplayName = kz_json:get_ne_binary_value([?FEATURE_CNAM, ?CNAM_DISPLAY_NAME], JObj),
    Data = kz_json:from_list([{?CNAM_DISPLAY_NAME, DisplayName}]),
    kz_json:set_value(Feature, Data, Acc);
features_fold(?CNAM_INBOUND_LOOKUP=Feature, Acc, _) ->
    Data = kz_json:from_list([{Feature, 'true'}]),
    kz_json:set_value(?FEATURE_CNAM_INBOUND, Data, Acc);
features_fold(?LEGACY_DASH_E911=Feature, Acc, JObj) ->
    Data = kz_json:get_value(Feature, JObj),
    kz_json:set_value(?FEATURE_E911, Data, Acc);
features_fold(?LEGACY_VITELITY_E911=Feature, Acc, JObj) ->
    Data = kz_json:get_value(Feature, JObj),
    kz_json:set_value(?FEATURE_E911, Data, Acc);
features_fold(?LEGACY_TELNYX_E911=Feature, Acc, JObj) ->
    Data = kz_json:get_value(Feature, JObj),
    kz_json:set_value(?FEATURE_E911, Data, Acc);
features_fold(FeatureKey, Acc, JObj) ->
    %% Encompasses at least: ?FEATURE_PORT
    Data = kz_json:get_ne_value(FeatureKey, JObj, kz_json:new()),
    ?LOG_DEBUG("encompassed ~p ~s", [FeatureKey, kz_json:encode(Data)]),
    kz_json:set_value(FeatureKey, Data, Acc).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec from_json_with_options(kz_json:object(), record() | knm_options:options()) ->
          record().
from_json_with_options(JObj, #knm_phone_number{}=PN) ->
    Options = [{'dry_run', dry_run(PN)}
              ,{'batch_run', batch_run(PN)}
              ,{'mdn_run', mdn_run(PN)}
              ,{'auth_by', auth_by(PN)}
              ],
    from_json_with_options(JObj, Options);
from_json_with_options(JObj, Options)
  when is_list(Options) ->
    Updates = [{fun set_assign_to/2, knm_options:assign_to(Options)}
               %% See knm_options:default/0 for these 4.
              ,{fun set_dry_run/2, knm_options:dry_run(Options, 'false')}
              ,{fun set_batch_run/2, knm_options:batch_run(Options, 'false')}
              ,{fun set_mdn_run/2, knm_options:mdn_run(Options)}
              ,{fun set_auth_by/2, knm_options:auth_by(Options, ?KNM_DEFAULT_AUTH_BY)}
               |case props:is_defined('module_name', Options) of
                    'true' -> [{fun set_module_name/2, knm_options:module_name(Options)}];
                    'false' -> []
                end
              ],
    {'ok', PN} = setters(from_json(JObj), Updates),
    PN.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_phone_number(any()) -> boolean().
is_phone_number(#knm_phone_number{}) -> 'true';
is_phone_number(_) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec setters(knm_pipe:collection(), set_functions()) -> knm_pipe:collection();
             (record(), set_functions()) -> return().
setters(#knm_phone_number{}=PN, Routines) ->
    setters_pn(PN, Routines);
setters(T0, Routines) when is_map(T0) ->
    setters_collection(T0, Routines).

-spec setters_pn(record(), set_functions()) -> return().
setters_pn(PN, Routines) ->
    try lists:foldl(fun setters_fold/2, PN, Routines) of
        #knm_phone_number{}=NewPN -> {'ok', NewPN}
    catch
        'throw':{'stop', Error} -> Error;
        ?STACKTRACE('error', 'function_clause', ST)
        {FName, Arg} =
        case ST of
            [{'lists', 'foldl', [Name|_aPN], Arg2}|_] -> {Name, Arg2};
            [{_M, Name, [_aPN,Arg2|_], _Info}|_] -> {Name, Arg2}
        end,
        ?LOG_ERROR("~s failed, argument: ~p", [FName, Arg]),
        kz_log:log_stacktrace(ST),
        {'error', FName};
        ?STACKTRACE('error', Reason, ST)
        kz_log:log_stacktrace(ST),
        {'error', Reason}
        end.

-spec setters_collection(knm_pipe:collection(), set_functions()) -> knm_pipe:collection().
%% FIXME: opaque
setters_collection(T0=#{'todo' := PNs}, Routines) ->
    F = fun (#knm_phone_number{}=PN, T) ->
                case setters(PN, Routines) of
                    {'ok', #knm_phone_number{}=NewPN} -> knm_pipe:set_succeeded(T, NewPN);
                    {'error', R} -> knm_pipe:set_failed(T, number(PN), R)
                end
        end,
    lists:foldl(F, T0, PNs).

-type set_function() :: fun((record()) -> setter_acc()) |
                        fun((record(), V) -> setter_acc()) |
                        {fun((record(), V) -> setter_acc()), V} |
                         {fun((record(), K, V) -> setter_acc()), [K | V,...]} |
                          {fun((record(), K, V) -> setter_acc()), K, V}.
-type set_functions() :: [set_function()].

-type setter_acc() :: record().

-spec setters_fold(set_function(), record()) -> record().
setters_fold(_, {'error', _R}=Error) ->
    throw({'stop', Error});
setters_fold({Fun, Key, Value}, PN) when is_function(Fun, 3) ->
    setters_fold_apply(Fun, [PN, Key, Value]);
setters_fold({Fun, Value}, PN) when is_function(Fun, 2) ->
    setters_fold_apply(Fun, [PN, Value]);
setters_fold(Fun, PN) when is_function(Fun, 1) ->
    setters_fold_apply(Fun, [PN]).

-spec setters_fold_apply(set_function(), nonempty_list()) -> record().
setters_fold_apply(Fun, [{'ok',PN}|Args]) ->
    setters_fold_apply(Fun, [PN|Args]);
setters_fold_apply(Fun, Args) ->
    erlang:apply(Fun, Args).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec number(record()) -> kz_term:ne_binary().
number(#knm_phone_number{number=Num}) -> Num.

-spec set_number(record(), kz_term:ne_binary()) -> record().
set_number(PN, <<"+",_:8,_/binary>>=NormalizedNum) ->
    NumberDb = knm_converters:to_db(NormalizedNum),
    case {PN#knm_phone_number.number, PN#knm_phone_number.number_db} of
        {undefined, 'undefined'} ->
            PN#knm_phone_number{number = NormalizedNum
                               ,number_db = NumberDb
                               };
        {NormalizedNum, NumberDb} -> PN;
        _ ->
            ?DIRTY(PN#knm_phone_number{number = NormalizedNum
                                      ,number_db = NumberDb
                                      })
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec number_db(record()) -> kz_term:ne_binary().
number_db(#knm_phone_number{number_db=NumberDb}) -> NumberDb.

-spec rev(record()) -> kz_term:api_ne_binary().
rev(#knm_phone_number{rev=Rev}) -> Rev.

-spec set_rev(record(), kz_term:ne_binary()) -> record().
set_rev(N, ?NE_BINARY=Rev) -> N#knm_phone_number{rev=Rev}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec assign_to(record()) -> kz_term:api_ne_binary().
assign_to(#knm_phone_number{assign_to=AssignTo}) ->
    AssignTo.

%% This is not stored on number doc
-spec set_assign_to(record(), kz_term:api_ne_binary()) -> record().
set_assign_to(PN=#knm_phone_number{assign_to = V}, V) -> PN;
set_assign_to(PN, AssignTo=undefined) ->
    PN#knm_phone_number{assign_to = AssignTo};
set_assign_to(PN, AssignTo=?MATCH_ACCOUNT_RAW(_)) ->
    PN#knm_phone_number{assign_to = AssignTo}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec assigned_to(record()) -> kz_term:api_ne_binary().
assigned_to(#knm_phone_number{assigned_to=AssignedTo}) ->
    AssignedTo.

-spec set_assigned_to(record(), kz_term:api_ne_binary()) -> record().
set_assigned_to(PN=#knm_phone_number{assigned_to = V}, V) -> PN;
set_assigned_to(PN0, AssignedTo=undefined) ->
    PN = set_prev_assigned_to(PN0, assigned_to(PN0)),
    ?DIRTY(PN#knm_phone_number{assigned_to = AssignedTo
                              ,used_by = 'undefined'
                              });
set_assigned_to(PN0, AssignedTo=?MATCH_ACCOUNT_RAW(_)) ->
    PN = set_prev_assigned_to(PN0, assigned_to(PN0)),
    ?DIRTY(PN#knm_phone_number{assigned_to = AssignedTo
                              ,used_by = 'undefined'
                              }).

%% This is used only by from_json/1
-spec set_assigned_to(record(), kz_term:api_ne_binary(), kz_term:api_ne_binary()) -> record().
set_assigned_to(PN, AssignedTo=undefined, UsedBy=undefined) ->
    PN#knm_phone_number{assigned_to = AssignedTo
                       ,used_by = UsedBy
                       };
set_assigned_to(PN, AssignedTo=undefined, UsedBy=?NE_BINARY) ->
    PN#knm_phone_number{assigned_to = AssignedTo
                       ,used_by = UsedBy
                       };
set_assigned_to(PN, AssignedTo=?MATCH_ACCOUNT_RAW(_), UsedBy=undefined) ->
    PN#knm_phone_number{assigned_to = AssignedTo
                       ,used_by = UsedBy
                       };
set_assigned_to(PN, AssignedTo=?MATCH_ACCOUNT_RAW(_), UsedBy=?NE_BINARY) ->
    PN#knm_phone_number{assigned_to = AssignedTo
                       ,used_by = UsedBy
                       }.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec prev_assigned_to(record()) -> kz_term:api_ne_binary().
prev_assigned_to(#knm_phone_number{prev_assigned_to=PrevAssignedTo}) ->
    PrevAssignedTo.

%% Called from set_assigned_to/2 & from_json/1.
-spec set_prev_assigned_to(record(), kz_term:api_ne_binary()) -> record().
set_prev_assigned_to(PN=#knm_phone_number{prev_assigned_to = 'undefined'}
                    ,PrevAssignedTo=?MATCH_ACCOUNT_RAW(_)) ->
    PN#knm_phone_number{prev_assigned_to = PrevAssignedTo};

set_prev_assigned_to(PN, 'undefined') -> PN;

set_prev_assigned_to(PN=#knm_phone_number{prev_assigned_to = V}, V) -> PN;
set_prev_assigned_to(PN, PrevAssignedTo=?MATCH_ACCOUNT_RAW(_)) ->
    ?DIRTY(PN#knm_phone_number{prev_assigned_to = PrevAssignedTo}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec used_by(record()) -> kz_term:api_ne_binary().
used_by(#knm_phone_number{used_by=UsedBy}) -> UsedBy.

%% This is never called from from_json/1. See set_assigned_to/3
-spec set_used_by(record(), kz_term:api_ne_binary()) -> record().
set_used_by(PN=#knm_phone_number{used_by = V}, V) -> PN;
set_used_by(PN, UsedBy='undefined') ->
    ?LOG_DEBUG("unassigning ~s from ~s", [number(PN), PN#knm_phone_number.used_by]),
    ?DIRTY(PN#knm_phone_number{used_by = UsedBy});
set_used_by(PN, UsedBy=?NE_BINARY) ->
    ?LOG_DEBUG("assigning ~s to ~s from ~s", [number(PN), UsedBy, PN#knm_phone_number.used_by]),
    ?DIRTY(PN#knm_phone_number{used_by = UsedBy}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec features(record()) -> kz_json:object().
features(#knm_phone_number{features=Features}) -> Features.

-spec features_list(record()) -> kz_term:ne_binaries().
features_list(PN) ->
    lists:usort(kz_json:get_keys(features(PN))).

-spec set_features(record(), kz_json:object()) -> record().
set_features(PN=#knm_phone_number{features = 'undefined'}, Features) ->
    'true' = kz_json:is_json_object(Features),
    case kz_json:is_empty(Features) of
        'true' -> PN;  %% See last part of from_json/1
        'false' -> PN#knm_phone_number{features = Features}
    end;
set_features(PN, Features) ->
    'true' = kz_json:is_json_object(Features),
    case kz_json:are_equal(PN#knm_phone_number.features, Features) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{features = Features})
    end.

-spec feature(record(), kz_term:ne_binary()) -> kz_json:api_json_term().
feature(PN, Feature) ->
    kz_json:get_ne_value(Feature, features(PN)).

-spec set_feature(record(), kz_term:ne_binary(), kz_json:api_json_term()) ->
                         record().
set_feature(PN0, Feature=?NE_BINARY, Data) ->
    Features = case PN0#knm_phone_number.features of
                   'undefined' -> ?DEFAULT_FEATURES;
                   F -> F
               end,
    PN = set_features(PN0, kz_json:set_value(Feature, Data, Features)),
    PN#knm_phone_number.is_dirty
        andalso ?LOG_DEBUG("setting ~s feature ~s: ~s", [number(PN), Feature, kz_json:encode(Data)]),
    PN.

-spec reset_features(record()) -> record().
reset_features(PN=#knm_phone_number{module_name = ?CARRIER_LOCAL}) ->
    Features = kz_json:set_value(?FEATURE_LOCAL, local_feature(PN), ?DEFAULT_FEATURES),
    set_features(PN, Features);
reset_features(PN=#knm_phone_number{module_name = ?CARRIER_MDN}) ->
    Features = kz_json:set_value(?FEATURE_LOCAL, local_feature(PN), ?DEFAULT_FEATURES),
    set_features(PN, Features);
reset_features(PN) ->
    set_features(PN, ?DEFAULT_FEATURES).

-spec set_features_allowed(record(), kz_term:ne_binaries()) -> record().
set_features_allowed(PN=#knm_phone_number{features_allowed = 'undefined'}, Features) ->
    'true' = lists:all(fun kz_term:is_ne_binary/1, Features),
    PN#knm_phone_number{features_allowed = Features};
set_features_allowed(PN, Features) ->
    'true' = lists:all(fun kz_term:is_ne_binary/1, Features),
    case lists:usort(PN#knm_phone_number.features_allowed) =:= lists:usort(Features) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{features_allowed = Features})
    end.

-spec set_features_denied(record(), kz_term:ne_binaries()) -> record().
set_features_denied(PN=#knm_phone_number{features_denied = 'undefined'}, Features) ->
    'true' = lists:all(fun kz_term:is_ne_binary/1, Features),
    PN#knm_phone_number{features_denied = Features};
set_features_denied(PN, Features) ->
    'true' = lists:all(fun kz_term:is_ne_binary/1, Features),
    case lists:usort(PN#knm_phone_number.features_denied) =:= lists:usort(Features) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{features_denied = Features})
    end.

-spec add_allowed_feature(record(), kz_term:ne_binary()) -> record().
add_allowed_feature(PN=#knm_phone_number{features_allowed = Allowed}, Feature=?NE_BINARY) ->
    case lists:member(Feature, Allowed) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{features_allowed = [Feature|Allowed]})
    end.

-spec remove_allowed_feature(record(), kz_term:ne_binary()) -> record().
remove_allowed_feature(PN=#knm_phone_number{features_allowed = Allowed}, Feature=?NE_BINARY) ->
    case lists:member(Feature, Allowed) of
        'false' -> PN;
        'true' -> ?DIRTY(PN#knm_phone_number{features_allowed = lists:delete(Feature, Allowed)})
    end.

-spec add_denied_feature(record(), kz_term:ne_binary()) -> record().
add_denied_feature(PN=#knm_phone_number{features_denied = Denied}, Feature=?NE_BINARY) ->
    case lists:member(Feature, Denied) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{features_denied = [Feature|Denied]})
    end.

-spec remove_denied_feature(record(), kz_term:ne_binary()) -> record().
remove_denied_feature(PN=#knm_phone_number{features_denied = Denied}, Feature=?NE_BINARY) ->
    case lists:member(Feature, Denied) of
        'false' -> PN;
        'true' -> ?DIRTY(PN#knm_phone_number{features_denied = lists:delete(Feature, Denied)})
    end.

-spec features_allowed(record()) -> kz_term:ne_binaries().
features_allowed(#knm_phone_number{features_allowed = Features}) -> Features.

-spec features_denied(record()) -> kz_term:ne_binaries().
features_denied(#knm_phone_number{features_denied = Features}) -> Features.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec state(record()) -> kz_term:api_ne_binary().
state(#knm_phone_number{state=State}) -> State.

-spec set_state(record(), kz_term:ne_binary()) -> record().
set_state(PN=#knm_phone_number{state = V}, V) -> PN;
set_state(PN=#knm_phone_number{state = 'undefined'}, State) ->
    'true' = is_state(State),
    PN#knm_phone_number{state = State};
set_state(PN, State) ->
    'true' = is_state(State),
    ?LOG_DEBUG("updating state from ~s to ~s", [PN#knm_phone_number.state, State]),
    ?DIRTY(PN#knm_phone_number{state = State}).

-spec is_state(any()) -> boolean().
is_state(State)
  when State =:= ?NUMBER_STATE_PORT_IN;
       State =:= ?NUMBER_STATE_PORT_OUT;
       State =:= ?NUMBER_STATE_DISCOVERY;
       State =:= ?NUMBER_STATE_IN_SERVICE;
       State =:= ?NUMBER_STATE_RELEASED;
       State =:= ?NUMBER_STATE_RESERVED;
       State =:= ?NUMBER_STATE_AVAILABLE;
       State =:= ?NUMBER_STATE_DELETED;
       State =:= ?NUMBER_STATE_AGING
       -> 'true';
is_state(_) -> 'false'.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec reserve_history(record()) -> kz_term:ne_binaries().
reserve_history(#knm_phone_number{reserve_history=History}) -> History.

-spec set_reserve_history(record(), kz_term:ne_binaries()) -> record().
set_reserve_history(PN=#knm_phone_number{reserve_history = V}, V) -> PN;
set_reserve_history(PN0=#knm_phone_number{reserve_history = 'undefined'}, History)
  when is_list(History) ->
    PN1 = PN0#knm_phone_number{reserve_history=?DEFAULT_RESERVE_HISTORY},
    PN2 = lists:foldr(fun add_reserve_history/2, PN1, History),
    case not PN0#knm_phone_number.is_dirty
        andalso PN2#knm_phone_number.is_dirty
        andalso History =:= PN2#knm_phone_number.reserve_history
    of
        'false' -> PN2;
        %% Since add_reserve_history/2 is exported, it has to dirty things itself.
        %% Us reverting here is the only way to work around that.
        'true' ->
            dev:debug("undirty ~s", [number(PN2)]),
            PN2#knm_phone_number{is_dirty = 'false'
                                ,modified = PN0#knm_phone_number.modified
                                }
    end;
set_reserve_history(PN0, History)
  when is_list(History) ->
    PN1 = PN0#knm_phone_number{reserve_history=?DEFAULT_RESERVE_HISTORY},
    lists:foldr(fun add_reserve_history/2, PN1, History).

-spec add_reserve_history(kz_term:api_ne_binary(), record()) -> record().
add_reserve_history(undefined, PN) -> PN;
add_reserve_history(?MATCH_ACCOUNT_RAW(AccountId)
                   ,PN=#knm_phone_number{reserve_history=[AccountId|_]}
                   ) -> PN;
add_reserve_history(?MATCH_ACCOUNT_RAW(AccountId)
                   ,PN=#knm_phone_number{reserve_history=ReserveHistory}
                   ) ->
    ?DIRTY(PN#knm_phone_number{reserve_history=[AccountId|ReserveHistory]}).

-spec push_reserve_history(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
push_reserve_history(T=#{'todo' := PNs, 'options' := Options}) ->
    AssignTo = knm_options:assign_to(Options),
    NewPNs = [add_reserve_history(AssignTo, PN) || PN <- PNs],
    knm_pipe:set_succeeded(T, NewPNs).

-spec unwind_reserve_history(knm_pipe:collection() | record()) ->
                                    record() |
                                    knm_pipe:collection().
%% FIXME: opaque
unwind_reserve_history(T=#{'todo' := PNs}) ->
    NewPNs = [unwind_reserve_history(PN) || PN <- PNs],
    knm_pipe:set_succeeded(T, NewPNs);
unwind_reserve_history(PN0) ->
    case reserve_history(PN0) of
        [_AssignedTo, NewAssignedTo | NewReserveHistory] ->
            PN1 = set_assigned_to(PN0, NewAssignedTo),
            PN2 = set_reserve_history(PN1, [NewAssignedTo|NewReserveHistory]),
            set_state(PN2, ?NUMBER_STATE_RESERVED);
        _ ->
            PN1 = set_assigned_to(PN0, 'undefined'),
            PN2 = set_reserve_history(PN1, []),
            set_state(PN2, knm_config:released_state())
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec ported_in(record()) -> boolean().
ported_in(#knm_phone_number{ported_in=Ported}) -> Ported.

-spec set_ported_in(record(), boolean()) -> record().
set_ported_in(PN=#knm_phone_number{ported_in = V}, V) -> PN;
set_ported_in(PN=#knm_phone_number{ported_in = 'undefined'}, Ported)
  when is_boolean(Ported) ->
    PN#knm_phone_number{ported_in = Ported};
set_ported_in(PN, Ported) when is_boolean(Ported) ->
    ?LOG_DEBUG("updating ported_in from ~s to ~s", [PN#knm_phone_number.ported_in, Ported]),
    ?DIRTY(PN#knm_phone_number{ported_in = Ported}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec module_name(record()) -> kz_term:api_ne_binary().
module_name(#knm_phone_number{module_name = Name}) -> Name.

-spec set_module_name(record(), kz_term:ne_binary()) -> record().
%% knm_bandwidth is deprecated, updating to the new module
set_module_name(PN, <<"wnm_", Name/binary>>) ->
    ?DIRTY(set_module_name(PN, <<"knm_", Name/binary>>));
set_module_name(PN, <<"knm_bandwidth">>) ->
    ?DIRTY(set_module_name(PN, <<"knm_bandwidth2">>));
%% Some old docs have these as module name
set_module_name(PN, <<"undefined">>) ->
    ?DIRTY(set_module_name(PN, ?CARRIER_LOCAL));

set_module_name(PN, 'undefined') ->
    ?DIRTY(set_module_name(PN, ?CARRIER_LOCAL));

set_module_name(PN, ?CARRIER_LOCAL=Name) ->
    set_module_name_local(PN, Name);
set_module_name(PN, ?CARRIER_MDN=Name) ->
    set_module_name_local(PN, Name);

set_module_name(PN=#knm_phone_number{module_name = Name}, Name=?NE_BINARY) -> PN;

set_module_name(PN=#knm_phone_number{module_name = 'undefined', features = 'undefined'}
               ,Name=?NE_BINARY
               ) ->
    %% Only during from_json/1
    PN#knm_phone_number{module_name = Name};
set_module_name(PN0=#knm_phone_number{module_name = 'undefined', features = Features}
               ,Name=?NE_BINARY
               ) ->
    PN = PN0#knm_phone_number{module_name = Name},
    NewFeatures = kz_json:delete_key(?FEATURE_LOCAL, Features),
    set_features(PN, NewFeatures);

set_module_name(PN0, Name=?NE_BINARY) ->
    ?LOG_DEBUG("updating module_name from ~p to ~p", [PN0#knm_phone_number.module_name, Name]),
    PN = ?DIRTY(PN0#knm_phone_number{module_name = Name}),
    Features = kz_json:delete_key(?FEATURE_LOCAL, features(PN)),
    set_features(PN, Features).

set_module_name_local(PN=#knm_phone_number{module_name = Name}, Name) -> PN;
set_module_name_local(PN0=#knm_phone_number{module_name = 'undefined'}, Name) ->
    PN = set_feature(PN0, ?FEATURE_LOCAL, local_feature(PN0)),
    PN#knm_phone_number{module_name = Name};
set_module_name_local(PN0, Name) ->
    ?LOG_DEBUG("updating module_name from ~p to ~p", [PN0#knm_phone_number.module_name, Name]),
    PN = set_feature(PN0, ?FEATURE_LOCAL, local_feature(PN0)),
    ?DIRTY(PN#knm_phone_number{module_name = Name}).

local_feature(PN) ->
    case feature(PN, ?FEATURE_LOCAL) of
        'undefined' -> kz_json:new();
        LocalFeature -> LocalFeature
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec carrier_data(record()) -> kz_json:object().
carrier_data(#knm_phone_number{carrier_data=Data}) -> Data.

-spec set_carrier_data(record(), kz_term:api_object()) -> record().
set_carrier_data(PN=#knm_phone_number{carrier_data = 'undefined'}, 'undefined') ->
    set_carrier_data(PN, ?DEFAULT_CARRIER_DATA);
set_carrier_data(PN=#knm_phone_number{carrier_data = 'undefined'}, Data) ->
    'true' = kz_json:is_json_object(Data),
    PN#knm_phone_number{carrier_data = Data};
set_carrier_data(PN, 'undefined') ->
    set_carrier_data(PN, ?DEFAULT_CARRIER_DATA);
set_carrier_data(PN, Data) ->
    'true' = kz_json:is_json_object(Data),
    case kz_json:are_equal(PN#knm_phone_number.carrier_data, Data) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{carrier_data = Data})
    end.

-spec update_carrier_data(record(), kz_json:object()) -> record().
update_carrier_data(PN=#knm_phone_number{carrier_data = Data}, JObj) ->
    'true' = kz_json:is_json_object(JObj),
    Updated = kz_json:merge(JObj, Data),
    case kz_json:are_equal(PN#knm_phone_number.carrier_data, Updated) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{carrier_data = Updated})
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec region(record()) -> kz_term:api_ne_binary().
region(#knm_phone_number{region=Region}) -> Region.

-spec set_region(record(), kz_term:api_ne_binary()) -> record().
set_region(PN=#knm_phone_number{region = V}, V) -> PN;
set_region(PN=#knm_phone_number{region = 'undefined'}, Region=?NE_BINARY) ->
    PN#knm_phone_number{region = Region};
set_region(PN, Region='undefined') ->
    ?LOG_DEBUG("updating region from ~s to ~s", [PN#knm_phone_number.region, Region]),
    ?DIRTY(PN#knm_phone_number{region = Region});
set_region(PN, Region=?NE_BINARY) ->
    ?LOG_DEBUG("updating region from ~s to ~s", [PN#knm_phone_number.region, Region]),
    ?DIRTY(PN#knm_phone_number{region = Region}).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec auth_by(record()) -> kz_term:api_ne_binary().
auth_by(#knm_phone_number{auth_by=AuthBy}) -> AuthBy.

-spec set_auth_by(record(), kz_term:api_ne_binary()) -> record().
set_auth_by(PN, AuthBy='undefined') ->
    PN#knm_phone_number{auth_by=AuthBy};
set_auth_by(PN, AuthBy=?KNM_DEFAULT_AUTH_BY) ->
    PN#knm_phone_number{auth_by=AuthBy};
set_auth_by(PN, ?MATCH_ACCOUNT_RAW(AuthBy)) ->
    PN#knm_phone_number{auth_by=AuthBy}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_admin(record() | kz_term:api_ne_binary()) -> boolean().
is_admin(#knm_phone_number{auth_by=AuthBy}) -> is_admin(AuthBy);
is_admin(?KNM_DEFAULT_AUTH_BY) ->
    ?LOG_INFO("bypassing auth"),
    'true';
is_admin(AuthBy) ->
    kzd_accounts:is_superduper_admin(AuthBy).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_dirty(record()) -> boolean().
is_dirty(#knm_phone_number{is_dirty = IsDirty}) -> IsDirty.

-spec set_dirty(record(), boolean()) -> record().
set_dirty(PN, IsDirty) when is_boolean(IsDirty) -> PN#knm_phone_number{is_dirty = IsDirty}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec dry_run(record()) -> boolean().
dry_run(#knm_phone_number{dry_run=DryRun}) -> DryRun.

-spec set_dry_run(record(), boolean()) -> record().
set_dry_run(PN, DryRun) when is_boolean(DryRun) ->
    PN#knm_phone_number{dry_run=DryRun}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec batch_run(record()) -> boolean().
batch_run(#knm_phone_number{batch_run=BatchRun}) -> BatchRun.

-spec set_batch_run(record(), boolean()) -> record().
set_batch_run(PN, BatchRun) when is_boolean(BatchRun) ->
    PN#knm_phone_number{batch_run=BatchRun}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec mdn_run(record()) -> boolean().
mdn_run(#knm_phone_number{mdn_run=MDNRun}) -> MDNRun.

-spec set_mdn_run(record(), boolean()) -> record().
set_mdn_run(PN, MDNRun) when is_boolean(MDNRun) ->
    PN#knm_phone_number{mdn_run=MDNRun}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec locality(record()) -> kz_json:object().
locality(#knm_phone_number{locality=Locality}) -> Locality.

-spec set_locality(record(), kz_json:object()) -> record().
set_locality(PN=#knm_phone_number{locality = 'undefined'}, JObj) ->
    'true' = kz_json:is_json_object(JObj),
    PN#knm_phone_number{locality = JObj};
set_locality(PN, JObj) ->
    'true' = kz_json:is_json_object(JObj),
    case kz_json:are_equal(JObj, PN#knm_phone_number.locality) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{locality = JObj})
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec doc(record()) -> kz_json:object().
doc(#knm_phone_number{doc=Doc}) -> Doc.

-spec set_doc(record(), kz_json:object()) -> record().
set_doc(PN=#knm_phone_number{doc = 'undefined'}, JObj0) ->
    'true' = kz_json:is_json_object(JObj0),
    JObj = doc_from_public_fields(JObj0),
    case kz_json:are_equal(JObj, JObj0) of
        'true' -> PN#knm_phone_number{doc = JObj};
        'false' -> ?DIRTY(PN#knm_phone_number{doc = JObj})
    end;
set_doc(PN, JObj0) ->
    'true' = kz_json:is_json_object(JObj0),
    JObj = doc_from_public_fields(JObj0),
    case kz_json:are_equal(JObj, PN#knm_phone_number.doc) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{doc = JObj})
    end.

-spec update_doc(record(), kz_json:object()) -> record().
update_doc(PN=#knm_phone_number{doc = Doc}, JObj0) ->
    'true' = kz_json:is_json_object(JObj0),
    JObj1 = kz_json:merge(Doc, kz_doc:public_fields(JObj0)),
    JObj = doc_from_public_fields(JObj1),
    case kz_json:are_equal(JObj, PN#knm_phone_number.doc) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{doc = JObj})
    end.

-spec reset_doc(record(), kz_json:object()) -> record().
reset_doc(PN=#knm_phone_number{doc = Doc}, JObj0) ->
    'true' = kz_json:is_json_object(JObj0),
    JObj1 = kz_json:merge(kz_doc:public_fields(JObj0), kz_doc:private_fields(Doc)),
    JObj = doc_from_public_fields(JObj1),
    case kz_json:are_equal(JObj, PN#knm_phone_number.doc) of
        'true' -> PN;
        'false' -> ?DIRTY(PN#knm_phone_number{doc = JObj})
    end.

-spec reset_doc(record()) -> record().
reset_doc(PN) ->
    reset_doc(PN, kz_json:new()).

doc_from_public_fields(JObj) ->
    maybe_rename_public_features(
      sanitize_public_fields(JObj)).

%% @doc only return 'true' if deleted, otherwise 'undefined', for filtering
-spec is_deleted(record()) -> 'true' | 'undefined'.
is_deleted(#knm_phone_number{doc=JObj}) ->
    case kz_doc:is_deleted(JObj)
        orelse kz_doc:is_soft_deleted(JObj)
    of
        'true' -> 'true';
        'false' -> 'undefined'
    end.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec current_doc(record()) -> kz_json:object().
current_doc(#knm_phone_number{current_doc=Doc}) -> Doc.

-spec set_current_doc(record(), kz_json:object()) -> record().
set_current_doc(PN=#knm_phone_number{}, JObj) ->
    %% Only during from_json/1
    'true' = kz_json:is_json_object(JObj),
    PN#knm_phone_number{current_doc = JObj}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec modified(record()) -> kz_time:gregorian_seconds().
modified(#knm_phone_number{modified = 'undefined'}) -> kz_time:now_s();
modified(#knm_phone_number{modified = Modified}) -> Modified.

-spec set_modified(record(), kz_time:gregorian_seconds() | 'undefined') -> record().
set_modified(PN=#knm_phone_number{modified = 'undefined'}, 'undefined') ->
    ?DIRTY(PN#knm_phone_number{modified = kz_time:now_s()});
set_modified(PN=#knm_phone_number{modified = V}, V) -> PN;
set_modified(PN, Modified)
  when is_integer(Modified), Modified > 0 ->
    PN#knm_phone_number{modified = Modified}.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec created(record()) -> kz_time:gregorian_seconds().
created(#knm_phone_number{created = 'undefined'}) -> kz_time:now_s();
created(#knm_phone_number{created = Created}) -> Created.

-spec set_created(record(), kz_time:gregorian_seconds()) -> record().
set_created(PN=#knm_phone_number{created = 'undefined'}, Created)
  when is_integer(Created), Created > 0 ->
    PN#knm_phone_number{created = Created};
set_created(PN=#knm_phone_number{created = 'undefined'}, 'undefined') ->
    ?DIRTY(PN#knm_phone_number{created = kz_time:now_s()});
set_created(PN=#knm_phone_number{created = V}, V) -> PN;
set_created(PN, Created)
  when is_integer(Created), Created > 0 ->
    ?DIRTY(PN#knm_phone_number{created = Created}).

-spec remove_denied_features(record()) -> record().
remove_denied_features(PN) ->
    DeniedFeatures = knm_providers:features_denied(PN),
    RemoveFromPvt = lists:usort(lists:flatmap(fun remove_in_private/1, DeniedFeatures)),
    RemoveFromPub = lists:usort(lists:flatmap(fun remove_in_public/1, DeniedFeatures)),
    ?LOG_WARNING("removing out of sync pvt features: ~s"
                ,[kz_term:iolist_join($,, lists:usort([ToRm || [ToRm|_] <- RemoveFromPvt]))]
                ),
    ?LOG_WARNING("removing out of sync pub features: ~s"
                ,[kz_term:iolist_join($,, lists:usort([ToRm || [ToRm|_] <- RemoveFromPub]))]
                ),
    NewPvt = kz_json:prune_keys(RemoveFromPvt, features(PN)),
    NewPub = kz_json:prune_keys(RemoveFromPub, doc(PN)),
    Updates = [{fun set_features/2, NewPvt}
              ,{fun set_doc/2, NewPub}
              ],
    {'ok', NewPN} = setters(PN, Updates),
    NewPN.

-spec remove_in_private(kz_term:ne_binary()) -> [kz_json:path()].
remove_in_private(Feature) ->
    case maps:is_key(Feature, private_to_public()) of
        'false' -> [];
        'true' -> [[Feature]]
    end.

-spec remove_in_public(kz_term:ne_binary()) -> [kz_json:path()].
remove_in_public(Feature) ->
    maps:get(Feature, private_to_public(), []).

-spec private_to_public() -> map().
private_to_public() ->
    E911Pub = [[?FEATURE_E911]
              ,[?LEGACY_VITELITY_E911]
              ,[?LEGACY_DASH_E911]
              ,[?LEGACY_TELNYX_E911]
              ],
    CNAMPub = [[?FEATURE_CNAM, ?CNAM_INBOUND_LOOKUP]
              ,[?FEATURE_CNAM, ?CNAM_DISPLAY_NAME]
              ],
    PrependPub = [[?FEATURE_PREPEND, ?PREPEND_ENABLED]
                 ,[?FEATURE_PREPEND, ?PREPEND_NAME]
                 ,[?FEATURE_PREPEND, ?PREPEND_NUMBER]
                 ],
    FailoverPub = [[?FEATURE_FAILOVER, ?FAILOVER_E164]
                  ,[?FEATURE_FAILOVER, ?FAILOVER_SIP]
                  ],
    RingbackPub = [[?FEATURE_RINGBACK, ?RINGBACK_EARLY]
                  ,[?FEATURE_RINGBACK, ?RINGBACK_TRANSFER]
                  ],
    #{?FEATURE_E911 => E911Pub
     ,?LEGACY_VITELITY_E911 => E911Pub
     ,?LEGACY_DASH_E911 => E911Pub
     ,?LEGACY_TELNYX_E911 => E911Pub
     ,?FEATURE_CNAM => CNAMPub
     ,?FEATURE_CNAM_INBOUND => CNAMPub
     ,?FEATURE_CNAM_OUTBOUND => CNAMPub
     ,?FEATURE_PREPEND => PrependPub
     ,?FEATURE_FAILOVER => FailoverPub
     ,?FEATURE_RINGBACK => RingbackPub
     ,?FEATURE_FORCE_OUTBOUND => [[?FEATURE_FORCE_OUTBOUND]]
     ,?FEATURE_SMS => [[?FEATURE_SMS]]
     ,?FEATURE_MMS => [[?FEATURE_MMS]]
     }.

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec list_attachments(record(), kz_term:ne_binary()) ->
          {'ok', kz_json:object()} |
          {'error', any()}.
list_attachments(PN, AuthBy) ->
    AssignedTo = assigned_to(PN),
    case state(PN) =:= ?NUMBER_STATE_PORT_IN
        andalso is_in_account_hierarchy(AuthBy, AssignedTo)
    of
        'true' -> {'ok', kz_doc:attachments(doc(PN), kz_json:new())};
        'false' -> {'error', 'unauthorized'}
    end.

%%------------------------------------------------------------------------------
%% @doc Sanitize phone number docs fields and remove deprecated fields
%% @end
%%------------------------------------------------------------------------------
-spec sanitize_public_fields(kz_json:object()) -> kz_json:object().
sanitize_public_fields(JObj) ->
    Keys = [<<"id">>
           ,<<"used_by">>
           ],
    kz_json:delete_keys(Keys, kz_doc:public_fields(JObj)).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_authorized(record() | knm_pipe:collection()) ->
                           knm_pipe:collection() |
                           boolean().
is_authorized(T) when is_map(T) -> is_authorized_collection(T);
is_authorized(#knm_phone_number{auth_by = ?KNM_DEFAULT_AUTH_BY}) -> 'true';
is_authorized(#knm_phone_number{auth_by = 'undefined'}) -> 'false';
is_authorized(#knm_phone_number{assigned_to = 'undefined'
                               ,assign_to = 'undefined'
                               ,auth_by = AuthBy
                               }) ->
    ?LOG_DEBUG("assigns all 'undefined', checking if auth is super duper"),
    is_admin(AuthBy);
is_authorized(#knm_phone_number{assigned_to = 'undefined'
                               ,assign_to = AssignTo
                               ,auth_by = AuthBy
                               }) ->
    is_admin_or_in_account_hierarchy(AuthBy, AssignTo);
is_authorized(#knm_phone_number{assigned_to = AssignedTo
                               ,auth_by = AuthBy
                               }) ->
    is_admin_or_in_account_hierarchy(AuthBy, AssignedTo).

-spec is_reserved_from_parent(record() | knm_pipe:collection()) ->
                                     knm_pipe:collection() |
                                     boolean().
is_reserved_from_parent(T) when is_map(T) -> is_reserved_from_parent_collection(T);
is_reserved_from_parent(#knm_phone_number{assigned_to = ?MATCH_ACCOUNT_RAW(AssignedTo)
                                         ,auth_by = AuthBy
                                         ,state = ?NUMBER_STATE_RESERVED
                                         }) ->
    Authorized = is_admin_or_in_account_hierarchy(AssignedTo, AuthBy),
    Authorized
        andalso ?LOG_DEBUG("is reserved from parent, allowing"),
    Authorized;
is_reserved_from_parent(_) -> 'false'.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec is_admin_or_in_account_hierarchy(kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_admin_or_in_account_hierarchy(AuthBy, AccountId) ->
    case is_admin(AuthBy) of
        'true' ->
            ?LOG_DEBUG("auth is admin"),
            'true';
        'false' ->
            ?LOG_DEBUG("is authz ~s ~s", [AuthBy, AccountId]),
            is_in_account_hierarchy(AuthBy, AccountId)
    end.

-spec is_in_account_hierarchy(kz_term:ne_binary(), kz_term:ne_binary()) -> boolean().
is_in_account_hierarchy(AuthBy, AccountId) ->
    kzd_accounts:is_in_account_hierarchy(AuthBy, AccountId, 'true').

-spec is_authorized_collection(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
is_authorized_collection(T0=#{'todo' := PNs}) ->
    Reason = error_unauthorized(),
    F = fun (PN, T) ->
                case is_authorized(PN) of
                    'true' -> knm_pipe:set_succeeded(T, PN);
                    'false' -> knm_pipe:set_failed(T, number(PN), Reason)
                end
        end,
    lists:foldl(F, T0, PNs).

-spec is_reserved_from_parent_collection(knm_pipe:collection()) -> knm_pipe:collection().
%% FIXME: opaque
is_reserved_from_parent_collection(T0=#{'todo' := PNs}) ->
    Reason = error_unauthorized(),
    F = fun (PN, T) ->
                case is_authorized(PN)
                    orelse is_reserved_from_parent(PN)
                of
                    'true' -> knm_pipe:set_succeeded(T, PN);
                    'false' -> knm_pipe:set_failed(T, number(PN), Reason)
                end
        end,
    lists:foldl(F, T0, PNs).

error_unauthorized() ->
    {'error', A} = (catch knm_errors:unauthorized()),
    knm_errors:to_json(A).

%%------------------------------------------------------------------------------
%% @doc
%% @end
%%------------------------------------------------------------------------------
-spec save_to_number_db(knm_pipe:collection()) -> knm_pipe:collection().
save_to_number_db(T0) ->
    save_to(fun group_phone_number_by_number_db/2, fun database_error/3, T0).

%%------------------------------------------------------------------------------
%% @doc Makes sure number is assigned to assigned_to by creating number doc
%% that may not yet exist in AssignedTo DB.
%% @end
%%------------------------------------------------------------------------------
assign(T0) ->
    save_to(fun group_phone_number_by_assigned_to/2, fun assign_failure/3, T0).

%%------------------------------------------------------------------------------
%% @doc Makes sure number is unassigned from prev_assigned_to by removing
%% number doc that may still exist in PrevAssignedTo DB.
%% @end
%%------------------------------------------------------------------------------
-spec unassign_from_prev(knm_pipe:collection()) -> knm_pipe:collection().
unassign_from_prev(T0) ->
    ?LOG_DEBUG("unassign_from_prev"),
    try_delete_from(fun group_phone_number_by_prev_assigned_to/2, T0, 'true').

try_delete_number_doc(T0) ->
    ?LOG_DEBUG("try_delete_number_doc"),
    try_delete_from(fun group_phone_number_by_number_db/2, T0).

try_delete_account_doc(T0) ->
    ?LOG_DEBUG("try_delete_account_doc"),
    try_delete_from(fun group_phone_number_by_assigned_to/2, T0).

-spec try_delete_from(group_by_fun(), knm_pipe:collection()) -> knm_pipe:collection().
try_delete_from(GroupFun, T0) ->
    try_delete_from(GroupFun, T0, 'false').

-spec try_delete_from(group_by_fun(), knm_pipe:collection(), boolean()) -> knm_pipe:collection().
try_delete_from(GroupFun, T0, IgnoreDbNotFound) ->
    F = fun(Db, PNs, T) -> delete_from_fold(Db, PNs, T, IgnoreDbNotFound) end,
    maps:fold(F, T0, group_by(knm_pipe:todo(T0), GroupFun)).

delete_from_fold('undefined', PNs, T, _IgnoreDbNotFound) ->
    ?LOG_DEBUG("skipping: no db for ~s", [[[number(PN),$\s] || PN <- PNs]]),
    knm_pipe:add_succeeded(T, PNs);
delete_from_fold(_Db, [], T, _IgnoreDbNotFound) ->
    ?LOG_DEBUG("skipping, no phone numbers to delete"),
    knm_pipe:add_succeeded(T, []);
delete_from_fold(Db, PNs, T, IgnoreDbNotFound) ->
    Nums = [number(PN) || PN <- PNs],
    ?LOG_DEBUG("deleting from ~s: ~p", [Db, Nums]),
    case delete_docs(Db, Nums) of
        {'ok', []} ->
            ?LOG_DEBUG("no docs were deleted"),
            knm_pipe:add_succeeded(T, PNs);
        {'ok', JObjs} ->
            ?LOG_DEBUG("deleted docs: ~p", [JObjs]),
            RetryF = fun(Db1, PNs1, Num, T1) ->
                             retry_delete(Db1, PNs1, fun database_error/3, Num, T1)
                     end,
            handle_bulk_change(Db, JObjs, PNs, T, fun database_error/3, RetryF);
        {'error', 'not_found'} when IgnoreDbNotFound ->
            ?LOG_DEBUG("db ~s does not exist, ignoring", [Db]),
            knm_pipe:add_succeeded(T, PNs);
        {'error', E} ->
            ?LOG_ERROR("failed to delete from ~s (~p): ~p", [Db, E, Nums]),
            database_error(Nums, E, T)
    end.

-spec existing_db_key(kz_term:ne_binary()) -> kz_term:api_ne_binary().
existing_db_key(Db) ->
    case kz_datamgr:db_exists(Db) of
        'false' -> 'undefined';
        _ -> Db
    end.

-spec save_to(group_by_fun(), bulk_change_error_fun(), knm_pipe:collection()) -> knm_pipe:collection().
save_to(GroupFun, ErrorF, T0) ->
    F = fun FF ('undefined', PNs, T) ->
                %% NumberDb can never be 'undefined', AccountDb can.
                ?LOG_DEBUG("no db for ~p", [[number(PN) || PN <- PNs]]),
                knm_pipe:add_succeeded(T, PNs);
            FF (Db, PNs, T) ->
                ?LOG_DEBUG("saving to ~s", [Db]),
                Docs = [to_json(PN) || PN <- PNs],
                IsNumberDb = 'numbers' =:= kz_datamgr:db_classification(Db),
                case save_docs(Db, Docs) of
                    {'ok', JObjs} ->
                        RetryF = fun(Db1, PNs1, Num, T1) ->
                                         retry_save(Db1, PNs1, ErrorF, Num, T1)
                                 end,
                        handle_bulk_change(Db, JObjs, PNs, T, ErrorF, RetryF);
                    {'error', 'not_found'} when IsNumberDb ->
                        Nums = [kz_doc:id(Doc) || Doc <- Docs],
                        ?LOG_DEBUG("creating new number db '~s' for numbers ~p", [Db, Nums]),
                        'true' = kz_datamgr:db_create(Db),
                        _ = kapps_maintenance:refresh(Db),
                        FF(Db, PNs, T);
                    {'error', E} ->
                        Nums = [kz_doc:id(Doc) || Doc <- Docs],
                        ?LOG_ERROR("failed to assign numbers to ~s (~p): ~p", [Db, E, Nums]),
                        database_error(Nums, E, T)
                end
        end,
    maps:fold(F, T0, group_by(knm_pipe:todo(T0), GroupFun)).

%%------------------------------------------------------------------------------
%% @doc Works the same with the output of save_docs and del_docs
%% @end
%%------------------------------------------------------------------------------
-spec handle_bulk_change(kz_term:ne_binary(), kz_json:objects(), records() | grouped_phone_number()
                        ,knm_pipe:collection(), bulk_change_error_fun(), bulk_change_retry_fun()
                        ) -> knm_pipe:collection().
handle_bulk_change(Db, JObjs, PNsMap, T0, ErrorF, RetryF)
  when is_map(PNsMap) ->
    F = fun(JObj, T) -> handle_bulk_change_fold(JObj, T, Db, PNsMap, ErrorF) end,
    retry_conflicts(lists:foldl(F, T0, JObjs), Db, PNsMap, RetryF);
handle_bulk_change(Db, JObjs, PNs, T, ErrorF, RetryF) ->
    PNsMap = group_by(PNs, fun group_phone_number_by_number/2),
    handle_bulk_change(Db, JObjs, PNsMap, T, ErrorF, RetryF).

handle_bulk_change_fold(JObj, T, Db, PNsMap, ErrorF) ->
    Num = kz_json:get_ne_value(<<"id">>, JObj),
    Revision = kz_doc:revision(JObj),
    case kz_json:get_ne_value(<<"ok">>, JObj) =:= 'true'
        orelse Revision =/= 'undefined'
    of
        'true' ->
            ?LOG_DEBUG("successfully changed ~s in ~s", [Num, Db]),
            knm_pipe:set_succeeded(T, maps:get(Num, PNsMap));
        'false' ->
            %% Weirdest thing here is on conflict doc was actually properly saved!
            R = kz_json:get_ne_value(<<"error">>, JObj),
            ?LOG_WARNING("error changing ~s in ~s: ~s", [Num, Db, kz_json:encode(JObj)]),
            ErrorF(Num, kz_term:to_atom(R, 'true'), T)
    end.

-spec retry_save(kz_term:ne_binary(), grouped_phone_number(), bulk_change_error_fun(), kz_term:ne_binary(), knm_pipe:collection()) ->
                        knm_pipe:collection().
retry_save(Db, PNsMap, ErrorF, Num, T) ->
    PN = maps:get(Num, PNsMap),
    Update = kz_json:to_proplist(kz_doc:delete_revision(to_json(PN))),
    case kz_datamgr:update_doc(Db, Num, [{'update', Update}
                                        ,{'ensure_saved', 'true'}
                                        ])
    of
        {'ok', _} -> knm_pipe:set_succeeded(T, PN);
        {'error', R} -> ErrorF(Num, R, T)
    end.

-spec retry_delete(kz_term:ne_binary(), grouped_phone_number(), bulk_change_error_fun(), kz_term:ne_binary(), knm_pipe:collection()) ->
                          knm_pipe:collection().
retry_delete(Db, PNsMap, ErrorF, Num, T) ->
    case kz_datamgr:del_doc(Db, Num) of
        {'ok', _Deleted} -> knm_pipe:set_succeeded(T, maps:get(Num, PNsMap));
        {'error', R} -> ErrorF(Num, R, T)
    end.

-spec retry_conflicts(knm_pipe:collection(), kz_term:ne_binary(), grouped_phone_number(), bulk_change_retry_fun()) ->
                             knm_pipe:collection().
retry_conflicts(T0, Db, PNsMap, RetryF) ->
    {Conflicts, BaseT} = take_conflits(T0),
    fold_retry(RetryF, Db, PNsMap, Conflicts, BaseT).

%% FIXME: opaque
take_conflits(T=#{'failed' := Failed}) ->
    F = fun ({_Num, R}) when is_atom(R) -> 'false';
            ({_Num, R}) -> knm_errors:cause(R) =:= <<"conflict">>
        end,
    {Conflicts, NewFailed} = lists:partition(F, maps:to_list(Failed)),
    {Nums, _} = lists:unzip(Conflicts),
    {Nums, knm_pipe:set_failed(T, maps:from_list(NewFailed))}.

-spec fold_retry(bulk_change_retry_fun(), kz_term:ne_binary(), grouped_phone_number(), kz_term:ne_binaries(), knm_pipe:collection()) ->
                        knm_pipe:collection().
fold_retry(_, _, _, [], T) -> T;
fold_retry(RetryF, Db, PNsMap, [Conflict|Conflicts], T0) ->
    ?LOG_WARNING("~s conflicted, retrying", [Conflict]),
    T = RetryF(Db, PNsMap, Conflict, T0),
    fold_retry(RetryF, Db, PNsMap, Conflicts, T).

assign_failure(NumOrNums, E, T) ->
    {'error', A, B, C} = (catch knm_errors:assign_failure('undefined', E)),
    Reason = knm_errors:to_json(A, B, C),
    knm_pipe:set_failed(T, NumOrNums, Reason).

database_error(NumOrNums, E, T) ->
    {'error', A, B, C} = (catch knm_errors:database_error(E, 'undefined')),
    Reason = knm_errors:to_json(A, B, C),
    knm_pipe:set_failed(T, NumOrNums, Reason).

-spec delete_docs(kz_term:ne_binary(), kz_term:ne_binaries()) ->
                         {'ok', kz_json:objects()} |
                         {'error', kz_data:data_errors()}.
delete_docs(Db, Ids) ->
    %% Note: deleting nonexistent docs returns ok.
    kz_datamgr:del_docs(Db, Ids).

-spec save_docs(kz_term:ne_binary(), kz_json:objects()) ->
                       {'ok', kz_json:objects()} |
                       {'error', kz_data:data_errors()}.
save_docs(Db, Docs) ->
    kz_datamgr:save_docs(Db, prepare_docs(Db, Docs, [])).

-spec prepare_docs(kz_term:ne_binary(), kz_json:objects(), kz_json:objects()) ->
                          kz_json:objects().
prepare_docs(_Db, [], Updated) ->
    Updated;
prepare_docs(Db, [Doc|Docs], Updated) ->
    case kz_datamgr:lookup_doc_rev(Db, kz_doc:id(Doc)) of
        {'ok', Rev} ->
            prepare_docs(Db, Docs, [kz_doc:set_revision(Doc, Rev)|Updated]);
        {'error', _} ->
            prepare_docs(Db, Docs, [kz_doc:delete_revision(Doc)|Updated])
    end.

%%%=============================================================================
%%% Group things functions
%%%=============================================================================

-type group_by_fun() :: fun((kz_term:ne_binary(), record()) -> group_by_return()).
-type group_by_return() :: grouped_binaries() |
                           grouped_phone_number() |
                           grouped_phone_numbers().

-type grouped_binaries() :: #{kz_term:ne_binary() => kz_term:ne_binaries()}.
-type grouped_phone_number() :: #{kz_term:ne_binary() => record()}.
-type grouped_phone_numbers() :: #{kz_term:api_ne_binary() => records()}.

%%------------------------------------------------------------------------------
%% @doc Generic group by function, groups/split things using a group function.
%% @end
%%------------------------------------------------------------------------------
-spec group_by(kz_term:ne_binaries() | records(), group_by_fun()) -> group_by_return().
group_by(Things, GroupFun)
  when is_list(Things),
       is_function(GroupFun, 2) ->
    lists:foldl(GroupFun, #{}, Things).

%%------------------------------------------------------------------------------
%% @doc Group numbers by their database name.
%% @end
%%------------------------------------------------------------------------------
-spec group_number_by_db(kz_term:ne_binary(), grouped_binaries()) -> grouped_binaries().
group_number_by_db(Number, MapAcc) ->
    Key = knm_converters:to_db(Number),
    MapAcc#{Key => [Number | maps:get(Key, MapAcc, [])]}.

-spec group_phone_number_by_number(record(), grouped_phone_number()) ->
                                          grouped_phone_number().
group_phone_number_by_number(PN, MapAcc) ->
    MapAcc#{number(PN) => PN}.

-spec group_phone_number_by_number_db(record(), grouped_phone_numbers()) -> grouped_phone_numbers().
group_phone_number_by_number_db(PN, MapAcc) ->
    Key = number_db(PN),
    MapAcc#{Key => [PN | maps:get(Key, MapAcc, [])]}.

-spec group_phone_number_by_assigned_to(record(), grouped_phone_numbers()) -> grouped_phone_numbers().
group_phone_number_by_assigned_to(PN, MapAcc) ->
    AssignedTo = assigned_to(PN),
    Key = case kz_term:is_empty(AssignedTo) of
              'true' -> 'undefined';
              'false' -> existing_db_key(kzs_util:format_account_db(AssignedTo))
          end,
    MapAcc#{Key => [PN | maps:get(Key, MapAcc, [])]}.

-spec group_phone_number_by_prev_assigned_to(record(), grouped_phone_numbers()) -> grouped_phone_numbers().
group_phone_number_by_prev_assigned_to(PN, MapAcc) ->
    PrevAssignedTo = prev_assigned_to(PN),
    PrevIsCurrent = assigned_to(PN) =:= PrevAssignedTo,
    Key = case PrevIsCurrent
              orelse kz_term:is_empty(PrevAssignedTo)
          of
              'true' when PrevIsCurrent ->
                  ?LOG_DEBUG("~s prev_assigned_to is same as assigned_to,"
                              " not unassign-ing from prev", [number(PN)]
                             ),
                  'undefined';
              'true' ->
                  ?LOG_DEBUG("prev_assigned_to is empty for ~s, ignoring", [number(PN)]),
                  'undefined';
              'false' -> existing_db_key(kzs_util:format_account_db(PrevAssignedTo))
          end,
    MapAcc#{Key => [PN | maps:get(Key, MapAcc, [])]}.

-spec on_success(record()) -> callbacks().
on_success(#knm_phone_number{on_success = CB}) -> CB.

-spec add_on_success(record(), callback()) -> record().
add_on_success(PN = #knm_phone_number{on_success = CB}, Callback) ->
    PN#knm_phone_number{on_success = [Callback | CB]}.

-spec reset_on_success(record()) -> record().
reset_on_success(PN = #knm_phone_number{}) ->
    PN#knm_phone_number{on_success = []}.
