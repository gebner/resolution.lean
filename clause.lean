import init.meta.tactic utils
open expr list tactic monad decidable

meta structure clause :=
(num_quants : ℕ)
(num_lits : ℕ)
(proof : expr)
(type : expr)

namespace clause

private meta def tactic_format (c : clause) : tactic format := do
prf_fmt : format ← pp (proof c),
type_fmt ← pp (type c),
return $ prf_fmt ++ to_fmt " : " ++ type_fmt ++ to_fmt " (" ++
  to_fmt (num_quants c) ++ to_fmt " quants, " ++ to_fmt (num_lits c) ++ to_fmt " lits" ++ to_fmt ")"

meta instance : has_to_tactic_format clause := ⟨tactic_format⟩

meta def num_binders (c : clause) : ℕ := num_quants c + num_lits c

/- foo foo -- bar baz -/

private meta def parse_clause_type : expr → ℕ × ℕ × bool
| (pi n bi d b) :=
  match parse_clause_type b with
  | (0, ls, fin) := if has_var b then (1, ls, fin) else (0, ls+1, fin)
  | (qs, ls, fin) := (qs+1, ls, fin)
  end
| e := if expr.is_false e then (0, 0, ff) else (0, 1, tt)

meta def validate (c : clause) : tactic unit := do
type' ← infer_type c↣proof,
unify c↣type type' <|> (do pp_ty ← pp c↣type, pp_ty' ← pp type',
                           fail (to_fmt "wrong type: " ++ pp_ty ++ " =!= " ++ pp_ty'))

meta def inst (c : clause) (e : expr) : clause :=
(if num_quants c > 0
  then mk (num_quants c - 1) (num_lits c)
  else mk 0 (num_lits c - 1))
(app (proof c) e) (instantiate_var (binding_body (type c)) e)

meta def instn (c : clause) (es : list expr) : clause :=
foldr (λe c', inst c' e) c es

meta def open_const (c : clause) : tactic (clause × expr) := do
n ← mk_fresh_name,
b ← return $ local_const n (binding_name (type c)) (binding_info (type c)) (binding_domain (type c)),
return (inst c b, b)

meta def open_meta (c : clause) : tactic (clause × expr) := do
b ← mk_meta_var (binding_domain (type c)),
return (inst c b, b)

meta def close_const (c : clause) (e : expr) : clause :=
match e with
| local_const uniq pp info t :=
    let abst_type' := abstract_local (type c) (local_uniq_name e) in
    let type' := pi pp binder_info.default t (abstract_local (type c) uniq) in
    let abs_prf := abstract_local (proof c) uniq in
    let proof' := lambdas [e] c↣proof in
    if num_quants c > 0 ∨ has_var abst_type' then
      { c with num_quants := c↣num_quants + 1, proof := proof', type := type' }
    else
      { c with num_lits := c↣num_lits + 1, proof := proof', type := type' }
| _ := ⟨0, 0, default expr, default expr⟩
end

meta def open_constn : clause → ℕ → tactic (clause × list expr)
| c 0 := return (c, nil)
| c (n+1) := do
  (c', b) ← open_const c,
  (c'', bs) ← open_constn c' n,
  return (c'', b::bs)

meta def open_metan : clause → ℕ → tactic (clause × list expr)
| c 0 := return (c, nil)
| c (n+1) := do
  (c', b) ← open_meta c,
  (c'', bs) ← open_metan c' n,
  return (c'', b::bs)

meta def close_constn : clause → list expr → clause
| c [] := c
| c (b::bs') := close_const (close_constn c bs') b

set_option eqn_compiler.max_steps 500

private meta def parse_clause : expr → expr → tactic clause
| proof (pi n bi d b) := do
  lc_n ← mk_fresh_name,
  lc ← return $ local_const lc_n n bi d,
  c ← parse_clause (app proof lc) (instantiate_var b lc),
  return $ c↣close_const (local_const lc_n n binder_info.default d)
| proof (const ``false []) := return { num_quants := 0, num_lits := 0, proof := proof, type := false_ }
| proof (app (const ``not []) formula) := parse_clause proof (formula↣imp false_)
| proof type := do
  univ ← infer_univ type,
  not_type ← return $ if univ = level.zero then not_ type else type↣imp false_,
  parse_clause (lam `H binder_info.default not_type $ app (mk_var 0) proof) (imp not_type false_)

meta def of_proof_and_type (proof type : expr) : tactic clause :=
parse_clause proof type

meta def of_proof (proof : expr) : tactic clause := do
type ← infer_type proof,
of_proof_and_type proof type

meta def inst_mvars (c : clause) : tactic clause := do
proof' ← instantiate_mvars (proof c),
type' ← instantiate_mvars (type c),
return { c with proof := proof', type := type' }

meta inductive literal
| left : expr → literal
| right : expr → literal

namespace literal

meta instance : decidable_eq literal := by mk_dec_eq_instance

meta def formula : literal → expr
| (left f) := f
| (right f) := f

meta def is_neg : literal → bool
| (left _) := tt
| (right _) := ff

meta def is_pos (l : literal) : bool := bnot l↣is_neg

meta def to_formula (l : literal) : tactic expr :=
if is_neg l then mk_mapp ``not [some (formula l)]
else return (formula l)

meta def type_str : literal → string
| (literal.left _) := "left"
| (literal.right _) := "right"

meta instance : has_to_tactic_format literal :=
⟨λl, do
pp_f ← pp l↣formula,
return $ to_fmt l↣type_str ++ " (" ++ pp_f ++ ")"⟩

end literal

private meta def get_binding_body : expr → ℕ → expr
| e 0 := e
| e (i+1) := get_binding_body e↣binding_body i

meta def get_binder (e : expr) (i : nat) :=
binding_domain (get_binding_body e i)

meta def get_lit (c : clause) (i : nat) : literal :=
let bind := get_binder (type c) (num_quants c + i) in
match is_not bind with
| some formula := literal.right formula
| none := literal.left bind
end

meta def lits_where (c : clause) (p : literal → bool) : list nat :=
list.filter (λl, p (get_lit c l)) (range (num_lits c))

meta def get_lits (c : clause) : list literal :=
list.map (get_lit c) (range c↣num_lits)

meta def is_maximal (gt : expr → expr → bool) (c : clause) (i : nat) : bool :=
list.empty (filter (λj, gt (get_lit c j)↣formula (get_lit c i)↣formula) (range c↣num_lits))

meta def normalize (c : clause) : tactic clause := do
opened  ← open_constn c (num_binders c),
lconsts_in_types ← return $ contained_lconsts_list (list.map local_type opened.2),
quants' ← return $ filter (λlc, rb_map.contains lconsts_in_types (local_uniq_name lc)) opened.2,
lits' ← return $ filter (λlc, ¬rb_map.contains lconsts_in_types (local_uniq_name lc)) opened.2,
return $ close_constn opened.1 (quants' ++ lits')

meta def whnf_head_lit (c : clause) : tactic clause := do
atom' ← whnf (literal.formula $ get_lit c 0),
return $
if literal.is_neg (get_lit c 0) then
  { c with type := imp atom' (binding_body c↣type) }
else
  { c with type := imp (app (const ``not []) atom') c↣type↣binding_body }

end clause

meta def unify_lit (l1 l2 : clause.literal) : tactic unit :=
if clause.literal.is_pos l1 = clause.literal.is_pos l2 then
  unify_core transparency.none (clause.literal.formula l1) (clause.literal.formula l2)
else
  fail "cannot unify literals"

-- FIXME: this is most definitely broken with meta-variables that were already in the goal
meta def sort_and_constify_metas : list expr → tactic (list expr)
| exprs_with_metas := do
inst_exprs ← mapM instantiate_mvars exprs_with_metas,
metas ← return $ inst_exprs >>= get_metas,
match list.filter (λm, ¬has_meta_var (get_meta_type m)) metas with
| [] :=
     if list.empty metas then
       return []
     else do
       forM' metas (λm, do trace (expr.to_string m), t ← infer_type m, trace (expr.to_string t)),
       fail "could not sort metas"
| ((mvar n t) :: _) := do
  t' ← infer_type (mvar n t),
  uniq ← mk_fresh_name,
  c ← return (local_const uniq uniq binder_info.default t'),
  unify c (mvar n t),
  rest ← sort_and_constify_metas metas,
  return (rest ++ [c])
| _ := failed
end

namespace clause

meta def meta_closure (metas : list expr) (qf : clause) : tactic clause := do
bs ← sort_and_constify_metas metas,
qf' ← clause.inst_mvars qf,
clause.inst_mvars $ clause.close_constn qf' bs

end clause
