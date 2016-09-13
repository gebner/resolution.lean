import clause prover_state
open tactic monad

private meta_definition try_subsume_core (small large : list cls.lit) : tactic unit :=
if list_empty small = tt then skip
else first (do
  i ← list_zipwithindex small,
  j ← list_zipwithindex large,
  return (do
    unify_lit i.1 j.1,
    try_subsume_core (list_remove small i.2) large))

-- FIXME: this is incorrect if a quantifier is unused
meta_definition try_subsume (small large : cls) : tactic unit := do
small_open ← cls.open_metan small (cls.num_quants small),
large_open ← cls.open_constn large (cls.num_quants large),
try_subsume_core (cls.get_lits small_open.1) (cls.get_lits large_open.1)

meta_definition does_subsume (small large : cls) : tactic bool :=
(try_subsume small large >> return tt) <|> return ff

set_option new_elaborator true
example
  (i : Type)
  (p : i → Prop)
  (f : i → i)
  (prf1 : ∀x, ¬p x → false)
  (prf2 : ∀x, ¬p (f x) → p x → false)
  (prf3 : ∀x, p (f x) → ¬p x → false)
  : true :=
by do
  prf1 ← get_local `prf1, ty1 ← infer_type prf1, cls1 ← return $ cls.mk 1 1 prf1 ty1,
  prf2 ← get_local `prf2, ty2 ← infer_type prf2, cls2 ← return $ cls.mk 1 2 prf2 ty2,
  prf3 ← get_local `prf3, ty3 ← infer_type prf3, cls3 ← return $ cls.mk 1 2 prf3 ty3,
  forM' [cls1,cls2,cls3] (λc1, forM' [cls1,cls2,cls3] (λc2, do
    trace "Subsuming:",
    trace (cls.type c1),
    trace (cls.type c2),
    does_subsume c1 c2 >>= trace,
    trace ""
  )),
  mk_const ``true.intro >>= apply
set_option new_elaborator false

meta_definition any_tt (active : rb_map name active_cls) (pred : active_cls → tactic bool) : tactic bool :=
rb_map.fold active (return ff) $ λk a cont, do
  v ← pred a, if v = tt then return tt else cont

meta_definition forward_subsumption : inference := redundancy_inference $ λgiven, do
active ← get_active,
resolution_prover_of_tactic $ any_tt active (λa, does_subsume (active_cls.c a) (active_cls.c given))

meta_definition forward_subsumption_new : preprocessing_rule := λnew, do
active ← get_active,
filterM (λn, resolution_prover_of_tactic $
  any_tt active (λa, does_subsume (active_cls.c a) n)) new

meta_definition keys_where_tt (active : rb_map name active_cls) (pred : active_cls → tactic bool) : tactic (list name) :=
@rb_map.fold _ _ (tactic (list name)) active (return []) $ λk a cont, do
  v ← pred a, rest ← cont, return $ if v = tt then k::rest else rest

meta_definition backward_subsumption : inference := λgiven, do
active ← get_active,
ss ← resolution_prover_of_tactic $
  keys_where_tt active (λa, does_subsume (active_cls.c given) (active_cls.c a)),
return ([], ss)