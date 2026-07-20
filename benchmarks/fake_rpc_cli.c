#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
  char line[65536];
  while (fgets(line, sizeof(line), stdin) != NULL) {
    char *id_marker = strstr(line, "\"id\":");
    long id = id_marker == NULL ? 0 : strtol(id_marker + 5, NULL, 10);
    printf("{\"jsonrpc\":\"2.0\",\"id\":%ld,\"result\":{\"status\":\"idle\"}}\n", id);
    fflush(stdout);
  }
  return 0;
}
