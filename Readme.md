# RZE (this is probably never going to work/finish)

## The Plan

The dream of RZE is to be a few things. At the core of RZE is something called
the rzvm. This VM is a bytecode interpreter designed to hold a few languages.
Most bytecode interpreters are made to be more efficient then an interpreted
language or to be able to run on multiple different operating systems. This
bytecode interpreter is moreso made to allow multiple language to interop with
each other. Because all of the languages should easily interop this should be
defined in the bytecode/VM/ISA and not in the language. Any language specific
feature should probably be apart of the ISA. The big downside of this is that
the ISA will be large but i feel that should be OKAY.

The main goal right now is to create the bytecode interpreter then follow it up
with a basic lisp language. I like using standards so ideally I would attempt to
implement Scheme. After this I could start on a simple shell (ideally
posix-like). Once that is done for langauges i would love to attempt to
implement lua-like or javascript-like or even try to do elisp/viml but
realistically what i am doing is already way too much work for one person.

After the languages are created and the featureset is usable I can start
actually using them. Before the text editor is useful it would be motivating to
start using RZX as my main shell. One thing shell sucks at is dealing with
strings so adding ways to parse strings would be very benefitual. This could
totally be a library that is in my scheme language.

RZVM numbers will have 48 bits of data and 16 bits of header data. specifically
    type_info: TypeInfo, // u8
    ptr: u1,
    mutable: u1,
    nullable: u1,
    err: u1,
    gc: GcBit, // u2
    reserved: u2,
    data: u48,
This means that each value being passed around between languages also has some
other information that all languages should support. All RZVM languages should
define functions as variables so that the other languages have access to them.

One particular feature I want is I should be able to do `(define func(x y) (+ x
y)` to make a function which adds x+y. I then want to be able to call said
function in ANY of the rzvm languages. To do that each compiler will have to
share a symbol table. The reason this isnt in the VM would be for performance so
there also should be a group of functions for the "standard way of doing things"
in each of the languages defined.


