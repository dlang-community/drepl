import dawg.drepl, std.stdio, std.string, std.conv, std.json;

void main()
{
    auto intp = interpreter(dmdEngine());
    foreach (line; stdin.byLine())
    {
        auto res = intp.interpret(line);
        JSONValue json;
        json = [
            "state" : to!string(res.state),
            "stdout" : res.stdout.strip(),
            "stderr" : res.stderr.strip(),
        ];
        writeln(json);
        stdout.flush();
    }
}
