%{
#include <stdio.h>
#include <stdlib.h>
%}

%token INT
%token Float
%token STRING
%token OPERATOR


%%
input:  /* empty */
        | input line
;

line:   '\n'
        | exp '\n'  {
                        printf ("\t%.10g\n", $1);
                    }
;

exp:    
        INT             { $$ = $1; }
        | exp exp '+'   { $$ = $1 + $2; }
        | exp exp '-'   { $$ = $1 - $2; }
        | exp exp '*'   { $$ = $1 * $2; }
        | exp exp '/'   { $$ = $1 / $2; }
        /* Exponentition */
        | exp exp '^'   { $$ = pow ($1, $2); }
        /* Unary minus */
        | exp 'n'       { $$ = -$1; }
;
%%

int main() {
    yyparse();
    return 0;
}

void yyerror(const char *s) {
    fprintf(stderr, "Error: %s\n", s);
}