import init.meta.tactic
open expr list tactic monad decidable

meta_definition imp (a b : expr) : expr :=
pi (default name) binder_info.default a b

definition range : ℕ → list ℕ
| (n+1) := n :: range n
| 0 := []

definition option_getorelse {B} (opt : option B) (val : B) : B :=
match opt with
| some x := x
| none := val
end

definition list_empty {A} (l : list A) : bool :=
match l with
| [] := tt
| _::_ := ff
end

private definition list_zipwithindex' {A} : nat → list A → list (A × nat)
| _ nil := nil
| i (x::xs) := (x,i) :: list_zipwithindex' (i+1) xs

definition list_zipwithindex {A} : list A → list (A × nat) :=
list_zipwithindex' 0

definition list_remove {A} : list A → nat → list A
| []      _     := []
| (x::xs) 0     := xs
| (x::xs) (i+1) := x :: list_remove xs i

structure cls :=
(num_quants : ℕ)
(num_lits : ℕ)
(prf : expr)
(type : expr)

namespace cls

definition num_binders (c : cls) := num_quants c + num_lits c

/- private -/ lemma clause_of_formula {p} : p → ¬p → false := λx y, y x

meta_definition of_proof (prf : expr) : tactic cls := do
prf' ← mk_mapp ``clause_of_formula [none, some prf],
type' ← infer_type prf',
return (mk 0 1 prf' type')

meta_definition inst (c : cls) (e : expr) : cls :=
(if num_quants c > 0
  then mk (num_quants c - 1) (num_lits c)
  else mk 0 (num_lits c - 1))
(app (prf c) e) (instantiate_var (binding_body (type c)) e)

meta_definition open_const (c : cls) : tactic (cls × expr) := do
n ← mk_fresh_name,
b ← return $ local_const n (binding_name (type c)) (binding_info (type c)) (binding_domain (type c)),
return (inst c b, b)

meta_definition open_meta (c : cls) : tactic (cls × expr) := do
b ← mk_meta_var (binding_domain (type c)),
return (inst c b, b)

set_option new_elaborator true
meta_definition close_const (c : cls) (e : expr) : cls :=
match e with
| local_const uniq pp info t :=
    let abst_type' := abstract_local (type c) (local_uniq_name e) in
    let type' := pi pp info t (abstract_local (type c) uniq) in
    let prf' := lam pp info t (abstract_local (prf c) uniq) in
    if num_quants c > 0 ∨ has_var abst_type' then
      mk (num_quants c + 1) (num_lits c) prf' type'
    else
      mk 0 (num_lits c + 1) prf' type'
| _ := mk 0 0 (mk_var 0) (mk_var 0)
end
set_option new_elaborator false

meta_definition open_constn (c : cls) : nat → tactic (cls × list expr)
| 0 := return (c, nil)
| (n+1) := do
  (c', b) ← open_const c,
  (c'', bs) ← open_constn c' n,
  return (c'', b::bs)

meta_definition open_metan (c : cls) : nat → tactic (cls × list expr)
| 0 := return (c, nil)
| (n+1) := do
  (c', b) ← open_meta c,
  (c'', bs) ← open_metan c' n,
  return (c'', b::bs)

meta_definition close_constn (c : cls) (bs : list expr) : cls :=
match bs with
| nil := c
| b::bs' := close_constn (close_const c b) bs'
end

meta_definition inst_mvars (c : cls) : tactic cls := do
prf' ← instantiate_mvars (prf c),
type' ← instantiate_mvars (type c),
return $ cls.mk (cls.num_quants c) (cls.num_lits c) prf' type'

private meta_definition get_binder (e : expr) (i : nat) :=
if i = 0 then binding_domain e else get_binder (binding_body e) (i-1)

inductive lit
| pos : expr → lit
| neg : expr → lit

namespace lit

definition formula : lit → expr
| (pos f) := f
| (neg f) := f

definition is_neg : lit → bool
| (pos _) := ff
| (neg _) := tt

definition is_pos (l : lit) : bool := bool.bnot (is_neg l)

meta_definition to_formula : lit → tactic expr
| (pos f) := mk_mapp ``not [some f]
| (neg f) := return f

end lit

set_option new_elaborator true
meta_definition get_lit (c : cls) (i : nat) : lit :=
let bind := get_binder (type c) (num_quants c + i) in
if is_app_of bind ``not = tt ∧ get_app_num_args bind = 1 then
  lit.pos (app_arg bind)
else
  lit.neg bind
set_option new_elaborator false

private meta_definition lits_where' (c : cls) (p : lit → bool) (i : nat) : list nat :=
if i = cls.num_lits c then
  []
else if p (get_lit c i) = tt then
  i :: lits_where' c p (i+1)
else
  lits_where' c p (i+1)

meta_definition lits_where (c : cls) (p : lit → bool) : list nat :=
lits_where' c p 0

meta_definition get_lits (c : cls) : list lit :=
map (get_lit c) (range (num_lits c))

end cls

meta_definition unify_lit : cls.lit → cls.lit → tactic unit
| (cls.lit.pos a) (cls.lit.pos b) := unify a b
| (cls.lit.neg a) (cls.lit.neg b) := unify a b
| _ _ := fail "cannot unify literals"

-- FIXME: this is most definitely broken with meta-variables that were already in the goal

meta_definition get_metas : expr → list expr
| (var _) := []
| (sort _) := []
| (const _ _) := []
| (meta n t) := expr.meta n t :: get_metas t
| (local_const _ _ _ t) := get_metas t
| (app a b) := get_metas a ++ get_metas b
| (lam _ _ d b) := get_metas d ++ get_metas b
| (pi _ _ d b) := get_metas d ++ get_metas b
| (elet _ t v b) := get_metas t ++ get_metas v ++ get_metas b
| (macro _ _ _) := []

meta_definition get_meta_type : expr → expr
| (meta _ t) := t
| _ := mk_var 0

meta_definition sort_and_constify_metas (exprs_with_metas : list expr) : tactic (list expr) := do
inst_exprs ← @mapM tactic _ _ _ instantiate_mvars exprs_with_metas,
metas ← return $ inst_exprs >>= get_metas,
match list.filter (λm, has_meta_var (get_meta_type m) = ff) metas with
| [] := if list_empty metas = tt then return [] else forM' metas (λm, do trace (to_string m), t ← infer_type m, trace (to_string t)) >> fail "could not sort metas"
| ((meta n t) :: _) := do
  t' ← infer_type (meta n t),
  uniq ← mk_fresh_name,
  c ← return (local_const uniq uniq binder_info.default t'),
  unify c (meta n t),
  rest ← sort_and_constify_metas metas,
  return (rest ++ [c])
| _ := failed
end