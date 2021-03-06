%% -*- mode: erlang; erlang-indent-level: 2 -*-
%%% Author  : Mats Cronqvist <masse@cronqvi.st>
%%% Created : 10 Mar 2010 by Mats Cronqvist <masse@kreditor.se>

%% msc - match spec compiler
%% transforms a string to a call trace expression;
%% {MFA,MatchSpec} == {{M,F,A},{Head,Cond,Body}}


-module('redbug_msc').

-export([transform/1]).

transform(E) ->
  try
    compile(parse(to_string(E)))
  catch
    throw:{R,Info} -> exit({syntax_error,{R,Info}})
  end.

-define(is_string(Str), (Str=="" orelse (9=<hd(Str) andalso hd(Str)=<255))).
to_string(A) when is_atom(A)    -> atom_to_list(A);
to_string(S) when ?is_string(S) -> S;
to_string(X)                    -> throw({illegal_input,X}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compiler
%% returns {{Module,Function,Arity},[{Head,Cond,Body}],[Flag]}
%% i.e. the args to erlang:trace_pattern/3

compile({Mod,F,As,Gs,Acts}) ->
  {Fun,Arg}   = compile_function(F,As),
  {Vars,Args} = compile_args(As),
  Guards      = compile_guards(Gs,Vars),
  Actions     = compile_acts(Acts),
  Flags       = compile_flags(F,Acts),
  {{Mod,Fun,Arg},[{Args,Guards,Actions}],Flags}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compile function name
compile_function(' ',_) -> {'_','_'};
compile_function(F,'_') -> {F,'_'};
compile_function(F,As)  -> {F,length(As)}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compile argument list
compile_args('_') ->
  {[{'$_','$_'}],'_'};
compile_args(As) ->
  lists:foldl(fun ca_fun/2,{[],[]},As).

ca_fun({map,Map},{Vars,O}) ->
  {Vs,Ps} = ca_map(Map,Vars),
  {Vs,O++[maps:from_list(Ps)]};
ca_fun({list,Es},{Vars,O}) ->
  {Vs,Ps} = ca_list(Es,Vars),
  {Vs,O++[Ps]};
ca_fun({tuple,Es},{Vars,O}) ->
  {Vs,Ps} = ca_list(Es,Vars),
  {Vs,O++[list_to_tuple(Ps)]};
ca_fun({var,'_'},{Vars,O}) ->
  {Vars,O++['_']};
ca_fun({var,Var},{Vars,O}) ->
  V = get_var(Var, Vars),
  {[{Var,V}|Vars],O++[V]};
ca_fun({Type,Val},{Vars,O}) ->
  assert_type(Type,Val),
  {Vars,O++[Val]}.

ca_map(Fs,Vars) ->
  cfm(Fs,{Vars,[]}).

cfm([],O) -> O;
cfm([{K,V}|Fs],{V0,P0}) ->
  {[],[PK]} = ca_fun(K,{[],[]}),
  {Vs,[PV]} = ca_fun(V,{V0,[]}),
  cfm(Fs,{lists:usort(V0++Vs),P0++[{PK,PV}]}).

ca_list(Es,Vars) ->
  cfl(Es,{Vars,[]}).

cfl([],O) -> O;
cfl([E|Es],{V0,P0}) when is_list(Es) ->
  {V,P} = ca_fun(E,{V0,[]}),
  cfl(Es,{lists:usort(V0++V),P0++P});
cfl([E1|E2],{V0,P0}) ->
  %% non-proper list / tail match
  {V1,[P1]} = ca_fun(E1,{V0,[]}),
  {V2,[P2]} = ca_fun(E2,{lists:usort(V0++V1),[]}),
  {lists:usort(V0++V1++V2),P0++[P1|P2]}.

get_var(Var,Vars) ->
  case proplists:get_value(Var,Vars) of
    undefined -> list_to_atom("\$"++integer_to_list(length(Vars)+1));
    X -> X
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compile guards
compile_guards(Gs,Vars) ->
  {Vars,O} = lists:foldr(fun gd_fun/2,{Vars,[]},Gs),
  O.

gd_fun({Op,As},{Vars,O}) when is_list(As) -> % function
  {Vars,[unpack_op(Op,As,Vars)|O]};
gd_fun({Op,V},{Vars,O}) ->                   % unary
  {Vars,[{Op,unpack_var(V,Vars)}|O]};
gd_fun({Op,V1,V2},{Vars,O}) ->               % binary
  {Vars,[{Op,unpack_var(V1,Vars),unpack_var(V2,Vars)}|O]}.

unpack_op(Op,As,Vars) ->
  list_to_tuple([Op|[unpack_var(A,Vars)||A<-As]]).

unpack_var({map,M},Vars) ->
  maps:from_list([{unpack_var(K,Vars),unpack_var(V,Vars)}||{K,V}<-M]);
unpack_var({tuple,Es},Vars) ->
  {list_to_tuple([unpack_var(E,Vars)||E<-Es])};
unpack_var({list,Es},Vars) ->
  [unpack_var(E,Vars)||E<-Es];
unpack_var({string,S},_) ->
  S;
unpack_var({var,Var},Vars) ->
  case proplists:get_value(Var,Vars) of
    undefined -> throw({unbound_var,Var});
    V -> V
  end;
unpack_var({Op,As},Vars) when is_list(As) ->
  unpack_op(Op,As,Vars);
unpack_var({Op,V1,V2},Vars) ->
  unpack_op(Op,[V1,V2],Vars);
unpack_var({Type,Val},_) ->
  assert_type(Type,Val),
  Val.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compile trace flags
compile_flags(F,Acts) ->
  LG =
    case F of
      ' ' -> global;
      _   -> local
    end,
  lists:foldr(fun(E,A)->try [fl_fun(E)|A] catch _:_ -> A end end,[LG],Acts).

fl_fun("count") -> call_count;
fl_fun("time")  -> call_time.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% compile actions
compile_acts(As) ->
  lists:foldr(fun(E,A)->try [ac_fun(E)|A] catch _:_ -> A end end,[],As).

ac_fun("stack") -> {message,{process_dump}};
ac_fun("return")-> {exception_trace}.

assert_type(Type,Val) ->
  case lists:member(Type,[integer,atom,string,char,bin]) of
    true -> ok;
    false-> throw({bad_type,{Type,Val}})
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% parser
%% accepts strings like;
%%   "a","a:b","a:b/2","a:b(X,y)",
%%   "a:b(X,Y)when is_record(X,rec) and Y==0, (X==z)"
%%   "a:b->stack", "a:b(X)whenX==2->return"
%% returns
%%   {atom(M),atom(F),list(Arg)|atom('_'),list(Guard),list(Action)}
parse(Str) ->
  {Body,Guard,Action} = split(Str),
  {M,F,A}             = body(Body),
  Guards              = guards(Guard),
  Actions             = actions(Action),
  {M,F,A,Guards,Actions}.

%% split the input string in three parts; body, guards, actions
%% we parse them separately
split(Str) ->
  %% strip off the actions, if any
  {St,Action} =
    case re:run(Str,"^(.+)->\\s*([a-z;,]+)\\s*\$",[{capture,[1,2],list}]) of
      {match,[Z,A]} -> {Z,A};
      nomatch       -> {Str,""}
    end,
  %% strip off the guards, if any
  {Body,Guard} =
    case re:run(St,"^(.+[\\s)])+when\\s(.+)\$",[{capture,[1,2],list}]) of
      {match,[Y,G]} -> {Y,G};
      nomatch       -> {St,""}
    end,
  {Body,Guard,Action}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% parse body
body(Str) ->
  case erl_scan:tokens([],Str++". ",1) of
    {done,{ok,Toks,1},[]} ->
      case erl_parse:parse_exprs(Toks) of
        {ok,[{op,_,'/',{remote,_,{atom,_,M},{atom,_,F}},{integer,_,Ari}}]} ->
          {M,F,lists:duplicate(Ari,{var,'_'})}; % m:f/2
        {ok,[{call,_,{remote,_,{atom,_,M},{atom,_,F}},Args}]} ->
          {M,F,[arg(A) || A<-Args]};            % m:f(...)
        {ok,[{call,_,{remote,_,{atom,_,M},{var,_,'_'}},Args}]} ->
          {M,' ',[arg(A) || A<-Args]};          % m:_(...)
        {ok,[{call,_,{remote,_,{atom,_,M},{var,_,_}},Args}]} ->
          {M,' ',[arg(A) || A<-Args]};          % m:V(...)
        {ok,[{remote,_,{atom,_,M},{atom,_,F}}]} ->
          {M,F,'_'};                            % m:f
        {ok,[{remote,_,{atom,_,M},{var,_,'_'}}]} ->
          {M,' ','_'};                          % m:_
        {ok,[{remote,_,{atom,_,M},{var,_,_}}]} ->
          {M,' ','_'};                          % m:V
        {ok,[{atom,_,M}]} ->
          {M,'_','_'};                          % m
        {ok,C} ->
          throw({parse_error,C});
        {error,{_,erl_parse,L}} ->
          throw({parse_error,lists:flatten(L)})
     end;
    _ ->
      throw({scan_error,Str})
  end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% parse guards
guards("") -> "";
guards(Str) ->
  case erl_scan:tokens([],Str++". ",1) of
    {done,{ok,Toks,1},[]} ->
      case erl_parse:parse_exprs(disjunct_guard(Toks)) of
        {ok,Guards} ->
          [guard(G)||G<-Guards];
        {error,{_,erl_parse,L}} ->
          throw({parse_error,lists:flatten(L)})
      end;
    _ ->
      throw({scan_error,Str})
  end.

%% deal with disjunct guards by replacing ';' with 'orelse'
disjunct_guard(Toks) ->
  [case T of {';',1} -> {'orelse',1}; _ -> T end||T<-Toks].

guard({call,_,{atom,_,G},As}) -> {G,[guard(A) || A<-As]};   % function
guard({op,_,Op,One,Two})      -> {Op,guard(One),guard(Two)};% binary op
guard({op,_,Op,One})          -> {Op,guard(One)};           % unary op
guard(Guard)                  -> arg(Guard).                % variable

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% parse actions
actions(Str) ->
  Acts = string:tokens(Str,";,"),
  [throw({unknown_action,A}) || A <- Acts,not lists:member(A,acts())],
  Acts.

acts() ->
  ["stack","return","time","count"].


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% parse arguments
arg({op,_,'++',A1,A2}) -> plusplus(A1,A2);
arg({nil,_})           -> {list,[]};
arg({cons,_,H,T})      -> {list,arg_list({cons,1,H,T})};
arg({tuple,_,Args})    -> {tuple,[arg(A)||A<-Args]};
arg({map,_,Map})       -> {map,[{arg(K),arg(V)}||{_,_,K,V}<-Map]};
arg({bin,_,Bin})       -> {bin,eval_bin(Bin)};
arg({T,_,Var})         -> {T,Var}.

plusplus({string,_,[]},Var) -> arg(Var);
plusplus({string,_,St},Var) -> {list,arg_list(consa(St,Var))};
plusplus(A1,A2)             -> throw({illegal_plusplus,{A1,A2}}).

consa([C],T)    -> {cons,1,{char,1,C},T};
consa([C|Cs],T) -> {cons,1,{char,1,C},consa(Cs,T)}.

arg_list({cons,_,H,T}) -> [arg(H)|arg_list(T)];
arg_list({nil,_})      -> [];
arg_list(V)            -> arg(V).

eval_bin(Bin) ->
  try
    {value,B,[]} = erl_eval:expr({bin,1,Bin},[]),
    B
  catch
    _:R -> throw({bad_binary,R})
  end.
