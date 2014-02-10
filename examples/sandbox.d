import dawg.drepl, std.stdio, std.conv : to;

void main()
{
    auto intp = interpreter(dmdEngine());
    foreach (line; stdin.byLine())
    {
        auto res = intp.interpret(line);
        writeln(res[0], ",", res[1]); stdout.flush();
    }
}
