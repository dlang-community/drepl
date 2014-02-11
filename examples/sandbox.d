import dawg.drepl, std.stdio, std.string, std.conv;

void main()
{
    auto intp = interpreter(dmdEngine());
    foreach (line; stdin.byLine())
    {
        auto res = intp.interpret(line);
        writeln("===SOC===");
        writeln(res[0]);
        res[1] = res[1].strip();
        if (res[1].length) writeln(res[1]);
        writeln("===EOC===");
        stdout.flush();
    }
}
