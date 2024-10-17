%{
    #include "parser.tab.h"
    void showError();
%}

%option noyywrap

numbers ([0-9])+
alpha   ([a-zA-Z])+

%%

{numbers}+\.{numbers}   { yylval.fval = atof(yytext); return FLOAT; }
{numbers}               { yylval.ival = atoi(yytext); return INT; }
\"[^\"]*\"              { yylval.sval = strdup(yytext); return STRING; }

";"                     { return SEMICOLON;}

\n                      { return EOL; }

[ \t]         // Ignore whitespace

.               { showError(); return(OTHER); }

%%


void showError()
{
    printf("Other input");
}