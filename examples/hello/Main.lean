def fib : Nat → Nat
  | 0 => 0 | 1 => 1 | n+2 => fib n + fib (n+1)

def main (args : List String) : IO UInt32 := do
  IO.println s!"Hello from Lean {Lean.versionString} on a RISC-V guest!"
  IO.println s!"fib 25 = {fib 25}, 2^100 = {2^100}"
  let xs := (List.range 10).map (· * 3)
  IO.println s!"xs = {xs}, sum = {xs.foldl (· + ·) 0}, args = {args}"
  return 0
