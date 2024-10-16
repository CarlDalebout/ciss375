/*
 *  The scanner definition for COOL.
 */

/*
 *  Stuff enclosed in %{ %} in the first section is copied verbatim to the
 *  output, so headers and global definitions are placed here to be visible
 * to the code in the file.  Don't remove anything that was here initially
 */
%{
#include <cool-parse.h>
#include <stringtab.h>
#include <utilities.h>

/* The compiler assumes these identifiers. */
#define yylval cool_yylval
#define yylex  cool_yylex

/* Max size of string constants */
#define MAX_STR_CONST 1025
#define YY_NO_UNPUT   /* keep g++ happy */

extern FILE *fin; /* we read from this file */

/* define YY_INPUT so we read from the FILE fin:
 * This change makes it possible to use this scanner in
 * the Cool compiler.
 */
#undef YY_INPUT
#define YY_INPUT(buf,result,max_size) \
  if ( (result = fread( (char*)buf, sizeof(char), max_size, fin)) < 0) \
    YY_FATAL_ERROR( "read() in flex scanner failed");

/* ============== Declarations ============================================== */

char string_buf[MAX_STR_CONST]; /* to assemble string constants */
char *string_buf_ptr;

extern int curr_lineno;
extern int verbose_flag;
extern YYSTYPE cool_yylval;

/* make sure we don't go over the Cool string limit */
int str_size = 0;

/* use to deal with nested comments correctly */
int nested_comment = 0;

/* function declarations, initialized at the bottom in subroutines. */
#define OUTPUT_ERROR(message) { \
      cool_yylval.error_msg = (message); \
      return ERROR; \
  }

#define ADD_TO_STR(characters) { \
      if (string_buf_ptr + 1 > &string_buf[MAX_STR_CONST - 1]) { \
          BEGIN(INVALID_STRING); \
          OUTPUT_ERROR("String constant too long"); \
      } \
      *string_buf_ptr++ = (characters); \
  }

%}

/* here to make g++ happy */
%option noyywrap

/*  ================================================================================
 *  Definitions
 *  ================================================================================ */

%x COMMENT
%x IN_LINE_COMMENT

%x STRING
%x INVALID_STRING

/* Defined names for regular expressions */

DIGIT         [0-9]
OBJECTID      [a-z][a-zA-Z0-9_]*
TYPEID        [A-Z][a-zA-Z0-9_]*

LE            <=
ASSIGN        <-
DARROW        =>

%%

/*  ================================================================================
 *  Rules
 *  ================================================================================
 *
 * Define regular expressions for the tokens of COOL here. Make sure, you
 * handle correctly special cases, like:
 *   - Nested comments
 *   - String constants: They use C like systax and can contain escape
 *     sequences. Escape sequence \c is accepted for all characters c. Except
 *     for \n \t \b \f, the result is c.
 *   - Keywords: They are case-insensitive except for the values true and
 *     false, which must begin with a lower-case letter.
 *   - Multiple-character operators (like <-): The scanner should produce a
 *     single token for every such operator.
 *   - Line counting: You should keep the global variable curr_lineno updated
 *     with the correct line number
 */

/* operators/other symbols */


"-"              return '-';
"*"              return '*';
"+"              return '+';
"/"              return '/';

"="              return '=';
"<"              return '<';
"."              return '.';
":"              return ':';
"@"              return '@';
"~"              return '~';
","              return ',';
";"              return ';';
"{"              return '{';
"}"              return '}';
"("              return '(';
")"              return ')';


{DARROW}    return DARROW;
{ASSIGN}    return ASSIGN;
{LE}        return LE;

/* ================================================================================
 * Structers
 * ================================================================================*/

(?i:class)        return (CLASS);

(?i:if)           return (IF);
(?i:fi)           return (FI);
(?i:else)         return (ELSE);
(?i:then)         return (THEN);

(?i:loop)         return (LOOP);
(?i:pool)         return (POOL);

(?i:case)         return (CASE);
(?i:esac)         return (ESAC);

(?i:in)           return (IN);
(?i:inherits)     return (INHERITS);
(?i:let)          return (LET);
(?i:while)        return (WHILE);
(?i:isvoid)       return (ISVOID);
(?i:new)          return (NEW);
(?i:of)           return (OF);
(?i:not)          return (NOT);


t(?i:rue)     {
                 cool_yylval.boolean = true;
                 return (BOOL_CONST);
              }
f(?i:alse)    {
                 cool_yylval.boolean = false;
                 return (BOOL_CONST);
              }

/* ================================================================================
 * Regex
 * ================================================================================*/

{DIGIT}+      {
                 cool_yylval.symbol = inttable.add_string(yytext);
                 return INT_CONST;
	            }

{OBJECTID}    {
                 cool_yylval.symbol = stringtable.add_string(yytext);
                 return (OBJECTID);
              }
{TYPEID}      {
                 cool_yylval.symbol = stringtable.add_string(yytext);
                 return (TYPEID);
              }

/* ================================================================================
 * String Rules
 * ================================================================================*/

\"          {
                string_buf_ptr = string_buf;
                BEGIN(STRING);
            }
<STRING>\" {
                cool_yylval.symbol = stringtable.add_string(string_buf);
                *string_buf_ptr = '\0';
                BEGIN(INITIAL);
                return STR_CONST;
}
<STRING>\0 {
                BEGIN(INVALID_STRING);
                OUTPUT_ERROR("String contains null character");
}
<STRING>\\\0 {
                BEGIN(INVALID_STRING);
                OUTPUT_ERROR("String contains null character");
}
<STRING>\n {
                ++curr_lineno;
                BEGIN(INITIAL);
                OUTPUT_ERROR("Unterminated string constant");
}
<STRING><<EOF>> {
                BEGIN(INITIAL);
                OUTPUT_ERROR("EOF in string constant");
}
<STRING>\\b {
                ADD_TO_STR('\b');       /* backspace */
}
<STRING>\\f {
                ADD_TO_STR('\f');       /* formfeed */
}
<STRING>\\t {
                ADD_TO_STR('\t');       /* tab */
}
<STRING>\\n {
                ADD_TO_STR('\n');       /* newline */
}
<STRING>\\\n {
                /* escaped newline */
                ++curr_lineno;
                ADD_TO_STR('\n');

}
<STRING>\\. {
                ADD_TO_STR(yytext[1]);
}
<STRING>[^\\\n\0\"]+ {
                if (string_buf_ptr + yyleng >
                        &string_buf[MAX_STR_CONST - 1]) {
                    BEGIN(INVALID_STRING);
                    OUTPUT_ERROR("String constant too long");
                }
                strcpy(string_buf_ptr, yytext);
                string_buf_ptr += yyleng;
}

/* ================================================================================
 * Invalid string rules
 * ================================================================================*/

<INVALID_STRING>\"          {
                BEGIN(INITIAL);
}
<INVALID_STRING>\n          {
                ++curr_lineno;
                BEGIN(INITIAL);
}
<INVALID_STRING>\\\n        {
                ++curr_lineno;
}
<INVALID_STRING>\\.         {}
<INVALID_STRING>[^\\\n\"]+  {}

/* ================================================================================
 * Comments/white space rules
 * ================================================================================*/

"//"[^}\n]*         /*  eat up one-line comments */

[ \t\n]+            /*  eat up white space */

%%