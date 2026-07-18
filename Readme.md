# RZE (this is probably never going to work/finish)

## The Plan

The dream of RZE is to be a few things. At the core of RZE is something called
the rzvm. This VM is a bytecode interpreter designed to hold a few languages.
Most bytecode interpreters are made to be more efficient then an interpreted
language or to be able to run on multiple different operating systems. This
bytecode interpreter is moreso made to allow multiple language to interop with
each other over everything else. Because all of the languages should easily
interop this should be defined in the bytecode and not in the language. All rzvm
languages should use rzvm constructs whenever possible and if there is not a
construct for it, then it should be added.

This project is very ambitious and to start out my goal is to make a (mostly)
posix compliant shell. This is import to RZE because
1. Most people know some shell basics
2. Most shells which do have interesting features are not posix
3. Modern posix shells are slow and contain some archeaic choices (ie dynamic scoping)
4. I need a language which is able to deal with strings efficiently (most shells
   are OK at this but can be better)
5. I need a language to invoke editor commands
6. If the shell is good then people may want to use it without the editor

The core of the editor is planned to be written in a more stricter programming
language. To make it easy on myself that language is probably going to be a
scheme like language as
1. Its well defined so I have a standard I can follow
2. I can likely grab already existing libraries
3. It is very dynamic so I can make changes on the fly
4. It is simple to parse

The goal will be able to easily share state between the shell and scheme
language. If I am able to ever actually finish this I may look into doing stuff
like supporting elisp or a lua/js like language but I doubt I would be able to
do that. Keep in mind when i say lua/js moreso mean a lua/js like language as I
have already made some core decisions which would make this impossible/less
performant.

RZVM numbers will have 48 bits of data and 16 bits of header data. specifically
    type_info: TypeInfo, // u8
    ptr: bool,
    mutable: bool,
    nullable: bool,
    gc: GcBit, // u2
    reserved: u3,
    data: u48,
This means that each value being passed around between languages also has some
other information that all languages should support.

One particular feature I want is I should be able to do `(define func(x y) (+ x
y)` to make a function which adds x+y. I then want to be able to call said
function in ANY of the rzvm languages. To do that each compiler will have to
share a symbol table. The reason this isnt in the VM would be for performance so
there also should be a group of functions for the "standard way of doing things"
in each of the languages defined.


## Contribution

I would not suggest contributing until I start to actually make feature
branches because this repo is currently a mess of ideas. I may have broken the
style a lot but the goal is to use zig's standard contribution style.
https://ziglang.org/documentation/0.16.0/#Style-Guide . (when they exist) please
run test code to determine if you broke anything and if there are no tests for
your new feature then please make some basic ones.

You are allowed to use AI however please do not commit any AI code. Contributing
should help you learn how this project works. If you just want new features and
dont care about vibecoding then please fork this project and every once in a
while just pull from this repo. If you genuinely have no idea how this project
works then asking AI some basic questions is a great way to start but isnt the
only thing you should do. After asking questions then try to test your knowledge
by repeating back what you understand about it. If you don't think learning
through AI is good then great, don't use it this paragraph isnt for you just
read the source.
