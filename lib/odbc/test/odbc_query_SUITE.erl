%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2002-2011. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%

-module(odbc_query_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("test_server_line.hrl").
-include("odbc_test.hrl").

%%--------------------------------------------------------------------
%% all(Arg) -> [Doc] | [Case] | {skip, Comment}
%% Arg - doc | suite
%% Doc - string()
%% Case - atom() 
%%	Name of a test case function. 
%% Comment - string()
%% Description: Returns documentation/test cases in this test suite
%%		or a skip tuple if the platform is not supported.  
%%--------------------------------------------------------------------
suite() -> [{ct_hooks,[ts_install_cth]}].

all() -> 
    case odbc_test_lib:odbc_check() of
	ok ->
	    [sql_query, first, last, next, prev, select_count,
	     select_next, select_relative, select_absolute,
	     create_table_twice, delete_table_twice, duplicate_key,
	     not_connection_owner, no_result_set, query_error,
	     multiple_select_result_sets, multiple_mix_result_sets,
	     multiple_result_sets_error,
	     {group, parameterized_queries}, {group, describe_table},
	     delete_nonexisting_row];
	Other -> {skip, Other}
    end.

groups() -> 
    [{parameterized_queries, [],
      [{group, param_integers}, param_insert_decimal,
       param_insert_numeric, {group, param_insert_string},
       param_insert_float, param_insert_real,
       param_insert_double, param_insert_mix, param_update,
       param_delete, param_select]},
     {param_integers, [],
      [param_insert_tiny_int, param_insert_small_int,
       param_insert_int, param_insert_integer]},
     {param_insert_string, [],
      [param_insert_char, param_insert_character,
       param_insert_char_varying,
       param_insert_character_varying]},
     {describe_table, [],
      [describe_integer, describe_string, describe_floating,
       describe_dec_num, describe_no_such_table]}].

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config) -> Config
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Initiation before the whole suite
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) when is_list(Config) ->
    %% application:start(odbc),
    odbc:start(), % make sure init_per_suite fails if odbc is not built
    [{tableName, odbc_test_lib:unique_table_name()}| Config].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config) -> _
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Cleanup after the whole suite
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    application:stop(odbc),
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(Case, Config) -> Config
%% Case - atom()
%%   Name of the test case that is about to be run.
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Initiation before each test case
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(_Case, Config) ->
    {ok, Ref} = odbc:connect(?RDBMS:connection_string(), []),
    Dog = test_server:timetrap(?default_timeout),
    Temp = lists:keydelete(connection_ref, 1, Config),
    NewConfig = lists:keydelete(watchdog, 1, Temp),
    [{watchdog, Dog}, {connection_ref, Ref} | NewConfig].

%%--------------------------------------------------------------------
%% Function: end_per_testcase(Case, Config) -> _
%% Case - atom()
%%   Name of the test case that is about to be run.
%% Config - [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Cleanup after each test case
%%--------------------------------------------------------------------
end_per_testcase(_Case, Config) ->
    Ref = ?config(connection_ref, Config),
    ok = odbc:disconnect(Ref),
    %% Clean up if needed 
    Table = ?config(tableName, Config),
    {ok, NewRef} = odbc:connect(?RDBMS:connection_string(), []),
    odbc:sql_query(NewRef, "DROP TABLE " ++ Table), 
    odbc:disconnect(NewRef),
    Dog = ?config(watchdog, Config),
    test_server:timetrap_cancel(Dog),
    ok.

%%-------------------------------------------------------------------------
%% Test cases starts here.
%%-------------------------------------------------------------------------
sql_query(doc)->
    ["Test the common cases"];
sql_query(suite) -> [];
sql_query(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} =
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++ 
		       " (ID integer, DATA varchar(10))"),

    {updated, Count} = 
	odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ " VALUES(1,'bar')"),

    true = odbc_test_lib:check_row_count(1, Count),

    InsertResult = ?RDBMS:insert_result(),
    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {updated, NewCount} = 
	odbc:sql_query(Ref, "UPDATE " ++ Table ++ 
		       " SET DATA = 'foo' WHERE ID = 1"),
    
    true = odbc_test_lib:check_row_count(1, NewCount),

    UpdateResult = ?RDBMS:update_result(),
    UpdateResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {updated,  NewCount1} = odbc:sql_query(Ref, "DELETE FROM " ++ Table ++ 
				  " WHERE ID = 1"),
    
    true = odbc_test_lib:check_row_count(1, NewCount1),

    {selected, Fields, []} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["ID","DATA"] = odbc_test_lib:to_upper(Fields),
    ok.

%%-------------------------------------------------------------------------
select_count(doc) -> 
    ["Tests select_count/[2,3]'s timeout, "
     " select_count's functionality will be better tested by other tests "
     " such as first."];
select_count(sute) -> [];
select_count(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, Count} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    true = odbc_test_lib:check_row_count(1, Count),
    {ok, _} = 
	odbc:select_count(Ref, "SELECT * FROM " ++ Table, ?TIMEOUT),
    {'EXIT', {function_clause, _}} = 
	(catch odbc:select_count(Ref, "SELECT * FROM ", -1)),
    ok.
%%-------------------------------------------------------------------------
first(doc) ->
    ["Tests first/[1,2]"];
first(suite) -> [];
first(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),
    
    {updated, Count} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    true = odbc_test_lib:check_row_count(1, Count),
    {updated, NewCount} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    true = odbc_test_lib:check_row_count(1, NewCount),
    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table),


    FirstResult = ?RDBMS:selected_ID(1, first),
    FirstResult = odbc:first(Ref),
    FirstResult = odbc:first(Ref, ?TIMEOUT), 
    {'EXIT', {function_clause, _}} = (catch odbc:first(Ref, -1)),
    ok.

%%-------------------------------------------------------------------------
last(doc) ->
    ["Tests last/[1,2]"];
last(suite) -> [];
last(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, Count} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    true = odbc_test_lib:check_row_count(1, Count),
    {updated, NewCount} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    true = odbc_test_lib:check_row_count(1, NewCount),
    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table),

    LastResult = ?RDBMS:selected_ID(2, last),
    LastResult = odbc:last(Ref),

    LastResult = odbc:last(Ref, ?TIMEOUT), 
    {'EXIT', {function_clause, _}} = (catch odbc:last(Ref, -1)),
    ok.

%%-------------------------------------------------------------------------
next(doc) ->
    ["Tests next/[1,2]"];
next(suite) -> [];
next(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, Count} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    true = odbc_test_lib:check_row_count(1, Count),
    {updated, NewCount} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    true = odbc_test_lib:check_row_count(1, NewCount),
    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table),

    NextResult = ?RDBMS:selected_ID(1, next),
    NextResult = odbc:next(Ref),
    NextResult2 = ?RDBMS:selected_ID(2, next),
    NextResult2 = odbc:next(Ref, ?TIMEOUT), 
    {'EXIT', {function_clause, _}} = (catch odbc:next(Ref, -1)),
    ok.
%%-------------------------------------------------------------------------
prev(doc) ->
    ["Tests prev/[1,2]"];
prev(suite) -> [];
prev(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, Count} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    true = odbc_test_lib:check_row_count(1, Count),
    {updated, NewCount} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    true = odbc_test_lib:check_row_count(1, NewCount),

    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table),

    odbc:last(Ref), % Position cursor last so there will be a prev
    PrevResult = ?RDBMS:selected_ID(1, prev),
    PrevResult = odbc:prev(Ref),

    odbc:last(Ref), % Position cursor last so there will be a prev
    PrevResult = odbc:prev(Ref, ?TIMEOUT), 
    {'EXIT', {function_clause, _}} = (catch odbc:prev(Ref, -1)),
    ok.
%%-------------------------------------------------------------------------
select_next(doc) ->
    ["Tests select/[4,5] with CursorRelation = next "];
select_next(suit) -> [];
select_next(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(3)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(4)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(5)"),

    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table), 

    SelectResult1 = ?RDBMS:selected_next_N(1),
    SelectResult1 = odbc:select(Ref, next, 3),

    %% Test that selecting stops at the end of the result set
    SelectResult2 = ?RDBMS:selected_next_N(2),
    SelectResult2 = odbc:select(Ref, next, 3, ?TIMEOUT), 
    {'EXIT',{function_clause, _}} = 
	(catch odbc:select(Ref, next, 2, -1)),

    %% If you try fetching data beyond the the end of result set,
    %% you get an empty list.
    {selected, Fields, []} = odbc:select(Ref, next, 1),

    ["ID"] = odbc_test_lib:to_upper(Fields),
    ok.

%%-------------------------------------------------------------------------
select_relative(doc) ->
    ["Tests select/[4,5] with CursorRelation = relative "];
select_relative(suit) -> [];
select_relative(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"), 
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(3)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(4)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(5)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(6)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(7)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(8)"),

    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table),

    SelectResult1 = ?RDBMS:selected_relative_N(1),
    SelectResult1 = odbc:select(Ref, {relative, 2}, 3),

    %% Test that selecting stops at the end of the result set
    SelectResult2 = ?RDBMS:selected_relative_N(2),
    SelectResult2 = odbc:select(Ref, {relative, 3}, 3, ?TIMEOUT),
    {'EXIT',{function_clause, _}} = 
	(catch odbc:select(Ref, {relative, 3} , 2, -1)),
    ok.

%%-------------------------------------------------------------------------
select_absolute(doc) ->
    ["Tests select/[4,5] with CursorRelation = absolute "];
select_absolute(suit) -> [];
select_absolute(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),
    Table = ?config(tableName, Config),

    {updated, _} = odbc:sql_query(Ref, 
				  "CREATE TABLE " ++ Table ++
				  " (ID integer)"),

    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(1)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(2)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(3)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(4)"),
    {updated, 1} = odbc:sql_query(Ref, "INSERT INTO " ++ Table ++
				  " VALUES(5)"),
    {ok, _} = odbc:select_count(Ref, "SELECT * FROM " ++ Table), 

    SelectResult1 = ?RDBMS:selected_absolute_N(1),
    SelectResult1 = odbc:select(Ref, {absolute, 1}, 3),

    %% Test that selecting stops at the end of the result set
    SelectResult2 = ?RDBMS:selected_absolute_N(2),
    SelectResult2 = odbc:select(Ref, {absolute, 1}, 6, ?TIMEOUT),
    {'EXIT',{function_clause, _}} = 
	(catch odbc:select(Ref, {absolute, 1}, 2, -1)),
    ok.

%%-------------------------------------------------------------------------
create_table_twice(doc) ->
    ["Test what happens if you try to create the same table twice."];
create_table_twice(suite) -> [];
create_table_twice(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID integer, DATA varchar(10))"),
    {error, Error} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID integer, DATA varchar(10))"),
    is_driver_error(Error),
    ok.

%%-------------------------------------------------------------------------
delete_table_twice(doc) ->
    ["Test what happens if you try to delete the same table twice."];
delete_table_twice(suite) -> [];
delete_table_twice(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID integer, DATA varchar(10))"),
    {updated, _} = odbc:sql_query(Ref, "DROP TABLE " ++ Table),
    {error, Error} = odbc:sql_query(Ref, "DROP TABLE " ++ Table),
    is_driver_error(Error),
    ok.

%-------------------------------------------------------------------------
duplicate_key(doc) ->
    ["Test what happens if you try to use the same key twice"];
duplicate_key(suit) -> [];
duplicate_key(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID integer, DATA char(10), PRIMARY KEY(ID))"),

    {updated, 1} = 
	odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ " VALUES(1,'bar')"),

    {error, Error} =
	odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ " VALUES(1,'foo')"),
    is_driver_error(Error),
    ok.

%%-------------------------------------------------------------------------
not_connection_owner(doc) ->
    ["Test what happens if a process that did not start the connection"
     " tries to acess it."];
not_connection_owner(suite) -> [];
not_connection_owner(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    spawn_link(?MODULE, not_owner, [self(), Ref, Table]),

    receive 
	continue ->
	    ok
    end.

not_owner(Pid, Ref, Table) ->
    {error, process_not_owner_of_odbc_connection} =
	odbc:sql_query(Ref, "CREATE TABLE " ++ Table ++ " (ID integer)"),

    {error, process_not_owner_of_odbc_connection} =
	odbc:disconnect(Ref),

    Pid ! continue.

%%-------------------------------------------------------------------------
no_result_set(doc) ->
    ["Tests what happens if you try to use a function that needs an "
     "associated result set when there is none."];
no_result_set(suite) -> [];
no_result_set(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   

    {error, result_set_does_not_exist} = odbc:first(Ref),
    {error, result_set_does_not_exist} = odbc:last(Ref),
    {error, result_set_does_not_exist} = odbc:next(Ref),
    {error, result_set_does_not_exist} = odbc:prev(Ref),
    {error, result_set_does_not_exist} = odbc:select(Ref, next, 1),
    {error, result_set_does_not_exist} = 
	odbc:select(Ref, {absolute, 2}, 1),
    {error, result_set_does_not_exist} = 
	odbc:select(Ref, {relative, 2}, 1),
    ok.
%%-------------------------------------------------------------------------
query_error(doc) ->
    ["Test what happens if there is an error in the query."];
query_error(suite) ->
    [];
query_error(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID integer, DATA char(10), PRIMARY KEY(ID))"),
    {updated, 1} = 
	odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ " VALUES(1,'bar')"),

    {error, _} = 
	odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ " VALUES(1,'bar')"),

    {error, _} = 
	odbc:sql_query(Ref, "INSERT ONTO " ++ Table ++ " VALUES(1,'bar')"),
    ok.

%%-------------------------------------------------------------------------
multiple_select_result_sets(doc) ->
    ["Test what happens if you have a batch of select queries."];
multiple_select_result_sets(suite) ->
    [];
multiple_select_result_sets(Config) when is_list(Config) ->
    case ?RDBMS of
	sqlserver ->
	    Ref = ?config(connection_ref, Config),   
	    Table = ?config(tableName, Config),
	    
	    {updated, _} = 
		odbc:sql_query(Ref, 
			       "CREATE TABLE " ++ Table ++
			       " (ID integer, DATA varchar(10), "
			       "PRIMARY KEY(ID))"),
	    {updated, 1} = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(1,'bar')"),
	    
	    {updated, 1} = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(2, 'foo')"),
	    
	    MultipleResult = ?RDBMS:multiple_select(),
	    
	    MultipleResult = 
		odbc:sql_query(Ref, "SELECT * FROM " ++ Table ++ 
			       "; SELECT DATA FROM "++ Table ++ 
			       " WHERE ID=2"),
	    ok;
	_ ->
	    {skip, "multiple result_set not supported"}
    end.
	    
%%-------------------------------------------------------------------------
multiple_mix_result_sets(doc) ->
    ["Test what happens if you have a batch of select and other type of"
     " queries."];
multiple_mix_result_sets(suite) ->
    [];
multiple_mix_result_sets(Config) when is_list(Config) ->
    case ?RDBMS of
	sqlserver ->
	    Ref = ?config(connection_ref, Config),   
	    Table = ?config(tableName, Config),
	    
	    {updated, _} = 
		odbc:sql_query(Ref, 
			       "CREATE TABLE " ++ Table ++
			       " (ID integer, DATA varchar(10), "
			       "PRIMARY KEY(ID))"),
	    {updated, 1} = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(1,'bar')"),

	    MultipleResult = ?RDBMS:multiple_mix(),
	    
	    MultipleResult = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(2,'foo'); UPDATE " ++ Table ++ 
			       " SET DATA = 'foobar' WHERE ID =1;SELECT "
			       "* FROM " 
			       ++ Table ++ ";DELETE FROM " ++ Table ++
			       " WHERE ID =1; SELECT DATA FROM " ++ Table),
	    ok;
	_ ->
	    {skip, "multiple result_set not supported"}
    end.
%%-------------------------------------------------------------------------
multiple_result_sets_error(doc) ->
    ["Test what happens if one of the batched queries fails."];
multiple_result_sets_error(suite) ->
    [];
multiple_result_sets_error(Config) when is_list(Config) ->
    case ?RDBMS of
	sqlserver ->
	    Ref = ?config(connection_ref, Config),   
	    Table = ?config(tableName, Config),
	    
	    {updated, _} = 
		odbc:sql_query(Ref, 
			       "CREATE TABLE " ++ Table ++
			       " (ID integer, DATA varchar(10), "
			       "PRIMARY KEY(ID))"),
	    {updated, 1} = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(1,'bar')"),
	    
	    {error, Error} = 
		odbc:sql_query(Ref, "INSERT INTO " ++ Table ++ 
			       " VALUES(1,'foo'); SELECT * FROM " ++ Table),
	    is_driver_error(Error),
	    
	    {error, NewError} = 
		odbc:sql_query(Ref, "SELECT * FROM " 
			       ++ Table ++ ";INSERT INTO " ++ Table ++ 
		       " VALUES(1,'foo')"),
	    is_driver_error(NewError),
	    ok;
	_ ->
	    {skip, "multiple result_set not supported"}
    end.   

%%-------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%%-------------------------------------------------------------------------
param_insert_tiny_int(doc)->
    ["Test insertion of tiny ints by parameterized queries."];
param_insert_tiny_int(suite) ->
    [];
param_insert_tiny_int(Config) when is_list(Config) ->
    case ?RDBMS of 
	sqlserver ->
	    Ref = ?config(connection_ref, Config),   
	    Table = ?config(tableName, Config),
	    
	    {updated, _} = 
		odbc:sql_query(Ref, 
			       "CREATE TABLE " ++ Table ++
			       " (FIELD TINYINT)"),
	    
	    {updated, Count} = 
		odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				 "(FIELD) VALUES(?)", 
				 [{sql_tinyint, [1, 2]}],
				 ?TIMEOUT),%Make sure to test timeout clause
	    
	    true = odbc_test_lib:check_row_count(2, Count),
	    
	    InsertResult = ?RDBMS:param_select_tiny_int(),
	    
	    InsertResult = 
		odbc:sql_query(Ref, "SELECT * FROM " ++ Table),
	    
	    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
		(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
					[{sql_tinyint, [1, "2"]}])),
	    ok;
	_  ->
	    {skip, "Type tiniyint not supported"}
    end.
%%-------------------------------------------------------------------------
param_insert_small_int(doc)->
    ["Test insertion of small ints by parameterized queries."];
param_insert_small_int(suite) ->
    [];
param_insert_small_int(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD SMALLINT)"),

    {updated, Count} = 
	odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
			 "(FIELD) VALUES(?)", [{sql_smallint, [1, 2]}],
			 ?TIMEOUT), %% Make sure to test timeout clause

    true = odbc_test_lib:check_row_count(2, Count),

    InsertResult = ?RDBMS:param_select_small_int(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
				[{sql_smallint, [1, "2"]}])),    
    ok.

%%-------------------------------------------------------------------------
param_insert_int(doc)->
    ["Test insertion of ints by parameterized queries."];
param_insert_int(suite) ->
    [];
param_insert_int(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD INT)"),

    Int = ?RDBMS:small_int_max() + 1,

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{sql_integer, [1, Int]}]),
    true = odbc_test_lib:check_row_count(2, Count),
    
    InsertResult = ?RDBMS:param_select_int(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
				[{sql_integer, [1, "2"]}])),
    ok.

%%-------------------------------------------------------------------------
param_insert_integer(doc)->
    ["Test insertion of integers by parameterized queries."];
param_insert_integer(suite) ->
    [];
param_insert_integer(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD INTEGER)"),

    Int = ?RDBMS:small_int_max() + 1,

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(FIELD) VALUES(?)", 
				    [{sql_integer, [1, Int]}]),
    true = odbc_test_lib:check_row_count(2, Count),

    InsertResult = ?RDBMS:param_select_int(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{sql_integer, [1, 2.3]}])),  
    ok.

%%-------------------------------------------------------------------------
param_insert_decimal(doc)->
    ["Test insertion of decimal numbers by parameterized queries."];
param_insert_decimal(suite) ->
    [];
param_insert_decimal(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD DECIMAL (3,0))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(FIELD) VALUES(?)", 
				    [{{sql_decimal, 3, 0}, [1, 2]}]),
    true = odbc_test_lib:check_row_count(2, Count),
    
    InsertResult = ?RDBMS:param_select_decimal(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{{sql_decimal, 3, 0}, [1, "2"]}])),


    odbc:sql_query(Ref, "DROP TABLE " ++ Table),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD DECIMAL (3,1))"),

    {updated, NewCount} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
					   "(FIELD) VALUES(?)", 
				    [{{sql_decimal, 3, 1}, [0.25]}]),
    true = odbc_test_lib:check_row_count(1, NewCount),
    
    {selected, Fields, [{Value}]} = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fields),
    
    odbc_test_lib:match_float(Value, 0.3, 0.01),
    
    ok.

%%-------------------------------------------------------------------------
param_insert_numeric(doc)->
    ["Test insertion of numeric numbers by parameterized queries."];
param_insert_numeric(suite) ->
    [];
param_insert_numeric(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD NUMERIC (3,0))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{{sql_numeric,3,0}, [1, 2]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    InsertResult = ?RDBMS:param_select_numeric(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{{sql_decimal, 3, 0}, [1, "2"]}])),    

    odbc:sql_query(Ref, "DROP TABLE " ++ Table),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD NUMERIC (3,1))"),

    {updated, NewCount} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(FIELD) VALUES(?)", 
				    [{{sql_numeric, 3, 1}, [0.25]}]),

    true = odbc_test_lib:check_row_count(1, NewCount),

    {selected, Fileds, [{Value}]} = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    odbc_test_lib:match_float(Value, 0.3, 0.01),
    ok.

%%-------------------------------------------------------------------------

%%-------------------------------------------------------------------------
param_insert_char(doc)->
    ["Test insertion of fixed length string by parameterized queries."];
param_insert_char(suite) ->
    [];
param_insert_char(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD CHAR (10))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{{sql_char, 10}, 
				     ["foofoofoof", "0123456789"]}]),
    true = odbc_test_lib:check_row_count(2, Count),

    {selected,Fileds,[{"foofoofoof"}, {"0123456789"}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    {error, _} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				  "(FIELD) VALUES(?)", 
				  [{{sql_char, 10}, 
				    ["foo", "01234567890"]}]),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
				[{{sql_char, 10}, ["1", 2.3]}])), 
    ok.

%%-------------------------------------------------------------------------
param_insert_character(doc)->
    ["Test insertion of fixed length string by parameterized queries."];
param_insert_character(suite) ->
    [];
param_insert_character(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD CHARACTER (10))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{{sql_char, 10}, 
				     ["foofoofoof", "0123456789"]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    {selected, Fileds, [{"foofoofoof"}, {"0123456789"}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    {error, _} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				  "(FIELD) VALUES(?)", 
				  [{{sql_char, 10}, 
				    ["foo", "01234567890"]}]),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{{sql_char, 10}, ["1", 2]}])), 
    ok.

%%------------------------------------------------------------------------
param_insert_char_varying(doc)->
    ["Test insertion of variable length strings by parameterized queries."];
param_insert_char_varying(suite) ->
    [];
param_insert_char_varying(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD CHAR VARYING(10))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{{sql_varchar, 10}, 
				     ["foo", "0123456789"]}]),
    
    true = odbc_test_lib:check_row_count(2, Count),

    {selected, Fileds, [{"foo"}, {"0123456789"}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    {error, _} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				  "(FIELD) VALUES(?)", 
				  [{{sql_varchar, 10}, 
				    ["foo", "01234567890"]}]),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{{sql_varchar, 10}, ["1", 2.3]}])), 
    ok.

%%-------------------------------------------------------------------------
param_insert_character_varying(doc)->
    ["Test insertion of variable length strings by parameterized queries."];
param_insert_character_varying(suite) ->
    [];
param_insert_character_varying(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD CHARACTER VARYING(10))"),


    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{{sql_varchar, 10}, 
				     ["foo", "0123456789"]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    {selected, Fileds, [{"foo"}, {"0123456789"}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    {error, _} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				  "(FIELD) VALUES(?)", 
				  [{{sql_varchar, 10}, 
				    ["foo", "01234567890"]}]),

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{{sql_varchar, 10}, ["1", 2]}])), 
    ok.
%%-------------------------------------------------------------------------
param_insert_float(doc)->
    ["Test insertion of floats by parameterized queries."];
param_insert_float(suite) ->
    [];
param_insert_float(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD FLOAT(5))"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(FIELD) VALUES(?)", 
				    [{{sql_float,5}, [1.3, 1.2]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    {selected, Fileds, [{Float1},{Float2}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    case (odbc_test_lib:match_float(Float1, 1.3, 0.000001) and 
	  odbc_test_lib:match_float(Float2, 1.2, 0.000001)) of
	true ->
	    ok;
	false ->
	    test_server:fail(float_numbers_do_not_match)
    end,

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
				[{{sql_float, 5}, [1.0, "2"]}])),
    ok.

%%-------------------------------------------------------------------------
param_insert_real(doc)->
    ["Test insertion of real numbers by parameterized queries."];
param_insert_real(suite) ->
    [];
param_insert_real(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD REAL)"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{sql_real, [1.3, 1.2]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    %_InsertResult = ?RDBMS:param_select_real(),

    {selected, Fileds, [{Real1},{Real2}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    case (odbc_test_lib:match_float(Real1, 1.3, 0.000001) and 
	  odbc_test_lib:match_float(Real2, 1.2, 0.000001)) of
	true ->
	    ok;
	false ->
	    test_server:fail(real_numbers_do_not_match)
    end,

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)",
				[{sql_real,[1.0, "2"]}])),
    ok.

%%-------------------------------------------------------------------------
param_insert_double(doc)->
    ["Test insertion of doubles by parameterized queries."];
param_insert_double(suite) ->
    [];
param_insert_double(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (FIELD DOUBLE PRECISION)"),

    {updated, Count} = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				   "(FIELD) VALUES(?)", 
				   [{sql_double, [1.3, 1.2]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    {selected, Fileds, [{Double1},{Double2}]} =
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),

    ["FIELD"] = odbc_test_lib:to_upper(Fileds),

    case (odbc_test_lib:match_float(Double1, 1.3, 0.000001) and 
	  odbc_test_lib:match_float(Double2, 1.2, 0.000001)) of
	true ->
	    ok;
	false ->
	    test_server:fail(double_numbers_do_not_match)
    end,

    {'EXIT',{badarg,odbc,param_query,'Params'}} = 
	(catch odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				"(FIELD) VALUES(?)", 
				[{sql_double, [1.0, "2"]}])),
    ok.

%%-------------------------------------------------------------------------
param_insert_mix(doc)->
    ["Test insertion of a mixture of datatypes by parameterized queries."];
param_insert_mix(suite) ->
    [];
param_insert_mix(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID INTEGER, DATA CHARACTER VARYING(10),"
		       " PRIMARY KEY(ID))"),

    {updated, Count}  = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(ID, DATA) VALUES(?, ?)",
				    [{sql_integer, [1, 2]}, 
				     {{sql_varchar, 10}, ["foo", "bar"]}]),

    true = odbc_test_lib:check_row_count(2, Count),

    InsertResult = ?RDBMS:param_select_mix(),

    InsertResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),
    ok.
%%-------------------------------------------------------------------------
param_update(doc)->
    ["Test parameterized update query."];
param_update(suite) ->
    [];
param_update(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID INTEGER, DATA CHARACTER VARYING(10),"
		       " PRIMARY KEY(ID))"),

    {updated, Count}  = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(ID, DATA) VALUES(?, ?)",
				    [{sql_integer, [1, 2, 3]}, 
				     {{sql_varchar, 10}, 
				      ["foo", "bar", "baz"]}]),

    true = odbc_test_lib:check_row_count(3, Count),

    {updated, NewCount}  = odbc:param_query(Ref, "UPDATE " ++ Table ++
				    " SET DATA = 'foobar' WHERE ID = ?",
				    [{sql_integer, [1, 2]}]), 

     true = odbc_test_lib:check_row_count(2, NewCount),

    UpdateResult = ?RDBMS:param_update(),

    UpdateResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),
    ok.

%%-------------------------------------------------------------------------
delete_nonexisting_row(doc) ->		% OTP-5759
    ["Make a delete...where with false conditions (0 rows deleted). ",
     "This used to give an error message (see ticket OTP-5759)."];
delete_nonexisting_row(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} =
	odbc:sql_query(Ref, "CREATE TABLE " ++ Table
		       ++ " (ID INTEGER, DATA CHARACTER VARYING(10))"),
    {updated, Count} =
	odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
			 "(ID, DATA) VALUES(?, ?)",
			 [{sql_integer, [1, 2, 3]},
			  {{sql_varchar, 10}, ["foo", "bar", "baz"]}]),
     
    true = odbc_test_lib:check_row_count(3, Count),

    {updated, NewCount} =
	odbc:sql_query(Ref, "DELETE FROM " ++ Table ++ " WHERE ID = 8"),

    true = odbc_test_lib:check_row_count(0, NewCount),

    {updated, _} =
	odbc:sql_query(Ref, "DROP TABLE "++ Table),

    ok.

%%-------------------------------------------------------------------------
param_delete(doc) ->
    ["Test parameterized delete query."];
param_delete(suite) ->
    [];
param_delete(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID INTEGER, DATA CHARACTER VARYING(10),"
		       " PRIMARY KEY(ID))"),

    {updated, Count}  = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(ID, DATA) VALUES(?, ?)",
				    [{sql_integer, [1, 2, 3]}, 
				     {{sql_varchar, 10}, 
				      ["foo", "bar", "baz"]}]),
    true = odbc_test_lib:check_row_count(3, Count),

    {updated, NewCount}  = odbc:param_query(Ref, "DELETE FROM " ++ Table ++
				    " WHERE ID = ?",
				    [{sql_integer, [1, 2]}]), 

    true = odbc_test_lib:check_row_count(2, NewCount),

    UpdateResult = ?RDBMS:param_delete(),

    UpdateResult = 
	odbc:sql_query(Ref, "SELECT * FROM " ++ Table),
    ok.


%%-------------------------------------------------------------------------
param_select(doc) ->
    ["Test parameterized select query."];
param_select(suite) ->
    [];
param_select(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (ID INTEGER, DATA CHARACTER VARYING(10),"
		       " PRIMARY KEY(ID))"),

    {updated, Count}  = odbc:param_query(Ref, "INSERT INTO " ++ Table ++ 
				    "(ID, DATA) VALUES(?, ?)",
				    [{sql_integer, [1, 2, 3]}, 
				     {{sql_varchar, 10}, 
				      ["foo", "bar", "foo"]}]),

    true = odbc_test_lib:check_row_count(3, Count),

    SelectResult = ?RDBMS:param_select(),

    SelectResult = odbc:param_query(Ref, "SELECT * FROM " ++ Table ++
				    " WHERE DATA = ?",
				    [{{sql_varchar, 10}, ["foo"]}]), 
    ok.

%%-------------------------------------------------------------------------

%%-------------------------------------------------------------------------
describe_integer(doc) ->
    ["Test describe_table/[2,3] for integer columns."];
describe_integer(suite) ->
    [];
describe_integer(Config) when is_list(Config) ->    
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (int1 SMALLINT, int2 INT, int3 INTEGER)"),

    Decs = ?RDBMS:describe_integer(),
    %% Make sure to test timeout clause
    Decs = odbc:describe_table(Ref, Table, ?TIMEOUT), 
    ok.

%%-------------------------------------------------------------------------
describe_string(doc) ->
    ["Test describe_table/[2,3] for string columns."];
describe_string(suite) ->
    [];
describe_string(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (str1 char(10), str2 character(10), "
		       "str3 CHAR VARYING(10), str4 "
		       "CHARACTER VARYING(10))"),

    Decs = ?RDBMS:describe_string(),

    Decs = odbc:describe_table(Ref, Table),
    ok.

%%-------------------------------------------------------------------------
describe_floating(doc) ->
    ["Test describe_table/[2,3] for floting columns."];
describe_floating(suite) ->
    [];
describe_floating(Config) when is_list(Config) ->
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (f FLOAT(5), r REAL, "
		       "d DOUBLE PRECISION)"),

    Decs = ?RDBMS:describe_floating(),

    Decs = odbc:describe_table(Ref, Table),
    ok.

%%-------------------------------------------------------------------------
describe_dec_num(doc) ->
    ["Test describe_table/[2,3] for decimal and numerical columns"];
describe_dec_num(suite) ->
    [];
describe_dec_num(Config) when is_list(Config) ->

    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {updated, _} = 
	odbc:sql_query(Ref, 
		       "CREATE TABLE " ++ Table ++
		       " (dec DECIMAL(9,3), num NUMERIC(9,2))"),

    Decs = ?RDBMS:describe_dec_num(),

    Decs = odbc:describe_table(Ref, Table),
    ok.


%%-------------------------------------------------------------------------
describe_timestamp(doc) ->
    ["Test describe_table/[2,3] for tinmestap columns"];
describe_timestamp(suite) ->
    [];
describe_timestamp(Config) when is_list(Config) ->
    
    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),
    
    {updated, _} =  % Value == 0 || -1 driver dependent!
	odbc:sql_query(Ref,  "CREATE TABLE " ++ Table ++ 
		       ?RDBMS:create_timestamp_table()),

    Decs = ?RDBMS:describe_timestamp(),

    Decs = odbc:describe_table(Ref, Table),
    ok.

%%-------------------------------------------------------------------------
describe_no_such_table(doc) ->
    ["Test what happens if you try to describe a table that does not exist."];
describe_no_such_table(suite) ->
    [];
describe_no_such_table(Config) when is_list(Config) ->

    Ref = ?config(connection_ref, Config),   
    Table = ?config(tableName, Config),

    {error, _ } = odbc:describe_table(Ref, Table),
    ok.

%%-------------------------------------------------------------------------
%% Internal functions
%%-------------------------------------------------------------------------

is_driver_error(Error) ->
    case is_list(Error) of
	true ->
	    test_server:format("Driver error ~p~n", [Error]),
	    ok;
	false ->
	    test_server:fail(Error)
    end.
