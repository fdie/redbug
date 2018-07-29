Nonterminals
  rtp
  mfa module function args arity
  terms term list tuple
  record map record_fields record_field map_fields map_field
  guards guard guard_value test
  actions.

Terminals
  '(' ')' '[' ']' '{' '}'
  '->' 'when' ':' ';' '#' ',' '=' ':=' '#{' '/' '|' '++'
  'variable' 'bin' 'float' 'int' 'atom' 'string'
  'comparison_op' 'arithmetic_op' 'boolean_op1' 'boolean_op2'
  'type_test1' 'type_test2' 'bif0' 'bif1' 'bif2'.

Rootsymbol rtp.

Left  4 arithmetic_op.
Left  3 comparison_op.
Right 2 boolean_op1.
Left  1 boolean_op2.

rtp -> mfa                                              : {'$1', '_', '_'}.
rtp -> mfa '->' actions                                 : {'$1', '_', '$3'}.
rtp -> mfa 'when' guards                                : {'$1', '$3', '_'}.
rtp -> mfa 'when' guards '->' actions                   : {'$1', '$3', '$5'}.

mfa -> module                                           : {'$1', '_', '_'}.
mfa -> module ':' function                              : {'$1', '$3', '_'}.
mfa -> module ':' function '/' arity                    : {'$1', '$3', '$5'}.
mfa -> module ':' function '(' args ')'                 : {'$1', '$3', fix_vars('$5')}.

module -> 'atom'                                        : lift('$1').

function -> 'atom'                                      : lift('$1').
function -> 'variable'                                  : lift('$1').

args -> terms                                           : '$1'.

arity -> 'int'                                          : lift('$1').

terms -> '$empty'                                       : [].
terms -> term                                           : ['$1'].
terms -> terms ',' term                                 : '$1' ++ ['$3'].

term -> 'variable'                                      : lift('$1').
term -> 'bin'                                           : lift('$1').
term -> 'float'                                         : lift('$1').
term -> 'int'                                           : lift('$1').
term -> 'atom'                                          : lift('$1').
term -> list                                            : '$1'.
term -> tuple                                           : '$1'.
term -> record                                          : '$1'.
term -> map                                             : '$1'.

list -> 'string'                                        : lift('$1').
list -> '[' terms ']'                                   : '$2'.
list -> '[' terms '|' term ']'                          : mk_cons('$2', '$4').
list -> list '++' 'variable'                            : mk_cons('$1', lift('$3')).
list -> list '++' list                                  : mk_cons('$1', '$3').

tuple -> '{' terms '}'                                  : mk_tuple('$2').

record -> 'atom' '#' 'atom'                             : mk_record(lift('$1'), lift('$3'), []).
record -> 'atom' '#' 'atom' '{' record_fields '}'       : mk_record(lift('$1'), lift('$3'), '$5').

record_fields -> '$empty'                               : [].
record_fields -> record_field                           : ['$1'].
record_fields -> record_fields ',' record_field         : '$1' ++ ['$3'].

record_field -> 'atom' '=' term                         : {lift('$1'), '$3'}.

map -> '#{' map_fields '}'                              : mk_map('$2').

map_fields -> '$empty'                                  : [].
map_fields -> map_field                                 : ['$1'].
map_fields -> map_fields ',' map_field                  : '$1' ++ ['$3'].

map_field -> term ':=' term                             : {'$1', '$3'}.

guards -> '(' guards ')'                                : '$2'.
guards -> guard                                         : '$1'.
guards -> guards ',' guard                              : {'andalso', ['$1', '$3']}.
guards -> guards ';' guard                              : {'orelse', ['$1', '$3']}.
guards -> 'boolean_op1' guard                           : {lift('$1'), ['$2']}.
guards -> guards 'boolean_op2' guard                    : {lift('$2'), ['$1', '$3']}.

guard -> '(' guard ')'                                  : '$2'.
guard -> test                                           : '$1'.
guard -> 'boolean_op1' test                             : {lift('$1'), ['$2']}.
guard -> test 'boolean_op2' test                        : {lift('$2'), ['$1', '$3']}.

test -> '(' test ')'                                    : '$2'.
test -> 'type_test1' '(' 'variable' ')'                 : {lift('$1'), [lift('$3')]}.
test -> 'type_test2' '(' 'variable' ',' 'variable' ')'  : {lift('$1'), [lift('$3'), lift('$5')]}.
test -> 'type_test2' '(' 'atom' ',' 'variable' ')'      : {lift('$1'), [lift('$3'), lift('$5')]}.
test -> guard_value 'comparison_op' guard_value         : {lift('$2'), ['$1', '$3']}.

guard_value -> '(' guard_value ')'                        : '$2'.
guard_value -> term                                       : '$1'.
guard_value -> 'bif0' '(' ')'                             : {lift('$1'), []}.
guard_value -> 'bif1' '(' guard_value ')'                 : {lift('$1'), ['$3']}.
guard_value -> 'bif2' '(' guard_value ',' guard_value ')' : {lift('$1'), ['$3', '$5']}.
guard_value -> guard_value 'arithmetic_op' guard_value    : {lift('$2'), ['$1', '$3']}.

actions -> 'atom'                                       : [chk_action('$1')].
actions -> actions ',' 'atom'                           : '$1' ++ [chk_action('$3')].
actions -> actions ';' 'atom'                           : '$1' ++ [chk_action('$3')].

Erlang code.

mk_tuple(List) -> list_to_tuple(List).

mk_cons(H, T) -> lists:foldr(fun(E,O) -> [E|O] end, T, H).

mk_map(KVs) -> maps:from_list(KVs).

mk_record(Mod, Rec, KVs) -> {record, {Mod, Rec, KVs}}.

chk_action({atom, _, stack})  -> {action, {message,{process_dump}}};
chk_action({atom, _, return}) -> {action, exception_trace};
chk_action({atom, _, time})   -> {flag, call_time};
chk_action({atom, _, count})  -> {flag,call_count};
chk_action({atom, L, Act})    -> return_error(L, io_lib:format("illegal action; ~p", [Act])).

lift({'variable', _, "_"}) -> '_';
lift({'variable', L, Var}) -> lift_var(Var, L);
lift({_, _, Value})        -> Value;
lift({Token, _})           -> Token.

%% after we've processed the args (where vars can be unbound) we call this to
%% indicate that from now on (in guards) vars must be bound
fix_vars(X) ->
    putv(bound, true),
    X.

% is the var bound? if so, good.
lift_var(Var, L) ->
    case getv(Var, nil) of
        nil -> lift_var(getv(bound, false), Var, L);
        V -> V
    end.

%% we've seen an unbound var. either create it (if we're parsing args), or throw a syntax
%% error (if we're parsing guards)
lift_var(false, Var, _) -> putv(Var, list_to_atom("$"++integer_to_list(bumpv(count))));
lift_var(true, Var, L) -> return_error(L, io_lib:format("unbound variable; ~p", [Var])).

%% a global dictionary. used to store the bound vars, the count of vars, and whether
%% we're currently allowing creation of new vars.
bumpv(Key) ->
    putv(Key, getv(Key, 0)+1).

getv(Key, Def) ->
    case get({redbug_parser, Key}) of
        undefined -> Def;
        Val -> Val
    end.

putv(Var, V) ->
    put({redbug_parser, Var}, V),
    V.