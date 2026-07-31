#include "io.h"

#include <termios.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>

struct term{
  struct termios orig;
  struct termios raw;

  char prompt[MAX_PROMPTSIZE];
}t;

// @TODO(Renzix): Replace with actual text editor commands
static const struct { const char *seq; cmd_fn fn; } keymap[] = {
  { "\x01"   ,  ln_beginning         },
  { "\x05"   ,  ln_end               },
  { "\x04"   ,  ln_delete_or_eof     },
  { "\x7f"   ,  ln_backward_delete   },
  { "\x0d"   ,  ln_accept            },
  { "\x0A"   ,  ln_accept            },
  { "\x0b"   ,  ln_kill              },
  { "\eb"    ,  ln_backward_word     },
  { "\ef"    ,  ln_forward_word      },
  { "\e[D"   ,  ln_backward_char     },
  { "\e[C"   ,  ln_forward_char      },
};

void rzterm_init(const char* prompt, size_t promptsize) {
  if(promptsize>=MAX_PROMPTSIZE) _exit(1);
  tcgetattr(STDIN_FILENO, &t.orig);
  t.raw = t.orig;
  strncpy(t.prompt, prompt, promptsize);

  t.raw.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
  t.raw.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);
  t.raw.c_cflag |=  CS8;
  t.raw.c_cc[VMIN]  = 1;
  t.raw.c_cc[VTIME] = 0;
}

int rzterm_getline(char* arr, size_t arrsize) {
  tcsetattr(STDIN_FILENO, TCSADRAIN, &t.raw);
  line_t l = {0};
  l.buf = arr;
  l.cap = arrsize;
  l.n = 0;
  l.pos = 0;
  bool blk = false;
  rzterm_refresh(&l);

  char temp[MAX_CODE] = {0};
  uint8_t index=0;
  input_sm sm = INPUT_INIT;
  while (l.n < l.cap - 1) {
    char ch;
    ssize_t r = read(STDIN_FILENO, &ch, 1);
    if (r == 0) break;
    if (r < 0) { if (errno == EINTR) continue; return -1; }

    if (index>=MAX_CODE) _exit(1);
    temp[index]=ch;
    sm = read_more_input(sm, temp, index++);
    if (sm != INPUT_DONE) continue;
    sm = INPUT_INIT;
    cmd_fn fn = keymap_lookup(temp, index);
    index=0;

    cmdret_t ret = fn ? fn(&l) : ln_self_insert(&l, ch);
    switch (ret) {
      case CMD_REFRESH: {
        rzterm_refresh(&l);
      }
      case CMD_NORM: {
        break;
      }
      case CMD_EOF: {
        return -1;
      }
      case CMD_DONE: {
        blk = true;
        break;
      }

    }
    if (blk) break;
  }
  l.buf[l.n] = '\0';

  write(STDOUT_FILENO, "\r\n", 2);
  tcsetattr(STDIN_FILENO, TCSADRAIN, &t.orig);
  return l.n;
}

void rzterm_refresh(line_t *l) {
  char out[MAX_OUT]; // @TODO(Renzix): Make better
  size_t k = 0;
  size_t plen = strlen(t.prompt);

  out[k++] = '\r';
  memcpy(out + k, t.prompt, plen);
  k += plen;
  // @TODO(Renzix): syntax highlighting
  memcpy(out + k, l->buf, l->n);
  k += l->n;
  memcpy(out + k, "\x1b[0K", 4);
  k += 4;

  out[k++] = '\r';

  size_t col = plen + l->pos;
  if (col > 0)
    k += snprintf(out + k, sizeof(out) - k, "\x1b[%zuC", col);

  write(STDOUT_FILENO, out, k);
}

cmd_fn keymap_lookup(char* seq, size_t seqlen) {
  for (size_t i = 0; i < sizeof(keymap) / sizeof(keymap[0]); i++) {
    if (strlen(keymap[i].seq) == seqlen &&
        memcmp(keymap[i].seq, seq, seqlen) == 0)
      return keymap[i].fn;
  }
  return NULL;
}

cmdret_t ln_self_insert(line_t *l, char ch) {
  if (l->n + 1 >= l->cap)
    return CMD_NORM;
  memmove(l->buf + l->pos + 1, l->buf + l->pos, l->n - l->pos);
  l->buf[l->pos++] = ch;
  l->n++;
  return CMD_REFRESH;
}

input_sm read_more_input(input_sm sm, char* arr, size_t index) {
  char ch = arr[index];
  switch(sm) {
    case INPUT_INIT: {
      assert(index==0);
      switch(ch) {
        case '\e': { return INPUT_ESC; }
        default: { return INPUT_DONE; }
      }
      break;
    }
    case INPUT_ESC: {
      switch(ch) {
        case '[': return INPUT_CSI;
        default: return INPUT_DONE;
      }
      break;
    }
    case INPUT_CSI: {
      if ((ch < 0x40) || (ch > 0x7E))
        return INPUT_CSI;
      else
        return INPUT_DONE;
      break;
    }
    case INPUT_DONE: {
      break;
    }
  }
  printf("Failed to read input");
  assert(false);
}

// keybinded commands @TODO(Renzix): put into my language or zig?
cmdret_t ln_backward_delete(line_t *l) {
  if (l->pos == 0)
    return CMD_NORM;
  memmove(l->buf + l->pos - 1, l->buf + l->pos, l->n - l->pos);
  l->n--;
  l->pos--;
  return CMD_REFRESH;
}

cmdret_t ln_accept(line_t *l) {
  return CMD_DONE;
}

cmdret_t ln_beginning(line_t *l) {
  l->pos = 0;
  return CMD_REFRESH;
}
cmdret_t ln_end(line_t *l) {
  l->pos = l->n;
  return CMD_REFRESH;
}

cmdret_t ln_delete_or_eof(line_t *l) {
  if (l->n==0)
    return CMD_EOF;
  if (l->pos == l->n)
    return CMD_NORM;
  memmove(l->buf + l->pos - 1, l->buf + l->pos, l->n - l->pos);
  l->n--;
  return CMD_REFRESH;
}

cmdret_t ln_kill(line_t *l) {
  l->n=l->pos;
  return CMD_REFRESH;
}

cmdret_t ln_backward_word(line_t *l) {
  while((l->pos > 0) && (l->buf[l->pos-1] == ' ')) l->pos--;
  while((l->pos > 0) && (l->buf[l->pos-1] != ' ')) l->pos--;
  return CMD_REFRESH;
}

cmdret_t ln_forward_word(line_t *l) {
  while((l->pos < l->n-1) && (l->buf[l->pos] == ' ')) l->pos++;
  while((l->pos < l->n-1) && (l->buf[l->pos] != ' ')) l->pos++;
  return CMD_REFRESH;
}

cmdret_t ln_forward_char(line_t *l) {
  if (l->pos < l->n) l->pos++;
  return CMD_REFRESH;
}

cmdret_t ln_backward_char(line_t *l) {
  if (l->pos >= 0) l->pos--;
  return CMD_REFRESH;
}
