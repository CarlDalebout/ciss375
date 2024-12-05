#! /bin/bash
for f in $(ls *.out | sed 's/\.\(\|ref\)out$//' | sort | uniq); do
  echo "---- $f ----"
  diff -u $f.out $f.refout;
done
