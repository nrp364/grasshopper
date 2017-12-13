(** SPL abstract syntax. *)

open Grass

type idents = ident list

type pos = source_position

type name = string

type names = name list

type typ =
  | IdentType of ident
  | StructType of ident
  | MapType of typ * typ
  | ArrayType of typ
  | ArrayCellType of typ
  | SetType of typ
  | IntType
  | BoolType
  | ByteType
  | UnitType
  | AnyRefType
  | PermType (* SL formulas *)
  | AnyType

type var_decl_id =
  | IdentDecl of ident
  | ArrayDecl of var_decl_id

type spl_program =
    { includes: (name * pos) list;
      type_decls: typedecls;
      var_decls: vars;
      proc_decls: procs;
      pred_decls: preds;
      background_theory: (expr * pos) list; 
    }

and decl =
  | TypeDecl of typedecl
  | VarDecl of var
  | ProcDecl of proc
  | PredDecl of pred

and decls = decl list

and proc =
    { p_name: ident;
      p_formals: idents;
      p_returns: idents;
      p_locals: vars;
      p_contracts: contracts;
      p_body: stmt; 
      p_pos: pos;
    }

and procs = proc IdMap.t

and pred =
    { pr_name: ident;
      pr_formals: idents;
      pr_outputs: idents;
      pr_locals: vars;
      pr_contracts: contracts;
      pr_body: expr option; 
      pr_pos: pos;
    }

and preds = pred IdMap.t

and var =
    { v_name: ident;
      v_type: typ; 
      v_ghost: bool;
      v_implicit: bool;
      v_aux: bool;
      v_pos: pos;
      v_scope: pos;
    }

and vars = var IdMap.t

and typedecl =
    { t_name: ident;
      t_def: type_def;      
      t_pos: pos;
    }

and type_def =
  | FreeTypeDef
  | StructTypeDef of vars
      
and typedecls = typedecl IdMap.t
      
and contract =
  | Requires of expr * bool
  | Ensures of expr * bool

and contracts = contract list

and stmt =
  | Skip of pos
  | Block of stmts * pos
  | LocalVars of var list * exprs option * pos
  | Assume of expr * bool * pos
  | Assert of expr * bool * pos
  | Assign of exprs * exprs * pos
  | Havoc of exprs * pos
  | Dispose of expr * pos
  | If of expr * stmt * stmt * pos
  | Loop of loop_contracts * stmt * expr * stmt * pos
  | Return of exprs * pos

and stmts = stmt list

and loop_contracts = loop_contract list

and loop_contract = 
  | Invariant of expr * bool

and bound_var =
  | GuardedVar of ident * expr
  | UnguardedVar of var

and expr =
  | Null of typ * pos
  | Emp of pos
  | Setenum of typ * exprs * pos
  | IntVal of Int64.t * pos
  | BoolVal of bool * pos
  | New of typ * exprs * pos
  | Read of expr * expr * pos
  | ProcCall of ident * exprs * pos
  | PredApp of pred_sym * exprs * pos
  | Binder of binder_kind * bound_var list * expr * pos
  | UnaryOp of un_op * expr * pos
  | BinaryOp of expr * bin_op * expr * typ * pos
  | Ident of ident * pos
  | Annot of expr * annotation * pos

and exprs = expr list

and bin_op = 
  | OpDiff | OpUn | OpInt 
  | OpMinus | OpPlus | OpMult | OpDiv | OpMod 
  | OpEq | OpGt | OpLt | OpGeq | OpLeq | OpIn
  | OpPts | OpSepStar | OpSepPlus | OpSepIncl
  | OpBvAnd | OpBvOr | OpBvShiftL | OpBvShiftR 
  | OpAnd | OpOr | OpImpl 

and un_op =
  | OpArrayCells | OpIndexOfCell | OpArrayOfCell | OpLength
  | OpUMinus | OpUPlus
  | OpBvNot | OpToInt | OpToByte
  | OpNot
  | OpOld
  | OpKnown
      
and pred_sym =
  | AccessPred | BtwnPred | DisjointPred | FramePred | ReachPred | Pred of ident
      
and binder_kind =
  | Forall | Exists | SetComp

and annotation =
  | GeneratorAnnot of (expr * ident list) list * expr
  | PatternAnnot of expr
  | CommentAnnot of string

(** Utility functions *)
        
let pos_of_expr = function
  | Null (_, p) 
  | Emp p 
  | IntVal (_, p) 
  | BoolVal (_, p)
  | Setenum (_, _, p)
  | New (_, _, p)
  | Read (_, _, p)
  | Binder (_, _, _, p)
  | ProcCall (_, _, p)
  | PredApp (_, _, p)
  | UnaryOp (_, _, p)
  | BinaryOp (_, _, _, _, p)
  | Ident (_, p) -> p
  | Annot (_, _, p) -> p  

let free_vars e =
  let rec fv bv acc = function
    | Ident (x, _) ->
        if IdSet.mem x bv then acc else IdSet.add x acc
    | Setenum (_, es, _)
    | New (_, es, _)
    | ProcCall (_, es, _)
    | PredApp (_, es, _) ->
        List.fold_left (fv bv) acc es
    | UnaryOp (_, e, _)
    | Annot (e, _, _) ->
        fv bv acc e
    | Read (e1, e2, _) 
    | BinaryOp (e1, _, e2, _, _) ->
        fv bv (fv bv acc e1) e2
    | Binder (_, vs, e, _) ->
        let bv, acc =
          List.fold_left (fun (bv, acc) -> function
            | UnguardedVar v ->
                IdSet.add v.v_name bv, acc
            | GuardedVar (x, e) ->
                let acc = fv bv acc e in
                IdSet.add x bv, acc)
            (bv, acc) vs
        in
        fv bv acc e
    | _ -> acc
  in fv IdSet.empty IdSet.empty e

(** Variable substitution for expressions (not capture avoiding) *)
let subst_id sm =
  let rec s bv = function
    | Ident (x, pos) as e ->
        if IdSet.mem x bv || not @@ IdMap.mem x sm
        then e
        else Ident (IdMap.find x sm, pos)
    | Setenum (ty, es, pos) ->
        Setenum (ty, List.map (s bv) es, pos)
    | New (ty, es, pos) ->
        New (ty, List.map (s bv) es, pos)
    | ProcCall (p, es, pos) ->
        ProcCall (p, List.map (s bv) es, pos)
    | PredApp (p, es, pos) ->
        PredApp (p, List.map (s bv) es, pos)
    | UnaryOp (op, e, pos) ->
        UnaryOp (op, s bv e, pos)
    | Annot (e, a, pos) ->
        Annot (s bv e, a, pos) (* TODO: substitute in a *)
    | Read (e1, e2, pos) ->
        Read (s bv e1, s bv e2, pos)
    | BinaryOp (e1, op, e2, ty, pos) ->
        BinaryOp (s bv e1, op, s bv e2, ty, pos)
    | Binder (b, vs, e, pos) ->
        let bv =
          List.fold_left (fun bv -> function
            | UnguardedVar v ->
                IdSet.add v.v_name bv
            | GuardedVar (x, e) ->
                IdSet.add x bv)
            bv vs
        in
        Binder (b, vs, s bv e, pos)
    | e -> e
  in s IdSet.empty
    
let pos_of_stmt = function
  | Skip pos
  | Block (_, pos)
  | LocalVars (_, _, pos)
  | Assume (_, _, pos)
  | Assert (_, _, pos)
  | Assign (_, _, pos)
  | Dispose (_, pos)
  | Havoc (_, pos)
  | If (_, _, _, pos)
  | Loop (_, _, _, _, pos)
  | Return (_, pos) -> pos

let proc_decl hdr body =
  { hdr with p_body = body }

let struct_decl sname sfields pos =
  { t_name = sname;  t_def = StructTypeDef sfields; t_pos = pos }

let var_decl vname vtype vghost vimpl vpos vscope =
  { v_name = vname; v_type = vtype; v_ghost = vghost; v_implicit = vimpl; v_aux = false; v_pos = vpos; v_scope = vscope } 

let pred_decl hdr body =
  { hdr with pr_body = body }

let extend_spl_program incls decls bg_th prog =
  let check_uniqueness id pos (tdecls, vdecls, pdecls, prdecls) =
    if IdMap.mem id tdecls || IdMap.mem id vdecls || IdMap.mem id pdecls || IdMap.mem id prdecls
    then ProgError.error pos ("redeclaration of identifier " ^ (fst id) ^ ".");
  in
  let tdecls, vdecls, pdecls, prdecls =
    List.fold_left (fun (tdecls, vdecls, pdecls, prdecls as decls) -> function
      | TypeDecl decl -> 
          check_uniqueness decl.t_name decl.t_pos decls;
          IdMap.add decl.t_name decl tdecls, vdecls, pdecls, prdecls
      | VarDecl decl -> 
          check_uniqueness decl.v_name decl.v_pos decls;
          tdecls, IdMap.add decl.v_name decl vdecls, pdecls, prdecls
      | ProcDecl decl -> 
          check_uniqueness decl.p_name decl.p_pos decls;
          tdecls, vdecls, IdMap.add decl.p_name decl pdecls, prdecls
      | PredDecl decl -> 
          check_uniqueness decl.pr_name decl.pr_pos decls;
          tdecls, vdecls, pdecls, IdMap.add decl.pr_name decl prdecls)
      (prog.type_decls, prog.var_decls, prog.proc_decls, prog.pred_decls)
      decls
  in
  { includes = incls @ prog.includes;
    type_decls = tdecls;
    var_decls = vdecls; 
    proc_decls = pdecls;
    pred_decls = prdecls;
    background_theory = bg_th @ prog.background_theory;
  }

let merge_spl_programs prog1 prog2 =
  let tdecls =
    IdMap.fold (fun _ decl acc -> TypeDecl decl :: acc) prog1.type_decls []
  in
  let vdecls =
    IdMap.fold (fun _ decl acc -> VarDecl decl :: acc) prog1.var_decls tdecls
  in
  let prdecls =
    IdMap.fold (fun _ decl acc -> PredDecl decl :: acc) prog1.pred_decls vdecls
  in
  let decls =
    IdMap.fold (fun _ decl acc -> ProcDecl decl :: acc) prog1.proc_decls prdecls
  in
  extend_spl_program prog1.includes decls prog1.background_theory prog2

let add_alloc_decl prog =
  let alloc_decls =
    IdMap.fold
      (fun _ decl acc ->
        match decl.t_def with
        | StructTypeDef _ ->
            let sid = decl.t_name in
            let id = Prog.alloc_id (FreeSrt sid) in
            let tpe = SetType (StructType sid) in
            let pos = GrassUtil.dummy_position in
            let scope = GrassUtil.global_scope in
            let vdecl = VarDecl (var_decl id tpe true false pos scope) in
            vdecl :: acc
        | _ -> acc)
      prog.type_decls
      []
  in
    extend_spl_program [] alloc_decls [] prog

let empty_spl_program =
  { includes = [];
    type_decls = IdMap.empty;
    var_decls = IdMap.empty;
    proc_decls = IdMap.empty;
    pred_decls = IdMap.empty;
    background_theory = [];
  }
    
let mk_block pos = function
  | [] -> Skip pos
  | [stmt] -> stmt
  | stmts -> Block (stmts, pos)

(** Pretty printing *)

open Format

let rec pr_type ppf = function
  | AnyRefType -> fprintf ppf "AnyRef" 
  | BoolType -> fprintf ppf "%s" bool_sort_string
  | IntType -> fprintf ppf "%s" int_sort_string
  | ByteType -> fprintf ppf "%s" byte_sort_string
  | UnitType -> fprintf ppf "Unit"
  | StructType id | IdentType id -> pr_ident ppf id
  | ArrayType e -> fprintf ppf "%s<@[%a@]>" array_sort_string pr_type e
  | ArrayCellType e -> fprintf ppf "%s<@[%a@]>" array_cell_sort_string pr_type e
  | MapType (d, r) -> fprintf ppf "%s<@[%a,@ %a@]>" map_sort_string pr_type d pr_type r
  | SetType s -> fprintf ppf "%s<@[%a@]>" set_sort_string pr_type s
  | PermType -> fprintf ppf "Permission"
  | AnyType -> fprintf ppf "Any"

let string_of_type t = pr_type str_formatter t; flush_str_formatter ()

