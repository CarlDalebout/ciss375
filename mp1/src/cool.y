/*
 *  cool.y
 *              Parser definition for the COOL language.
 *
 */
%{
#include <iostream>
#include "cool-tree.h"
#include "stringtab.h"
#include "utilities.h"

/* Add your own C declarations here */


/************************************************************************/
/*                DONT CHANGE ANYTHING IN THIS SECTION                  */

extern int yylex();           /* the entry point to the lexer  */
extern int curr_lineno;
extern char *curr_filename;
Program ast_root;            /* the result of the parse  */
Classes parse_results;       /* for use in semantic analysis */
int omerrs = 0;              /* number of errors in lexing and parsing */

/*
   The parser will always call the yyerror function when it encounters a parse
   error. The given yyerror implementation (see below) justs prints out the
   location in the file where the error was found. You should not change the
   error message of yyerror, since it will be used for grading puproses.
*/
void yyerror(const char *s);

/*
   The VERBOSE_ERRORS flag can be used in order to provide more detailed error
   messages. You can use the flag like this:

     if (VERBOSE_ERRORS)
       fprintf(stderr, "semicolon missing from end of declaration of class\n");

   By default the flag is set to 0. If you want to set it to 1 and see your
   verbose error messages, invoke your parser with the -v flag.

   You should try to provide accurate and detailed error messages. A small part
   of your grade will be for good quality error messages.
*/
extern int VERBOSE_ERRORS;

%}

/* A union of all the types that can be the result of parsing actions. */
%union {
  Boolean boolean;
  Symbol symbol;
  Program program;
  Class_ class_;
  Classes classes;
  Feature feature;
  Features features;
  Formal formal;
  Formals formals;
  Case case_;
  Cases cases;
  Expression expression;
  Expressions expressions;
  char *error_msg;
}

/* 
   Declare the terminals; a few have types for associated lexemes.
   The token ERROR is never used in the parser; thus, it is a parse
   error when the lexer returns it.

   The integer following token declaration is the numeric constant used
   to represent that token internally.  Typically, Bison generates these
   on its own, but we give explicit numbers to prevent version parity
   problems (bison 1.25 and earlier start at 258, later versions -- at
   257)
*/
%token CLASS 258 ELSE 259 FI 260 IF 261 IN 262 
%token INHERITS 263 LET 264 LOOP 265 POOL 266 THEN 267 WHILE 268
%token CASE 269 ESAC 270 OF 271 DARROW 272 NEW 273 ISVOID 274
%token <symbol>  STR_CONST 275 INT_CONST 276 
%token <boolean> BOOL_CONST 277
%token <symbol>  TYPEID 278 OBJECTID 279 
%token ASSIGN 280 NOT 281 LE 282 ERROR 283

/*  DON'T CHANGE ANYTHING ABOVE THIS LINE, OR YOUR PARSER WONT WORK       */
/**************************************************************************/
 
   /* Complete the nonterminal list below, giving a type for the semantic
      value of each non terminal. (See section 3.6 in the bison 
      documentation for details). */

/* Declare types for the grammar's non-terminals. */
%type <program> program
%type <classes> class_list
%type <class_> class

/* You will want to change the following line. */
%type <features> lst_feature
%type <feature> method attr

/* Precedence declarations go here. */
%type <formals> lst_formal
%type <formal> formal

%type <cases> lst_case
%type <case_> branch_case

%type <expressions> expression_list lst_arg
%type <expression> expression let_exp_nested

/* Precedence declarations go here. */
%left '.'
%left '+' '-'
%left '*' '/'
%left ISVOID
%left '~'
%left '@'

%right IN
%left NOT
%right ASSIGN
%nonassoc LE '<' '='

%%
/* 
   Save the root of the abstract syntax tree in a global variable.
*/
program : class_list 
        { 
          ast_root = program($1); 
        };

class_list : class            /* single class */
        { $$ = single_Classes($1); 
          parse_results = $$; 
        }
        | class_list class /* several classes */
        { $$ = append_Classes($1,single_Classes($2)); 
          parse_results = $$;
        };

/* When there isn't a parent class, default to inherit Object class.*/
  /* otherwise, the class name is curr_filename */
  class : CLASS TYPEID '{' lst_feature '}' ';'
    { $$ = class_($2, idtable.add_string("Object"), $4,
      stringtable.add_string(curr_filename)); }
    | CLASS TYPEID INHERITS TYPEID '{' lst_feature '}' ';'
    { $$ = class_($2, $4, $6, stringtable.add_string(curr_filename)); }
    ;

lst_feature : lst_feature method ';' /* feature may be a method */
  	{ $$ = append_Features($1, single_Features($2)); }
  	| lst_feature attr ';' /* feature may be an attribute 'attr'*/
  	{ $$ = append_Features($1, single_Features($2)); }
  	| /* the feature list may be empty*/
  	{ $$ = nil_Features(); }
  	| error ';'
  	{ $$ = 0; }
    ;

/* used if the lst_feature is an attribute */
	attr : OBJECTID ':' TYPEID	/* attribute is not initialized*/
  	{ $$ = attr($1, $3, no_expr()); }
  	| OBJECTID ':' TYPEID ASSIGN expression	/* attribute is initialized */
  	{ $$ = attr($1, $3, $5); }
  	;

/* used if the lst_feature is a method */
method : OBJECTID '(' lst_formal ')' ':' TYPEID '{' expression '}'
{ $$ = method($1, $3, $6, $8); }
;

/* formal list can have 0, 1, or many formals */
lst_formal : formal
{ $$ = single_Formals($1); }
| lst_formal ',' formal
{ $$ = append_Formals($1, single_Formals($3)); };
|
{ $$ = nil_Formals(); }
;

formal : OBJECTID ':' TYPEID
        { $$ = formal($1, $3); };

/* an expression has very many different forms. */
expression : OBJECTID ASSIGN expression
{ $$ = assign($1, $3); }
/* expression can be followed by @typeid.objectid and (args)*/
| expression '@' TYPEID '.' OBJECTID '(' lst_arg ')'
{ $$ = static_dispatch($1, $3, $5, $7); }
/* expression can be followed by .objectID and (args)*/
| expression '.' OBJECTID '(' lst_arg ')'
{ $$ = dispatch($1, $3, $5); }
/* can be objectID and (args)*/
| OBJECTID '(' lst_arg ')'
{ $$ = dispatch(object(idtable.add_string("self")), $1, $3); }
/* while statement */
| WHILE expression LOOP expression POOL
{ $$ = loop($2, $4); }
/* if statement*/
| IF expression THEN expression ELSE expression FI
{ $$ = cond($2, $4, $6); }
/* {a list of expressions} */
| '{' expression_list '}'
{ $$ = block($2); }
| '{' error '}'
{ $$ = 0; }
/* let statement */
| LET let_exp_nested
{ $$ = $2; }
/* expression with case */
| CASE expression OF lst_case ESAC
{ $$ = typcase($2, $4); }
/* new typeid exp */
| NEW TYPEID
{ $$ = new_($2); }
/* is void exp */
| ISVOID expression
{ $$ = isvoid($2); }
/* times exp */
| expression '*' expression
{ $$ = mul($1, $3);}
/* divide exp */
| expression '/' expression
{ $$ = divide($1, $3);}
| '~' expression
{ $$ = neg($2); }
/* plus exp */
| expression '+' expression
{ $$ = plus($1, $3);}
/* minus exp */
| expression '-' expression
{ $$ = sub($1, $3);}
/* less than exp */
| expression '<' expression
{ $$ = lt($1, $3);}
/* less than or equal to exp */
| expression LE expression	/* LE represent '<=' */
{ $$ = leq($1, $3);}
| expression '=' expression
{ $$ = eq($1, $3);}
/* not exp */
| NOT expression
{ $$ = comp($2);}
/* expression in parenthesis */
| '(' expression ')'
{ $$ = $2; }
/* a single string*/
| STR_CONST
{ $$ = string_const($1); }
/* a boolean */
| BOOL_CONST
{ $$ = bool_const($1); }
/* a single objectid */
| OBJECTID
{ $$ = object($1); }
/* a single int*/
| INT_CONST
{ $$ = int_const($1); }
;

/* a case list is one or more branch_case */
lst_case : branch_case
{ $$ = single_Cases($1); }
| lst_case branch_case
{ $$ = append_Cases($1, single_Cases($2)); }
;

/* this is the format for branch_case */
branch_case : OBJECTID ':' TYPEID DARROW expression ';'
        { $$ = branch($1, $3, $5); }

/* express a nested let expression */
let_exp_nested : OBJECTID ':' TYPEID IN expression
{ $$ = let($1, $3, no_expr(), $5); }
| OBJECTID ':' TYPEID ASSIGN expression IN expression
{ $$ = let($1, $3, $5, $7); }
| OBJECTID ':' TYPEID ',' let_exp_nested
{ $$ = let($1, $3, no_expr(), $5); }
| OBJECTID ':' TYPEID ASSIGN expression ',' let_exp_nested
{ $$ = let($1, $3, $5, $7); }
| error ','
{ $$ = 0; }
| error
{ $$ = 0; }
;

/* arguments are separated by commas in a function, and can be empty */
lst_arg : expression
{ $$ = single_Expressions($1); }
| lst_arg ',' expression
{ $$ = append_Expressions($1, single_Expressions($3)); }
| /* empty option */
{ $$ = nil_Expressions(); }
;

/* an expression list is some number of expressions followed by ; */
expression_list : expression ';'
{ $$ = single_Expressions($1); }
| expression_list expression ';'
{ $$ = append_Expressions($1, single_Expressions($2)); }
;

/* end of grammar, marked by %% */
%%

/* This function is called automatically when Bison detects a parse error. */
void yyerror(const char *s)
{
extern int curr_lineno;

cerr << "\"" << curr_filename << "\", line " << curr_lineno << ": " \
<< s << " at or near ";
print_cool_token(yychar);
cerr << endl;
omerrs++;

if(omerrs>50) {fprintf(stdout, "More than 50 errors\n"); exit(1);}
}