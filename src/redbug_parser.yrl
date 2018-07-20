Nonterminals
  rtp
  mfa module function args arity
  terms term list tuple
  record map record_fields record_field map_fields map_field
  guards guard guard_value test
  actions.

Terminals
  '(' ')' '[' ']' '{' '}'
  '->' 'when' ':' ';' '#' ',' '=' ':=' '_' '#{' '/' '|' '++'
  'variable' 'bin' 'float' 'int' 'atom' 'string'
  'comparison_op' 'arithmetic_op' 'boolean_op1' 'boolean_op2'
  'type_test1' 'type_test2' 'bif0' 'bif1' 'bif2'.

Rootsymbol rtp.

Right 15 boolean_op1.
Left 10 boolean_op2.
Left 20 comparison_op.
Left 30 arithmetic_op.

rtp -> mfa                            : {'$1', '_', '_'}.
rtp -> mfa '->' actions               : {'$1', '_', '$3'}.
rtp -> mfa 'when' guards              : {'$1', '$3', '_'}.
rtp -> mfa 'when' guards '->' actions : {'$1', '$3', '$5'}.

mfa -> module                           : {call, '$1', '_', '_'}.
mfa -> module ':' function              : {call, '$1', '$3', '_'}.
mfa -> module ':' function '/' arity    : {call, '$1', '$3', '$5'}.
mfa -> module ':' function '(' args ')' : {call, '$1', '$3', '$5'}.

module -> 'atom' : '$1'.

function -> 'atom' : '$1'.
function -> '_'    : '$1'.

args -> terms : '$1'.

arity -> 'int' : '$1'.

terms -> '$empty'       : [].
terms -> term           : ['$1'].
terms -> terms ',' term : '$1' ++ ['$3'].

term -> '_'        : '$1'.
term -> 'variable' : '$1'.
term -> 'bin'      : '$1'.
term -> 'float'    : '$1'.
term -> 'int'      : '$1'.
term -> 'atom'     : '$1'.
term -> 'string'   : '$1'.
term -> list       : '$1'.
term -> tuple      : '$1'.
term -> record     : '$1'.
term -> map        : '$1'.

list -> '[' terms ']'          : {list, '$2'}.
list -> '[' terms '|' term ']' : {cons, '$2', '$4'}.
list -> term '++' term         : {cat, '$1', '$3'}.

tuple -> '{' terms '}' : {tuple, '$2'}.

record -> 'atom' '#' 'atom'                       : {record, '$1', '$3', []}.
record -> 'atom' '#' 'atom' '{' record_fields '}' : {record, '$1', '$3', '$5'}.

record_fields -> '$empty'                       : [].
record_fields -> record_field                   : ['$1'].
record_fields -> record_fields ',' record_field : '$1' ++ ['$3'].

record_field -> 'atom' '=' term : {'$1', '$3'}.

map -> '#{' map_fields '}' : {map, '$2'}.

map_fields -> '$empty'                 : [].
map_fields -> map_field                : ['$1'].
map_fields -> map_fields ',' map_field : '$1' ++ ['$3'].

map_field -> term ':=' term : {'$1', '$3'}.

guards -> guard                      : '$1'.
guards -> guards ',' guard           : {'andalso', ['$1', '$3']}.
guards -> guards ';' guard           : {'orelse', ['$1', '$3']}.
guards -> 'boolean_op1' guard        : {'$1', ['$2']}.
guards -> guards 'boolean_op2' guard : {'$2', ['$1', '$3']}.

guard -> test                    : '$1'.
guard -> 'boolean_op1' test      : {'$1', ['$2']}.
guard -> test 'boolean_op2' test : {'$2', ['$1', '$3']}.

test -> type_test1 '(' 'variable' ')'                : {'$1', ['$3']}.
test -> type_test2 '(' 'variable' ',' 'variable' ')' : {'$1', ['$3', '$5']}.
test -> type_test2 '(' 'atom' ',' 'variable' ')'     : {'$1', ['$3', '$5']}.
test -> guard_value 'comparison_op' guard_value      : {'$2', ['$1', '$3']}.

guard_value -> term                                     : '$1'.
guard_value -> bif0 '(' ')'                             : {'$1', []}.
guard_value -> bif1 '(' guard_value ')'                 : {'$1', ['$3']}.
guard_value -> bif2 '(' guard_value ',' guard_value ')' : {'$1', ['$3', '$5']}.
guard_value -> guard_value 'arithmetic_op' guard_value  : {'$2', ['$1', '$3']}.

actions -> 'atom'             : ['$1'].
actions -> actions ',' 'atom' : '$1' ++ ['$3'].
actions -> actions ';' 'atom' : '$1' ++ ['$3'].
