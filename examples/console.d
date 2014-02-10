/*
  Copyright: Martin Nowak 2013 -
  License: Subject to the terms of the MIT license, as written in the included LICENSE file.
  Authors: $(WEB code.dawg.eu, Martin Nowak)
*/
import std.stdio, std.string, std.path, std.process;
import core.stdc.string : strlen;
import deimos.linenoise;
import dawg.drepl;

void main(string[] args)
{
    writeln("Welcome to D REPL.");

    auto history = buildPath(environment.get("HOME", ""), ".drepl_history").toStringz();
    linenoiseHistoryLoad(history);

    auto intp = interpreter(dmdEngine());

    char *line;
    const(char) *prompt = "D> ";
    while((line = linenoise(prompt)) !is null)
    {
        linenoiseHistoryAdd(line);
        linenoiseHistorySave(history);

        auto res = intp.interpret(line[0 .. strlen(line)]);
        final switch (res[0])
        {
        case Result.incomplete:
            prompt = " | ";
            break;

        case Result.success:
        case Result.error:
            if (res[1].length) writeln(res[1]);
            prompt = "D> ";
            break;
        }
    }
}
