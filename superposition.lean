import clause prover_state utils
open tactic monad expr

meta def get_rwr_positions : expr → list (list ℕ)
| (app a b) := [[]] ++
  do arg ← list.zip_with_index (get_app_args (app a b)),
     pos ← get_rwr_positions arg↣1,
     [arg↣2 :: pos]
| (var _) := []
| e := [[]]

meta def get_position : expr → list ℕ → expr
| (app a b) (p::ps) :=
match list.nth (get_app_args (app a b)) p with
| some arg := get_position arg ps
| none := (app a b)
end
| e _ := e

meta def replace_position (v : expr) : expr → list ℕ → expr
| (app a b) (p::ps) :=
let args := get_app_args (app a b) in
match args↣nth p with
| some arg := app_of_list a↣get_app_fn (args↣update p $ replace_position arg ps)
| none := app a b
end
| e [] := v
| e _ := e

variable gt : expr → expr → bool
variables (c1 c2 : clause)
variables (ac1 ac2 : active_cls)
variables (i1 i2 : nat)
variable pos : list ℕ
variable ltr : bool
variable congr_ax : name

lemma sup_ltr {A a1 a2} {f : A → Type _} : (f a1 → false) → f a2 → a1 = a2 → false :=
take hnfa1 hfa2 heq, hnfa1 (heq↣symm ▸ hfa2)
lemma sup_rtl {A a1 a2} {f : A → Type _} : (f a1 → false) → f a2 → a2 = a1 → false :=
take hnfa1 hfa2 heq, hnfa1 (heq ▸ hfa2)

meta def is_eq_dir (e : expr) (ltr : bool) : option (expr × expr) :=
match is_eq e with
| some (lhs, rhs) := if ltr then some (lhs, rhs) else some (rhs, lhs)
| none := none
end

meta def try_sup : tactic clause := do
guard $ (c1↣get_lit i1)↣is_pos,
qf1 ← c1↣open_metan c1↣num_quants,
qf2 ← c2↣open_metan c2↣num_quants,
(rwr_from, rwr_to) ← (is_eq_dir (qf1↣1↣get_lit i1)↣formula ltr)↣to_monad,
atom ← return (qf2↣1↣get_lit i2)↣formula,
eq_type ← infer_type rwr_from,
atom_at_pos_type ← infer_type $ get_position atom pos,
unify eq_type atom_at_pos_type,
unify rwr_from (get_position atom pos),
rwr_from' ← instantiate_mvars rwr_from,
rwr_to' ← instantiate_mvars rwr_to,
guard $ ¬gt rwr_to' rwr_from',
rwr_ctx_varn ← mk_fresh_name,
abs_rwr_ctx ← return $
  lam rwr_ctx_varn binder_info.default eq_type
  (if (qf2↣1↣get_lit i2)↣is_neg
   then replace_position (mk_var 0) atom pos
   else imp (replace_position (mk_var 0) atom pos) false_),
univ ← infer_univ eq_type,
op1 ← qf1↣1↣open_constn i1,
op2 ← qf2↣1↣open_constn c2↣num_lits,
hi2 ← (op2↣2↣nth i2)↣to_monad,
new_atom ← whnf $ app abs_rwr_ctx rwr_to',
new_hi2 ← return $ local_const hi2↣local_uniq_name `H binder_info.default new_atom,
new_fin_prf ←
  return $ app_of_list (const congr_ax [univ]) [eq_type, rwr_from, rwr_to,
            abs_rwr_ctx, (op2↣1↣close_const hi2)↣proof, new_hi2],
clause.meta_closure (qf1↣2 ++ qf2↣2) $ (op1↣1↣inst new_fin_prf)↣close_constn (op1↣2 ++ op2↣2↣update i2 new_hi2)

example (i : Type) (a b : i) (p : i → Prop) (H : a = b) (Hpa : p a) : true := by do
H ← get_local `H >>= clause.of_proof,
Hpa ← get_local `Hpa >>= clause.of_proof,
a ← get_local `a,
try_sup (λx y, ff) H Hpa 0 0 [0] tt ``sup_ltr >>= clause.validate,
to_expr `(trivial) >>= apply

example (i : Type) (a b : i) (p : i → Prop) (H : a = b) (Hpa : p a → false) (Hpb : p b → false) : true := by do
H ← get_local `H >>= clause.of_proof,
Hpa ← get_local `Hpa >>= clause.of_proof,
Hpb ← get_local `Hpb >>= clause.of_proof,
try_sup (λx y, ff) H Hpa 0 0 [0] tt ``sup_ltr >>= clause.validate,
try_sup (λx y, ff) H Hpb 0 0 [0] ff ``sup_rtl >>= clause.validate,
to_expr `(trivial) >>= apply

meta def rwr_positions (c : clause) (i : nat) : list (list ℕ) :=
get_rwr_positions (c↣get_lit i)↣formula

meta def try_add_sup : resolution_prover unit :=
(do c' ← ↑(try_sup gt ac1↣c ac2↣c i1 i2 pos ltr congr_ax),
    add_inferred c' [ac1,ac2]) <|> return ()

meta def superposition_back_inf : inference :=
take given, do active ← get_active, sequence' $ do
  given_i ← given↣selected,
  guard (given↣c↣get_lit given_i)↣is_pos,
  option.to_monad $ is_eq (given↣c↣get_lit given_i)↣formula,
  other ← rb_map.values active,
  other_i ← other↣selected,
  pos ← rwr_positions other↣c other_i,
  [do try_add_sup gt given other given_i other_i pos tt ``sup_ltr,
      try_add_sup gt given other given_i other_i pos ff ``sup_rtl]

meta def superposition_fwd_inf : inference :=
take given, do active ← get_active, sequence' $ do
  given_i ← given↣selected,
  other ← rb_map.values active,
  other_i ← other↣selected,
  guard (other↣c↣get_lit other_i)↣is_pos,
  option.to_monad $ is_eq (other↣c↣get_lit other_i)↣formula,
  pos ← rwr_positions given↣c given_i,
  [do try_add_sup gt other given other_i given_i pos tt ``sup_ltr,
      try_add_sup gt other given other_i given_i pos ff ``sup_rtl]

meta def superposition_inf : inference :=
take given, do gt ← get_term_order,
superposition_fwd_inf gt given,
superposition_back_inf gt given
