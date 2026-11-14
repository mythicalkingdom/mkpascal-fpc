program t;
begin
  writeln(7/2:0:2, ' ', round(2.5), ' ', round(-2.5), ' ', trunc(-2.7));
  writeln(sqrt(16.0):0:1, ' ', abs(-3), ' ', sqr(5), ' ', odd(3));
  writeln(pi:0:4, ' ', int(3.7):0:1, ' ', frac(3.25):0:2);
  writeln(exp(0):0:1, ' ', ln(1):0:1, ' ', sin(0):0:1, ' ', cos(0):0:1, ' ', arctan(1) * 4:0:5);
end.
