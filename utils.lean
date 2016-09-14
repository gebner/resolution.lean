open tactic expr list

meta_definition monadfail_of_option {m : Type → Type} [monad m] [alternative m] {A} : option A → m A
| none := failure
| (some a) := return a

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

definition list_orb : list bool → bool
| (tt::xs) := tt
| (ff::xs) := list_orb xs
| [] := ff

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

meta_definition expr_size : expr → nat
| (var _) := 1
| (sort _) := 1
| (const _ _) := 1
| (meta n t) := 1
| (local_const _ _ _ _) := 1
| (app a b) := expr_size a + expr_size b
| (lam _ _ d b) := expr_size b
| (pi _ _ d b) := expr_size b
| (elet _ t v b) := expr_size v + expr_size b
| (macro _ _ _) := 1

namespace rb_map
meta_definition values {K V} (m : rb_map K V) : list V :=
fold m [] (λk v vs, v::vs)
end rb_map

namespace list

definition foldr {A B} (f : A → B → B) (b : B) : list A → B
| [] := b
| (a::ass) := f a (foldr ass)

definition foldl {A B} (f : B → A → B) : B → list A → B
| b [] := b
| b (a::ass) := foldl (f b a) ass

private meta_definition contained_lconsts' : expr → rb_map name unit → rb_map name unit
| (var _) m := m
| (sort _) m := m
| (const _ _) m := m
| (meta _ t) m := contained_lconsts' t m
| (local_const uniq pp bi t) m := contained_lconsts' t (rb_map.insert m uniq ())
| (app a b) m := contained_lconsts' a (contained_lconsts' b m)
| (lam _ _ d b) m := contained_lconsts' d (contained_lconsts' b m)
| (pi _ _ d b) m := contained_lconsts' d (contained_lconsts' b m)
| (elet _ t v b) m := contained_lconsts' t (contained_lconsts' v (contained_lconsts' b m))
| (macro _ _ _) m := m

meta_definition contained_lconsts (e : expr) : rb_map name unit :=
contained_lconsts' e (rb_map.mk name unit)

meta_definition contained_lconsts_list (es : list expr) : rb_map name unit :=
foldl (λlcs e, contained_lconsts' e lcs) (rb_map.mk name unit) es

meta_definition local_type : expr → expr
| (local_const _ _ _ t) := t
| e := e

end list