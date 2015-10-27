%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2014, 2600Hz INC
%%% @doc
%%%
%%% @end
%%% @contributors:
%%%   Peter Defebvre
%%%-------------------------------------------------------------------
-module(cb_websockets).

-export([init/0
         ,authenticate/1
         ,authorize/1
         ,allowed_methods/0, allowed_methods/1
         ,resource_exists/0, resource_exists/1
         ,validate/1, validate/2
        ]).

-include("../crossbar.hrl").

-define(CB_LIST, <<"websockets/crossbar_listing">>).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Initializes the bindings this module will respond to.
%% @end
%%--------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authenticate">>, ?MODULE, 'authenticate'),
    _ = crossbar_bindings:bind(<<"*.authorize">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.websockets">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.websockets">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.websockets">>, ?MODULE, 'validate').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Authenticates the incoming request, returning true if the requestor is
%% known, or false if not.
%% @end
%%--------------------------------------------------------------------
-spec authenticate(cb_context:context()) -> 'false'.
authenticate(_) -> 'false'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%--------------------------------------------------------------------
-spec authorize(cb_context:context()) -> 'false'.
authorize(_) -> 'false'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%--------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
-spec allowed_methods(path_token()) -> http_methods().
allowed_methods() ->
    [?HTTP_GET].
allowed_methods(_) ->
    [?HTTP_GET].

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Does the path point to a valid resource
%% So /websockets => []
%%    /websockets/foo => [<<"foo">>]
%%    /websockets/foo/bar => [<<"foo">>, <<"bar">>]
%% @end
%%--------------------------------------------------------------------
-spec resource_exists() -> 'true'.
-spec resource_exists(path_token()) -> 'true'.
resource_exists() -> 'true'.
resource_exists(_) -> 'true'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /websockets mights load a list of websocket objects
%% /websockets/123 might load the websocket object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%--------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context) ->
    validate_websockets(Context, cb_context:req_verb(Context)).
validate(Context, Id) ->
    validate_websocket(Context, Id, cb_context:req_verb(Context)).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load running web sockets
%% @end
%%--------------------------------------------------------------------
-spec validate_websockets(cb_context:context(), http_method()) -> cb_context:context().
validate_websockets(Context, ?HTTP_GET) ->
    summary(Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load a web socket info
%% @end
%%--------------------------------------------------------------------
-spec validate_websocket(cb_context:context(), path_token(), http_method()) -> cb_context:context().
validate_websocket(Context, Id, ?HTTP_GET) ->
    read(Id, Context).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%--------------------------------------------------------------------
-spec summary(cb_context:context()) -> cb_context:context().
summary(Context) ->
    Result = blackhole_tracking:get_sockets(cb_context:account_id(Context)),
    cb_context:setters(Context, [{fun cb_context:set_resp_status/2, 'success'}
                                 ,{fun cb_context:set_resp_data/2, Result}
                                ]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load an instance from the database
%% @end
%%--------------------------------------------------------------------
-spec read(ne_binary(), cb_context:context()) -> cb_context:context().
read(Id, Context) ->
    case blackhole_tracking:get_socket(Id) of
        {'error', 'not_found'} ->
            ErrJobj = wh_json:from_list([{<<"cause">>, Id}]),
            cb_context:add_system_error('not_found', ErrJobj, Context);
        {'ok', BHContext} ->
            Result = bh_context:to_json(BHContext),
            cb_context:setters(Context, [{fun cb_context:set_resp_status/2, 'success'}
                                         ,{fun cb_context:set_resp_data/2, Result}
                                        ])
    end.
