%{
#include <stdio.h>
#include <stdlib.h>

int yylex(void);                // Declaration for yylex
void yyerror(const char *s);    // Declaration for yyerror
%}


%union 
{
    int ival;
    float fval;
    char *sval;
}

%token <ival>   INT
%token <fval>   FLOAT
%token <sval>   STRING

%token          OTHER SEMICOLON PIC EOL

%type <ival>    expression

%%

input:
    expression EOL              {printf("%d\n", $1); }
    EOL;

expression:                     { printf("Empty input \n"); }
    | INT                       { printf("Integer: %d\n", $1);  $$ = $1; }
    | FLOAT                     { printf("Float: %f\n", $1);    $$ = $1; }
    | STRING                    { printf("String: %s\n", $1); free($1); }
    | expression '+' expression { printf("Add\n");              $$ = $1 + $3; }
    ;

%%

int main() {
    return yyparse();
}

void yyerror(const char *s) {
    fprintf(stderr, "Error: %s\n", s);
}
