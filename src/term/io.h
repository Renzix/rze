#ifndef __IO_H__
#define __IO_H__

#include <stdio.h>
#include <stdbool.h>

extern void rzterm_init(const char* prompt, size_t promptsize);
extern int rzterm_getline(char* arr, size_t arrsize);

// internal
// Do not touch unless you know what ur doing
typedef enum { CMD_NORM, CMD_REFRESH, CMD_EOF, CMD_DONE, } cmdret_t;
typedef struct{
  char* buf;
  size_t pos, n, cap;
} line_t;
typedef cmdret_t (*cmd_fn)(line_t *l);

typedef enum { INPUT_INIT, INPUT_DONE, INPUT_ESC, INPUT_CSI } input_sm;

void rzterm_refresh(line_t *l);
cmd_fn keymap_lookup(char* seq, size_t seqlen);
input_sm read_more_input(input_sm sm, char* arr, size_t index);
cmdret_t ln_self_insert(line_t *l, char ch);

cmdret_t ln_backward_delete(line_t *l);
cmdret_t ln_accept(line_t *l);
cmdret_t ln_beginning(line_t *l);
cmdret_t ln_end(line_t *l);
cmdret_t ln_delete_or_eof(line_t *l);
cmdret_t ln_kill(line_t *l);

cmdret_t ln_forward_word(line_t *l);
cmdret_t ln_backward_word(line_t *l);

#endif // __IO_H__
