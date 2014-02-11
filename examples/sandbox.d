import dawg.drepl, std.stdio, std.string, std.conv;

void main()
{
    auto intp = interpreter(dmdEngine());
    foreach (line; stdin.byLine())
    {
        auto res = intp.interpret(line);
        writeln(res[0]);
        writeln(res[1].strip());
        writeln();
        stdout.flush();
    }
}
