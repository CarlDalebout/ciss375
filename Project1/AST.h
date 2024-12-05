#ifndef AST_H
#define AST_H

#include <iostream>
#include <string>
#include <vector>

enum OPERATOR 
{
    MULT,
    DIV,
    PLUS, 
    MINUS,
    LTE,
    LT,
    EQ,
    NOT,
    ASSIGN,
    ISVOID,
};

enum BOOL 
{
  TRUE,
  FALSE,
};

void printOp(int x);

#endif