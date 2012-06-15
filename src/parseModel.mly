%{
open Form
%}

%token <string * int> IDENT
%token <int> ELEM
%token <bool> BOOL
%token LBRACE RBRACE ARROW ELSE
%token UNSPEC
%token EOF
%start main
%type <Form.Model.model> main
%%

   
main:
  definition main { List.fold_right (Model.add_def (fst $1)) (snd $1) $2 }
| definition EOF {List.fold_right (Model.add_def (fst $1)) (snd $1) Model.empty}
;

definition:
  IDENT ARROW ELEM { ($1, [([], Model.Int $3)]) }
| IDENT ARROW BOOL { ($1, [([], Model.Bool $3)]) }
| IDENT ARROW LBRACE mappings RBRACE { ($1, $4) }
; 

mappings:
  mapping mappings { $1 :: $2 }
| ELSE ARROW UNSPEC { [] }
;

mapping:
  args ARROW BOOL { ($1, Model.Bool $3) }
| args ARROW ELEM { ($1, Model.Int $3) }
;

args:
  ELEM args { $1 :: $2 }
| ELEM { [$1] }
;

