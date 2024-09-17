input:  /* empty */
        | input line
;

line:   '\n'
        | exp '\n'  {
                        printf ("\t%.10g\n", $1);
                    }
;

exp:    NUM             { $$ = $1; }
        | exp exp '+'   { $$ = $1 + $2; }
        | exp exp '-'   { $$ = $1 - $2; }
        | exp exp '*'   { $$ = $1 * $2; }
        | exp exp '/'   { $$ = $1 / $2; }
        /* Exponentition */
        | exp exp '^'   { $$ = pow ($1, $2); }
        /* Unary minus *
        | exp 'n'       { $$ = -$1; }
;
%%