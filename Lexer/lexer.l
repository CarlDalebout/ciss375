%{
#include <math.h>
#include <ctype.h>
%}

%option noyywrap

DIGIT   [0-9]
ID      [a-zA-Z][a-z0-9]*
CHAR    [a-zA-Z]
STRING  ["][a-zA-Z ]+["]

/* rules */
%%

{ID}                {
                        printf("ID Token (%s)\n", yytext);
                    }

{STRING}            {
                        printf("String Token (%s)\n", yytext);
                    }

{DIGIT}+"."{DIGIT}* {
                        printf("Float token (%s)\n", yytext);
                    }

{DIGIT}+            {
                        printf("Int Token (%d)\n", atoi( yytext ));
                    }

"+"|"-"|"*"|"/"|"=" {
                        printf("Operator Token (%s)\n", yytext);
                    }

"//"[^}\n]*         /*  eat up one-line comments */

[ \t\n]+            /*  eat up white space */

%%

int main(){
    printf("Enter a string: ");
    yylex();

    return 0;
}